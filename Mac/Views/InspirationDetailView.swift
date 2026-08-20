import PinaxCore
import SwiftUI

struct InspirationDetailView: View {
    let inspiration: Inspiration
    let localImageURL: URL?
    let project: Project?
    let projects: [Project]
    let onMove: (Project.ID?) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            hero
                .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
                .layoutPriority(1)

            details
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 18)

            actionBar
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(folio)
        .overlay(alignment: .topTrailing) { closeButton }
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 480)
        .accessibilityElement(children: .contain)
    }

    private var hero: some View {
        GeometryReader { geometry in
            let topFade = min(88, max(52, geometry.size.height * 0.12))
            let bottomFade = min(160, max(72, geometry.size.height * 0.22))

            ZStack {
                folio

                if hasPreviewImage, !reduceTransparency {
                    DownsampledPreviewImage(
                        localURL: localImageURL,
                        remoteURL: inspiration.imageURL,
                        contentMode: .fill
                    ) {
                        Color.clear
                    } failure: {
                        Color.clear
                    }
                    .scaleEffect(1.16)
                    .blur(radius: 32)
                    .overlay(wash)
                }

                if hasPreviewImage {
                    DownsampledPreviewImage(
                        localURL: localImageURL,
                        remoteURL: inspiration.imageURL,
                        contentMode: .fit
                    ) {
                        ProgressView()
                    } failure: {
                        previewPlaceholder
                    }
                } else {
                    previewPlaceholder
                }

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(colorScheme == .dark ? 0.38 : 0.16),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: topFade)

                    Spacer(minLength: 0)

                    LinearGradient(
                        stops: [
                            .init(color: folio.opacity(0), location: 0),
                            .init(color: folio.opacity(0.55), location: 0.52),
                            .init(color: folio, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bottomFade)
                }
                .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewAccessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .tracking(-0.3)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                if let byline {
                    Text(byline)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let bodyText {
                    Text(bodyText)
                        .font(bodyFont)
                        .foregroundStyle(.primary)
                        .lineSpacing(5)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
            }

            metadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow(project?.name ?? "General") {
                if let project, let colorHex = project.colorHex {
                    Circle()
                        .fill(Color(hex: colorHex))
                        .frame(width: 8, height: 8)
                } else if project != nil {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 12, weight: .medium))
                }
            }

            metadataRow(
                inspiration.createdAt.formatted(date: .abbreviated, time: .shortened),
                systemImage: "clock"
            )

            metadataRow(sourceLabel, systemImage: "link")
                .help(inspiration.url.absoluteString)

            if inspiration.captureCount > 1 {
                metadataRow(
                    "Saved \(inspiration.captureCount) times",
                    systemImage: "square.stack.3d.up"
                )
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                openURL(inspiration.url)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Open original")

            Spacer(minLength: 8)

            ShareLink(item: inspiration.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Share")
            .accessibilityLabel("Share")

            Menu {
                Button("General") { onMove(nil) }
                Divider()
                ForEach(projects) { project in
                    Button(project.name) { onMove(project.id) }
                }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Move to project")
            .accessibilityLabel("Move to project")

            toolbarButton("pencil", help: "Edit", action: onEdit)

            toolbarButton("trash", help: "Delete", role: .destructive, action: onDelete)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.primary.opacity(0.14), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .help("Close details")
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Close details")
        .padding(.top, 14)
        .padding(.trailing, 12)
    }

    private var previewPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            if inspiration.source != .x {
                Label(sourceLabel, systemImage: "globe")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(placeholderText)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .lineSpacing(5)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            inspiration.source == .x
                ? PinaxCatalogPalette.quoteSurface(for: colorScheme)
                : PinaxCatalogPalette.webSurface(for: colorScheme)
        )
    }

    private func metadataRow(_ title: String, systemImage: String) -> some View {
        metadataRow(title) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private func metadataRow<Icon: View>(
        _ title: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon()
                .frame(width: 16, alignment: .center)
            Text(title)
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }

    private func toolbarButton(
        _ systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }

    private var folio: Color {
        PinaxCatalogPalette.folio(for: colorScheme)
    }

    private var wash: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.46)
            : Color.white.opacity(0.34)
    }

    private var hasPreviewImage: Bool {
        localImageURL != nil || inspiration.imageURL != nil
    }

    private var bodyFont: Font {
        inspiration.source == .x
            ? .system(size: 17, weight: .medium, design: .serif)
            : .system(size: 16, weight: .regular)
    }

    private var bodyText: String? {
        let text = inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != inspiration.title, text != displayTitle else { return nil }
        return text
    }

    private var byline: String? {
        guard inspiration.source != .x else { return nil }
        if let name = inspiration.authorName, let handle = xHandle {
            return "\(name)  @\(handle)"
        }
        if let name = inspiration.authorName { return name }
        if let handle = xHandle {
            return "@\(handle)"
        }
        return nil
    }

    private var displayTitle: String {
        if inspiration.source == .x {
            return inspiration.xUsernameLabel ?? "X"
        }
        let title = inspiration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = inspiration.url.host()?.lowercased()
        if !title.isEmpty, title.lowercased() != (host ?? "") { return title }
        let previewText = inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !previewText.isEmpty { return previewText }
        if let xHandle { return "Post by @\(xHandle)" }
        if !title.isEmpty { return title }
        return inspiration.url.host() ?? "Untitled item"
    }

    private var placeholderText: String {
        let text = inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return displayTitle
    }

    private var previewAccessibilityLabel: String {
        if let bodyText {
            return "\(displayTitle). \(bodyText)"
        }
        return displayTitle
    }

    private var sourceLabel: String {
        inspiration.url.host() ?? inspiration.url.absoluteString
    }

    private var xHandle: String? {
        if let handle = inspiration.authorHandle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
           !handle.isEmpty {
            return handle
        }

        guard inspiration.source == .x else { return nil }
        let path = inspiration.url.pathComponents.filter { $0 != "/" }
        guard path.count >= 3,
              path[1].lowercased() == "status",
              path[0].lowercased() != "i" else {
            return nil
        }
        return path[0]
    }
}
