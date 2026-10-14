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

/// The coding agent mood. launches for a study. Claude Code is the built-in
/// preset; any other command-line agent can be configured as `custom`.
public struct StudyAgentConfiguration: Codable, Equatable, Hashable, Sendable {
    public enum Preset: String, Codable, CaseIterable, Hashable, Sendable {
        case claudeCode
        case custom

        public var displayName: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .custom: "Other command-line agent"
            }
        }
    }

    public var preset: Preset
    /// A command name looked up on the user's PATH, or an absolute path.
    public var executable: String
    /// Arguments for `custom`, written as one shell-like line. Placeholders:
    /// `{prompt}`, `{moodAgent}`, `{skill}`, `{project}`, `{workdir}`. When
    /// `{prompt}` is absent, the prompt is written to the agent's stdin.
    public var arguments: String

    public init(preset: Preset, executable: String, arguments: String = "") {
        self.preset = preset
        self.executable = executable
        self.arguments = arguments
    }

    public static let claudeCode = StudyAgentConfiguration(preset: .claudeCode, executable: "claude")

    public static let customTemplate = StudyAgentConfiguration(
        preset: .custom,
        executable: "",
        arguments: "{prompt}"
    )

    public var trimmedExecutable: String {
        executable.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isComplete: Bool {
        !trimmedExecutable.isEmpty
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

    public init(
        projectID: Project.ID,
        projectName: String,
        subject: String,
        moodAgentPath: String,
        skillDirectory: String,
        workingDirectory: String
    ) {
        self.projectID = projectID
        self.projectName = projectName
        self.subject = subject
        self.moodAgentPath = moodAgentPath
        self.skillDirectory = skillDirectory
        self.workingDirectory = workingDirectory
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
            "Choose the command that starts your agent in Settings."
        case .unbalancedQuote:
            "The agent arguments have an unclosed quote."
        }
    }
}

public extension StudyAgentConfiguration {
    func invocation(
        task: StudyAgentTask,
        context: StudyAgentContext
    ) throws -> StudyAgentInvocation {
        guard isComplete else { throw StudyAgentConfigurationError.missingExecutable }
        let prompt = StudyAgentPrompt.make(task: task, context: context)
        let environment = [
            "MOOD_AGENT": context.moodAgentPath,
            "MOOD_STUDY_SKILL": context.skillDirectory,
            "MOOD_STUDY_PROJECT": context.projectID.uuidString,
            "MOOD_STUDY_TASK": task.rawValue,
            "MOOD_STUDY_PROMPT": prompt,
        ]

        switch preset {
        case .claudeCode:
            return StudyAgentInvocation(
                executable: trimmedExecutable,
                arguments: [
                    "-p", prompt,
                    "--permission-mode", "acceptEdits",
                    "--allowedTools", Self.claudeCodeAllowedTools(context: context).joined(separator: ","),
                ],
                environment: environment,
                workingDirectory: context.workingDirectory,
                standardInput: nil
            )
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
            return StudyAgentInvocation(
                executable: trimmedExecutable,
                arguments: resolved,
                environment: environment,
                workingDirectory: context.workingDirectory,
                standardInput: usesPromptPlaceholder ? nil : prompt
            )
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
