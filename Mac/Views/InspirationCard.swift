import PinaxCore
import SwiftUI

struct InspirationCard: View {
    let inspiration: Inspiration
    let localImageURL: URL?
    let canvasColumnCount: Int
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            cardArtwork(for: canvasColumnCount)
                .padding(matInset(for: canvasColumnCount))
                .background(Color.white)
                .clipShape(cardShape)
                .overlay {
                    cardShape.strokeBorder(.black.opacity(0.1), lineWidth: 0.5)

                    if isSelected {
                        cardShape.strokeBorder(
                            PinaxCatalogPalette.selectionInk,
                            lineWidth: 2
                        )
                    }
                }
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: isSelected ? 0 : (isHovering ? 8 : 4),
                    y: isSelected ? 0 : (isHovering ? 5 : 2)
                )
                .offset(y: isHovering && !isSelected && !reduceMotion ? -2 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)
        }
        .buttonStyle(.plain)
        .contentShape(cardShape)
        .onHover { isHovering = $0 }
        .draggable(inspiration.url.absoluteString) {
            dragPreview
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens item details")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cardArtwork(for density: Int) -> some View {
        preview(for: density)
            .overlay(alignment: .bottomLeading) {
                if inspiration.source != .x {
                    insetCaption(for: density)
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: innerCornerRadius(for: density),
                    style: .continuous
                )
            )
    }

    private func preview(for density: Int) -> some View {
        Rectangle()
            .fill(PinaxCatalogPalette.previewSurface(for: colorScheme))
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .overlay {
                Group {
                    if localImageURL != nil || inspiration.imageURL != nil {
                        DownsampledPreviewImage(
                            localURL: localImageURL,
                            remoteURL: inspiration.imageURL
                        ) {
                            fallbackPreview(for: density)
                                .opacity(0.72)
                                .redacted(reason: .placeholder)
                        } failure: {
                            fallbackPreview(for: density)
                        }
                        .scaleEffect(isHovering && !reduceMotion ? 1.018 : 1)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.2),
                            value: isHovering
                        )
                    } else {
                        fallbackPreview(for: density)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
    }

    @ViewBuilder
    private func fallbackPreview(for density: Int) -> some View {
        if inspiration.source == .x {
            quotePreview(for: density)
        } else {
            webpagePreview(for: density)
        }
    }

    private func quotePreview(for density: Int) -> some View {
        ZStack(alignment: .topLeading) {
            quoteBackground

            Text("“")
                .font(
                    .system(
                        size: quoteMarkFontSize(for: density),
                        weight: .regular,
                        design: .serif
                    )
                )
                .foregroundStyle(.white.opacity(0.18))
                .padding(.horizontal, artworkPadding(for: density))
                .padding(.top, max(2, artworkPadding(for: density) / 3))

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: artworkPadding(for: density))

                Text(previewText.isEmpty ? displayTitle : previewText)
                    .font(
                        .system(
                            size: fallbackFontSize(for: density),
                            weight: .medium,
                            design: .serif
                        )
                    )
                    .foregroundStyle(.white)
                    .lineSpacing(density <= 2 ? 2 : 0)
                    .lineLimit(fallbackLineLimit(for: density))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: artworkPadding(for: density))
            }
            .padding(artworkPadding(for: density))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func webpagePreview(for density: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: artworkPadding(for: density))

            Text(previewText.isEmpty ? displayTitle : previewText)
                .font(
                    .system(
                        size: fallbackFontSize(for: density),
                        weight: .medium,
                        design: .serif
                    )
                )
                .foregroundStyle(.primary.opacity(0.82))
                .lineSpacing(density <= 2 ? 2 : 0)
                .lineLimit(fallbackLineLimit(for: density))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: fallbackCaptionClearance(for: density))
        }
        .padding(artworkPadding(for: density))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(PinaxCatalogPalette.webSurface(for: colorScheme))
    }

    private func insetCaption(for density: Int) -> some View {
        VStack(alignment: .leading, spacing: captionSpacing(for: density)) {
            if showsSourceLabel(for: density) {
                Text(previewSourceLabel)
                    .font(
                        .system(
                            size: sourceFontSize(for: density),
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.black.opacity(0.78))
                    .lineLimit(1)
            }

            Text(compactDisplayTitle(for: density))
                .font(
                    .system(
                        size: titleFontSize(for: density),
                        weight: .semibold,
                        design: .serif
                    )
                )
                .foregroundStyle(.black.opacity(0.9))
                .lineLimit(titleLineLimit(for: density))
                .multilineTextAlignment(.leading)
                .offset(
                    x: inspiration.source == .x ? -0.75 : 0,
                    y: inspiration.source == .x ? 0.5 : 0
                )
        }
        .padding(captionInsets(for: density))
        .fixedSize(horizontal: false, vertical: true)
        .background {
            SteppedCaptionInsetShape(compact: !showsSourceLabel(for: density))
                .fill(Color.white)
        }
    }

    private var dragPreview: some View {
        cardArtwork(for: 3)
            .padding(matInset(for: 3))
            .frame(width: 190, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius(for: 3), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: outerCornerRadius(for: 3), style: .continuous)
                    .strokeBorder(.black.opacity(0.1), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 7, y: 4)
            .rotationEffect(.degrees(-1.5))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: outerCornerRadius(for: canvasColumnCount),
            style: .continuous
        )
    }

    private var previewText: String {
        inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewSourceLabel: String {
        if let name = inspiration.authorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if inspiration.source == .x, let handle = xHandle { return "@\(handle)" }
        return inspiration.url.host() ?? inspiration.url.absoluteString
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
        return inspiration.url.host() ?? "Untitled item"
    }

    private var shadowOpacity: Double {
        if colorScheme == .dark { return isHovering ? 0.36 : 0.24 }
        return isHovering ? 0.14 : 0.075
    }

    private var accessibilityLabel: String {
        if inspiration.source == .x { return displayTitle }
        return "\(displayTitle), from \(previewSourceLabel)"
    }

    private var previewAspectRatio: CGFloat {
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

    private var quoteBackground: Color {
        PinaxCatalogPalette.quoteFill(seed: layoutSeed)
    }

    private func compactDisplayTitle(for density: Int) -> String {
        guard density >= 5 else { return displayTitle }
        return displayTitle
            .split(whereSeparator: { $0.isNewline })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? displayTitle
    }

    private func matInset(for density: Int) -> CGFloat {
        switch density {
        case 1: 10
        case 2: 8
        case 3: 6
        case 4: 5
        case 5: 4
        default: 3
        }
    }

    private func outerCornerRadius(for density: Int) -> CGFloat {
        switch density {
        case 1: 5
        case 2...3: 4
        default: 3
        }
    }

    private func innerCornerRadius(for density: Int) -> CGFloat {
        max(1, outerCornerRadius(for: density) - 2)
    }

    private func showsSourceLabel(for density: Int) -> Bool {
        inspiration.source != .x && density <= 3
    }

    private func titleFontSize(for density: Int) -> CGFloat {
        switch density {
        case 1: 18
        case 2: 15
        case 3: 13
        case 4: 11.5
        case 5: 10.5
        case 6: 9.5
        case 7: 9
        default: 8.5
        }
    }

    private func sourceFontSize(for density: Int) -> CGFloat {
        switch density {
        case 1: 11
        case 2: 10
        default: 9
        }
    }

    private func titleLineLimit(for density: Int) -> Int {
        switch density {
        case 1...2: 3
        case 3...4: 2
        default: 1
        }
    }

    private func captionSpacing(for density: Int) -> CGFloat {
        switch density {
        case 1: 8
        case 2: 6
        case 3: 4
        default: 0
        }
    }

    private func captionPadding(for density: Int) -> CGFloat {
        switch density {
        case 1: 6
        case 2: 5.5
        case 3: 4.5
        case 4...5: 3.5
        default: 2.5
        }
    }

    private func captionInsets(for density: Int) -> EdgeInsets {
        let inset = captionPadding(for: density)
        return EdgeInsets(
            top: inset,
            leading: inset,
            bottom: inset,
            trailing: inset
        )
    }

    private func artworkPadding(for density: Int) -> CGFloat {
        switch density {
        case 1: 30
        case 2: 22
        case 3: 16
        case 4: 12
        case 5: 9
        default: 7
        }
    }

    private func fallbackFontSize(for density: Int) -> CGFloat {
        switch density {
        case 1: 24
        case 2: 18
        case 3: 15
        case 4: 12
        case 5: 10.5
        case 6: 9.5
        case 7: 8.5
        default: 8
        }
    }

    private func quoteMarkFontSize(for density: Int) -> CGFloat {
        switch density {
        case 1: 76
        case 2: 58
        case 3: 44
        case 4: 34
        default: 26
        }
    }

    private func fallbackLineLimit(for density: Int) -> Int {
        switch density {
        case 1: 7
        case 2: 5
        case 3: 4
        case 4: 3
        default: 2
        }
    }

    private func fallbackCaptionClearance(for density: Int) -> CGFloat {
        switch density {
        case 1: 86
        case 2: 66
        case 3: 52
        case 4: 38
        default: 28
        }
    }
}

private struct SteppedCaptionInsetShape: Shape {
    let compact: Bool

    private let preferredCornerRadius: CGFloat = 10
    private let compactCornerRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        if compact {
            let finalEdge = rect.maxX
            let radius = min(compactCornerRadius, rect.height / 2)

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

enum PinaxCatalogPalette {
    /// Black keyline on the permanent white card mat.
    static let selectionInk = Color.black

    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : Color(white: 0.96)
    }

    static func folio(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.067) : .white
    }

    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .black
    }

    static func accentInk(for colorScheme: ColorScheme) -> Color {
        accent(for: colorScheme)
    }

    static func previewSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.102) : Color(white: 0.941)
    }

    static func quoteSurface(for colorScheme: ColorScheme) -> Color {
        previewSurface(for: colorScheme)
    }

    static func webSurface(for colorScheme: ColorScheme) -> Color {
        previewSurface(for: colorScheme)
    }

    static func quoteFill(seed: Int) -> Color {
        let palette: [Color] = [
            .black,
            Color(white: 0.067),
            Color(white: 0.122),
            Color(white: 0.173),
        ]
        return palette[abs(seed) % palette.count]
    }
}
