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
                .inkProminentButtonStyle()
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

/// The top of the study board: the subject with its brief, and the verdict
/// filters at the far edge. The agent isn't here; it lives in the canvas
/// chrome.
struct StudyBoardHeader: View {
    let study: ProjectStudy
    let board: StudyBoard
    @Binding var filter: StudyBoardFilter
    var onEdit: (() -> Void)?

    var body: some View {
        BoardPageHeader(
            title: study.subject,
            detail: study.brief,
            onEdit: onEdit.map { edit in
                BoardPageEdit(
                    title: "Edit Study…",
                    help: study.brief.isEmpty ? "Edit the subject and brief" : study.brief,
                    hint: "Edits the subject and brief",
                    action: edit
                )
            }
        ) {
            StudyBoardFilterBar(selection: $filter, board: board)
        }
    }
}

/// The top of every board on one line, so the board starts right under it:
/// the page's name in display serif with a line about it beside it, and
/// whatever steers the board at the far edge, over a pencil rule. When the
/// line can't hold both, the trailing part drops below. The moodboard and
/// the study board share it, so moving between them keeps the top of the
/// page still.
struct BoardPageHeader<Trailing: View>: View {
    let title: String
    var detail = ""
    var onEdit: BoardPageEdit?
    @ViewBuilder var trailing: () -> Trailing

    /// The least of the detail worth showing beside the title before the
    /// trailing part moves to its own line.
    private let minimumDetailWidth: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleAndTrailing
            PencilRule()
                .stroke(Sketchbook.pencil, style: Sketchbook.inkStroke(1))
                .frame(height: 6)
                .accessibilityHidden(true)
        }
    }

    private var titleAndTrailing: some View {
        ViewThatFits(in: .horizontal) {
            // On the title's baseline, so the filters read as part of the
            // same line of writing.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                BoardPageTitleButton(edit: onEdit) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        titleText
                            .fixedSize()
                        if !detail.isEmpty {
                            detailText
                                .lineLimit(1)
                                .frame(minWidth: 0, idealWidth: minimumDetailWidth, alignment: .leading)
                        }
                    }
                }
                Spacer(minLength: 20)
                trailing()
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 14) {
                BoardPageTitleButton(edit: onEdit) {
                    VStack(alignment: .leading, spacing: 3) {
                        titleText
                            .lineLimit(2)
                        if !detail.isEmpty {
                            detailText
                                .lineLimit(2)
                        }
                    }
                }
                trailing()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: some View {
        Text(title)
            .font(StudyBoardType.subject)
            .tracking(-0.2)
            .accessibilityAddTraits(.isHeader)
    }

    private var detailText: some View {
        Text(detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .truncationMode(.tail)
    }
}

/// What clicking a page's title edits, and how that's said.
struct BoardPageEdit {
    let title: String
    let help: String
    let hint: String
    let action: () -> Void
}

extension BoardPageHeader where Trailing == EmptyView {
    init(title: String, detail: String = "", onEdit: BoardPageEdit? = nil) {
        self.init(title: title, detail: detail, onEdit: onEdit) { EmptyView() }
    }
}

/// A page's title, which opens its editor like a window title that renames:
/// a soft highlight on hover says it can be clicked, and it sits outside the
/// text so the words stay on the board's left edge.
private struct BoardPageTitleButton<Label: View>: View {
    let edit: BoardPageEdit?
    @ViewBuilder var label: () -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private let highlightInset = CGSize(width: 6, height: 3)

    var body: some View {
        if let edit {
            Button(action: edit.action) {
                label()
                    .padding(.horizontal, highlightInset.width)
                    .padding(.vertical, highlightInset.height)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.primary.opacity(isHovered ? 0.07 : 0))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.horizontal, -highlightInset.width)
                    .padding(.vertical, -highlightInset.height)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovering }
            }
            .help(edit.help)
            .contextMenu {
                Button(edit.title, action: edit.action)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(edit.hint)
        } else {
            label()
        }
    }
}

/// The verdict filters with their counts, written on the page. Choosing one
/// is the person's call, so the current filter is underlined in ink; it's
/// one of the only marks that touch a control.
struct StudyBoardFilterBar: View {
    @Binding var selection: StudyBoardFilter
    let board: StudyBoard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var underline

    private var minimumHeight: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 28
        #endif
    }

    var body: some View {
        #if os(iOS)
        // Large text can outgrow a phone's width; then the filters scroll.
        ViewThatFits(in: .horizontal) {
            control
            ScrollView(.horizontal, showsIndicators: false) {
                control
            }
            .trailingOverflowFade()
        }
        #else
        control
        #endif
    }

    private var control: some View {
        HStack(spacing: 18) {
            ForEach(StudyBoardFilter.allCases, id: \.self) { filter in
                segment(filter)
            }
        }
        .animation(reduceMotion ? nil : GlassSegmentMetrics.selection, value: selection)
    }

    private func segment(_ filter: StudyBoardFilter) -> some View {
        let isSelected = selection == filter
        return Button {
            selection = filter
        } label: {
            HStack(spacing: 5) {
                Text(filter.title)
                    .fontWeight(isSelected ? .semibold : .medium)
                Text("\(board.count(for: filter))")
                    .font(GlassSegmentMetrics.detailFont)
                    .monospacedDigit()
                    .foregroundStyle(Sketchbook.graphite)
                    .contentTransition(.numericText())
            }
            .font(GlassSegmentMetrics.font)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(minHeight: minimumHeight)
            .overlay(alignment: .bottom) {
                if isSelected {
                    InkUnderline()
                        .stroke(Sketchbook.ink, style: Sketchbook.inkStroke(2))
                        .frame(height: 6)
                        .padding(.horizontal, -3)
                        .offset(y: minimumHeight > 30 ? -6 : 1)
                        .matchedGeometryEffect(id: "underline", in: underline)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title), \(board.count(for: filter))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Glass controls

/// The floating glass capsule the canvas controls share: Liquid Glass where
/// there is some, a thin material before it, and an opaque fill when the
/// person reduces transparency.
struct FloatingGlassCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Self.opaqueFill, in: Capsule())
        } else if #available(macOS 26.0, iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.thinMaterial, in: Capsule())
        }
    }

    private static var opaqueFill: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

extension View {
    /// The floating glass capsule the canvas controls share, with its
    /// half-point hairline.
    func floatingGlassCapsule() -> some View {
        modifier(FloatingGlassCapsule())
            .overlay {
                Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

enum GlassSegmentMetrics {
    #if os(iOS)
    static let height: CGFloat = 44
    static let inset: CGFloat = 4
    static let horizontalPadding: CGFloat = 11
    static let font = Font.footnote.weight(.medium)
    static let detailFont = Font.caption
    #else
    static let height: CGFloat = 34
    static let inset: CGFloat = 3
    static let horizontalPadding: CGFloat = 12
    static let font = Font.system(size: 12.5, weight: .medium)
    static let detailFont = Font.system(size: 11.5)
    #endif

    /// Moving between segments: quick, barely springy.
    static let selection = Animation.spring(response: 0.19, dampingFraction: 0.8, blendDuration: 0.03)
}

/// Text segments in a floating glass capsule. The current one sits on a
/// pill concentric with the capsule that slides between segments, so the
/// control reads as one rounded object instead of square cells in a round
/// frame.
struct GlassSegmentedControl<Value: Hashable, SegmentLabel: View>: View {
    @Binding var selection: Value
    let values: [Value]
    let accessibilityLabel: (Value) -> String
    @ViewBuilder var label: (_ value: Value, _ isSelected: Bool) -> SegmentLabel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                segment(value)
            }
        }
        .padding(GlassSegmentMetrics.inset)
        .frame(height: GlassSegmentMetrics.height)
        .floatingGlassCapsule()
        .animation(reduceMotion ? nil : GlassSegmentMetrics.selection, value: selection)
    }

    private func segment(_ value: Value) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            label(value, isSelected)
                .font(GlassSegmentMetrics.font)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .padding(.horizontal, GlassSegmentMetrics.horizontalPadding)
                .frame(maxHeight: .infinity)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(selectionFill)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 1.5, y: 0.5)
                            .matchedGeometryEffect(id: "selection", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(value))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionFill: Color {
        colorScheme == .dark ? .white.opacity(0.18) : .white
    }
}

// MARK: - Agent card

/// The top of an agent card: what the agent is doing or can do next, and a
/// line on what that means.
struct StudyAgentCardHeading: View {
    let title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The nudge as a soft well, like a composer rather than a form field:
/// where to lean, with room for an action at its trailing edge.
struct StudyNudgeWell<Accessory: View>: View {
    @Binding var text: String
    let prompt: String
    var onSubmit: () -> Void = {}
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var isFocused: Bool

    private var minimumHeight: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 34
        #endif
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 6) {
            TextField("Nudge", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(onSubmit)
                #if os(iOS)
                .submitLabel(.go)
                #endif
                .help("Optional. Say where to look, and the agent leans that way while staying true to your seeds and verdicts.")
                .accessibilityLabel("Nudge the search")
            accessory()
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(minHeight: minimumHeight)
        .background(.primary.opacity(0.05), in: shape)
        .overlay {
            shape.strokeBorder(.primary.opacity(isFocused ? 0.24 : 0.08), lineWidth: isFocused ? 1 : 0.5)
        }
        .contentShape(shape)
        .onTapGesture { isFocused = true }
    }
}

extension StudyNudgeWell where Accessory == EmptyView {
    init(text: Binding<String>, prompt: String, onSubmit: @escaping () -> Void = {}) {
        self.init(text: text, prompt: prompt, onSubmit: onSubmit) { EmptyView() }
    }
}

/// An agent card's one primary action, across the card's whole width.
struct StudyAgentPrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .inkProminentButtonStyle()
        .controlSize(.large)
    }
}

/// Shown where cards would be when there are none to show.
/// A note written on the page where cards would be, under the header and on
/// its left edge, with what to do next.
struct BoardPageNote<Actions: View>: View {
    let title: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            actions()
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.vertical, 16)
    }
}

extension BoardPageNote where Actions == EmptyView {
    init(title: String, message: String?) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

struct StudyBoardEmptyState: View {
    let stage: StudyStage
    let filter: StudyBoardFilter
    let boardIsEmpty: Bool
    let isSearchingText: Bool

    var body: some View {
        BoardPageNote(title: title, message: message)
    }

    private var title: String {
        if isSearchingText { return "No matches" }
        if boardIsEmpty { return stage == .seed ? "Seed your study first" : "Nothing found yet" }
        switch filter {
        case .all: return "Nothing found yet"
        case .toJudge: return "All judged"
        case .kept: return "Nothing kept yet"
        case .rejected: return "Nothing rejected yet"
        }
    }

    private var message: String? {
        if isSearchingText { return "Try a title, a creator, or a reason." }
        if boardIsEmpty {
            return stage == .seed
                ? "Add \(ProjectStudy.minimumSeedCount) things you love to the moodboard, then find sources."
                : "Find sources to start the board."
        }
        return filter == .toJudge ? "Find more when you're ready." : nil
    }
}

/// Geist Serif carries the study's display moments; the system serif keeps
/// everything smaller, where Geist's hairlines would thin out.
enum StudyBoardType {
    static var subject: Font {
        #if os(macOS)
        return SketchbookType.display(size: 40, relativeTo: .largeTitle)
        #else
        return SketchbookType.display(size: 34, relativeTo: .largeTitle)
        #endif
    }

    static var closeLookTitle: Font {
        #if os(macOS)
        return SketchbookType.display(size: 32, relativeTo: .title)
        #else
        return SketchbookType.display(size: 28, relativeTo: .title)
        #endif
    }

    /// A pattern given a whole pane in the wide close look.
    static var patternStatement: Font {
        #if os(macOS)
        return SketchbookType.display(size: 40, relativeTo: .largeTitle)
        #else
        return SketchbookType.display(size: 34, relativeTo: .largeTitle)
        #endif
    }

    /// The person's own words, in ink, in the close look.
    static var reason: Font {
        #if os(macOS)
        return .system(size: 15, design: .serif).italic()
        #else
        return .system(.body, design: .serif).italic()
        #endif
    }
}

// MARK: - Board cards

/// Density-aware measurements shared by the board's own cards, the same
/// values as each platform's moodboard card so they sit side by side.
enum StudyCardMetrics {
    static func matInset(_ columns: Int) -> CGFloat {
        #if os(iOS)
        switch columns {
        case ...1: return 10
        case 2: return 8
        case 3: return 5
        default: return 3
        }
        #else
        switch columns {
        case ...1: return 10
        case 2: return 8
        case 3: return 6
        case 4: return 5
        case 5: return 4
        default: return 3
        }
        #endif
    }

    static func cornerRadius(_ columns: Int) -> CGFloat {
        #if os(iOS)
        switch columns {
        case ...1: return 5
        case 2: return 4
        default: return 3
        }
        #else
        switch columns {
        case ...1: return 5
        case 2...3: return 4
        default: return 3
        }
        #endif
    }

    static func innerCornerRadius(_ columns: Int) -> CGFloat {
        max(1.5, cornerRadius(columns) - 2)
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

    /// A pattern's statement, before Dynamic Type. A phone's two columns
    /// are a third as wide as the Mac's, so its sizes step down sooner.
    static func statementSize(_ columns: Int) -> CGFloat {
        #if os(iOS)
        switch columns {
        case ...1: 22
        case 2: 15.5
        case 3: 13
        default: 11.5
        }
        #else
        switch columns {
        case ...1: 24
        case 2: 19
        case 3: 16
        case 4: 13
        case 5: 11.5
        case 6: 10.5
        default: 9.5
        }
        #endif
    }

    /// The smallest a card's own text gets, such as a lens or how much a
    /// pattern rests on.
    static var minimumTextSize: CGFloat {
        #if os(iOS)
        return 11
        #else
        return 10
        #endif
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

/// The permanent white card mat with its hairline and print-like shadow,
/// matching the moodboard card's on each platform.
struct StudyCardMat: ViewModifier {
    let columns: Int
    var isSelected = false

    @Environment(\.colorScheme) private var colorScheme

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
            .shadow(color: .black.opacity(isSelected ? 0 : restShadowOpacity), radius: restShadowRadius, y: restShadowOffset)
    }

    private var restShadowOpacity: Double {
        #if os(iOS)
        return columns >= 3 ? 0.06 : 0.09
        #else
        return colorScheme == .dark ? 0.24 : 0.075
        #endif
    }

    private var restShadowRadius: CGFloat {
        #if os(iOS)
        return columns >= 3 ? 1 : 2
        #else
        return 4
        #endif
    }

    private var restShadowOffset: CGFloat {
        #if os(iOS)
        return 1
        #else
        return 2
        #endif
    }
}

/// A reflected pattern on the board: the agent's proposal, written on the
/// page in a pencil frame among the images it was drawn from. Confirming it
/// redraws the frame in ink; a new one is sketched in as it arrives.
struct StudyPatternCard: View {
    let reflection: StudyReflection
    let columns: Int
    var isSelected = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Follows the person's text size on iOS.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    /// How much of the frame is drawn: all of it, unless it's just arrived.
    @State private var drawn: CGFloat

    init(reflection: StudyReflection, columns: Int, isSelected: Bool = false, developsOnArrival: Bool = false) {
        self.reflection = reflection
        self.columns = columns
        self.isSelected = isSelected
        _drawn = State(initialValue: developsOnArrival ? 0 : 1)
    }

    var body: some View {
        let padding = StudyCardMetrics.padding(columns)
        VStack(alignment: .leading, spacing: max(5, padding * 0.45)) {
            Text(statement)
                .font(.system(size: StudyCardMetrics.statementSize(columns) * textScale, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(StudyCardMetrics.lineLimit(columns))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // What it rests on, in the agent's hand: pointing at the card
            // draws the lines to those saves.
            if let evidence {
                Text(evidence)
                    .font(.system(size: max(StudyCardMetrics.minimumTextSize, StudyCardMetrics.statementSize(columns) * 0.62) * textScale))
                    .foregroundStyle(Sketchbook.graphite)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(Double(drawn))
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: StudyCardMetrics.cornerRadius(columns), style: .continuous)
                    .fill(.primary.opacity(0.06))
            }
        }
        .overlay {
            PencilFrame(seed: frameSeed)
                .trim(from: 0, to: drawn)
                .stroke(isAnswered ? Sketchbook.ink : Sketchbook.pencil, style: Sketchbook.inkStroke(isAnswered ? 1.8 : 1.1))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pattern: \(statement)")
        .accessibilityValue(reflection.evidenceSummary ?? "")
        .onAppear {
            guard drawn < 1 else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { drawn = 1 }
        }
    }

    private var statement: String {
        reflection.acceptedStatement ?? reflection.statement
    }

    private var evidence: String? {
        guard columns <= 5 else { return nil }
        return reflection.evidenceSummary
    }

    /// Confirmed or corrected: the person has made it theirs.
    private var isAnswered: Bool {
        reflection.status == .confirmed || reflection.status == .corrected
    }

    private var frameSeed: UInt64 {
        SketchJitter.seed(for: reflection.id)
    }
}

/// Pencil hatching at the end of the board while an agent is still looking:
/// the slot a find will develop into, blocked in before it's drawn.
struct StudyLatentCard: View {
    let columns: Int
    let aspectRatio: CGFloat
    /// Offsets this tile's breathing from its neighbour's.
    var phase = 0.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathingIn = false

    var body: some View {
        PencilHatch(seed: UInt64(phase * 1000) + 3)
            .opacity(isBreathingIn ? 0.5 : 0.28)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                PencilFrame(seed: UInt64(phase * 1000) + 5)
                    .stroke(Sketchbook.pencil, style: Sketchbook.inkStroke(1.1))
            }
            .padding(StudyCardMetrics.matInset(columns))
            .accessibilityHidden(true)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(phase / .pi * 0.8))
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    isBreathingIn = true
                }
            }
    }
}

/// A way to make the user's own work better, on the board: an index card
/// with the lens it's seen through, the move, and the real source that
/// shows it done well.
struct StudyMoveCard: View {
    let suggestion: StudySuggestion
    /// The stored image of the moodboard item the source became, once kept.
    var localImageURL: URL?
    let columns: Int
    var isSelected = false

    /// Follows the person's text size on iOS.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        let padding = max(8, StudyCardMetrics.padding(columns) * 0.75)
        let shape = RoundedRectangle(cornerRadius: StudyCardMetrics.cornerRadius(columns) + 2, style: .continuous)
        VStack(alignment: .leading, spacing: max(6, padding * 0.5)) {
            Text(suggestion.move ?? suggestion.title)
                .font(.system(size: StudyCardMetrics.statementSize(columns) * 0.85 * textScale, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(StudyCardMetrics.lineLimit(columns))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let lens = suggestion.lens {
                StudyLensLabel(lens: lens)
                    .font(.system(size: max(StudyCardMetrics.minimumTextSize, StudyCardMetrics.statementSize(columns) * 0.6) * textScale))
            }
            if columns <= 5 {
                source
            }
        }
        .padding(padding)
        .background(Sketchbook.sheet, in: shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.14)),
                lineWidth: isSelected ? 2 : 0.5
            )
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var source: some View {
        let side: CGFloat = columns <= 2 ? 44 : 34
        return HStack(spacing: 8) {
            DownsampledPreviewImage(localURL: localImageURL, remoteURL: suggestion.imageURL) {
                Rectangle().fill(.quaternary)
            } failure: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            // The title may take two lines, so a large text size still
            // says what the source is.
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("by \(suggestion.creator)")
                    .font(.caption2)
                    .foregroundStyle(Sketchbook.graphite)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityText: String {
        let lens = suggestion.lens.map { "\($0): " } ?? ""
        return "Move. \(lens)\(suggestion.move ?? suggestion.title). Shown in \(suggestion.title) by \(suggestion.creator)."
    }
}

/// The lens a move was seen through, in the agent's graphite: metadata
/// under the move rather than a label over it.
struct StudyLensLabel: View {
    let lens: String

    var body: some View {
        Label {
            Text(lens)
        } icon: {
            Image(systemName: "eyeglasses")
                .imageScale(.small)
        }
        .labelStyle(StudyLensLabelStyle())
        .foregroundStyle(Sketchbook.graphite)
        .lineLimit(1)
        .accessibilityLabel("Through \(lens)")
    }
}

private struct StudyLensLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

/// What sits under a find on the board, at the densities with room for it:
/// the person's reason in ink once they've judged it, or the agent's note
/// on why it's here, in graphite, while it waits.
struct StudyMarginNote: View {
    let suggestion: StudySuggestion
    let columns: Int

    var body: some View {
        if columns <= Self.maximumColumns {
            switch suggestion.status {
            case .pending:
                note(suggestion.rationale, isReason: false)
            case .kept, .rejected:
                if let reason = suggestion.reason, !reason.isEmpty {
                    note("\u{201C}\(reason)\u{201D}", isReason: true)
                }
            }
        }
    }

    private func note(_ text: String, isReason: Bool) -> some View {
        Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(isReason ? reasonFont : agentFont)
            .foregroundStyle(isReason ? Sketchbook.ink : Sketchbook.graphite)
            .lineLimit(isReason ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .accessibilityLabel(isReason ? "Your reason: \(text)" : "Why it's here: \(text)")
    }

    private static var maximumColumns: Int {
        #if os(iOS)
        return 2
        #else
        return 4
        #endif
    }

    private var agentFont: Font {
        #if os(iOS)
        return .footnote
        #else
        return .system(size: columns >= 4 ? 11.5 : 12.5)
        #endif
    }

    private var reasonFont: Font {
        #if os(iOS)
        return .system(.subheadline, design: .serif).italic()
        #else
        return .system(size: columns >= 4 ? 13 : 14, design: .serif).italic()
        #endif
    }

    /// Clears the ink loop around a kept card above it.
    static let spacing: CGFloat = 12
}

/// The board's motion, in one place so it can be tuned together.
enum StudyBoardMotion {
    /// Cards settling into the masonry: a spring, so a quick change of mind
    /// retargets from wherever things are.
    static let settle = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Between cards entering together, top to bottom.
    static let stagger = 0.025
    static let maximumStaggeredCards = 12
    /// Stepping from one entry to the next in the close look.
    static let step = Animation.easeOut(duration: 0.18)
    /// Agent status changes in the header.
    static let status = Animation.spring(response: 0.3, dampingFraction: 0.9)

    /// Cards that appear together, like on a filter change, arrive in a
    /// short cascade; a find that just arrived appears at once, since it
    /// develops on its own. Leaving is quick and unstaggered.
    static func cardTransition(index: Int, arrivedJustNow: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let delay = arrivedJustNow ? 0 : Double(min(index, maximumStaggeredCards)) * stagger
        return .asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity).animation(settle.delay(delay)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }
}

extension View {
    /// Marks a board card with the person's verdict, in ink: a kept card is
    /// circled, and a rejected one steps back in grayscale with a stroke
    /// through it. A verdict given while the card is on screen is drawn in.
    /// - Parameter circlesKept: false for a card that shows being kept
    ///   itself, like a pattern whose frame turns to ink.
    func studyBoardVerdict(_ verdict: StudyBoardVerdict, seed: UUID, circlesKept: Bool = true) -> some View {
        modifier(StudyBoardVerdictStyle(verdict: verdict, seed: seed, circlesKept: circlesKept))
    }
}

private struct StudyBoardVerdictStyle: ViewModifier {
    let verdict: StudyBoardVerdict
    let seed: UUID
    let circlesKept: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The verdict the card was showing, so a change can be told from a
    /// card that simply arrived already judged.
    @State private var shownVerdict: StudyBoardVerdict?

    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .saturation(verdict == .rejected ? 0 : 1)
            .opacity(verdict == .rejected ? 0.5 : 1)
            .overlay {
                if verdict == .rejected || (verdict == .kept && circlesKept) {
                    StudyVerdictMark(
                        verdict: verdict,
                        seed: seed,
                        drawsIn: !reduceMotion && shownVerdict != nil && shownVerdict != verdict
                    )
                    .id(verdict)
                }
            }
            .onAppear { shownVerdict = verdict }
            .onChange(of: verdict) { _, newVerdict in shownVerdict = newVerdict }
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

/// The ink loop or stroke itself, drawn in the way a hand would when the
/// verdict is new.
private struct StudyVerdictMark: View {
    let verdict: StudyBoardVerdict
    let seed: UUID

    @State private var drawn: CGFloat

    init(verdict: StudyBoardVerdict, seed: UUID, drawsIn: Bool) {
        self.verdict = verdict
        self.seed = seed
        _drawn = State(initialValue: drawsIn ? 0 : 1)
    }

    var body: some View {
        Group {
            if verdict == .kept {
                InkLoop(seed: seed)
                    .trim(from: 0, to: drawn)
                    .stroke(Sketchbook.ink, style: Sketchbook.inkStroke(1.8))
                    .padding(-7)
            } else {
                InkStrike(seed: seed)
                    .trim(from: 0, to: drawn)
                    .stroke(Sketchbook.ink, style: Sketchbook.inkStroke(2.2))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard drawn < 1 else { return }
            withAnimation(.easeOut(duration: verdict == .kept ? 0.5 : 0.22)) { drawn = 1 }
        }
    }
}

extension StudyBoardArrivals {
    /// Just-arrived entries develop out of noise; the rest fade in as usual.
    func reveal(for id: UUID) -> PreviewImageReveal {
        fresh.contains(id) ? .develop : .fade
    }
}

// MARK: - Evidence

/// Where each card on the study board sits, so a pattern can point at the
/// cards it was drawn from.
struct StudyCardAnchorKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func studyCardAnchor(_ id: UUID) -> some View {
        anchorPreference(key: StudyCardAnchorKey.self, value: .bounds) { [id: $0] }
    }
}

extension StudyReflection {
    /// How much the pattern rests on, such as "Seen in 3 of your saves".
    var evidenceSummary: String? {
        switch inspirationIDs.count {
        case 0: nil
        case 1: "Seen in one of your saves"
        case let count: "Seen in \(count) of your saves"
        }
    }

    /// The finds on the board this pattern was drawn from: the ones kept
    /// into the items it cites.
    func evidence(in study: ProjectStudy) -> [StudySuggestion.ID] {
        study.suggestions
            .filter { suggestion in
                suggestion.savedInspirationID.map(inspirationIDs.contains) ?? false
            }
            .map(\.id)
    }
}

/// The agent showing its work: pencil lines from a pattern into the kept
/// cards it was drawn from, and dashed ones to the rejected finds it stands
/// against, drawn in while the pattern is pointed at.
struct StudyEvidenceLines: View {
    let pattern: UUID
    let evidence: [UUID]
    let contrasts: [UUID]
    let anchors: [UUID: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let source = anchors[pattern].map({ proxy[$0] }) {
                StudyEvidenceSketch(
                    source: source,
                    evidence: evidence.compactMap { anchors[$0].map { proxy[$0] } },
                    contrasts: contrasts.compactMap { anchors[$0].map { proxy[$0] } },
                    seed: SketchJitter.seed(for: pattern)
                )
                .id(pattern)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StudyEvidenceSketch: View {
    let source: CGRect
    let evidence: [CGRect]
    let contrasts: [CGRect]
    let seed: UInt64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            StudyEvidencePath(source: source, targets: evidence, seed: seed)
                .trim(from: 0, to: drawn)
                .stroke(Sketchbook.pencil, style: Sketchbook.inkStroke(1.5))
            StudyEvidencePath(source: source, targets: contrasts, seed: seed &+ 7)
                .trim(from: 0, to: drawn)
                .stroke(Sketchbook.pencil, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 5]))
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { drawn = 1 }
        }
    }
}

/// A quick curve from just outside the pattern to a little way into each
/// card, ending in a small ring, the way a hand points at something.
private struct StudyEvidencePath: Shape {
    let source: CGRect
    let targets: [CGRect]
    let seed: UInt64

    func path(in _: CGRect) -> Path {
        var jitter = SketchJitter(seed: seed)
        var path = Path()
        for target in targets {
            let targetCenter = CGPoint(x: target.midX, y: target.midY)
            let start = Self.edgePoint(of: source, toward: targetCenter, outset: 4)
            let edge = Self.edgePoint(of: target, toward: CGPoint(x: source.midX, y: source.midY), outset: 0)
            let reach = min(28, min(target.width, target.height) * 0.2)
            let end = Self.point(from: edge, toward: targetCenter, distance: reach)

            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(1, hypot(dx, dy))
            let bow = length * (0.12 + 0.06 * jitter.next())
            let control = CGPoint(
                x: (start.x + end.x) / 2 - dy / length * bow,
                y: (start.y + end.y) / 2 + dx / length * bow
            )
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            path.addEllipse(in: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10))
        }
        return path
    }

    /// Where a line from the rect's center toward `point` leaves the rect,
    /// pushed `outset` points further out.
    private static func edgePoint(of rect: CGRect, toward point: CGPoint, outset: CGFloat) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let halfWidth = rect.width / 2 + outset
        let halfHeight = rect.height / 2 + outset
        let scale = min(
            dx == 0 ? .infinity : halfWidth / abs(dx),
            dy == 0 ? .infinity : halfHeight / abs(dy)
        )
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    private static func point(from origin: CGPoint, toward target: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = hypot(dx, dy)
        guard length > distance else { return target }
        return CGPoint(x: origin.x + dx / length * distance, y: origin.y + dy / length * distance)
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
struct CloseLookFrame<Content: View>: View {
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
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)

                if let onClose {
                    Button(action: onClose) {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: navigationButtonSide, height: navigationButtonSide)
                            .contentShape(Rectangle())
                    }
                    .help("Close (esc)")
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)

            content()
        }
    }
}

/// Lays a close look out like a print on a table when there's room: the
/// image large on the left and the details in a column beside it. When it's
/// narrow, the image sits above the details in one scroll. Either way the
/// footer, where the verdict is given, stays put, so judging one thing after
/// another happens in the same place.
struct StudyCloseLookSplit<Hero: View, Details: View, Footer: View>: View {
    @ViewBuilder var hero: (_ isWide: Bool) -> Hero
    @ViewBuilder var details: () -> Details
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= CloseLookMetrics.wideMinimumWidth {
                HStack(spacing: 0) {
                    hero(true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(width: 0.5)

                    VStack(spacing: 0) {
                        ScrollView {
                            details()
                                .padding(24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        pinnedFooter(horizontalPadding: 24)
                    }
                    .frame(width: CloseLookMetrics.detailsWidth(for: geometry.size.width))
                }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            hero(false)
                            details()
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    pinnedFooter(horizontalPadding: 20)
                }
            }
        }
    }

    private func pinnedFooter(horizontalPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)
            footer()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum CloseLookMetrics {
    /// Below this the image and details stack instead of sitting side by side.
    static let wideMinimumWidth: CGFloat = 760

    static func detailsWidth(for width: CGFloat) -> CGFloat {
        min(420, max(340, (width * 0.34).rounded()))
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
/// agent thinks it relates to the person's seeds, and the verdict. A move
/// leads with the change it proposes and the work it's for; the image is
/// the source that shows it done well.
struct StudyFindingCloseLook: View {
    let suggestion: StudySuggestion
    /// The stored image of the moodboard item a kept find became.
    var savedImageURL: URL?
    let relatedItems: [StudyCloseLookItem]
    /// For a move: the person's own item it would make better.
    var targetItems: [StudyCloseLookItem] = []
    let onDecide: (StudyVerdict, String?) -> Void

    @State private var reason = ""

    var body: some View {
        StudyCloseLookSplit { isWide in
            StudyCloseLookHero(
                localURL: savedImageURL,
                remoteURL: suggestion.imageURL,
                fallbackTitle: suggestion.title,
                isFullBleed: isWide
            )
        } details: {
            VStack(alignment: .leading, spacing: 20) {
                if let move = suggestion.move {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(move)
                            .font(StudyBoardType.closeLookTitle)
                            .tracking(-0.2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .accessibilityAddTraits(.isHeader)
                        if let lens = suggestion.lens {
                            StudyLensLabel(lens: lens)
                                .font(.callout)
                        }
                    }
                    if !targetItems.isEmpty {
                        StudyCloseLookSection("For") {
                            StudyItemStrip(items: targetItems)
                        }
                    }
                    StudyCloseLookSection("Shown in") {
                        sourceCredit(titleFont: .headline)
                    }
                } else {
                    sourceCredit(titleFont: StudyBoardType.closeLookTitle)
                }

                StudyCloseLookSection(suggestion.isMove ? "Why it fits" : "Why it's here") {
                    Text(suggestion.rationale)
                        .foregroundStyle(Sketchbook.graphite)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if !relatedItems.isEmpty {
                    StudyCloseLookSection("Related to") {
                        StudyItemStrip(items: relatedItems)
                    }
                }
            }
        } footer: {
            verdict
        }
    }

    private func sourceCredit(titleFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.title)
                .font(titleFont)
                .tracking(suggestion.isMove ? 0 : -0.3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(suggestion.isMove ? [] : .isHeader)
            if !attribution.isEmpty {
                Text(attribution)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            // In the page's own ink rather than link blue, which would read
            // as the person's blue-black marks.
            Link(destination: suggestion.url) {
                Label(linkTitle, systemImage: "arrow.up.right.square")
            }
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var verdict: some View {
        switch suggestion.status {
        case .pending:
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "Why?",
                    text: $reason,
                    prompt: Text("Why? Your reasons steer the next search"),
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .font(StudyBoardType.reason)
                .foregroundStyle(Sketchbook.ink)
                StudyLensPicker(reason: $reason)
                HStack(spacing: 8) {
                    Button {
                        onDecide(.keep, reason)
                    } label: {
                        Label("Keep", systemImage: "checkmark")
                    }
                    .inkProminentButtonStyle()
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Keep, and save it to the moodboard (⌘↩)")

                    Button {
                        onDecide(.reject, reason)
                    } label: {
                        Label("Reject", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .kept:
            VStack(alignment: .leading, spacing: 4) {
                Label("Kept · on your moodboard", systemImage: "checkmark.circle")
                reasonText
            }
        case .rejected:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label("Rejected", systemImage: "xmark.circle")
                    Spacer(minLength: 8)
                    Button("Keep instead") {
                        onDecide(.keep, suggestion.reason)
                    }
                }
                reasonText
            }
        }
    }

    @ViewBuilder
    private var reasonText: some View {
        if let reason = suggestion.reason, !reason.isEmpty {
            Text("\u{201C}\(reason)\u{201D}")
                .font(StudyBoardType.reason)
                .foregroundStyle(Sketchbook.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        StudyCloseLookSplit { isWide in
            quotation(isWide: isWide)
        } details: {
            VStack(alignment: .leading, spacing: 20) {
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
                                if let reason = suggestion.reason, !reason.isEmpty {
                                    Text("\u{201C}\(reason)\u{201D}")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        } footer: {
            response
        }
    }

    private func quotation(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\u{201C}\(reflection.acceptedStatement ?? reflection.statement)\u{201D}")
                .font(isWide ? StudyBoardType.patternStatement : StudyBoardType.closeLookTitle)
                .tracking(-0.2)
                .lineSpacing(isWide ? 4 : 2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if reflection.status == .corrected {
                Text("Proposed as: \(reflection.statement)")
                    .font(.caption)
                    .foregroundStyle(Sketchbook.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(isWide ? 48 : 20)
        .frame(
            maxWidth: .infinity,
            maxHeight: isWide ? .infinity : nil,
            alignment: isWide ? .bottomLeading : .leading
        )
        .background(SketchPaper())
        .clipShape(RoundedRectangle(cornerRadius: isWide ? 0 : 10, style: .continuous))
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
                HStack(spacing: 8) {
                    Button("Save correction") {
                        onRespond(.correct(correction))
                        isCorrecting = false
                    }
                    .inkProminentButtonStyle()
                    .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") { isCorrecting = false }
                }
            } else {
                HStack(spacing: 8) {
                    Button("That's right") { onRespond(.confirm) }
                        .inkProminentButtonStyle()
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
        case .confirmed: ("You confirmed it.", "checkmark.circle")
        case .corrected: ("You corrected it.", "pencil.circle")
        case .dismissed: ("Not you.", "xmark.circle")
        }
    }
}

/// The whole image over a soft wash of itself, so any shape reads well.
/// Full bleed, it fills its pane; otherwise it's a rounded 4:3 print.
struct StudyCloseLookHero: View {
    let localURL: URL?
    let remoteURL: URL?
    let fallbackTitle: String
    var isFullBleed = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if isFullBleed {
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                stage
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image of \(fallbackTitle)")
        .accessibilityAddTraits(.isImage)
    }

    private var stage: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
            if localURL != nil || remoteURL != nil {
                if !reduceTransparency {
                    // Scaled past the edges so the blur has no fringe.
                    DownsampledPreviewImage(localURL: localURL, remoteURL: remoteURL, contentMode: .fill) {
                        Color.clear
                    } failure: {
                        Color.clear
                    }
                    .scaleEffect(1.16)
                    .blur(radius: 32)
                    .overlay(wash)
                }

                DownsampledPreviewImage(localURL: localURL, remoteURL: remoteURL, contentMode: .fit) {
                    ProgressView()
                        .controlSize(.small)
                } failure: {
                    fallback
                }
                .padding(isFullBleed ? 32 : 0)
                .closeLookPrintShadow(isEnabled: isFullBleed)
            } else {
                fallback
            }
        }
        .clipped()
    }

    private var wash: Color {
        colorScheme == .dark ? Color.black.opacity(0.46) : Color.white.opacity(0.34)
    }

    private var fallback: some View {
        Text(fallbackTitle)
            .font(.system(size: isFullBleed ? 28 : 20, weight: .medium, design: .serif))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
    }
}

extension View {
    /// A tight contact shadow under a wide ambient one, for an image resting
    /// on its own wash in a close look.
    func closeLookPrintShadow(isEnabled: Bool = true) -> some View {
        self
            .shadow(color: .black.opacity(isEnabled ? 0.12 : 0), radius: 2, y: 1)
            .shadow(color: .black.opacity(isEnabled ? 0.14 : 0), radius: 16, y: 8)
    }
}

/// Quick ways to say why, through Dieter Rams' principles of good design.
/// A lens goes into the reason as words, so it steers the search like
/// anything else the person writes; a chosen one is circled in ink.
struct StudyLensPicker: View {
    @Binding var reason: String

    static let lenses = [
        "As little design as possible",
        "Understandable",
        "Unobtrusive",
        "Honest",
        "Useful",
        "Thorough to the detail",
        "Long-lasting",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or say it through a lens")
                .font(.caption)
                .foregroundStyle(.secondary)
            #if os(iOS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { chips }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 7)
            }
            .trailingOverflowFade()
            .padding(.horizontal, -7)
            #else
            SketchFlowLayout(spacing: 8, lineSpacing: 8) { chips }
                .padding(.vertical, 4)
            #endif
        }
    }

    private var chips: some View {
        ForEach(Self.lenses, id: \.self) { lens in
            let isChosen = contains(lens)
            Button {
                toggle(lens)
            } label: {
                Text(lens)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isChosen ? AnyShapeStyle(Sketchbook.ink) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minHeight: chipHeight)
                    .overlay {
                        if isChosen {
                            InkLoop(seed: Self.seed(for: lens))
                                .stroke(Sketchbook.ink, style: Sketchbook.inkStroke(1.5))
                                .padding(-3)
                        } else {
                            Capsule().strokeBorder(.primary.opacity(0.16), lineWidth: 0.5)
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isChosen ? .isSelected : [])
            .accessibilityHint(isChosen ? "Removes it from your reason" : "Adds it to your reason")
        }
    }

    private var chipHeight: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 26
        #endif
    }

    private func contains(_ lens: String) -> Bool {
        reason.range(of: lens, options: [.caseInsensitive]) != nil
    }

    private func toggle(_ lens: String) {
        if let range = reason.range(of: lens, options: [.caseInsensitive]) {
            reason.removeSubrange(range)
            reason = reason
                .replacingOccurrences(of: "..", with: ".")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " .").union(.whitespacesAndNewlines))
            return
        }
        let current = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = current.last else {
            reason = lens
            return
        }
        reason = current + (".!?".contains(last) ? " " : ". ") + lens
    }

    /// Each lens keeps its own loop, the same every time.
    private static func seed(for lens: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in lens.utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] &* 31 &+ byte
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Lays chips out in rows, wrapping to the next when a row is full.
struct SketchFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
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
    static func make(for project: Project, nudge: String? = nil) -> String {
        var text = "Use the mood-study skill to find inspirations for my mood. study \"\(project.name)\" (project \(project.id.uuidString)). Suggest only real, credited work, tie each one to my seeds and notes, and add them with `mood-agent suggest` so I can keep or reject them in mood."
        if let nudge = StudyAgentNudge.cleaned(nudge) {
            text += " Lean this way: \"\(nudge)\"."
        }
        return text
    }

    /// Asks for moves that make one of the person's own items better.
    static func make(for project: Project, target: StudyAgentTarget) -> String {
        let lenses = switch target.lenses {
        case .rams: "Dieter Rams' ten principles of good design"
        case .direction: "my confirmed patterns, so it shows where the item strays from my direction"
        }
        return "Use the mood-study skill's \"Make it better\" section to propose ways to make my own work better in my mood. study \"\(project.name)\" (project \(project.id.uuidString)): the item \(target.inspirationID.uuidString) (\"\(target.title)\"). Look through \(lenses). Back every move with a real, credited source that shows it done well, never a drawn or generated variant, and add them with `mood-agent suggest` so I can keep or reject them in mood."
    }

    static func copy(for project: Project, nudge: String? = nil) {
        write(make(for: project, nudge: nudge))
    }

    static func copy(for project: Project, target: StudyAgentTarget) {
        write(make(for: project, target: target))
    }

    private static func write(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
