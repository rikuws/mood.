import SwiftUI

/// The white caption that grows out of a card's lower-left corner, the same
/// on both platforms: the source on a rounded shelf above the title, each as
/// wide as its own words, so the step follows the text and never cuts
/// across a line or lets a glyph run onto the picture.
struct InspirationCardCaption: View {
    let label: String?
    let title: String?
    let labelFontSize: CGFloat
    let titleFontSize: CGFloat
    let titleLineLimit: Int
    let spacing: CGFloat
    let insets: EdgeInsets
    let cornerRadius: CGFloat

    @State private var labelFrame: CGRect?

    private static let space = "InspirationCardCaption"

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let label {
                Text(label)
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.78))
                    .lineLimit(1)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.space))
                    } action: { frame in
                        labelFrame = frame
                    }
            }

            if let title {
                Text(title)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .serif))
                    .foregroundStyle(.black.opacity(0.9))
                    .lineLimit(titleLineLimit)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(insets)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(.named(Self.space))
        .background {
            SteppedCaptionInsetShape(shelf: shelf, cornerRadius: cornerRadius)
                .fill(Color.white)
        }
    }

    /// The source's own width and height, ending halfway to the title.
    private var shelf: CGSize? {
        guard label != nil, title != nil, let labelFrame else { return nil }
        return CGSize(
            width: labelFrame.maxX + insets.trailing,
            height: labelFrame.maxY + (spacing / 2)
        )
    }
}

private struct SteppedCaptionInsetShape: Shape {
    /// The source's shelf, measured from the caption's top-leading corner.
    /// Without one, or when the title is barely wider, it's a single block.
    var shelf: CGSize?
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        if let shelf, rect.maxX - (rect.minX + shelf.width) >= cornerRadius {
            let stepX = rect.minX + shelf.width
            let shelfY = rect.minY + shelf.height
            let radius = min(
                cornerRadius,
                shelf.height / 2,
                (rect.maxX - stepX) / 2,
                rect.maxY - shelfY
            )
            addRoundedStep(
                to: &path,
                stepX: stepX,
                fromY: rect.minY,
                toY: shelfY,
                radius: radius
            )
            addOuterCorner(
                to: &path,
                edgeX: rect.maxX,
                fromY: shelfY,
                radius: radius
            )
        } else {
            addOuterCorner(
                to: &path,
                edgeX: rect.maxX,
                fromY: rect.minY,
                radius: min(cornerRadius, rect.height / 2)
            )
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
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
