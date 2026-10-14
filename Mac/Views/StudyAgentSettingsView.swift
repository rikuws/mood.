import PinaxCore
import SwiftUI

/// Settings › Study Agent: which coding agent mood. starts for a study.
struct StudyAgentSettingsView: View {
    @State private var configuration = StudyAgentSettings.load()
    @State private var resolvedPath: String?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                Picker("Agent", selection: presetBinding) {
                    ForEach(StudyAgentConfiguration.Preset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                TextField(
                    "Command",
                    text: $configuration.executable,
                    prompt: Text(configuration.preset == .claudeCode ? "claude" : "/path/to/agent")
                )
                .font(.system(.body, design: .monospaced))

                if configuration.preset == .custom {
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
                    } else if let resolvedPath {
                        Label(resolvedPath, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Label("Not found", systemImage: "exclamationmark.triangle.fill")
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
            await check()
        }
    }

    private var presetBinding: Binding<StudyAgentConfiguration.Preset> {
        Binding(
            get: { configuration.preset },
            set: { preset in
                guard preset != configuration.preset else { return }
                configuration = preset == .claudeCode ? .claudeCode : .customTemplate
            }
        )
    }

    private var footer: String {
        switch configuration.preset {
        case .claudeCode:
            "mood. starts Claude Code with the bundled mood-study skill. It may read your study, search the web, and add pending sources and patterns through mood-agent. It can't run other programs or write outside its scratch folder, so the only library change it can make is a pending proposal. You keep or reject everything."
        case .custom:
            "mood. starts this command in a scratch folder with a prompt that points at the bundled mood-study skill and mood-agent helper. Give it only the permissions it needs; it should add pending proposals through mood-agent suggest and reflect, and you keep or reject everything."
        }
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        let command = configuration.trimmedExecutable
        guard !command.isEmpty else {
            resolvedPath = nil
            return
        }
        resolvedPath = await Task.detached {
            StudyAgentExecutableLocator.resolve(command)?.path
        }.value
    }
}

/// The study panel's agent controls on the Mac: start the connected agent,
/// watch what it's doing, and stop it.
struct StudyAgentSection: View {
    let store: LibraryStore
    let project: Project
    let study: ProjectStudy
    var onChange: @Sendable @MainActor (_ isFinal: Bool) async -> Void = { _ in }

    @State private var runner = StudyAgentRunner.shared
    @State private var errorMessage: String?
    @State private var showsOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("An agent you connect looks for real, credited work related to your seeds and notes, and later reflects the patterns in your verdicts. It adds proposals here for you to judge. It never generates images, and it won't suggest anything you've rejected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let run = runner.run(for: project.id) {
                runStatus(run)
            }

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
                SettingsLink {
                    Text("Agent: \(agentName)")
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if stage == .seed, !runner.isRunning(project.id) {
                Text("Add at least \(ProjectStudy.minimumSeedCount) seeds before asking for sources, so the agent has your taste to go on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .task {
            _ = await Task.detached { StudyAgentExecutableLocator.searchPath() }.value
        }
    }

    private var items: [Inspiration] {
        store.studyItems(for: project.id)
    }

    private var stage: StudyStage {
        study.stage(itemCount: items.count)
    }

    private var agentName: String {
        let configuration = StudyAgentSettings.load()
        switch configuration.preset {
        case .claudeCode: return "Claude Code"
        case .custom:
            let command = configuration.trimmedExecutable
            return command.isEmpty ? "not set" : (command as NSString).lastPathComponent
        }
    }

    @ViewBuilder
    private func runStatus(_ run: StudyAgentRunner.Run) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                switch run.phase {
                case .running:
                    ProgressView().controlSize(.small)
                    Text("\(run.agentName) is working: \(run.task.displayName.lowercased()). New proposals appear below as it adds them.")
                case .finished:
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text("\(run.agentName) finished. Judge what it added below.")
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(message)
                case .cancelled:
                    Image(systemName: "stop.circle").foregroundStyle(.secondary)
                    Text("Stopped. Anything it already added is waiting below.")
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

    private func start(_ task: StudyAgentTask) {
        errorMessage = nil
        do {
            try runner.start(
                task: task,
                project: project,
                configuration: StudyAgentSettings.load(),
                onChange: onChange
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
