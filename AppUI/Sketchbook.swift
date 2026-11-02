import CoreText
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Palette

/// The study board's two hands on one page. The agent drafts in pencil and
/// writes its notes in graphite; the person decides in ink. Saved work stays
/// crisp and is never drawn on: a kept find is circled, not marked up.
enum Sketchbook {
    /// Warm paper under the study board, in place of the moodboard's scenery.
    static let paper = Color(light: 0xF2EDE3, dark: 0x1A1916)
    /// A slip of lighter paper on it, such as a move's index card.
    static let sheet = Color(light: 0xFBF8F1, dark: 0x23211D)
    /// The agent's words: why a find is here, a pattern's label.
    static let graphite = Color(light: 0x6A655B, dark: 0xA29C90)
    /// The agent's marks: a proposed pattern's frame, slots still being filled.
    static let pencil = Color(light: 0x8F897C, dark: 0x7E786D)
    /// The person's marks and words: kept, rejected, reasons, the current filter.
    static let ink = Color(light: 0x2C43A3, dark: 0x93A6F2)

    static func inkStroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(sketchHex: isDark ? dark : light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(sketchHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(sketchHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#else
private extension UIColor {
    convenience init(sketchHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

// MARK: - Type

enum SketchbookType {
    /// Geist Serif, for display sizes only (28 pt and up): its hairlines are
    /// cut for headlines and thin out below that. The system serif stands in
    /// if the font can't be loaded.
    static func display(size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        guard GeistSerif.isAvailable else {
            return .system(size: size, weight: .medium, design: .serif)
        }
        return .custom(GeistSerif.postScriptName, size: size, relativeTo: style)
    }
}

/// Bundled with both apps under the SIL Open Font License (see
/// `GeistSerif-OFL.txt`) and registered for the process on first use.
private enum GeistSerif {
    static let postScriptName = "GeistSerif-Regular"

    static let isAvailable: Bool = {
        guard let url = Bundle.main.url(forResource: postScriptName, withExtension: "woff2") else {
            return false
        }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            return true
        }
        guard let error = error?.takeRetainedValue() else { return false }
        return CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue
    }()
}

// MARK: - Paper

/// The study board's paper: a warm ground with a little tooth.
struct SketchPaper: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Sketchbook.paper
            .overlay {
                Image(decorative: SketchPaperGrain.tile, scale: 2)
                    .resizable(resizingMode: .tile)
                    .blendMode(colorScheme == .dark ? .screen : .multiply)
                    .opacity(colorScheme == .dark ? 0.07 : 0.3)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

@MainActor
private enum SketchPaperGrain {
    static let tile = make()

    /// Warm specks at random strengths, drawn once and tiled.
    private static func make() -> CGImage {
        let side = 160
        let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var jitter = SketchJitter(seed: 0x7061_7065_72)
        for index in 0..<(side * side) {
            let alpha = max(0, jitter.next()) * 0.45
            let tone = 0.42 + jitter.next() * 0.12
            pixels[index * 4 + 0] = UInt8(255 * tone * alpha)
            pixels[index * 4 + 1] = UInt8(255 * (tone - 0.05) * alpha)
            pixels[index * 4 + 2] = UInt8(255 * (tone - 0.13) * alpha)
            pixels[index * 4 + 3] = UInt8(255 * alpha)
        }
        return context.makeImage()!
    }
}

// MARK: - Marks

/// A small, stable source of wobble, so a mark is drawn the same way every
/// time its card is.
struct SketchJitter {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    init(seed: UUID) {
        self.init(seed: Self.seed(for: seed))
    }

    /// The same number for the same ID on every launch, unlike `hashValue`.
    static func seed(for id: UUID) -> UInt64 {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            }
        }
        return value
    }

    /// The next value, between -1 and 1.
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(Double(z >> 11) / Double(UInt64(1) << 53)) * 2 - 1
    }
}

/// A loose ink loop around a kept card, like a select circled on a contact
/// sheet: a quick rounded box that runs a little past where it started.
struct InkLoop: Shape {
    var seed: UUID

    func path(in rect: CGRect) -> Path {
        var jitter = SketchJitter(seed: seed)
        let outline = RoundedOutline(rect: rect, radius: min(12, min(rect.width, rect.height) / 2))
        let wobble = min(3, min(rect.width, rect.height) * 0.04)
        // Starts along the top edge and runs a little past where it began.
        let start = outline.length * (0.06 + 0.04 * jitter.next())
        let run = outline.length * (1.07 + 0.02 * jitter.next())
        let sampleCount = max(24, Int(run / 9))
        let swellPhase = jitter.next() * .pi

        var drift = CGSize.zero
        var points: [CGPoint] = []
        for index in 0...sampleCount {
            let progress = CGFloat(index) / CGFloat(sampleCount)
            let (point, outward) = outline.point(at: start + run * progress)
            // Wobble that wanders rather than shakes.
            drift.width = drift.width * 0.9 + jitter.next() * wobble * 0.35
            drift.height = drift.height * 0.9 + jitter.next() * wobble * 0.35
            // A hand bows the sides out and pulls the corners in a little.
            let swell = 1.2 + 2.2 * sin(progress * 4 * .pi + swellPhase)
            // The tail swings outward, so it crosses the start instead of
            // closing neatly on it.
            let tail = max(0, (progress - 0.88) / 0.12) * 4
            points.append(
                CGPoint(
                    x: point.x + drift.width + outward.dx * (swell + tail),
                    y: point.y + drift.height + outward.dy * (swell + tail)
                )
            )
        }
        return Path.sketchCurve(through: points)
    }
}

/// A rounded box walked by distance, clockwise from its top-left corner, so
/// a mark can follow it at an even pace and know which way is outward.
private struct RoundedOutline {
    let rect: CGRect
    let radius: CGFloat

    private var straightWidth: CGFloat { max(0, rect.width - 2 * radius) }
    private var straightHeight: CGFloat { max(0, rect.height - 2 * radius) }
    private var corner: CGFloat { .pi / 2 * radius }

    var length: CGFloat { 2 * (straightWidth + straightHeight) + 4 * corner }

    func point(at distance: CGFloat) -> (CGPoint, CGVector) {
        var remaining = distance.truncatingRemainder(dividingBy: length)
        if remaining < 0 { remaining += length }
        let segments: [(length: CGFloat, place: (CGFloat) -> (CGPoint, CGVector))] = [
            (straightWidth, { d in (CGPoint(x: rect.minX + radius + d, y: rect.minY), CGVector(dx: 0, dy: -1)) }),
            (corner, { d in arc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), from: -.pi / 2, distance: d) }),
            (straightHeight, { d in (CGPoint(x: rect.maxX, y: rect.minY + radius + d), CGVector(dx: 1, dy: 0)) }),
            (corner, { d in arc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), from: 0, distance: d) }),
            (straightWidth, { d in (CGPoint(x: rect.maxX - radius - d, y: rect.maxY), CGVector(dx: 0, dy: 1)) }),
            (corner, { d in arc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), from: .pi / 2, distance: d) }),
            (straightHeight, { d in (CGPoint(x: rect.minX, y: rect.maxY - radius - d), CGVector(dx: -1, dy: 0)) }),
            (corner, { d in arc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), from: .pi, distance: d) }),
        ]
        for segment in segments {
            if remaining <= segment.length {
                return segment.place(remaining)
            }
            remaining -= segment.length
        }
        return (CGPoint(x: rect.minX + radius, y: rect.minY), CGVector(dx: 0, dy: -1))
    }

    private func arc(center: CGPoint, from angle: CGFloat, distance: CGFloat) -> (CGPoint, CGVector) {
        let theta = angle + (radius > 0 ? distance / radius : 0)
        let outward = CGVector(dx: cos(theta), dy: sin(theta))
        return (CGPoint(x: center.x + radius * outward.dx, y: center.y + radius * outward.dy), outward)
    }
}

/// One quick stroke across a card the person turned down.
struct InkStrike: Shape {
    var seed: UUID

    func path(in rect: CGRect) -> Path {
        var jitter = SketchJitter(seed: seed)
        let start = CGPoint(
            x: rect.minX + rect.width * (0.9 + jitter.next() * 0.03),
            y: rect.minY + rect.height * (0.07 + jitter.next() * 0.02)
        )
        let end = CGPoint(
            x: rect.minX + rect.width * (0.09 + jitter.next() * 0.03),
            y: rect.minY + rect.height * (0.93 + jitter.next() * 0.02)
        )
        let bow = CGPoint(
            x: (start.x + end.x) / 2 + rect.width * 0.05 * jitter.next(),
            y: (start.y + end.y) / 2 + rect.height * 0.04 * jitter.next()
        )
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: bow)
        return path
    }
}

/// A short ink underline, like the one under the current filter.
struct InkUnderline: Shape {
    var seed: UInt64 = 0x1D

    func path(in rect: CGRect) -> Path {
        var jitter = SketchJitter(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY + rect.height * 0.3))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 1, y: rect.midY - rect.height * 0.3),
            control1: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.midY - rect.height * (0.2 + jitter.next() * 0.1)),
            control2: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.midY + rect.height * (0.35 + jitter.next() * 0.1))
        )
        return path
    }
}

/// The agent's frame around what it proposes: four quick lines that cross
/// at the corners rather than meet.
struct PencilFrame: Shape {
    var seed: UInt64

    func path(in rect: CGRect) -> Path {
        var jitter = SketchJitter(seed: seed)
        let overshoot: CGFloat = 4
        var path = Path()

        func edge(from: CGPoint, to: CGPoint) {
            let middle = CGPoint(
                x: (from.x + to.x) / 2 + jitter.next() * 1.4,
                y: (from.y + to.y) / 2 + jitter.next() * 1.4
            )
            path.move(to: CGPoint(x: from.x + jitter.next(), y: from.y + jitter.next()))
            path.addQuadCurve(to: CGPoint(x: to.x + jitter.next(), y: to.y + jitter.next()), control: middle)
        }

        edge(from: CGPoint(x: rect.minX - overshoot, y: rect.minY), to: CGPoint(x: rect.maxX + overshoot / 2, y: rect.minY))
        edge(from: CGPoint(x: rect.maxX, y: rect.minY - overshoot / 2), to: CGPoint(x: rect.maxX, y: rect.maxY + overshoot))
        edge(from: CGPoint(x: rect.maxX + overshoot / 2, y: rect.maxY), to: CGPoint(x: rect.minX - overshoot, y: rect.maxY))
        edge(from: CGPoint(x: rect.minX, y: rect.maxY + overshoot / 2), to: CGPoint(x: rect.minX, y: rect.minY - overshoot))
        return path
    }
}

/// A light pencil line across the page, under the study board's header.
struct PencilRule: Shape {
    var seed: UInt64 = 0x2B

    func path(in rect: CGRect) -> Path {
        var jitter = SketchJitter(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + jitter.next()))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY + jitter.next()),
            control1: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.midY + jitter.next() * 1.6),
            control2: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.midY + jitter.next() * 1.6)
        )
        return path
    }
}

/// Diagonal pencil hatching: a slot blocked in before it's drawn.
struct PencilHatch: View {
    var seed: UInt64
    var spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var jitter = SketchJitter(seed: seed)
            let run = size.height * 0.78
            var path = Path()
            var x = -run
            while x < size.width {
                path.move(to: CGPoint(x: x + jitter.next(), y: size.height + jitter.next()))
                path.addLine(to: CGPoint(x: x + run + jitter.next(), y: jitter.next()))
                x += spacing + jitter.next() * 0.8
            }
            context.stroke(path, with: .color(Sketchbook.pencil), lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }
}

extension Path {
    /// A curve through every point, so a handful of samples reads as one
    /// stroke of the hand.
    static func sketchCurve(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 0..<(points.count - 1) {
            let before = points[max(index - 1, 0)]
            let from = points[index]
            let to = points[index + 1]
            let after = points[min(index + 2, points.count - 1)]
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + (to.x - before.x) / 6, y: from.y + (to.y - before.y) / 6),
                control2: CGPoint(x: to.x - (after.x - from.x) / 6, y: to.y - (after.y - from.y) / 6)
            )
        }
        return path
    }
}
