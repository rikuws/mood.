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
            "mood. starts the agent with its bundled mood-study skill and a copy of your study. When it finishes, mood. checks what it proposed and adds what passes for you to judge. The agent never touches your library, and you keep or reject everything."
        case .custom:
            "mood. starts this command in a scratch folder holding study.json. The prompt points it at the bundled mood-study skill and asks it to write suggestions.json or reflections.json there. When it exits, mood. checks that file and adds what passes for you to judge. The agent needs no access to your library."
        }
    }
}

/// The study panel's agent controls on the Mac. With an agent installed this
/// is one button; without one, it says what to install.
struct StudyAgentSection: View {
    let store: LibraryStore
    let project: Project
    let study: ProjectStudy
    var onChange: @Sendable @MainActor () async -> Void = {}

    @Environment(\.openSettings) private var openSettings
    @State private var runner = StudyAgentRunner.shared
    @State private var configuration = StudyAgentSettings.load()
    @State private var agent: ResolvedStudyAgent?
    @State private var installed: [ResolvedStudyAgent] = []
    @State private var isDetecting = true
    @State private var errorMessage: String?
    @State private var showsOutput = false

    private static let installURL = URL(string: "https://code.claude.com/docs/en/setup")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("An agent on this Mac looks for real, credited work related to your seeds and notes, and later reflects the patterns in your verdicts. It adds proposals here for you to judge. It never generates images, and it won't suggest anything you've rejected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let run = runner.run(for: project.id) {
                runStatus(run)
            }

            if isDetecting {
                ProgressView().controlSize(.small)
            } else if agent == nil, !runner.isRunning(project.id) {
                missingAgent
            } else {
                controls
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
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
                if runner.isRunning(project.id) {
                    Button("Stop") { runner.cancel(project.id) }
                } else {
                    Button("Find sources") { start(.findSources) }
                        .buttonStyle(.borderedProminent)
                        .disabled(stage == .seed)
                    Button("Reflect patterns") { start(.reflect) }
                        .disabled(study.decidedSuggestions.isEmpty)
                        .help("Available once you've kept or rejected a source.")
                }
                Spacer()
                if let agent {
                    agentMenu(current: agent)
                }
            }

            if stage == .seed, !runner.isRunning(project.id) {
                Text("Add at least \(ProjectStudy.minimumSeedCount) seeds before asking for sources, so the agent has your taste to go on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var items: [Inspiration] {
        store.studyItems(for: project.id)
    }

    private var stage: StudyStage {
        study.stage(itemCount: items.count)
    }

    @ViewBuilder
    private func runStatus(_ run: StudyAgentRunner.Run) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                switch run.phase {
                case .running:
                    ProgressView().controlSize(.small)
                    Text("\(run.agentName) is working: \(run.task.displayName.lowercased()). This can take several minutes. What it proposes appears below when it's done.")
                case .finished(let summary):
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text("\(run.agentName) finished. \(summary)")
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("\(message) If \(run.agentName) isn't signed in yet, open it in Terminal once to sign in.")
                case .cancelled:
                    Image(systemName: "stop.circle").foregroundStyle(.secondary)
                    Text("Stopped. Nothing was added.")
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            if !run.output.isEmpty {
                DisclosureGroup("Agent output", isExpanded: $showsOutput) {
                    ScrollView {
                        Text(run.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    onChange: onChange
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
