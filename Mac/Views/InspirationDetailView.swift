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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview

                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayTitle)
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .textSelection(.enabled)

                        if let byline {
                            Text(byline)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if !inspiration.text.isEmpty, inspiration.text != inspiration.title {
                            Text(inspiration.text)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineSpacing(3)
                        }
                    }

                    metadata
                }
                .padding(18)
            }

            Divider()
            actionBar
        }
        .background(PinaxCatalogPalette.folio(for: colorScheme))
        .frame(minWidth: 340, idealWidth: 400, maxWidth: 470)
    }

    private var header: some View {
        HStack {
            Text("Details")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close details")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PinaxCatalogPalette.previewSurface(for: colorScheme))

            if let localImageURL, let image = NSImage(contentsOf: localImageURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let imageURL = inspiration.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        previewPlaceholder
                    @unknown default:
                        previewPlaceholder
                    }
                }
            } else {
                previewPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.09), lineWidth: 0.5)
        }
    }

    private var previewPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            if inspiration.source != .x {
                Label(sourceLabel, systemImage: "globe")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(previewText.isEmpty ? displayTitle : previewText)
                .font(.system(size: 19, weight: .medium, design: .serif))
                .lineSpacing(3)
                .lineLimit(7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            inspiration.source == .x
                ? PinaxCatalogPalette.quoteSurface(for: colorScheme)
                : PinaxCatalogPalette.webSurface(for: colorScheme)
        )
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(project?.name ?? "General", systemImage: project == nil ? "tray" : "folder")
            Label(inspiration.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            Label(sourceLabel, systemImage: "link")
                .lineLimit(1)
                .help(inspiration.url.absoluteString)
            if inspiration.captureCount > 1 {
                Label("Saved \(inspiration.captureCount) times", systemImage: "square.stack.3d.up")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button {
                openURL(inspiration.url)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            .keyboardShortcut(.return, modifiers: [.command])

            ShareLink(item: inspiration.url) {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Share")

            Menu {
                Button("General") { onMove(nil) }
                Divider()
                ForEach(projects) { project in
                    Button(project.name) { onMove(project.id) }
                }
            } label: {
                Image(systemName: "folder")
            }
            .help("Move to project")

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .help("Edit")

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .frame(height: 52)
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
        if !previewText.isEmpty { return previewText }
        if let xHandle { return "Post by @\(xHandle)" }
        if !title.isEmpty { return title }
        return inspiration.url.host() ?? "Untitled inspiration"
    }

    private var previewText: String {
        inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
