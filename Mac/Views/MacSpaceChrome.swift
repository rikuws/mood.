import AppKit
import PinaxCore
import SwiftUI

struct MacSpaceIdentityButton: View {
    let title: String
    var colorHex: String? = nil
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let colorHex {
                    Circle()
                        .fill(Color(hex: colorHex))
                        .frame(width: 7, height: 7)
                }

                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary.opacity(0.82))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering || isExpanded ? 0.72 : 0.32)
                    .offset(y: 1)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isExpanded ? 180 : 0)))
            }
            .padding(.vertical, 4)
            .padding(.trailing, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isExpanded)
        .help("Switch project")
        .accessibilityLabel(title)
        .accessibilityHint("Shows the project switcher")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search your moodboard", text: $text)
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
        .frame(maxWidth: 260)
        .padding(.bottom, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(isFocused ? 0.28 : 0.12))
                .frame(height: 0.5)
        }
        .onAppear { isFocused = true }
        .onChange(of: activation) { _, _ in
            isFocused = true
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && text.isEmpty {
                onDismiss()
            }
        }
    }
}

struct MacProjectSwitcher: View {
    let projects: [Project]
    let counts: ProjectCounts
    let currentScope: LibraryScope
    let onSelect: (LibraryScope) -> Void
    let onCreate: () -> Void
    let onEdit: (Project) -> Void
    let onDelete: (Project) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var highlightedScope: LibraryScope?
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField("Go to…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isQueryFocused)
                    .onSubmit(confirmHighlighted)
                    .onKeyPress(.downArrow) {
                        moveHighlight(by: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveHighlight(by: -1)
                        return .handled
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if visibleRows.isEmpty {
                Text("No matching space")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(visibleRows) { row in
                                switcherRow(row)
                                    .id(row.scope)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: highlightedScope) { _, scope in
                        guard let scope else { return }
                        proxy.scrollTo(scope, anchor: .nearest)
                    }
                }
            }

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                Button(action: onCreate) {
                    Label("New Project…", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 276)
        .onAppear {
            highlightedScope = currentScope
            isQueryFocused = true
        }
        .onChange(of: query) { _, _ in
            highlightedScope = visibleRows.first?.scope
        }
    }

    private var allRows: [SwitcherRow] {
        var rows = [
            SwitcherRow(
                scope: .all,
                title: "All inspiration",
                count: counts.total,
                colorHex: nil
            ),
            SwitcherRow(
                scope: .general,
                title: "General",
                count: counts.general,
                colorHex: nil
            ),
        ]
        rows.append(
            contentsOf: projects.map { project in
                SwitcherRow(
                    scope: .project(project.id),
                    title: project.name,
                    count: counts[project.id],
                    colorHex: project.colorHex
                )
            }
        )
        return rows
    }

    private var visibleRows: [SwitcherRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return allRows }
        return allRows.filter { $0.title.localizedStandardContains(needle) }
    }

    private func switcherRow(_ row: SwitcherRow) -> some View {
        let isCurrent = row.scope == currentScope
        let isHighlighted = row.scope == highlightedScope

        return Button {
            onSelect(row.scope)
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let colorHex = row.colorHex {
                        Circle()
                            .fill(Color(hex: colorHex))
                            .frame(width: 7, height: 7)
                    } else {
                        Color.clear.frame(width: 7, height: 7)
                    }
                }

                Text(row.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(row.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PinaxCatalogPalette.accentInk(for: colorScheme))
                    .opacity(isCurrent ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? Color.primary.opacity(0.06) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let project = project(for: row.scope) {
                Button("Edit…") { onEdit(project) }
                Divider()
                Button("Delete", role: .destructive) { onDelete(project) }
            }
        }
        .onHover { hovering in
            if hovering { highlightedScope = row.scope }
        }
        .accessibilityLabel("\(row.title), \(row.count) item\(row.count == 1 ? "" : "s")")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func project(for scope: LibraryScope) -> Project? {
        guard case .project(let id) = scope else { return nil }
        return projects.first { $0.id == id }
    }

    private func moveHighlight(by delta: Int) {
        let rows = visibleRows
        guard !rows.isEmpty else { return }
        let currentIndex = rows.firstIndex { $0.scope == highlightedScope } ?? 0
        let next = min(rows.count - 1, max(0, currentIndex + delta))
        highlightedScope = rows[next].scope
    }

    private func confirmHighlighted() {
        if let highlightedScope {
            onSelect(highlightedScope)
        } else if let first = visibleRows.first {
            onSelect(first.scope)
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
        window.backgroundColor = Self.canvasBackground
    }

    private static let canvasBackground = NSColor(name: "PinaxCanvasWindowBackground") { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(srgbRed: 20 / 255, green: 19 / 255, blue: 25 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 244 / 255, green: 244 / 255, blue: 242 / 255, alpha: 1)
    }
}

private struct SwitcherRow: Identifiable {
    var id: LibraryScope { scope }
    let scope: LibraryScope
    let title: String
    let count: Int
    let colorHex: String?
}
