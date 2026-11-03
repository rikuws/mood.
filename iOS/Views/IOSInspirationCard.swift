import PinaxCore
import SwiftUI

struct IOSInspirationCard: View {
    let inspiration: Inspiration
    let localImageURL: URL?
    let canvasColumnCount: Int

    @ScaledMetric(relativeTo: .subheadline) private var titleFontSize = 13.0
    @ScaledMetric(relativeTo: .caption2) private var insetLabelFontSize = 9.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .overlay(alignment: .bottomLeading) {
                    if showsCaption {
                        imageInsetCaption
                    }
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: innerCornerRadius,
                        style: .continuous
                    )
                )
                .overlay(alignment: .bottomLeading) {
                    if showsCaption {
                        Rectangle()
                            .fill(Color.white)
                            .frame(
                                width: innerCornerRadius + 1,
                                height: innerCornerRadius + 1
                            )
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let motion = inspiration.motion {
                        MotionBadge(motion: motion)
                    }
                }
        }
        .padding(matInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: outerCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .stroke(.black.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(
            color: .black.opacity(canvasColumnCount >= 3 ? 0.06 : 0.09),
            radius: canvasColumnCount >= 3 ? 1 : 2,
            y: 1
        )
        .contentShape(
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayTitle + (inspiration.motion.map { ", \($0.spokenDescription)" } ?? ""))
        .accessibilityHint("Opens item details")
    }

    private var imageInsetCaption: some View {
        InspirationCardCaption(
            label: showsSourceLabel ? previewSourceLabel : nil,
            title: captionTitle,
            labelFontSize: effectiveInsetLabelFontSize,
            titleFontSize: effectiveTitleFontSize,
            titleLineLimit: titleLineLimit,
            spacing: captionSpacing,
            insets: captionInsets,
            cornerRadius: showsSourceLabel && captionTitle != nil ? 10 : 4
        )
    }

    @ViewBuilder
    private var preview: some View {
        if hasImagePreview {
            Rectangle()
                .fill(.clear)
                .aspectRatio(imagePreviewAspectRatio, contentMode: .fit)
                .overlay {
                    InspirationImageView(
                        inspiration: inspiration,
                        localImageURL: localImageURL,
                        showsFallbackMetadata: false,
                        compactFallback: canvasColumnCount >= 3
                    )
                }
                .clipped()
        } else {
            InspirationImageView(
                inspiration: inspiration,
                localImageURL: localImageURL,
                showsFallbackMetadata: false,
                compactFallback: canvasColumnCount >= 3
            )
            .frame(minHeight: fallbackPreviewMinimumHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var matInset: CGFloat {
        switch canvasColumnCount {
        case 1: 10
        case 2: 8
        case 3: 5
        default: 3
        }
    }

    private var outerCornerRadius: CGFloat {
        switch canvasColumnCount {
        case 1: 5
        case 2: 4
        default: 3
        }
    }

    private var innerCornerRadius: CGFloat {
        max(1.5, outerCornerRadius - 2)
    }

    private var showsSourceLabel: Bool {
        inspiration.source != .x && canvasColumnCount <= 2
    }

    private var effectiveTitleFontSize: CGFloat {
        switch canvasColumnCount {
        case 1: titleFontSize * 1.15
        case 2: titleFontSize
        case 3: titleFontSize * 0.8
        default: titleFontSize * 0.64
        }
    }

    private var effectiveInsetLabelFontSize: CGFloat {
        canvasColumnCount == 1 ? insetLabelFontSize * 1.1 : insetLabelFontSize
    }

    private var titleLineLimit: Int {
        switch canvasColumnCount {
        case 1...2: 3
        case 3: 2
        default: 1
        }
    }

    private var captionSpacing: CGFloat {
        canvasColumnCount <= 2 ? 8 : 0
    }

    private var captionPadding: CGFloat {
        switch canvasColumnCount {
        case 1...2: 5.5
        case 3: 3.5
        default: 2.5
        }
    }

    private var captionInsets: EdgeInsets {
        EdgeInsets(
            top: captionPadding,
            leading: captionPadding,
            bottom: captionPadding,
            trailing: captionPadding + 2
        )
    }

    private var fallbackPreviewMinimumHeight: CGFloat {
        let base: CGFloat = inspiration.source == .x ? 154 : 174
        switch canvasColumnCount {
        case 1: return base * 1.45
        case 2: return base
        case 3: return base * 0.72
        default: return base * 0.52
        }
    }

    private var hasImagePreview: Bool {
        localImageURL != nil || inspiration.imageURL != nil
    }

    private var imagePreviewAspectRatio: CGFloat {
        if let localImageURL,
           let ratio = PreviewImageDecoder.aspectRatio(
            at: localImageURL,
            clampedTo: 0.8...1.35
           ) {
            return ratio
        }

        let ratios: [CGFloat] = [0.82, 0.96, 1.12, 1.28]
        return ratios[layoutSeed % ratios.count]
    }

    private var layoutSeed: Int {
        inspiration.id.uuidString.unicodeScalars.reduce(0) {
            $0 + Int($1.value)
        }
    }

    private var displayTitle: String {
        if inspiration.source == .x {
            return inspiration.xUsernameLabel ?? "X"
        }
        return captionTitle ?? inspiration.url.host() ?? "Untitled item"
    }

    /// What the caption names the item, or nil when it's an image with
    /// nothing to add: a file name like "IMG_2041.jpeg" says less than the
    /// picture, so the caption keeps to the source.
    private var captionTitle: String? {
        if let title = inspiration.meaningfulTitle { return title }
        let text = inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return hasImagePreview ? nil : (inspiration.url.host() ?? "Untitled item")
    }

    private var showsCaption: Bool {
        inspiration.source != .x && (showsSourceLabel || captionTitle != nil)
    }

    private var previewSourceLabel: String {
        if let name = inspiration.authorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let handle = inspiration.authorHandle {
            return "@\(handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))"
        }
        return inspiration.url.host() ?? "Saved reference"
    }
}
