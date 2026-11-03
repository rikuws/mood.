import AppKit
import PinaxCore
import SwiftUI

enum MacChromeMotion {
    static let chrome = Animation.spring(
        response: 0.24,
        dampingFraction: 0.76,
        blendDuration: 0.04
    )
    static let quick = Animation.spring(
        response: 0.19,
        dampingFraction: 0.8,
        blendDuration: 0.03
    )
    static let panel = Animation.spring(
        response: 0.25,
        dampingFraction: 0.82,
        blendDuration: 0.04
    )
    static let fade = Animation.easeOut(duration: 0.14)
}

/// Moodboard or study board, in the same glass segmented capsule as the
/// study board's verdict filters.
struct MacCanvasModeSwitch: View {
    @Binding var showsStudyBoard: Bool

    var body: some View {
        GlassSegmentedControl(
            selection: $showsStudyBoard,
            values: [false, true],
            accessibilityLabel: title
        ) { value, _ in
            Text(title(value))
        }
        .accessibilityRepresentation {
            Picker("Show", selection: $showsStudyBoard) {
                Text("Moodboard").tag(false)
                Text("Study board").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private func title(_ showsStudyBoard: Bool) -> String {
        showsStudyBoard ? "Study board" : "Moodboard"
    }
}

struct MacCanvasSearchControl: View {
    @Binding var text: String
    let isExpanded: Bool
    let activation: UUID
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private let collapsedWidth: CGFloat = 64
    private let expandedWidth: CGFloat = 264

    var body: some View {
        ZStack(alignment: .trailing) {
            if isExpanded {
                MacCanvasSearchField(
                    text: $text,
                    activation: activation,
                    onDismiss: onDismiss
                )
                .transition(.opacity)
            } else {
                MacCanvasSearchButton(action: onOpen)
                    .transition(.opacity)
            }
        }
        .frame(
            width: isExpanded ? expandedWidth : collapsedWidth,
            height: 34,
            alignment: .trailing
        )
        .floatingGlassCapsule()
        .contentShape(Capsule())
    }
}

struct MacCanvasSearchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))

                Text("/")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 22, height: 22)
                    .background(
                        Color.primary.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .foregroundStyle(.primary.opacity(0.7))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Search (/)")
        .accessibilityLabel("Search moodboard")
        .accessibilityHint("Press slash or Command-F to search")
    }
}

struct MacCanvasSearchField: View {
    @Binding var text: String
    var activation: UUID
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search moodboard", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand {
                    if text.isEmpty {
                        onDismiss()
                    } else {
                        text = ""
                    }
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            Capsule().strokeBorder(
                .primary.opacity(isFocused ? 0.08 : 0),
                lineWidth: 0.5
            )
        }
        .onAppear(perform: requestFocus)
        .onChange(of: activation) { _, _ in
            requestFocus()
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && text.isEmpty {
                onDismiss()
            }
        }
    }

    private func requestFocus() {
        Task { @MainActor in
            await Task.yield()
            isFocused = true
        }
    }
}

struct MacCanvasWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("MacCanvasWindowConfigurator")
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        if window.title != ProductIdentity.displayName {
            window.title = ProductIdentity.displayName
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if window.toolbar != nil {
            window.toolbar = nil
        }
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

struct MacProjectSidebarItem: Identifiable {
    var id: LibraryScope { scope }

    let scope: LibraryScope
    let title: String
    let count: Int
    let colorHex: String?
    /// The project's own picture, so each project is told apart at a glance.
    let cover: MacProjectSidebarCover?
    let project: Project?
}

struct MacProjectSidebarCover: Equatable {
    let localURL: URL?
    let remoteURL: URL?
}

struct MacProjectSidebar: View {
    let items: [MacProjectSidebarItem]
    let currentScope: LibraryScope
    let isCollapsed: Bool
    let onSelect: (LibraryScope) -> Void
    let onToggleCollapse: () -> Void
    let onCreate: () -> Void
    let onCreateStudy: () -> Void
    let onEdit: (Project) -> Void
    let onStudy: (Project) -> Void
    let onDelete: (Project) -> Void
    let onCapture: () -> Void
    let onBrowserSetup: () -> Void

    @State private var hoveredScope: LibraryScope?

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(libraryItems) { item in
                        sidebarRow(item)
                    }

                    if !projectItems.isEmpty {
                        if !isCollapsed {
                            Text("Projects")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.46))
                                .padding(.horizontal, 10)
                                .padding(.top, 16)
                                .padding(.bottom, 5)
                                .transition(.opacity)
                        } else {
                            Divider()
                                .overlay(.white.opacity(0.12))
                                .padding(.vertical, 8)
                        }

                        ForEach(projectItems) { item in
                            sidebarRow(item)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            sidebarFooter
        }
        .foregroundStyle(.white)
        .background(sidebarBackground)
    }

    private var libraryItems: [MacProjectSidebarItem] {
        items.filter { $0.project == nil }
    }

    private var projectItems: [MacProjectSidebarItem] {
        items.filter { $0.project != nil }
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        Group {
            if isCollapsed {
                Button(action: onToggleCollapse) {
                    Text("m.")
                        .font(SketchbookType.display(size: 28, relativeTo: .title))
                        .tracking(-0.4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show projects")
                .accessibilityLabel("Show projects sidebar")
            } else {
                HStack(spacing: 10) {
                    // The sketchbook's name on its cover, in the same serif
                    // as the page titles.
                    Text("mood.")
                        .font(SketchbookType.display(size: 28, relativeTo: .title))
                        .tracking(-0.4)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("mood.")

                    collapseButton
                        .transition(.opacity)
                }
            }
        }
        .padding(.leading, isCollapsed ? 8 : 14)
        .padding(.trailing, isCollapsed ? 8 : 10)
        .padding(.top, 25)
        .frame(height: 74)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 0.5)
        }
    }

    private var collapseButton: some View {
        Button(action: onToggleCollapse) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Focus on moodboard")
        .accessibilityLabel("Collapse projects sidebar")
    }

    private func sidebarRow(_ item: MacProjectSidebarItem) -> some View {
        let isSelected = item.scope == currentScope
        let isHovered = item.scope == hoveredScope

        return Button {
            onSelect(item.scope)
        } label: {
            HStack(spacing: 9) {
                sidebarArtwork(for: item)

                if !isCollapsed {
                    Text(item.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.76))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text("\(item.count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(isSelected ? 0.62 : 0.36))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, isCollapsed ? 0 : 8)
            .frame(height: isCollapsed ? 42 : 38)
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowFill(isSelected: isSelected, isHovered: isHovered))
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredScope = hovering ? item.scope : nil
        }
        .help(isCollapsed ? item.title : "")
        .contextMenu {
            if let project = item.project {
                Button("Edit Project…") { onEdit(project) }
                Button(project.isStudy ? "Open Study" : "Start a Study…") { onStudy(project) }
                Divider()
                Button("Delete Project", role: .destructive) { onDelete(project) }
            }
        }
        .accessibilityLabel("\(item.title), \(item.count) item\(item.count == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A project shows its own picture; until it has one, or while it
    /// loads, its initial on its color.
    @ViewBuilder
    private func sidebarArtwork(for item: MacProjectSidebarItem) -> some View {
        if item.project != nil, let cover = item.cover {
            DownsampledPreviewImage(localURL: cover.localURL, remoteURL: cover.remoteURL) {
                sidebarArtworkFallback(for: item)
            } failure: {
                sidebarArtworkFallback(for: item)
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            }
        } else {
            sidebarArtworkFallback(for: item)
        }
    }

    private func sidebarArtworkFallback(for item: MacProjectSidebarItem) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fallbackFill(for: item))
            .frame(width: 26, height: 26)
            .overlay {
                if let symbol = systemSymbol(for: item.scope) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    Text(String(item.title.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
    }

    private func fallbackFill(for item: MacProjectSidebarItem) -> Color {
        if let colorHex = item.colorHex {
            return Color(hex: colorHex).opacity(0.72)
        }
        // A project without a color, like a new study, still gets its own.
        if let project = item.project {
            let seed = project.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return Color(hex: ProjectEditorSheet.colors[seed % ProjectEditorSheet.colors.count]).opacity(0.72)
        }
        return .white.opacity(item.scope == .all ? 0.16 : 0.1)
    }

    private func systemSymbol(for scope: LibraryScope) -> String? {
        switch scope {
        case .all: "rectangle.grid.2x2"
        case .general: "tray"
        case .project: nil
        }
    }

    private func rowFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return .white.opacity(0.14) }
        if isHovered { return .white.opacity(0.075) }
        return .clear
    }

    private var sidebarFooter: some View {
        VStack(spacing: 4) {
            sidebarAction(
                title: "New project",
                systemImage: "plus",
                action: onCreate
            )
            sidebarAction(
                title: "Save a link",
                systemImage: "link.badge.plus",
                action: onCapture
            )

            // Drawn as its own label rather than a borderless menu button,
            // which centered it and tinted it apart from the actions above.
            Menu {
                Button("New Visual Study…", action: onCreateStudy)
                Divider()
                Button("Browser Setup…", action: onBrowserSetup)
            } label: {
                sidebarActionLabel(title: "More", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help(isCollapsed ? "More" : "")
        }
        .padding(8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 0.5)
        }
    }

    private func sidebarAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            sidebarActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? title : "")
    }

    private func sidebarActionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)

            if !isCollapsed {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white.opacity(0.68))
        .padding(.horizontal, isCollapsed ? 0 : 8)
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var sidebarBackground: Color {
        Sketchbook.cover
    }
}
