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

/// The study board's agent controls on the Mac: one row. Idle, a nudge field
/// with Find and Reflect; running, a live count with Steer and Stop. Without
/// an agent, what to install.
struct StudyAgentSection: View {
    let store: LibraryStore
    let project: Project
    let study: ProjectStudy
    /// Called each time the running agent's finds are added.
    var onProgress: @Sendable @MainActor () async -> Void = {}
    /// Called once the agent has exited and everything it proposed is in.
    var onChange: @Sendable @MainActor () async -> Void = {}

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runner = StudyAgentRunner.shared
    @State private var configuration = StudyAgentSettings.load()
    @State private var agent: ResolvedStudyAgent?
    @State private var installed: [ResolvedStudyAgent] = []
    @State private var isDetecting = true
    @State private var errorMessage: String?
    @State private var showsOutput = false
    @State private var nudge = ""

    private static let installURL = URL(string: "https://code.claude.com/docs/en/setup")!

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Stacked, so one state crossfades into the next in place.
            ZStack(alignment: .leading) {
                if runner.redirecting.contains(project.id) {
                    redirectingRow
                        .transition(.opacity)
                } else if let run = runner.run(for: project.id), run.phase == .running {
                    runningRow(run)
                        .transition(.opacity)
                } else if isDetecting {
                    ProgressView().controlSize(.small)
                        .transition(.opacity)
                } else if let agent {
                    idleRow(agent: agent)
                        .transition(.opacity)
                } else {
                    missingAgentRow
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 28)
            .animation(reduceMotion ? nil : StudyBoardMotion.status, value: rowState)

            if let run = runner.run(for: project.id),
               run.phase != .running,
               !runner.redirecting.contains(project.id) {
                lastRunRow(run)
            } else if let note = seedNote, !runner.isBusy(project.id) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
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

    // MARK: Rows

    private func idleRow(agent: ResolvedStudyAgent) -> some View {
        HStack(spacing: 8) {
            nudgeField(prompt: "Nudge it: warmer light, fewer posters…") {
                start(.findSources)
            }

            // One primary action: whichever moves the study on next.
            if reflectsNext {
                findButton
                    .buttonStyle(.bordered)
                reflectButton
                    .buttonStyle(.borderedProminent)
            } else {
                findButton
                    .buttonStyle(.borderedProminent)
                reflectButton
                    .buttonStyle(.bordered)
            }

            Spacer(minLength: 8)

            agentMenu(current: agent)
        }
    }

    private var findButton: some View {
        Button(study.suggestions.isEmpty ? "Find sources" : "Find more") {
            start(.findSources)
        }
        .disabled(stage == .seed)
    }

    private var reflectButton: some View {
        Button("Reflect") {
            start(.reflect)
        }
        .disabled(study.decidedSuggestions.isEmpty)
        .help("Reflect patterns in what you kept and rejected")
    }

    /// Enough verdicts to say something, and nothing waiting to be judged:
    /// reflecting moves the study on more than another search.
    private var reflectsNext: Bool {
        study.decidedSuggestions.count >= ProjectStudy.decisionsBeforeReflection
            && study.pendingSuggestions.isEmpty
            && study.pendingReflections.isEmpty
    }

    private func runningRow(_ run: StudyAgentRunner.Run) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            runningStatus(run)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                // The count ticks over like an odometer as finds land.
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : StudyBoardMotion.status, value: run.result.addedCount)

            Spacer(minLength: 8)

            if run.task == .findSources, let agent {
                nudgeField(prompt: "Steer it somewhere else…") {
                    steer(agent: agent)
                }
                Button("Steer") { steer(agent: agent) }
                    .disabled(StudyAgentNudge.cleaned(nudge) == nil)
                    .help("Start the search again in this direction, keeping what it found")
            }

            outputButton(run)
            Button("Stop") { runner.cancel(project.id) }
        }
    }

    private var redirectingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Changing direction…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Stop") { runner.cancel(project.id) }
        }
    }

    private var missingAgentRow: some View {
        HStack(spacing: 8) {
            Text(missingAgentText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if configuration.preset == .automatic {
                Link("Get Claude Code", destination: Self.installURL)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Use Automatic") { choose(.automatic) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Check Again") { Task { await detect() } }
            Menu {
                Button("Other Agent…") { openSettings() }
                copyPromptButton
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
        }
    }

    private func lastRunRow(_ run: StudyAgentRunner.Run) -> some View {
        HStack(spacing: 6) {
            Image(systemName: lastRunSymbol(run))
                .foregroundStyle(isFailure(run) ? AnyShapeStyle(Color.orange) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .imageScale(.small)
            Text(lastRunText(run))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(lastRunHelp(run))
            outputButton(run)
            Button {
                runner.clear(project.id)
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Pieces

    private func nudgeField(prompt: String, onSubmit: @escaping () -> Void) -> some View {
        TextField("Nudge", text: $nudge, prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 150, idealWidth: 300, maxWidth: 340)
            .onSubmit(onSubmit)
            .help("Optional. Say where to look, and the agent leans that way while staying true to your seeds and verdicts.")
            .accessibilityLabel("Nudge the search")
    }

    private func runningStatus(_ run: StudyAgentRunner.Run) -> Text {
        let action = run.task == .findSources ? "is looking" : "is reflecting"
        var status = "\(run.agentName) \(action) · \(progressCount(run))"
        if let nudge = run.nudge {
            status += " · \u{201C}\(nudge)\u{201D}"
        }
        return Text(status)
            .font(.callout.monospacedDigit())
    }

    /// Which row shows, so changing state animates but typing doesn't.
    private var rowState: String {
        if runner.redirecting.contains(project.id) { return "redirecting" }
        if runner.run(for: project.id)?.phase == .running { return "running" }
        if isDetecting { return "detecting" }
        return agent == nil ? "missing" : "idle"
    }

    private func progressCount(_ run: StudyAgentRunner.Run) -> String {
        switch run.task {
        case .findSources:
            let count = run.result.addedSuggestions
            return count == 0 ? "nothing yet" : "\(count) found"
        case .reflect:
            let count = run.result.addedReflections
            return count == 0 ? "nothing yet" : "\(count) pattern\(count == 1 ? "" : "s")"
        }
    }

    private func lastRunSymbol(_ run: StudyAgentRunner.Run) -> String {
        switch run.phase {
        case .running, .finished: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "stop.circle"
        }
    }

    private func isFailure(_ run: StudyAgentRunner.Run) -> Bool {
        if case .failed = run.phase { return true }
        return false
    }

    private func lastRunText(_ run: StudyAgentRunner.Run) -> String {
        let tally = Self.tally(run.result)
        switch run.phase {
        case .running, .finished:
            return "\(run.agentName): \(tally ?? "nothing new")"
        case .cancelled:
            return tally.map { "Stopped · \($0)" } ?? "Stopped"
        case .failed:
            let kept = tally.map { " · \($0)" } ?? ""
            return "\(run.agentName) stopped with an error\(kept). Not signed in? Open it in Terminal once."
        }
    }

    private func lastRunHelp(_ run: StudyAgentRunner.Run) -> String {
        if case .failed(let message) = run.phase {
            return "\(message) \(run.result.summary)"
        }
        return run.result.summary
    }

    /// "7 new finds · 2 skipped", or nil when nothing came of the run.
    private static func tally(_ result: StudyAgentHandoffResult) -> String? {
        var parts: [String] = []
        if result.addedSuggestions > 0 {
            parts.append("\(result.addedSuggestions) new find\(result.addedSuggestions == 1 ? "" : "s")")
        }
        if result.addedReflections > 0 {
            parts.append("\(result.addedReflections) pattern\(result.addedReflections == 1 ? "" : "s")")
        }
        let skipped = result.skipped.count + result.unusableFiles.count + result.overLimit
        if skipped > 0 {
            parts.append("\(skipped) skipped")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
            copyPromptButton
        } label: {
            Text(current.displayName)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("The agent that searches. Choose another, or copy a prompt for one mood. doesn't start.")
    }

    private var copyPromptButton: some View {
        Button("Copy Prompt for Another Agent") {
            StudyAgentPromptText.copy(for: project, nudge: nudge)
        }
    }

    private var missingAgentText: String {
        switch configuration.preset {
        case .automatic: "Finding sources needs Claude Code or Codex on this Mac."
        case .custom: "The agent command wasn't found."
        case .claudeCode, .codex: "\(configuration.preset.displayName) isn't installed."
        }
    }

    private var stage: StudyStage {
        study.stage(itemCount: store.studyItems(for: project.id).count)
    }

    private var seedNote: String? {
        guard stage == .seed, agent != nil else { return nil }
        let remaining = max(1, ProjectStudy.minimumSeedCount - store.studyItems(for: project.id).count)
        return "Add \(remaining) more seed\(remaining == 1 ? "" : "s") to the moodboard first."
    }

    // MARK: Actions

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
        guard let agent, !(task == .findSources && stage == .seed) else { return }
        errorMessage = nil
        let direction = nudge
        nudge = ""
        Task {
            do {
                try await runner.start(
                    task: task,
                    project: project,
                    agent: agent,
                    configuration: configuration,
                    repository: store.repository,
                    nudge: direction,
                    onProgress: onProgress,
                    onChange: onChange
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func steer(agent: ResolvedStudyAgent) {
        guard StudyAgentNudge.cleaned(nudge) != nil else { return }
        errorMessage = nil
        let direction = nudge
        nudge = ""
        Task {
            do {
                try await runner.redirect(
                    task: .findSources,
                    project: project,
                    agent: agent,
                    configuration: configuration,
                    repository: store.repository,
                    nudge: direction,
                    onProgress: onProgress,
                    onChange: onChange
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
