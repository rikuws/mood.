import Foundation
import Observation
import os
import OSLog
import PinaxCore

/// The study agent the user connected in Settings, stored in user defaults.
enum StudyAgentSettings {
    static let defaultsKey = "studyAgentConfiguration"

    static func load(from defaults: UserDefaults = .standard) -> StudyAgentConfiguration {
        guard let data = defaults.data(forKey: defaultsKey),
              let configuration = try? JSONDecoder().decode(StudyAgentConfiguration.self, from: data) else {
            return .automatic
        }
        return configuration
    }

    static func save(_ configuration: StudyAgentConfiguration, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// The helper and skill bundled in mood.app, which every run points at.
    static var bundledMoodAgent: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/mood-agent", isDirectory: false)
    }

    static var bundledSkillDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Skills/mood-study", isDirectory: true)
    }
}

/// Finds a command the way the user's Terminal would. Apps launched from the
/// Finder get a minimal PATH, so the login shell's PATH and the usual install
/// locations for agent CLIs are searched too.
enum StudyAgentExecutableLocator {
    private static let cache = OSAllocatedUnfairLock<String?>(initialState: nil)

    static func searchPath() -> String {
        if let cached = cache.withLock({ $0 }) { return cached }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = loginShellPath().split(separator: ":").map(String.init)
        directories += [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        var seen = Set<String>()
        let path = directories.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        cache.withLock { $0 = path }
        return path
    }

    static func resolve(_ command: String) -> URL? {
        let fileManager = FileManager.default
        if command.hasPrefix("/") || command.hasPrefix("~") {
            let path = (command as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        for directory in searchPath().split(separator: ":") {
            let candidate = "\(directory)/\(command)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    private static func loginShellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ProcessInfo.processInfo.environment["PATH"] ?? ""
        }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return ProcessInfo.processInfo.environment["PATH"] ?? ""
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

/// An agent found on this Mac for a configuration.
struct ResolvedStudyAgent: Equatable, Sendable {
    let preset: StudyAgentConfiguration.Preset
    let executable: URL

    var displayName: String {
        preset == .custom ? executable.lastPathComponent : preset.displayName
    }

    /// The first installed agent the configuration allows. Can block briefly
    /// the first time, while the login shell's PATH is read.
    static func resolve(_ configuration: StudyAgentConfiguration) -> ResolvedStudyAgent? {
        for candidate in configuration.candidates {
            if let url = StudyAgentExecutableLocator.resolve(candidate.command) {
                return ResolvedStudyAgent(preset: candidate.preset, executable: url)
            }
        }
        return nil
    }

    /// Every known agent installed on this Mac, for the agent menu.
    static func installed() -> [ResolvedStudyAgent] {
        StudyAgentConfiguration.Preset.detectable.compactMap { preset in
            resolve(StudyAgentConfiguration(preset: preset))
        }
    }
}

/// Runs the connected agent for a study and keeps its progress observable.
/// The agent writes back only through `mood-agent suggest`/`reflect`, which
/// add pending proposals, so the library reloads while it runs and the user
/// judges every proposal in the study panel.
@MainActor
@Observable
final class StudyAgentRunner {
    enum Phase: Equatable {
        case running
        case finished
        case failed(String)
        case cancelled
    }

    struct Run: Equatable {
        let task: StudyAgentTask
        let agentName: String
        let startedAt: Date
        var phase: Phase
        var output: String
    }

    static let shared = StudyAgentRunner()

    private(set) var runs: [Project.ID: Run] = [:]

    @ObservationIgnored private var processes: [Project.ID: Process] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "com.rikuwikman.Pinax", category: "study-agent")
    private static let outputLimit = 64_000

    func run(for projectID: Project.ID) -> Run? {
        runs[projectID]
    }

    func isRunning(_ projectID: Project.ID) -> Bool {
        runs[projectID]?.phase == .running
    }

    /// Launches the agent. `onChange` is called as the library may have
    /// changed: periodically while running, then once with `isFinal`.
    func start(
        task: StudyAgentTask,
        project: Project,
        agent: ResolvedStudyAgent,
        configuration: StudyAgentConfiguration,
        storageDirectory: URL,
        onChange: @escaping @Sendable @MainActor (_ isFinal: Bool) async -> Void
    ) throws {
        guard !isRunning(project.id) else { return }
        let invocation = try makeInvocation(
            task: task,
            project: project,
            agent: agent,
            configuration: configuration,
            storageDirectory: storageDirectory
        )
        let executable = agent.executable

        let process = Process()
        process.executableURL = executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: invocation.workingDirectory, isDirectory: true)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = StudyAgentExecutableLocator.searchPath()
        environment.merge(invocation.environment) { _, new in new }
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let input: Pipe?
        if invocation.standardInput != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            input = pipe
        } else {
            process.standardInput = FileHandle.nullDevice
            input = nil
        }

        let projectID = project.id
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.append(text, to: projectID) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            Task { @MainActor in
                await self?.finish(
                    projectID,
                    status: status,
                    reason: reason,
                    workingDirectory: invocation.workingDirectory,
                    onChange: onChange
                )
            }
        }

        runs[projectID] = Run(
            task: task,
            agentName: agent.displayName,
            startedAt: Date(),
            phase: .running,
            output: ""
        )
        do {
            try process.run()
        } catch {
            runs[projectID]?.phase = .failed(error.localizedDescription)
            try? FileManager.default.removeItem(atPath: invocation.workingDirectory)
            throw error
        }
        processes[projectID] = process
        logger.notice("Started study agent \(executable.path, privacy: .public) for \(task.rawValue, privacy: .public)")

        if let input, let text = invocation.standardInput {
            let handle = input.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                try? handle.write(contentsOf: Data(text.utf8))
                try? handle.close()
            }
        }

        Task { @MainActor [weak self] in
            while self?.isRunning(projectID) == true {
                try? await Task.sleep(for: .seconds(3))
                guard self?.isRunning(projectID) == true else { break }
                await onChange(false)
            }
        }
    }

    func cancel(_ projectID: Project.ID) {
        guard let process = processes[projectID], process.isRunning else { return }
        runs[projectID]?.phase = .cancelled
        process.terminate()
    }

    func clear(_ projectID: Project.ID) {
        guard !isRunning(projectID) else { return }
        runs[projectID] = nil
    }

    private func makeInvocation(
        task: StudyAgentTask,
        project: Project,
        agent: ResolvedStudyAgent,
        configuration: StudyAgentConfiguration,
        storageDirectory: URL
    ) throws -> StudyAgentInvocation {
        let fileManager = FileManager.default
        let helper = StudyAgentSettings.bundledMoodAgent
        guard fileManager.isExecutableFile(atPath: helper.path) else {
            throw StudyAgentRunnerError.missingBundledResource("mood-agent helper")
        }
        guard let skill = StudyAgentSettings.bundledSkillDirectory,
              fileManager.fileExists(atPath: skill.appendingPathComponent("SKILL.md").path) else {
            throw StudyAgentRunnerError.missingBundledResource("mood-study skill")
        }
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("mood-study-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let context = StudyAgentContext(
            projectID: project.id,
            projectName: project.name,
            subject: project.study?.subject ?? project.name,
            moodAgentPath: helper.path,
            skillDirectory: skill.path,
            workingDirectory: workingDirectory.path,
            storageDirectory: storageDirectory.path
        )
        do {
            return try configuration.invocation(
                task: task,
                context: context,
                agent: agent.preset,
                executable: agent.executable.path
            )
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            throw error
        }
    }

    private func append(_ text: String, to projectID: Project.ID) {
        guard var run = runs[projectID] else { return }
        run.output += text
        if run.output.count > Self.outputLimit {
            run.output = String(run.output.suffix(Self.outputLimit))
        }
        runs[projectID] = run
    }

    private func finish(
        _ projectID: Project.ID,
        status: Int32,
        reason: Process.TerminationReason,
        workingDirectory: String,
        onChange: @MainActor (_ isFinal: Bool) async -> Void
    ) async {
        processes[projectID] = nil
        try? FileManager.default.removeItem(atPath: workingDirectory)
        if runs[projectID]?.phase == .running {
            if reason == .exit, status == 0 {
                runs[projectID]?.phase = .finished
            } else {
                runs[projectID]?.phase = .failed(
                    reason == .uncaughtSignal
                        ? "The agent stopped unexpectedly."
                        : "The agent exited with status \(status)."
                )
            }
        }
        logger.notice("Study agent finished with status \(status)")
        await onChange(true)
    }
}

enum StudyAgentRunnerError: Error, LocalizedError {
    case missingBundledResource(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledResource(let name):
            "This build of mood. is missing its bundled \(name). Reinstall mood. for Mac."
        }
    }
}
