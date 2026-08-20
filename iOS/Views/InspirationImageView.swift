import PinaxCore
import SwiftUI

struct InspirationImageView: View {
    let inspiration: Inspiration
    let localImageURL: URL?
    var contentMode: ContentMode = .fill
    var showsFallbackMetadata = true
    var compactFallback = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.pinaxPreviewSurface)

            if localImageURL != nil || inspiration.imageURL != nil {
                DownsampledPreviewImage(
                    localURL: localImageURL,
                    remoteURL: inspiration.imageURL,
                    contentMode: contentMode
                ) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } failure: {
                    fallbackPreview
                }
            } else {
                fallbackPreview
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewAccessibilityLabel)
    }

    @ViewBuilder
    private var fallbackPreview: some View {
        if inspiration.source == .x, !previewCopy.isEmpty {
            quotePreview
        } else {
            webPreview
        }
    }

    private var quotePreview: some View {
        ZStack(alignment: .topLeading) {
            quoteBackground

            Text("“")
                .font(
                    .system(
                        size: compactFallback ? 30 : 62,
                        weight: .regular,
                        design: .serif
                    )
                )
                .foregroundStyle(.white.opacity(0.18))
                .padding(.horizontal, compactFallback ? 8 : 15)
                .padding(.top, compactFallback ? 3 : 6)

            VStack(alignment: .leading, spacing: compactFallback ? 6 : 12) {
                Spacer(minLength: compactFallback ? 10 : 24)

                if showsFallbackMetadata, let quoteTitle {
                    Text(quoteTitle)
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                }

                Text(previewCopy)
                    .font(
                        .system(
                            size: compactFallback ? 10 : 16,
                            weight: .medium,
                            design: .serif
                        )
                    )
                    .foregroundStyle(.white)
                    .lineSpacing(compactFallback ? 0 : 2)
                    .lineLimit(
                        showsFallbackMetadata
                            ? (quoteTitle == nil ? 6 : 5)
                            : (compactFallback ? 3 : 4)
                    )

                Spacer(minLength: compactFallback ? 4 : 8)

                if showsFallbackMetadata {
                    if let byline {
                        Text(byline)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    } else {
                        Text("Saved from X")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
            .padding(compactFallback ? 8 : 18)
        }
    }

    private var webPreview: some View {
        VStack(alignment: .leading, spacing: compactFallback ? 8 : 14) {
            if showsFallbackMetadata {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.caption.weight(.semibold))
                    Text(inspiration.url.host() ?? "Saved link")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text(displayTitle)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                if !webExcerpt.isEmpty {
                    Text(webExcerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(3)
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.pinaxRose)
                        .frame(width: 6, height: 6)
                    Text("Saved reference")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(webArtworkCopy)
                    .font(
                        .system(
                            size: compactFallback ? 10 : 16,
                            weight: .medium,
                            design: .serif
                        )
                    )
                    .foregroundStyle(.secondary)
                    .lineSpacing(compactFallback ? 0 : 2)
                    .lineLimit(compactFallback ? 3 : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(compactFallback ? 8 : 18)
        .background(Color.pinaxPreviewSurface)
    }

    private var displayTitle: String {
        let title = inspiration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let text = inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return inspiration.url.host() ?? "Untitled item"
    }

    private var previewCopy: String {
        let text = inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return inspiration.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var quoteTitle: String? {
        let title = inspiration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != previewCopy else { return nil }
        return title
    }

    private var webExcerpt: String {
        let text = inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != displayTitle else { return "" }
        return text
    }

    private var webArtworkCopy: String {
        webExcerpt.isEmpty ? displayTitle : webExcerpt
    }

    private var byline: String? {
        if let name = inspiration.authorName, let handle = inspiration.authorHandle {
            return "\(name) · @\(handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))"
        }
        if let name = inspiration.authorName { return name }
        if let handle = inspiration.authorHandle {
            return "@\(handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))"
        }
        return nil
    }

    private var quoteBackground: Color {
        let palette: [Color] = [
            .black,
            Color(white: 0.067),
            Color(white: 0.122),
            Color(white: 0.173),
        ]
        let index = inspiration.id.uuidString.unicodeScalars.reduce(0) {
            $0 + Int($1.value)
        } % palette.count
        return palette[index]
    }

    private var previewAccessibilityLabel: String {
        if inspiration.source == .x {
            return "Post preview: \(previewCopy.isEmpty ? displayTitle : previewCopy)"
        }
        return "Web preview: \(displayTitle)"
    }
}
