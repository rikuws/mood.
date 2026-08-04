import ImageIO
import PinaxCore
import SwiftUI

struct IOSInspirationCard: View {
    let inspiration: Inspiration
    let localImageURL: URL?
    let canvasColumnCount: Int

    @ScaledMetric(relativeTo: .subheadline) private var titleFontSize = 13.0
    @ScaledMetric(relativeTo: .caption2) private var insetLabelFontSize = 9.0

    private static let aspectRatioCache = NSCache<NSURL, NSNumber>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .overlay(alignment: .bottomLeading) {
                    imageInsetCaption
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: innerCornerRadius,
                        style: .continuous
                    )
                )
                .overlay(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(
                            width: innerCornerRadius + 1,
                            height: innerCornerRadius + 1
                        )
                        .accessibilityHidden(true)
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
        .accessibilityLabel(displayTitle)
        .accessibilityHint("Opens item details")
    }

    private var imageInsetCaption: some View {
        VStack(alignment: .leading, spacing: captionSpacing) {
            if showsSourceLabel {
                Text(previewSourceLabel)
                    .font(
                        .system(
                            size: effectiveInsetLabelFontSize,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(1)
            }

            Text(displayTitle)
                .font(
                    .system(
                        size: effectiveTitleFontSize,
                        weight: .semibold,
                        design: .serif
                    )
                )
                .foregroundStyle(.black.opacity(0.9))
                .lineLimit(titleLineLimit)
                .multilineTextAlignment(.leading)
        }
        .padding(captionInsets)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            SteppedCaptionInsetShape(compact: !showsSourceLabel)
                .fill(Color.white)
        }
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
        if let localImageURL {
            let cacheKey = localImageURL as NSURL
            if let cached = Self.aspectRatioCache.object(forKey: cacheKey) {
                return CGFloat(cached.doubleValue)
            }

            if let source = CGImageSourceCreateWithURL(localImageURL as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
               let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
               height.doubleValue > 0 {
                let ratio = min(
                    max(CGFloat(width.doubleValue / height.doubleValue), 0.8),
                    1.35
                )
                Self.aspectRatioCache.setObject(NSNumber(value: ratio), forKey: cacheKey)
                return ratio
            }
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
        if !inspiration.title.isEmpty { return inspiration.title }
        if !inspiration.text.isEmpty { return inspiration.text }
        return inspiration.url.host() ?? "Untitled item"
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

private struct SteppedCaptionInsetShape: Shape {
    let compact: Bool

    private let preferredCornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        if compact {
            let finalEdge = rect.maxX
            let radius = min(preferredCornerRadius, rect.height / 2)

            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            addOuterCorner(
                to: &path,
                edgeX: finalEdge,
                fromY: rect.minY,
                radius: radius
            )
            path.addLine(to: CGPoint(x: finalEdge, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }

        let firstStepX = rect.minX + (rect.width * 0.56)
        let secondStepX = rect.minX + (rect.width * 0.8)
        let finalEdge = rect.maxX
        let firstShelfY = rect.minY + (rect.height * 0.32)
        let secondShelfY = rect.minY + (rect.height * 0.64)
        let radius = min(
            preferredCornerRadius,
            (firstShelfY - rect.minY) / 2,
            (secondShelfY - firstShelfY) / 2,
            (finalEdge - secondStepX) / 2
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        addRoundedStep(
            to: &path,
            stepX: firstStepX,
            fromY: rect.minY,
            toY: firstShelfY,
            radius: radius
        )
        addRoundedStep(
            to: &path,
            stepX: secondStepX,
            fromY: firstShelfY,
            toY: secondShelfY,
            radius: radius
        )
        addOuterCorner(
            to: &path,
            edgeX: finalEdge,
            fromY: secondShelfY,
            radius: radius
        )
        path.addLine(to: CGPoint(x: finalEdge, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func addRoundedStep(
        to path: inout Path,
        stepX: CGFloat,
        fromY: CGFloat,
        toY: CGFloat,
        radius: CGFloat
    ) {
        let curve = radius * 0.552_284_75

        path.addLine(to: CGPoint(x: stepX - radius, y: fromY))
        path.addCurve(
            to: CGPoint(x: stepX, y: fromY + radius),
            control1: CGPoint(x: stepX - radius + curve, y: fromY),
            control2: CGPoint(x: stepX, y: fromY + radius - curve)
        )
        path.addLine(to: CGPoint(x: stepX, y: toY - radius))
        path.addCurve(
            to: CGPoint(x: stepX + radius, y: toY),
            control1: CGPoint(x: stepX, y: toY - radius + curve),
            control2: CGPoint(x: stepX + radius - curve, y: toY)
        )
    }

    private func addOuterCorner(
        to path: inout Path,
        edgeX: CGFloat,
        fromY: CGFloat,
        radius: CGFloat
    ) {
        let curve = radius * 0.552_284_75

        path.addLine(to: CGPoint(x: edgeX - radius, y: fromY))
        path.addCurve(
            to: CGPoint(x: edgeX, y: fromY + radius),
            control1: CGPoint(x: edgeX - radius + curve, y: fromY),
            control2: CGPoint(x: edgeX, y: fromY + radius - curve)
        )
    }
}
