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

private struct MacFloatingGlassCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.thinMaterial, in: Capsule())
        }
    }
}

private extension View {
    func macFloatingGlassCapsule() -> some View {
        modifier(MacFloatingGlassCapsuleModifier())
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
        .macFloatingGlassCapsule()
        .overlay {
            Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
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
/// Renders an original built-in pixel landscape behind the moodboard. The
/// artwork is decorative and deliberately washed so saved imagery stays primary.
struct MacMoodboardArtworkLayer: View {
    let assetName: String
    let projectColorHex: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                fallbackField

                if let artwork = NSImage(named: NSImage.Name(assetName)) {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(1.005)
                        .saturation(colorScheme == .dark ? 0.72 : 0.9)
                        .contrast(colorScheme == .dark ? 0.88 : 0.94)
                        .brightness(colorScheme == .dark ? -0.12 : 0)
                        .id(assetName)
                        .transition(.opacity)
                }

                treatmentOverlay
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .animation(reduceMotion ? nil : MacChromeMotion.fade, value: assetName)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var treatmentOverlay: some View {
        ZStack {
            if colorScheme == .dark {
                Color(red: 0.055, green: 0.06, blue: 0.065)
                    .opacity(reduceTransparency ? 0.94 : 0.5)
            } else {
                Color(red: 0.91, green: 0.93, blue: 0.92)
                    .opacity(reduceTransparency ? 0.94 : 0.36)
            }

            LinearGradient(
                colors: stageGradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var stageGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                .black.opacity(reduceTransparency ? 0.16 : 0.03),
                .black.opacity(reduceTransparency ? 0.34 : 0.12),
            ]
        }
        return [
            .white.opacity(reduceTransparency ? 0.24 : 0.08),
            .white.opacity(reduceTransparency ? 0.5 : 0.28),
        ]
    }

    private var fallbackField: some View {
        let projectColor = projectColorHex.map { Color(hex: $0) }
        return LinearGradient(
            colors: fallbackColors(accent: projectColor),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func fallbackColors(accent: Color?) -> [Color] {
        if colorScheme == .dark {
            return [
                accent?.opacity(0.24) ?? Color(red: 0.12, green: 0.14, blue: 0.15),
                Color(red: 0.035, green: 0.04, blue: 0.045),
            ]
        }
        return [
            accent?.opacity(0.24) ?? Color(red: 0.79, green: 0.83, blue: 0.82),
            Color(red: 0.9, green: 0.88, blue: 0.82),
        ]
    }
}

struct MacProjectSidebarItem: Identifiable {
    var id: LibraryScope { scope }

    let scope: LibraryScope
    let title: String
    let count: Int
    let colorHex: String?
    let landscapeAssetName: String
    let project: Project?
}

struct MacProjectSidebar: View {
    let items: [MacProjectSidebarItem]
    let currentScope: LibraryScope
    let isCollapsed: Bool
    let onSelect: (LibraryScope) -> Void
    let onToggleCollapse: () -> Void
    let onCreate: () -> Void
    let onEdit: (Project) -> Void
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
                            Text("PROJECTS")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(.white.opacity(0.42))
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
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .tracking(-0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show projects")
                .accessibilityLabel("Show projects sidebar")
            } else {
                HStack(spacing: 10) {
                    Text("mood.")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .tracking(-0.7)
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
                Divider()
                Button("Delete Project", role: .destructive) { onDelete(project) }
            }
        }
        .accessibilityLabel("\(item.title), \(item.count) item\(item.count == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func sidebarArtwork(for item: MacProjectSidebarItem) -> some View {
        if item.project != nil,
           let artwork = NSImage(named: NSImage.Name(item.landscapeAssetName)) {
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
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

            Menu {
                Button("Browser Setup…", action: onBrowserSetup)
            } label: {
                sidebarActionLabel(title: "More", systemImage: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            // Borderless macOS menus otherwise inherit the light-appearance
            // control tint and can render this label black on the dark rail.
            .tint(.white.opacity(0.68))
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .help("More actions")
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
        Color(red: 0.025, green: 0.027, blue: 0.03)
    }
}
