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


/// The study's agent on the Mac: a glass capsule in the canvas chrome, beside
/// the board switch, that says what the agent is doing or what it can do
/// next. Clicking it opens a card to nudge and start it, steer or stop it
/// while it looks, and choose which agent searches. Without an agent, the
/// card says what to install.
struct StudyAgentControl: View {
    let store: LibraryStore
    let project: Project
    let study: ProjectStudy
    /// Called each time the running agent's finds are added.
    var onProgress: @Sendable @MainActor () async -> Void = {}
    /// Called once the agent has exited and everything it proposed is in.
    var onChange: @Sendable @MainActor () async -> Void = {}
    /// Called when the finds still to judge are rejected to make way for a
    /// fresh search.
    var onRefresh: () -> Void = {}

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runner = StudyAgentRunner.shared
    @State private var configuration = StudyAgentSettings.load()
    @State private var agent: ResolvedStudyAgent?
    @State private var installed: [ResolvedStudyAgent] = []
    @State private var isDetecting = true
    @State private var errorMessage: String?
    @State private var showsOutput = false
    @State private var isPresented = false
    @State private var nudge = ""

    private static let installURL = URL(string: "https://code.claude.com/docs/en/setup")!
    private static let cardWidth: CGFloat = 304

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            capsuleLabel
        }
        .buttonStyle(.plain)
        .floatingGlassCapsule()
        .contentShape(Capsule())
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            card
        }
        .help(capsuleHelp)
        .accessibilityLabel(capsuleTitle)
        .accessibilityHint("Shows the study agent")
        .animation(reduceMotion ? nil : StudyBoardMotion.status, value: capsuleTitle)
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

    // MARK: Capsule

    private var capsuleLabel: some View {
        HStack(spacing: 6) {
            capsuleGlyph
                .frame(width: 14, height: 14)
            Text(capsuleTitle)
                .lineLimit(1)
                // The count ticks over like an odometer as finds land.
                .contentTransition(.numericText())
        }
        .font(GlassSegmentMetrics.font)
        .foregroundStyle(.primary)
        // The glyph's side reads tighter than the text's, so it gets less.
        .padding(.leading, 11)
        .padding(.trailing, 13)
        .frame(height: GlassSegmentMetrics.height)
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var capsuleGlyph: some View {
        if runner.isBusy(project.id) {
            ProgressView()
                .controlSize(.mini)
        } else if let run = finishedRun, isFailure(run) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "sparkles")
        }
    }

    /// What the agent is doing, or what it would do next.
    private var capsuleTitle: String {
        if runner.redirecting.contains(project.id) { return "Changing direction…" }
        if let run = runningRun {
            switch run.task {
            case .findSources:
                let count = run.result.addedSuggestions
                return count == 0 ? "\(run.agentName) is looking" : "\(run.agentName) · \(count) found"
            case .reflect:
                return "\(run.agentName) is reflecting"
            }
        }
        if let run = finishedRun {
            let added = run.result.addedSuggestions + run.result.addedReflections
            switch run.phase {
            case .running, .finished:
                return added == 0 ? "\(run.agentName) · nothing new" : "\(run.agentName) · \(added) new"
            case .cancelled:
                return added == 0 ? "Stopped" : "Stopped · \(added) new"
            case .failed:
                return "\(run.agentName) stopped"
            }
        }
        if !isDetecting, agent == nil { return "Set up an agent" }
        return nextActionTitle
    }

    private var capsuleHelp: String {
        if let run = finishedRun { return lastRunHelp(run) }
        return "The agent that finds sources and reflects patterns for this study"
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isDetecting {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if runner.redirecting.contains(project.id) {
                StudyAgentCardHeading(title: "Changing direction…", message: "It keeps what it found so far.")
                stopButton
            } else if let run = runningRun {
                runningCard(run)
            } else if let agent {
                idleCard(agent: agent)
            } else {
                missingAgentCard
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isDetecting {
                Divider()
                footer
            }
        }
        .padding(16)
        .frame(width: Self.cardWidth)
        .animation(reduceMotion ? nil : StudyBoardMotion.status, value: rowState)
    }

    @ViewBuilder
    private func idleCard(agent: ResolvedStudyAgent) -> some View {
        StudyAgentCardHeading(title: idleTitle, message: idleMessage(agent: agent))

        if let run = finishedRun {
            lastRunRow(run)
        }

        StudyNudgeWell(text: $nudge, prompt: "Nudge it: warmer light, fewer posters…") {
            start(reflectsNext ? .reflect : .findSources)
        }
        .disabled(stage == .seed)

        // One primary action: whichever moves the study on next.
        StudyAgentPrimaryButton(nextActionTitle) {
            start(reflectsNext ? .reflect : .findSources)
        }
        .disabled(reflectsNext ? study.decidedSuggestions.isEmpty : stage == .seed)

        let secondary = secondaryActions
        if !secondary.isEmpty {
            HStack(spacing: 16) {
                ForEach(secondary, id: \.title) { action in
                    Button(action.title, action: action.perform)
                        .help(action.help)
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func runningCard(_ run: StudyAgentRunner.Run) -> some View {
        StudyAgentCardHeading(
            title: run.task == .findSources ? "\(run.agentName) is looking" : "\(run.agentName) is reflecting",
            message: runningMessage(run)
        )
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : StudyBoardMotion.status, value: run.result.addedCount)

        if run.task == .findSources, let agent {
            StudyNudgeWell(text: $nudge, prompt: "Steer it somewhere else…") {
                steer(agent: agent)
            } accessory: {
                if StudyAgentNudge.cleaned(nudge) != nil {
                    Button("Steer") { steer(agent: agent) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Start the search again in this direction, keeping what it found")
                        .transition(.opacity)
                }
            }
        }

        stopButton
    }

    private var stopButton: some View {
        Button {
            runner.cancel(project.id)
        } label: {
            Text("Stop")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private var missingAgentCard: some View {
        StudyAgentCardHeading(title: "Set up an agent", message: missingAgentText)

        if configuration.preset == .automatic {
            Link(destination: Self.installURL) {
                Text("Get Claude Code")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            StudyAgentPrimaryButton("Use Automatic") { choose(.automatic) }
        }

        Button("Check Again") { Task { await detect() } }
            .buttonStyle(.borderless)
            .font(.callout)
            .frame(maxWidth: .infinity)
    }

    private func lastRunRow(_ run: StudyAgentRunner.Run) -> some View {
        HStack(spacing: 6) {
            Image(systemName: lastRunSymbol(run))
                .foregroundStyle(isFailure(run) ? AnyShapeStyle(Color.orange) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .imageScale(.small)
            Text(lastRunText(run))
                .fixedSize(horizontal: false, vertical: true)
                .help(lastRunHelp(run))
            Spacer(minLength: 4)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// The agent in use and where else to send the study.
    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(installed, id: \.preset) { option in
                    Button {
                        choose(StudyAgentConfiguration(preset: option.preset))
                    } label: {
                        if option.preset == agent?.preset {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
                if !installed.isEmpty {
                    Divider()
                }
                Button("Other Agent…") { openSettings() }
                Button("Copy Prompt for Another Agent") {
                    StudyAgentPromptText.copy(for: project, nudge: nudge)
                }
            } label: {
                Text(agent?.displayName ?? "Agent")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("The agent that searches. Choose another, or copy a prompt for one mood. doesn't start.")

            Spacer(minLength: 8)

            if let run = runner.run(for: project.id), !run.output.isEmpty {
                Button("Output") { showsOutput.toggle() }
                    .buttonStyle(.borderless)
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
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Words

    private var nextActionTitle: String {
        if reflectsNext { return "Reflect" }
        return study.suggestions.isEmpty ? "Find sources" : "Find more"
    }

    private var idleTitle: String {
        if reflectsNext { return "Reflect on your verdicts" }
        return study.suggestions.isEmpty ? "Find sources" : "Look for more"
    }

    private func idleMessage(agent: ResolvedStudyAgent) -> String {
        if let seedNote { return seedNote }
        if reflectsNext {
            return "Everything's judged. \(agent.displayName) can say what your \(study.decidedSuggestions.count) verdicts have in common."
        }
        if study.suggestions.isEmpty {
            return "\(agent.displayName) looks for real, credited work that fits your seeds. You keep or reject each find."
        }
        let decided = study.decidedSuggestions.count
        let pending = study.pendingSuggestions.count
        let steer = decided == 0
            ? "Keep or reject finds to steer the next search."
            : "Your \(decided) verdict\(decided == 1 ? "" : "s") steer the next search."
        return pending == 0 ? steer : "\(pending) still to judge. \(steer)"
    }

    private func runningMessage(_ run: StudyAgentRunner.Run) -> String {
        var message: String
        switch run.task {
        case .findSources:
            let count = run.result.addedSuggestions
            message = count == 0 ? "Nothing yet. Finds appear on the board as they land." : "\(count) found so far."
        case .reflect:
            let count = run.result.addedReflections
            message = count == 0
                ? "Looking for patterns in what you kept and rejected."
                : "\(count) pattern\(count == 1 ? "" : "s") so far."
        }
        if let nudge = run.nudge {
            message += " Leaning \u{201C}\(nudge)\u{201D}."
        }
        return message
    }

    /// The other things worth doing from here, kept quiet.
    private var secondaryActions: [SecondaryAction] {
        var actions: [SecondaryAction] = []
        if reflectsNext {
            actions.append(SecondaryAction(title: "Find more", help: "Look for more sources") {
                start(.findSources)
            })
        } else if !study.decidedSuggestions.isEmpty {
            actions.append(SecondaryAction(title: "Reflect", help: "Reflect patterns in what you kept and rejected") {
                start(.reflect)
            })
        }
        let pending = study.pendingSuggestions.count
        if pending > 0, stage != .seed {
            actions.append(SecondaryAction(
                title: "Reject \(pending) and look again",
                help: "Reject the \(pending) still to judge and find new ones",
                perform: refresh
            ))
        }
        return actions
    }

    private struct SecondaryAction {
        let title: String
        let help: String
        let perform: () -> Void
    }

    private var missingAgentText: String {
        switch configuration.preset {
        case .automatic: "Finding sources needs Claude Code or Codex on this Mac."
        case .custom: "The agent command wasn't found."
        case .claudeCode, .codex: "\(configuration.preset.displayName) isn't installed."
        }
    }

    private var seedNote: String? {
        guard stage == .seed else { return nil }
        let remaining = max(1, ProjectStudy.minimumSeedCount - store.studyItems(for: project.id).count)
        return "Add \(remaining) more seed\(remaining == 1 ? "" : "s") to the moodboard first."
    }

    private func lastRunSymbol(_ run: StudyAgentRunner.Run) -> String {
        switch run.phase {
        case .running, .finished: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "stop.circle"
        }
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

    // MARK: State

    private var runningRun: StudyAgentRunner.Run? {
        guard let run = runner.run(for: project.id), run.phase == .running else { return nil }
        return run
    }

    /// The last run, once it has ended, until it's dismissed.
    private var finishedRun: StudyAgentRunner.Run? {
        guard let run = runner.run(for: project.id),
              run.phase != .running,
              !runner.redirecting.contains(project.id) else { return nil }
        return run
    }

    private func isFailure(_ run: StudyAgentRunner.Run) -> Bool {
        if case .failed = run.phase { return true }
        return false
    }

    /// Enough verdicts to say something, and nothing waiting to be judged:
    /// reflecting moves the study on more than another search.
    private var reflectsNext: Bool {
        study.decidedSuggestions.count >= ProjectStudy.decisionsBeforeReflection
            && study.pendingSuggestions.isEmpty
            && study.pendingReflections.isEmpty
    }

    /// Which card shows, so changing state animates but typing doesn't.
    private var rowState: String {
        if runner.redirecting.contains(project.id) { return "redirecting" }
        if runningRun != nil { return "running" }
        if isDetecting { return "detecting" }
        return agent == nil ? "missing" : "idle"
    }

    private var stage: StudyStage {
        study.stage(itemCount: store.studyItems(for: project.id).count)
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

    /// Starts the agent and closes the card, so what it finds can be seen
    /// developing on the board.
    private func start(_ task: StudyAgentTask) {
        guard let agent, !(task == .findSources && stage == .seed) else { return }
        errorMessage = nil
        let direction = nudge
        nudge = ""
        isPresented = false
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
                isPresented = true
            }
        }
    }

    /// Rejects the finds still to judge, so the search knows not to bring
    /// them back, then looks again with whatever nudge is typed.
    private func refresh() {
        guard agent != nil, stage != .seed else { return }
        errorMessage = nil
        Task {
            do {
                try await store.rejectPendingStudySuggestions(projectID: project.id)
                onRefresh()
                start(.findSources)
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
        isPresented = false
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
                isPresented = true
            }
        }
    }
}
