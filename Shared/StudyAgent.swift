import Foundation

/// What the user asks a connected coding agent to do for a study. Both tasks
/// only add pending proposals through `mood-agent`; the user decides in mood.
public enum StudyAgentTask: String, Codable, CaseIterable, Hashable, Sendable {
    /// Find real, credited sources and add them with `mood-agent suggest`.
    case findSources
    /// Reflect patterns in keeps and rejects with `mood-agent reflect`.
    case reflect

    public var displayName: String {
        switch self {
        case .findSources: "Find sources"
        case .reflect: "Reflect patterns"
        }
    }
}

/// The coding agent mood. starts for a study. By default mood. picks the
/// first known agent installed on the Mac, so there is nothing to set up;
/// any other command-line agent can be configured as `custom`.
public struct StudyAgentConfiguration: Codable, Equatable, Hashable, Sendable {
    public enum Preset: String, Codable, CaseIterable, Hashable, Sendable {
        /// The first installed agent from `detectable`.
        case automatic
        case claudeCode
        case codex
        case custom

        /// Agents mood. knows how to start safely, in the order it tries them.
        public static let detectable: [Preset] = [.claudeCode, .codex]

        public var displayName: String {
            switch self {
            case .automatic: "Automatic"
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .custom: "Other command"
            }
        }

        /// The command a known agent installs on the user's PATH.
        public var commandName: String? {
            switch self {
            case .claudeCode: "claude"
            case .codex: "codex"
            case .automatic, .custom: nil
            }
        }
    }

    public var preset: Preset
    /// For `custom`: a command name looked up on the user's PATH, or an
    /// absolute path.
    public var executable: String
    /// For `custom`: arguments written as one shell-like line. Placeholders:
    /// `{prompt}`, `{moodAgent}`, `{skill}`, `{project}`, `{workdir}`. When
    /// `{prompt}` is absent, the prompt is written to the agent's stdin.
    public var arguments: String

    public init(preset: Preset = .automatic, executable: String = "", arguments: String = "{prompt}") {
        self.preset = preset
        self.executable = executable
        self.arguments = arguments
    }

    public static let automatic = StudyAgentConfiguration()

    public var trimmedExecutable: String {
        executable.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The commands to look for, in order, for this configuration.
    public var candidates: [(preset: Preset, command: String)] {
        switch preset {
        case .automatic:
            Preset.detectable.compactMap { preset in preset.commandName.map { (preset, $0) } }
        case .claudeCode, .codex:
            preset.commandName.map { [(preset, $0)] } ?? []
        case .custom:
            trimmedExecutable.isEmpty ? [] : [(.custom, trimmedExecutable)]
        }
    }
}

/// Everything about one run that the app resolves before launching the agent.
public struct StudyAgentContext: Equatable, Sendable {
    public var projectID: Project.ID
    public var projectName: String
    public var subject: String
    /// Absolute path of the bundled `mood-agent` helper.
    public var moodAgentPath: String
    /// Absolute path of the bundled `mood-study` skill directory.
    public var skillDirectory: String
    /// A scratch directory the agent may write temporary JSON into.
    public var workingDirectory: String
    /// The library folder `mood-agent` writes to, for agents whose sandbox
    /// has to allow it explicitly.
    public var storageDirectory: String

    public init(
        projectID: Project.ID,
        projectName: String,
        subject: String,
        moodAgentPath: String,
        skillDirectory: String,
        workingDirectory: String,
        storageDirectory: String
    ) {
        self.projectID = projectID
        self.projectName = projectName
        self.subject = subject
        self.moodAgentPath = moodAgentPath
        self.skillDirectory = skillDirectory
        self.workingDirectory = workingDirectory
        self.storageDirectory = storageDirectory
    }
}

/// A fully resolved process launch, independent of how the platform runs it.
public struct StudyAgentInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String
    /// Written to stdin and closed, or `nil` for an empty stdin.
    public var standardInput: String?

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String,
        standardInput: String?
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.standardInput = standardInput
    }
}

public enum StudyAgentConfigurationError: Error, Equatable, LocalizedError {
    case missingExecutable
    case unbalancedQuote

    public var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "Choose the agent to use in Settings › Study Agent."
        case .unbalancedQuote:
            "The agent arguments have an unclosed quote."
        }
    }
}

public extension StudyAgentConfiguration {
    /// Builds the launch for a resolved agent. `agent` is the concrete preset
    /// that was found (never `automatic`), and `executable` its path.
    func invocation(
        task: StudyAgentTask,
        context: StudyAgentContext,
        agent: Preset,
        executable: String
    ) throws -> StudyAgentInvocation {
        let executable = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executable.isEmpty, agent != .automatic else {
            throw StudyAgentConfigurationError.missingExecutable
        }
        let prompt = StudyAgentPrompt.make(task: task, context: context)
        let environment = [
            "MOOD_AGENT": context.moodAgentPath,
            "MOOD_STUDY_SKILL": context.skillDirectory,
            "MOOD_STUDY_PROJECT": context.projectID.uuidString,
            "MOOD_STUDY_TASK": task.rawValue,
            "MOOD_STUDY_PROMPT": prompt,
            PinaxAgentLibraryLocation.environmentKey: context.storageDirectory,
        ]

        func launch(_ arguments: [String], stdin: String? = nil) -> StudyAgentInvocation {
            StudyAgentInvocation(
                executable: executable,
                arguments: arguments,
                environment: environment,
                workingDirectory: context.workingDirectory,
                standardInput: stdin
            )
        }

        switch agent {
        case .automatic:
            throw StudyAgentConfigurationError.missingExecutable
        case .claudeCode:
            return launch([
                "-p", prompt,
                "--permission-mode", "acceptEdits",
                "--allowedTools", Self.claudeCodeAllowedTools(context: context).joined(separator: ","),
            ])
        case .codex:
            // Codex's workspace-write sandbox has no network for commands and
            // writes only to the scratch folder and the library folder that
            // mood-agent updates; web research uses its built-in search.
            return launch([
                "exec",
                "--skip-git-repo-check",
                "--ephemeral",
                "--sandbox", "workspace-write",
                "--add-dir", context.storageDirectory,
                "-c", #"web_search="live""#,
                prompt,
            ])
        case .custom:
            let tokens = try Self.splitArguments(arguments)
            let placeholders = [
                "{prompt}": prompt,
                "{moodAgent}": context.moodAgentPath,
                "{skill}": context.skillDirectory,
                "{project}": context.projectID.uuidString,
                "{workdir}": context.workingDirectory,
            ]
            let usesPromptPlaceholder = tokens.contains { $0.contains("{prompt}") }
            let resolved = tokens.map { token in
                placeholders.reduce(token) { result, entry in
                    result.replacingOccurrences(of: entry.key, with: entry.value)
                }
            }
            return launch(resolved, stdin: usesPromptPlaceholder ? nil : prompt)
        }
    }

    /// Claude Code runs unattended, so it gets only what the study needs:
    /// reading images and skill files, web research, and the bundled helper.
    /// Temporary JSON is written in the working directory under
    /// `acceptEdits`; no other shell command is allowed.
    static func claudeCodeAllowedTools(context: StudyAgentContext) -> [String] {
        [
            "Read",
            "Glob",
            "Grep",
            "WebSearch",
            "WebFetch",
            "Bash(\(context.moodAgentPath):*)",
        ]
    }

    /// Splits a shell-like argument line on whitespace, honoring single and
    /// double quotes and backslash escapes. Nothing is expanded.
    static func splitArguments(_ line: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasToken = false
        var quote: Character?
        var escaping = false

        for character in line {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if character == "\\", activeQuote == "\"" {
                    escaping = true
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case "\\":
                escaping = true
                hasToken = true
            case "\"", "'":
                quote = character
                hasToken = true
            case _ where character.isWhitespace:
                if hasToken {
                    tokens.append(current)
                    current = ""
                    hasToken = false
                }
            default:
                current.append(character)
                hasToken = true
            }
        }
        if quote != nil || escaping { throw StudyAgentConfigurationError.unbalancedQuote }
        if hasToken { tokens.append(current) }
        return tokens
    }
}

/// The instructions handed to whichever agent the user connected. The agent
/// follows the bundled `mood-study` skill and can only add pending proposals.
public enum StudyAgentPrompt {
    public static func make(task: StudyAgentTask, context: StudyAgentContext) -> String {
        let helper = context.moodAgentPath
        let project = context.projectID.uuidString
        let skill = (context.skillDirectory as NSString).appendingPathComponent("SKILL.md")

        let job: String = switch task {
        case .findSources:
            """
            Your task: find 6 to 10 real, credited sources for this study, following the skill's \
            "Find sources" section, and add them with `\(helper) suggest --project \(project) --file <json>`. \
            Don't add reflections in this run.
            """
        case .reflect:
            """
            Your task: reflect 2 to 4 patterns in the user's keeps and rejects, following the skill's \
            "Reflect patterns back" section, and add them with `\(helper) reflect --project \(project) --file <json>`. \
            Don't suggest new sources in this run.
            """
        }

        return """
        mood. started you from its study panel to help with the visual study "\(context.projectName)" \
        (project \(project)), subject: "\(context.subject)".

        Read the mood-study skill at \(skill) and its references/agent-api.md, and follow its hard rules: \
        real, credited work only, never generated imagery; tie each proposal to the user's seeds, notes and verdicts.

        The mood-agent helper is already located at \(helper). Call it by that absolute path for every \
        command (start with `\(helper) study --project \(project) --pretty`); don't run the finder script or use \
        a shell variable. Write temporary JSON files only in the current working directory.

        \(job)

        You only propose. The user keeps, rejects, confirms or corrects everything in mood., so never claim \
        anything was kept and never change the library any other way. Nobody can answer questions during \
        this run: if the study isn't ready, say why and stop. Finish with a short plain summary of what you \
        added and anything mood-agent skipped.
        """
    }
}
