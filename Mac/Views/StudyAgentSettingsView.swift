import AppKit
import Combine
import PinaxCore
import SwiftUI

/// Settings › Study Agent. Nothing needs setting: Automatic uses the first
/// known agent installed on this Mac. This is only for choosing another one.
struct StudyAgentSettingsView: View {
    @State private var configuration = StudyAgentSettings.load()
    @State private var resolved: ResolvedStudyAgent?
    @State private var isChecking = true

    var body: some View {
        Form {
            Section {
                Picker("Agent", selection: presetBinding) {
                    ForEach(StudyAgentConfiguration.Preset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                if configuration.preset == .custom {
                    TextField("Command", text: $configuration.executable, prompt: Text("/path/to/agent"))
                        .font(.system(.body, design: .monospaced))
                    TextField("Arguments", text: $configuration.arguments, prompt: Text("{prompt}"))
                        .font(.system(.body, design: .monospaced))
                    Text("Placeholders: {prompt}, {moodAgent}, {skill}, {project}, {workdir}. Without {prompt}, the prompt is sent on standard input. The same values are in the MOOD_AGENT, MOOD_STUDY_SKILL, MOOD_STUDY_PROJECT and MOOD_STUDY_PROMPT environment variables.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Status") {
                    if isChecking {
                        ProgressView().controlSize(.small)
                    } else if let resolved {
                        Label("Using \(resolved.displayName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help(resolved.executable.path)
                    } else {
                        Label(notFoundMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Study agent")
            } footer: {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .task(id: configuration) {
            StudyAgentSettings.save(configuration)
            isChecking = true
            let current = configuration
            resolved = await Task.detached { ResolvedStudyAgent.resolve(current) }.value
            isChecking = false
        }
    }

    private var presetBinding: Binding<StudyAgentConfiguration.Preset> {
        Binding(
            get: { configuration.preset },
            set: { configuration.preset = $0 }
        )
    }

    private var notFoundMessage: String {
        switch configuration.preset {
        case .automatic: "No agent found. Install Claude Code or Codex."
        case .claudeCode, .codex: "\(configuration.preset.displayName) isn't installed"
        case .custom: configuration.trimmedExecutable.isEmpty ? "Enter a command" : "Command not found"
        }
    }

    private var footer: String {
        switch configuration.preset {
        case .automatic, .claudeCode, .codex:
            "mood. starts the agent with its bundled mood-study skill and a copy of your study. Each time it saves a find, mood. checks it and adds it to the study board if it passes, so you can judge while it keeps looking. The agent never touches your library, and you keep or reject everything."
        case .custom:
            "mood. starts this command in a scratch folder holding study.json. The prompt points it at the bundled mood-study skill and asks it to save each proposal as its own file in suggestions/ or reflections/ there; one suggestions.json or reflections.json at the end also works. mood. checks each file as it appears and adds what passes for you to judge. The agent needs no access to your library."
        }
    }
}

/// The study board's agent controls on the Mac. With an agent installed this
/// is one button; while it runs, a live count of what it has found so far.
/// Without an agent, it says what to install.
struct StudyAgentSection: View {
    let store: LibraryStore
    let project: Project
    let study: ProjectStudy
    /// Called each time the running agent's finds are added.
    var onProgress: @Sendable @MainActor () async -> Void = {}
    /// Called once the agent has exited and everything it proposed is in.
    var onChange: @Sendable @MainActor () async -> Void = {}

    @Environment(\.openSettings) private var openSettings
    @State private var runner = StudyAgentRunner.shared
    @State private var configuration = StudyAgentSettings.load()
    @State private var agent: ResolvedStudyAgent?
    @State private var installed: [ResolvedStudyAgent] = []
    @State private var isDetecting = true
    @State private var errorMessage: String?
    @State private var showsOutput = false
    @State private var didCopyPrompt = false

    private static let installURL = URL(string: "https://code.claude.com/docs/en/setup")!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let run = runner.run(for: project.id), run.phase == .running {
                runningStatus(run)
            } else if isDetecting {
                ProgressView().controlSize(.small)
            } else if agent == nil {
                missingAgent
            } else {
                controls
            }

            if let run = runner.run(for: project.id), run.phase != .running {
                lastRun(run)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .task { await detect() }
        // Pick up a choice made in Settings or an agent installed meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await detect() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            if StudyAgentSettings.load() != configuration { Task { await detect() } }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    start(.findSources)
                } label: {
                    Label("Find sources", systemImage: "binoculars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(stage == .seed)

                Button {
                    start(.reflect)
                } label: {
                    Label("Reflect patterns", systemImage: "text.bubble")
                }
                .disabled(study.decidedSuggestions.isEmpty)
                .help("Available once you've kept or rejected a find.")

                if let agent {
                    agentMenu(current: agent)
                }

                Button(didCopyPrompt ? "Copied" : "Copy prompt for another agent") {
                    StudyAgentPromptText.copy(for: project)
                    didCopyPrompt = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if stage == .seed {
                Text("Add at least \(ProjectStudy.minimumSeedCount) seeds to the moodboard before asking for sources, so the agent has your taste to go on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runningStatus(_ run: StudyAgentRunner.Run) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(run.agentName) is \(run.task == .findSources ? "looking for sources" : "reflecting patterns") · \(progressCount(run))")
                    .font(.callout.weight(.medium))
                    .contentTransition(.numericText())
                Text(run.task == .findSources
                     ? "Each find appears on the board as soon as its credit checks out. Judge them while it keeps looking."
                     : "Each pattern appears on the board as soon as it's checked against your images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            outputButton(run)
            Button("Stop") { runner.cancel(project.id) }
        }
        .accessibilityElement(children: .contain)
    }

    private func progressCount(_ run: StudyAgentRunner.Run) -> String {
        switch run.task {
        case .findSources:
            let count = run.result.addedSuggestions
            return count == 0 ? "nothing yet" : "\(count) found so far"
        case .reflect:
            let count = run.result.addedReflections
            return count == 0 ? "nothing yet" : "\(count) pattern\(count == 1 ? "" : "s") so far"
        }
    }

    @ViewBuilder
    private func lastRun(_ run: StudyAgentRunner.Run) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch run.phase {
            case .running:
                EmptyView()
            case .finished:
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text("\(run.agentName) finished. \(run.result.summary)")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(failureText(message, run: run))
            case .cancelled:
                Image(systemName: "stop.circle").foregroundStyle(.secondary)
                Text(run.result.addedCount > 0
                     ? "Stopped. What it found so far stays on the board for you to judge."
                     : "Stopped before it found anything.")
            }
            Spacer(minLength: 8)
            outputButton(run)
            Button {
                runner.clear(project.id)
            } label: {
                Label("Dismiss", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func failureText(_ message: String, run: StudyAgentRunner.Run) -> String {
        var text = "\(message) If \(run.agentName) isn't signed in yet, open it in Terminal once to sign in."
        if run.result.addedCount > 0 {
            text += " What it found before it stopped is on the board."
        }
        return text
    }

    @ViewBuilder
    private func outputButton(_ run: StudyAgentRunner.Run) -> some View {
        if !run.output.isEmpty {
            Button("Output") { showsOutput.toggle() }
                .buttonStyle(.borderless)
                .font(.caption)
                .popover(isPresented: $showsOutput, arrowEdge: .bottom) {
                    ScrollView {
                        Text(run.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(width: 480, height: 300)
                }
        }
    }

    private func agentMenu(current: ResolvedStudyAgent) -> some View {
        Menu {
            ForEach(installed, id: \.preset) { option in
                Button {
                    choose(StudyAgentConfiguration(preset: option.preset))
                } label: {
                    if option.preset == current.preset {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
            Divider()
            Button("Other Agent…") { openSettings() }
        } label: {
            Text("Using \(current.displayName)")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var missingAgent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(configuration.preset == .automatic
                 ? "To find sources, mood. uses a coding agent on this Mac. Install Claude Code and sign in once, then come back here."
                 : "\(configuration.preset == .custom ? "The agent command" : configuration.preset.displayName) wasn't found on this Mac.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if configuration.preset == .automatic {
                    Link("Get Claude Code", destination: Self.installURL)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Use Automatic") { choose(.automatic) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Check Again") { Task { await detect() } }
                Button("Other Agent…") { openSettings() }
                    .buttonStyle(.borderless)
                Button(didCopyPrompt ? "Copied" : "Copy prompt for another agent") {
                    StudyAgentPromptText.copy(for: project)
                    didCopyPrompt = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var stage: StudyStage {
        study.stage(itemCount: store.studyItems(for: project.id).count)
    }

    private func choose(_ newConfiguration: StudyAgentConfiguration) {
        StudyAgentSettings.save(newConfiguration)
        Task { await detect() }
    }

    private func detect() async {
        let current = StudyAgentSettings.load()
        let found = await Task.detached {
            (ResolvedStudyAgent.resolve(current), ResolvedStudyAgent.installed())
        }.value
        configuration = current
        agent = found.0
        installed = found.1
        isDetecting = false
    }

    private func start(_ task: StudyAgentTask) {
        errorMessage = nil
        guard let agent else { return }
        Task {
            do {
                try await runner.start(
                    task: task,
                    project: project,
                    agent: agent,
                    configuration: configuration,
                    repository: store.repository,
                    onProgress: onProgress,
                    onChange: onChange
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
