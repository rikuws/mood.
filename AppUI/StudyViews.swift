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

// MARK: - Board header

/// The top of the study board: the subject in the person's own words, what
/// to do next, the agent's controls, and the verdict filters with counts.
struct StudyBoardHeader<Controls: View>: View {
    let study: ProjectStudy
    let itemCount: Int
    let board: StudyBoard
    @Binding var filter: StudyBoardFilter
    var onEdit: (() -> Void)?
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Visual study")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let onEdit {
                        Button("Edit study", action: onEdit)
                            .buttonStyle(.borderless)
                            .font(.callout)
                    }
                }
                Text(study.subject)
                    .font(StudyBoardType.subject)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                if !study.brief.isEmpty {
                    Text(study.brief)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)

            StudyStageLine(stage: study.stage(itemCount: itemCount), itemCount: itemCount)

            controls()

            StudyBoardFilterBar(selection: $filter, board: board)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What to do next, in one glance. Stages only guide; nothing is locked.
struct StudyStageLine: View {
    let stage: StudyStage
    let itemCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .accessibilityElement(children: .combine)
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
            return "Add \(remaining) more piece\(remaining == 1 ? "" : "s") you already love to the moodboard: a still, a screenshot, an object, a typeface. Note what you love about each one."
        case .explore:
            return "Keep or reject each find and say why. Rejections count as much as keeps."
        case .reflect:
            return "Confirm the patterns that are true to you, and correct the ones that aren't quite right."
        case .distill:
            return "Your confirmed patterns and verdicts are ready for mood-distill to turn into a design language."
        }
    }
}

/// Text-first verdict filters: the current one is semibold with an ink
/// underline, counts are quiet monospaced digits.
struct StudyBoardFilterBar: View {
    @Binding var selection: StudyBoardFilter
    let board: StudyBoard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 18) {
            ForEach(StudyBoardFilter.allCases, id: \.self) { filter in
                let count = board.count(for: filter)
                let isSelected = selection == filter
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        selection = filter
                    }
                } label: {
                    VStack(spacing: 5) {
                        HStack(spacing: 5) {
                            Text(filter.title)
                            Text("\(count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Capsule()
                            .fill(isSelected ? Color.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    #if os(iOS)
                    .frame(minHeight: 44)
                    #endif
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.title), \(count)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Shown where cards would be when there are none to show.
struct StudyBoardEmptyState: View {
    let stage: StudyStage
    let filter: StudyBoardFilter
    let boardIsEmpty: Bool
    let isSearchingText: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if isSearchingText { return "No findings match" }
        if boardIsEmpty { return stage == .seed ? "Seed your study first" : "Nothing found yet" }
        switch filter {
        case .all: return "Nothing found yet"
        case .toJudge: return "Nothing to judge"
        case .kept: return "Nothing kept yet"
        case .rejected: return "Nothing rejected yet"
        }
    }

    private var message: String {
        if isSearchingText { return "Try a title, a creator, or words from a reason." }
        if boardIsEmpty {
            return stage == .seed
                ? "Add at least \(ProjectStudy.minimumSeedCount) things you already love to the moodboard, with a note on each. Then ask for sources: they appear here as they're found."
                : "Ask for sources, and real, credited work related to your seeds appears here as it's found."
        }
        switch filter {
        case .all: return "Ask for sources, and real, credited work appears here as it's found."
        case .toJudge: return "Everything here has your verdict. Ask for more sources when you're ready."
        case .kept: return "What you keep goes to the moodboard and stays here, marked kept."
        case .rejected: return "Rejections count as much as keeps: they steer what's found next."
        }
    }
}

enum StudyBoardType {
    static var subject: Font {
        #if os(macOS)
        return .system(size: 30, weight: .semibold, design: .serif)
        #else
        return .system(.title, design: .serif, weight: .bold)
        #endif
    }

    static var closeLookTitle: Font {
        #if os(macOS)
        return .system(size: 24, weight: .semibold, design: .serif)
        #else
        return .system(.title2, design: .serif, weight: .semibold)
        #endif
    }
}

// MARK: - Board cards

/// Density-aware measurements shared by the board's own cards, matching the
/// moodboard's white mat at the same column count.
enum StudyCardMetrics {
    static func matInset(_ columns: Int) -> CGFloat {
        switch columns {
        case ...1: 10
        case 2: 8
        case 3: 6
        case 4: 5
        case 5: 4
        default: 3
        }
    }

    static func cornerRadius(_ columns: Int) -> CGFloat {
        switch columns {
        case ...1: 5
        case 2...3: 4
        default: 3
        }
    }

    static func innerCornerRadius(_ columns: Int) -> CGFloat {
        max(1, cornerRadius(columns) - 2)
    }

    static func padding(_ columns: Int) -> CGFloat {
        switch columns {
        case ...1: 26
        case 2: 20
        case 3: 15
        case 4: 12
        case 5: 9
        default: 7
        }
    }

    static func statementSize(_ columns: Int) -> CGFloat {
        switch columns {
        case ...1: 24
        case 2: 19
        case 3: 16
        case 4: 13
        case 5: 11.5
        case 6: 10.5
        default: 9.5
        }
    }

    static func lineLimit(_ columns: Int) -> Int {
        switch columns {
        case ...1: 8
        case 2: 7
        case 3: 6
        case 4: 5
        default: 4
        }
    }
}

/// The permanent white card mat with its hairline and print-like shadow.
struct StudyCardMat: ViewModifier {
    let columns: Int
    var isSelected = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: StudyCardMetrics.cornerRadius(columns), style: .continuous)
        content
            .padding(StudyCardMetrics.matInset(columns))
            .background(Color.white)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.black.opacity(0.1), lineWidth: 0.5)
                if isSelected {
                    shape.strokeBorder(Color.black, lineWidth: 2)
                }
            }
            .shadow(color: .black.opacity(isSelected ? 0 : 0.08), radius: 3, y: 1.5)
    }
}

/// A reflected pattern on the board: a serif quotation on grayscale ground,
/// like a text-only reference, so the person's taste in words sits among
/// the images it was drawn from.
struct StudyPatternCard: View {
    let reflection: StudyReflection
    let columns: Int
    var isSelected = false
    var developsOnArrival = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if developsOnArrival, !reduceMotion {
                DiffusionDevelopingView { quotation }
            } else {
                quotation
            }
        }
        .clipShape(
            RoundedRectangle(cornerRadius: StudyCardMetrics.innerCornerRadius(columns), style: .continuous)
        )
        .modifier(StudyCardMat(columns: columns, isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pattern: \(statement)")
    }

    private var quotation: some View {
        let padding = StudyCardMetrics.padding(columns)
        return VStack(alignment: .leading, spacing: max(5, padding * 0.45)) {
            Text("Pattern")
                .font(.system(size: max(8.5, StudyCardMetrics.statementSize(columns) * 0.55), weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(statement)
                .font(
                    .system(
                        size: StudyCardMetrics.statementSize(columns),
                        weight: .medium,
                        design: .serif
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(StudyCardMetrics.lineLimit(columns))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(padding)
        .padding(.top, padding)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .background(alignment: .topLeading) {
            Text("\u{201C}")
                .font(.system(size: StudyCardMetrics.statementSize(columns) * 2.8, design: .serif))
                .foregroundStyle(.white.opacity(0.18))
                .padding(.horizontal, padding)
                .accessibilityHidden(true)
        }
        .background(StudyBoardPalette.quoteFill(for: reflection.id))
    }

    private var statement: String {
        reflection.acceptedStatement ?? reflection.statement
    }
}

/// A card-shaped field of moving grain at the end of the board while an agent
/// is still looking: the slot a find will develop into.
struct StudyLatentCard: View {
    let columns: Int
    let aspectRatio: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(white: 0.9))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { DiffusionNoiseField(intensity: 0.55) }
            .clipShape(
                RoundedRectangle(cornerRadius: StudyCardMetrics.innerCornerRadius(columns), style: .continuous)
            )
            .modifier(StudyCardMat(columns: columns))
            .opacity(0.85)
            .accessibilityHidden(true)
    }
}

enum StudyBoardPalette {
    /// The same grayscale grounds text-only references use, picked by ID.
    static func quoteFill(for id: UUID) -> Color {
        let seed = id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let palette: [Color] = [
            .black,
            Color(white: 0.067),
            Color(white: 0.122),
            Color(white: 0.173),
        ]
        return palette[seed % palette.count]
    }
}

extension View {
    /// Marks a board card with the person's verdict: kept cards carry a quiet
    /// badge, rejected ones step back in grayscale.
    func studyBoardVerdict(_ verdict: StudyBoardVerdict) -> some View {
        modifier(StudyBoardVerdictStyle(verdict: verdict))
    }
}

private struct StudyBoardVerdictStyle: ViewModifier {
    let verdict: StudyBoardVerdict

    func body(content: Content) -> some View {
        content
            .saturation(verdict == .rejected ? 0 : 1)
            .opacity(verdict == .rejected ? 0.5 : 1)
            .overlay(alignment: .topLeading) {
                if verdict != .pending {
                    Label(
                        verdict == .kept ? "Kept" : "Rejected",
                        systemImage: verdict == .kept ? "checkmark" : "xmark"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white, in: Capsule())
                    .overlay { Capsule().strokeBorder(.black.opacity(0.1), lineWidth: 0.5) }
                    .padding(9)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityValue(verdictDescription)
    }

    private var verdictDescription: String {
        switch verdict {
        case .pending: "To judge"
        case .kept: "Kept"
        case .rejected: "Rejected"
        }
    }
}

extension StudyBoardArrivals {
    /// Just-arrived entries develop out of noise; the rest fade in as usual.
    func reveal(for id: UUID) -> PreviewImageReveal {
        fresh.contains(id) ? .develop : .fade
    }
}

// MARK: - Close look

/// A study item shown in the close look, such as the seed a find relates to.
struct StudyCloseLookItem: Identifiable {
    let id: UUID
    let title: String
    let localImageURL: URL?
    let remoteImageURL: URL?

    init(inspiration: Inspiration, localImageURL: URL?) {
        id = inspiration.id
        let title = inspiration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.isEmpty ? (inspiration.url.host() ?? "Untitled") : title
        self.localImageURL = localImageURL
        remoteImageURL = inspiration.imageURL
    }
}

/// The frame around one board entry seen up close: step through the board
/// without going back to it (⌘[ and ⌘]), and close.
struct StudyCloseLookFrame<Content: View>: View {
    let position: Int?
    let count: Int
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    var onClose: (() -> Void)?
    @ViewBuilder var content: () -> Content

    private var navigationButtonSide: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 28
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    onPrevious?()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .frame(width: navigationButtonSide, height: navigationButtonSide)
                        .contentShape(Rectangle())
                }
                .disabled(onPrevious == nil)
                .keyboardShortcut("[", modifiers: .command)
                .help("Previous (⌘[)")

                Button {
                    onNext?()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                        .frame(width: navigationButtonSide, height: navigationButtonSide)
                        .contentShape(Rectangle())
                }
                .disabled(onNext == nil)
                .keyboardShortcut("]", modifiers: .command)
                .help("Next (⌘])")

                if let position {
                    Text("\(position) of \(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                Spacer(minLength: 0)

                if let onClose {
                    Button(action: onClose) {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: navigationButtonSide, height: navigationButtonSide)
                            .contentShape(Rectangle())
                    }
                    .help("Close")
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            content()
        }
    }
}

struct StudyCloseLookSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A find seen up close: the whole image, its credit and source, why the
/// agent thinks it relates to the person's seeds, and the verdict.
struct StudyFindingCloseLook: View {
    let suggestion: StudySuggestion
    /// The stored image of the moodboard item a kept find became.
    var savedImageURL: URL?
    let relatedItems: [StudyCloseLookItem]
    let onDecide: (StudyVerdict, String?) -> Void

    @State private var reason = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StudyCloseLookHero(
                    localURL: savedImageURL,
                    remoteURL: suggestion.imageURL,
                    fallbackTitle: suggestion.title
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(suggestion.title)
                        .font(StudyBoardType.closeLookTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    if !attribution.isEmpty {
                        Text(attribution)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Link(destination: suggestion.url) {
                        Label(linkTitle, systemImage: "arrow.up.right.square")
                    }
                    .font(.callout)
                }

                StudyCloseLookSection("Why it's here") {
                    Text(suggestion.rationale)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if !relatedItems.isEmpty {
                    StudyCloseLookSection("Related to") {
                        StudyItemStrip(items: relatedItems)
                    }
                }

                verdict
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var verdict: some View {
        switch suggestion.status {
        case .pending:
            StudyCloseLookSection("Your verdict") {
                TextField("Why? Your reason is the taste data", text: $reason, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 10) {
                    Button {
                        onDecide(.keep, reason)
                    } label: {
                        Label("Keep", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Keep (⌘↩)")

                    Button {
                        onDecide(.reject, reason)
                    } label: {
                        Label("Reject", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
                Text("Keeping saves it to your moodboard. Rejections count as much as keeps: they steer what's found next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .kept:
            StudyCloseLookSection("Your verdict") {
                Label("Kept. It's on your moodboard.", systemImage: "checkmark.circle.fill")
                reasonText
            }
        case .rejected:
            StudyCloseLookSection("Your verdict") {
                Label("Rejected", systemImage: "xmark.circle")
                reasonText
                Button("Keep instead") {
                    onDecide(.keep, suggestion.reason)
                }
            }
        }
    }

    private var reasonText: some View {
        Text(suggestion.reason.map { "\u{201C}\($0)\u{201D}" } ?? "No reason given")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attribution: String {
        [suggestion.creator, suggestion.sourceName ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var linkTitle: String {
        guard var host = suggestion.url.host() else { return "Open the source" }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return "Open on \(host)"
    }
}

/// A pattern seen up close: the statement, what it was seen in, what it
/// stands against, and the person's answer, which can change later.
struct StudyPatternCloseLook: View {
    let reflection: StudyReflection
    let citedItems: [StudyCloseLookItem]
    let contrasts: [StudySuggestion]
    let onRespond: (StudyReflectionResponse) -> Void

    @State private var isCorrecting = false
    @State private var correction = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pattern")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("\u{201C}\(reflection.acceptedStatement ?? reflection.statement)\u{201D}")
                        .font(StudyBoardType.closeLookTitle)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if reflection.status == .corrected {
                        Text("Proposed as: \(reflection.statement)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    StudyBoardPalette.quoteFill(for: reflection.id),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

                if !citedItems.isEmpty {
                    StudyCloseLookSection("Seen in") {
                        StudyItemStrip(items: citedItems)
                    }
                }

                if !contrasts.isEmpty {
                    StudyCloseLookSection("Unlike what you rejected") {
                        ForEach(contrasts) { suggestion in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.callout)
                                Text(suggestion.reason.map { "\u{201C}\($0)\u{201D}" } ?? "No reason given")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                response
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var response: some View {
        StudyCloseLookSection(reflection.status == .pending ? "Is this true to you?" : "Your answer") {
            if let answer {
                Label(answer.text, systemImage: answer.symbol)
            }
            if isCorrecting {
                TextField("How would you put it?", text: $correction, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 10) {
                    Button("Save correction") {
                        onRespond(.correct(correction))
                        isCorrecting = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") { isCorrecting = false }
                }
            } else {
                HStack(spacing: 10) {
                    Button("That's right") { onRespond(.confirm) }
                        .buttonStyle(.borderedProminent)
                        .disabled(reflection.status == .confirmed)
                    Button("Correct it") {
                        correction = reflection.acceptedStatement ?? reflection.statement
                        isCorrecting = true
                    }
                    Button("Not me") { onRespond(.dismiss) }
                        .disabled(reflection.status == .dismissed)
                }
            }
        }
    }

    private var answer: (text: String, symbol: String)? {
        switch reflection.status {
        case .pending: nil
        case .confirmed: ("You confirmed it.", "checkmark.circle.fill")
        case .corrected: ("You corrected it.", "pencil.circle.fill")
        case .dismissed: ("Not you.", "xmark.circle")
        }
    }
}

/// The whole image over a soft wash of itself, so any shape reads well.
struct StudyCloseLookHero: View {
    let localURL: URL?
    let remoteURL: URL?
    let fallbackTitle: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
            if localURL != nil || remoteURL != nil {
                DownsampledPreviewImage(localURL: localURL, remoteURL: remoteURL, contentMode: .fill) {
                    Color.clear
                } failure: {
                    Color.clear
                }
                .blur(radius: 28)
                .opacity(0.5)
                DownsampledPreviewImage(localURL: localURL, remoteURL: remoteURL, contentMode: .fit) {
                    ProgressView()
                        .controlSize(.small)
                } failure: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image of \(fallbackTitle)")
        .accessibilityAddTraits(.isImage)
    }

    private var fallback: some View {
        Text(fallbackTitle)
            .font(.system(size: 20, weight: .medium, design: .serif))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
    }
}

/// A row of small thumbnails with titles, for the seeds a find relates to.
struct StudyItemStrip: View {
    let items: [StudyCloseLookItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        DownsampledPreviewImage(
                            localURL: item.localImageURL,
                            remoteURL: item.remoteImageURL
                        ) {
                            Rectangle().fill(.quaternary)
                        } failure: {
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(width: 72, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Agents

@MainActor
enum StudyAgentPromptText {
    /// For an agent mood. doesn't start itself, which uses `mood-agent`.
    static func make(for project: Project) -> String {
        "Use the mood-study skill to find inspirations for my mood. study \"\(project.name)\" (project \(project.id.uuidString)). Suggest only real, credited work, tie each one to my seeds and notes, and add them with `mood-agent suggest` so I can keep or reject them in mood."
    }

    static func copy(for project: Project) {
        let text = make(for: project)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
