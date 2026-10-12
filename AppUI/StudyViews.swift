import PinaxCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Subject and brief for a new or existing visual study.
struct StudyStartForm: View {
    let existingProject: Project?
    let onStart: (_ subject: String, _ brief: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var subject: String
    @State private var brief: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        existingProject: Project? = nil,
        onStart: @escaping (_ subject: String, _ brief: String) async throws -> Void
    ) {
        self.existingProject = existingProject
        self.onStart = onStart
        _subject = State(initialValue: existingProject?.study?.subject ?? existingProject?.name ?? "")
        _brief = State(initialValue: existingProject?.study?.brief ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("What are you studying?", text: $subject, prompt: Text("2001: A Space Odyssey"))
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("What draws you to it? (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "Brief",
                    text: $brief,
                    prompt: Text("The cold white interiors, how empty the frames are"),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : actionTitle) {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedSubject.isEmpty || isSaving)
            }
        }
        .padding(22)
        #if os(macOS)
        .frame(width: 420)
        #endif
    }

    private var title: String {
        if existingProject?.study != nil { return "Edit study" }
        return existingProject == nil ? "New visual study" : "Start a study"
    }

    private var actionTitle: String {
        existingProject?.study != nil ? "Save" : "Start study"
    }

    private var explanation: String {
        if let existingProject, existingProject.study == nil {
            return "The items already in \(existingProject.name) become your seeds. Real sources are suggested for you to keep or reject; nothing is generated."
        }
        return "Seed it with a few things you already love. Real sources are suggested for you to keep or reject; nothing is generated."
    }

    private var trimmedSubject: String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func save() async {
        guard !trimmedSubject.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onStart(trimmedSubject, brief)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The guided study surface: what to do next, real sources waiting for a
/// verdict, patterns waiting for confirmation, and the history of decisions.
struct StudyPanel: View {
    let store: LibraryStore
    let projectID: Project.ID
    var onMutation: () -> Void = {}
    var onEdit: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var didCopyPrompt = false

    var body: some View {
        Group {
            if let project, let study = project.study {
                content(project: project, study: study)
            } else {
                ContentUnavailableView(
                    "No study",
                    systemImage: "eye",
                    description: Text("This project is no longer a visual study.")
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 680)
        #endif
    }

    private var project: Project? {
        store.snapshot.project(id: projectID)
    }

    private var items: [Inspiration] {
        store.studyItems(for: projectID)
    }

    @ViewBuilder
    private func content(project: Project, study: ProjectStudy) -> some View {
        let stage = study.stage(itemCount: items.count)

        VStack(spacing: 0) {
            header(project: project, study: study)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StudyStageGuide(stage: stage, itemCount: items.count)

                    if let errorMessage {
                        Text(errorMessage).font(.callout).foregroundStyle(.red)
                    }

                    findSection(project: project, study: study)

                    if !study.pendingReflections.isEmpty {
                        section("Patterns to check") {
                            ForEach(study.pendingReflections) { reflection in
                                StudyReflectionRow(
                                    reflection: reflection,
                                    citedTitles: citedTitles(for: reflection, in: study),
                                    onRespond: { respond(to: reflection, with: $0) }
                                )
                            }
                        }
                    }

                    if !study.pendingSuggestions.isEmpty {
                        section("Sources to judge") {
                            ForEach(study.pendingSuggestions) { suggestion in
                                StudySuggestionRow(
                                    suggestion: suggestion,
                                    basedOnTitles: titles(for: suggestion.basedOnInspirationIDs),
                                    onDecide: { decide(suggestion, verdict: $0, reason: $1) }
                                )
                            }
                        }
                    }

                    acceptedPatterns(study: study)
                    decisionHistory(study: study)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func header(project: Project, study: ProjectStudy) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Visual study")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(study.subject)
                    .font(.title2.weight(.semibold))
                if !study.brief.isEmpty {
                    Text(study.brief)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button("Edit", action: onEdit)
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private func findSection(project: Project, study: ProjectStudy) -> some View {
        section("Find inspirations") {
            Text("An agent looks for real, credited work related to your seeds and notes, and adds it here for you to judge. It never generates images, and it won't suggest anything you've rejected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(didCopyPrompt ? "Copied" : "Copy prompt for your agent") {
                    copyToClipboard(Self.agentPrompt(for: project, study: study))
                    didCopyPrompt = true
                }
                Text("Paste it into Claude Code or another agent with the mood-study skill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func acceptedPatterns(study: ProjectStudy) -> some View {
        let accepted = study.reflections.filter { $0.acceptedStatement != nil }
        if !accepted.isEmpty {
            section("Your patterns") {
                ForEach(accepted) { reflection in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reflection.acceptedStatement ?? "")
                        if reflection.status == .corrected {
                            Text("Corrected from: \(reflection.statement)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func decisionHistory(study: ProjectStudy) -> some View {
        let kept = study.suggestions.filter { $0.status == .kept }
        let rejected = study.suggestions.filter { $0.status == .rejected }
        if !kept.isEmpty || !rejected.isEmpty {
            section("Your verdicts") {
                if !kept.isEmpty {
                    DisclosureGroup("Kept (\(kept.count))") {
                        ForEach(kept) { suggestion in
                            StudyDecisionRow(suggestion: suggestion)
                        }
                    }
                }
                if !rejected.isEmpty {
                    DisclosureGroup("Rejected (\(rejected.count))") {
                        ForEach(rejected) { suggestion in
                            StudyDecisionRow(
                                suggestion: suggestion,
                                onReconsider: { decide(suggestion, verdict: .keep, reason: suggestion.reason) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func titles(for ids: [Inspiration.ID]) -> [String] {
        ids.compactMap { id in items.first(where: { $0.id == id }) }
            .map { $0.title.isEmpty ? ($0.url.host() ?? "Untitled") : $0.title }
    }

    private func citedTitles(for reflection: StudyReflection, in study: ProjectStudy) -> [String] {
        let kept = titles(for: reflection.inspirationIDs)
        let rejected = reflection.rejectedSuggestionIDs.compactMap { id in
            study.suggestions.first(where: { $0.id == id }).map { "Rejected: \($0.title)" }
        }
        return kept + rejected
    }

    private func decide(_ suggestion: StudySuggestion, verdict: StudyVerdict, reason: String?) {
        Task { @MainActor in
            do {
                try await store.decideStudySuggestion(
                    projectID: projectID,
                    suggestionID: suggestion.id,
                    verdict: verdict,
                    reason: reason
                )
                errorMessage = nil
                onMutation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func respond(to reflection: StudyReflection, with response: StudyReflectionResponse) {
        Task { @MainActor in
            do {
                try await store.respondToStudyReflection(
                    projectID: projectID,
                    reflectionID: reflection.id,
                    response: response
                )
                errorMessage = nil
                onMutation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    static func agentPrompt(for project: Project, study: ProjectStudy) -> String {
        "Use the mood-study skill to find inspirations for my mood. study \"\(project.name)\" (project \(project.id.uuidString)). Suggest only real, credited work, tie each one to my seeds and notes, and add them with `mood-agent suggest` so I can keep or reject them in mood."
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

private struct StudyStageGuide: View {
    let stage: StudyStage
    let itemCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var symbol: String {
        switch stage {
        case .seed: "leaf"
        case .explore: "binoculars"
        case .reflect: "text.bubble"
        case .distill: "checkmark.seal"
        }
    }

    private var title: String {
        switch stage {
        case .seed: "Seed it with what you love"
        case .explore: "Judge real sources"
        case .reflect: "Check the patterns"
        case .distill: "Ready to distill"
        }
    }

    private var detail: String {
        switch stage {
        case .seed:
            let remaining = max(0, ProjectStudy.minimumSeedCount - itemCount)
            return "Add \(remaining) more piece\(remaining == 1 ? "" : "s") you already love: a still, a screenshot, an object, a typeface. Note what you love about each one."
        case .explore:
            return "Keep or reject each suggestion and say why. Rejections count as much as keeps."
        case .reflect:
            return "Confirm the patterns that are true to you, and correct the ones that aren't quite right."
        case .distill:
            return "Your confirmed patterns and verdicts are ready for mood-distill to turn into a design language."
        }
    }
}

private struct StudySuggestionRow: View {
    let suggestion: StudySuggestion
    let basedOnTitles: [String]
    let onDecide: (StudyVerdict, String?) -> Void

    @State private var reason = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DownsampledPreviewImage(
                localURL: nil,
                remoteURL: suggestion.imageURL,
                placeholder: { thumbnailBackground },
                failure: {
                    thumbnailBackground.overlay {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
            )
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Link(destination: suggestion.url) {
                    Text(suggestion.title)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.leading)
                }
                Text(attribution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggestion.rationale)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if !basedOnTitles.isEmpty {
                    Text("Related to \(basedOnTitles.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Why? Your reason is the taste data", text: $reason, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Keep") { onDecide(.keep, reason) }
                        .buttonStyle(.borderedProminent)
                    Button("Reject") { onDecide(.reject, reason) }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var attribution: String {
        [suggestion.creator, suggestion.sourceName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var thumbnailBackground: some View {
        Rectangle().fill(.quaternary)
    }
}

private struct StudyReflectionRow: View {
    let reflection: StudyReflection
    let citedTitles: [String]
    let onRespond: (StudyReflectionResponse) -> Void

    @State private var isCorrecting = false
    @State private var correction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“\(reflection.statement)”")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if !citedTitles.isEmpty {
                Text("Seen in \(citedTitles.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isCorrecting {
                TextField("How would you put it?", text: $correction, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save correction") { onRespond(.correct(correction)) }
                        .buttonStyle(.borderedProminent)
                        .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") { isCorrecting = false }
                }
            } else {
                HStack {
                    Button("That's right") { onRespond(.confirm) }
                        .buttonStyle(.borderedProminent)
                    Button("Correct it") {
                        correction = reflection.statement
                        isCorrecting = true
                    }
                    Button("Not me") { onRespond(.dismiss) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StudyDecisionRow: View {
    let suggestion: StudySuggestion
    var onReconsider: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Link(suggestion.title, destination: suggestion.url)
                Text(suggestion.reason.map { "“\($0)”" } ?? "No reason given")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onReconsider {
                Button("Keep instead", action: onReconsider)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
