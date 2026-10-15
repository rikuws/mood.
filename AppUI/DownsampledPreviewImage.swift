import CoreGraphics
import PinaxCore
import SwiftUI

/// Renders a local or remote preview at the view's pixel size instead of
/// letting SwiftUI squash a full-resolution bitmap into a catalog card.
struct DownsampledPreviewImage<Placeholder: View, Failure: View>: View {
    var localURL: URL?
    var remoteURL: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure

    @Environment(\.displayScale) private var displayScale
    @Environment(\.previewImageReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?
    @State private var didFail = false
    @State private var developsImage = false
    @State private var loadState = PreviewImageLoadState()

    var body: some View {
        GeometryReader { geometry in
            let request = PreviewImageRequest(
                localURL: localURL,
                remoteURL: remoteURL,
                maxPixelSize: pixelSize(for: geometry.size)
            )

            ZStack {
                if let image {
                    let picture = Image(decorative: image, scale: displayScale)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    if developsImage {
                        DiffusionDevelopingView { picture }
                    } else {
                        picture.transition(.opacity)
                    }
                } else if didFail {
                    failure()
                } else if developsOnArrival {
                    placeholder()
                        .overlay { DiffusionNoiseField() }
                } else {
                    placeholder()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: request) {
                await load(request)
            }
        }
    }

    private func pixelSize(for size: CGSize) -> Int {
        guard size.width > 1, size.height > 1 else { return 0 }
        // A little headroom covers the catalog hover scale without a second decode.
        let longestSide = max(size.width, size.height) * displayScale * 1.05
        return PreviewImageDecoder.thumbnailPixelSize(forLongestSide: longestSide)
    }

    private var developsOnArrival: Bool {
        reveal == .develop && !reduceMotion
    }

    private func load(_ request: PreviewImageRequest) async {
        let source = request.sourceIdentity
        if loadState.activate(source) {
            image = nil
            didFail = false
            developsImage = false
        }

        guard request.maxPixelSize > 0 else { return }
        guard request.localURL != nil || request.remoteURL != nil else {
            if image == nil { didFail = true }
            return
        }

        let loaded = await PreviewImageLoading.image(for: request)
        guard !Task.isCancelled, loadState.isCurrent(source) else { return }

        if let loaded {
            // Only a source's first image develops; a sharper re-decode for
            // a new size replaces it in place.
            if image == nil, developsOnArrival {
                developsImage = true
                image = loaded
                didFail = false
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    image = loaded
                    didFail = false
                }
            }
        } else if image == nil {
            didFail = true
        }
    }
}

/// How a preview appears once its image has loaded.
enum PreviewImageReveal: Hashable, Sendable {
    /// A short crossfade.
    case fade
    /// Develops out of grain, the way a diffusion model resolves an image:
    /// while loading the preview is moving noise, then the image takes shape,
    /// color, and finally detail out of it in visible steps. For things that
    /// were just found, so they pop into the study board as they arrive.
    case develop
}

private struct PreviewImageRevealKey: EnvironmentKey {
    static let defaultValue = PreviewImageReveal.fade
}

extension EnvironmentValues {
    var previewImageReveal: PreviewImageReveal {
        get { self[PreviewImageRevealKey.self] }
        set { self[PreviewImageRevealKey.self] = newValue }
    }
}

/// The schedule a developing preview follows: a fixed number of steps, eased
/// so most of the change lands mid-way, like a diffusion sampler's.
enum DiffusionDevelop {
    static let stepCount = 16
    static let stepDuration = Duration.milliseconds(105)

    static func progress(step: Int) -> Double {
        let t = min(1, max(0, Double(step) / Double(stepCount)))
        return t * t * (3 - 2 * t)
    }

    /// Coarse shapes first, fine detail last.
    static func blurRadius(at progress: Double) -> CGFloat {
        CGFloat(18 * pow(1 - progress, 1.6))
    }

    static func grainOpacity(at progress: Double) -> Double {
        0.9 * (1 - progress)
    }

    static func imageOpacity(at progress: Double) -> Double {
        min(1, 0.3 + progress * 1.4)
    }
}

/// Resolves its content out of grain in discrete steps. Each step re-rolls
/// the grain and sharpens the image a little, so it reads as an image being
/// developed rather than a fade.
struct DiffusionDevelopingView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @State private var step = 0

    var body: some View {
        let progress = DiffusionDevelop.progress(step: step)
        content()
            .blur(radius: DiffusionDevelop.blurRadius(at: progress), opaque: true)
            .saturation(progress)
            .opacity(DiffusionDevelop.imageOpacity(at: progress))
            .overlay {
                if step < DiffusionDevelop.stepCount {
                    DiffusionGrainImage(frame: step)
                        .opacity(DiffusionDevelop.grainOpacity(at: progress))
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .task {
                // Resumes where it left off if the view was away mid-way.
                while step < DiffusionDevelop.stepCount {
                    try? await Task.sleep(for: DiffusionDevelop.stepDuration)
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: 0.09)) {
                        step += 1
                    }
                }
            }
    }
}

/// Moving grain that stands in for an image still being found or loaded.
struct DiffusionNoiseField: View {
    var intensity = 0.85
    /// How much the grain's density swells and settles, on a sine wave.
    var breath = 0.0
    /// Where in the wave this field starts, so neighbours don't breathe in step.
    var phase = 0.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = 0

    /// One frame of grain every 120 ms; a breath takes about 2.4 s.
    private static let frameInterval = Duration.milliseconds(120)
    private static let radiansPerFrame = 2 * Double.pi / 20

    var body: some View {
        DiffusionGrainImage(frame: frame)
            .opacity(max(0, min(1, intensity + breath * sin(Double(frame) * Self.radiansPerFrame + phase))))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.frameInterval)
                    // The tile swaps on the frame; the breath glides between frames.
                    withAnimation(.linear(duration: 0.12)) {
                        frame &+= 1
                    }
                }
            }
    }
}

struct DiffusionGrainImage: View {
    let frame: Int

    var body: some View {
        if let tile = DiffusionGrain.tile(for: frame) {
            Image(decorative: tile, scale: 1)
                .resizable(resizingMode: .tile)
                .interpolation(.none)
        } else {
            Color.gray
        }
    }
}

/// A few tiles of monochrome grain, generated once. Color belongs to the
/// collected imagery, so the noise stays gray.
@MainActor
enum DiffusionGrain {
    private static let tiles: [CGImage] = (1...4).compactMap { makeTile(seed: UInt64($0)) }

    static func tile(for frame: Int) -> CGImage? {
        guard !tiles.isEmpty else { return nil }
        let count = tiles.count
        return tiles[((frame % count) + count) % count]
    }

    private nonisolated static func makeTile(seed: UInt64) -> CGImage? {
        let side = 96
        var state = (seed &* 0x9E37_79B9_7F4A_7C15) | 1
        var pixels = [UInt8](repeating: 0, count: side * side)
        for index in pixels.indices {
            // xorshift64*
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            pixels[index] = UInt8(truncatingIfNeeded: (state &* 0x2545_F491_4F6C_DD1D) >> 56)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

private struct PreviewImageRequest: Equatable, Hashable, Sendable {
    var localURL: URL?
    var remoteURL: URL?
    var maxPixelSize: Int

    var sourceIdentity: PreviewImageSourceIdentity {
        PreviewImageSourceIdentity(localURL: localURL, remoteURL: remoteURL)
    }
}

private struct SendablePreviewImage: @unchecked Sendable {
    let image: CGImage
}

private enum PreviewImageLoading {
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 256 * 1_024 * 1_024
        return cache
    }()

    private static let lock = NSLock()
    nonisolated(unsafe) private static var inFlight: [String: Task<SendablePreviewImage?, Never>] = [:]

    static func image(for request: PreviewImageRequest) async -> CGImage? {
        let key = cacheKey(for: request)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let task: Task<SendablePreviewImage?, Never> = lock.withLock {
            if let existing = inFlight[key] {
                return existing
            }
            let created = Task.detached(priority: .userInitiated) {
                var produced: CGImage?
                if let localURL = request.localURL {
                    produced = PreviewImageDecoder.thumbnail(
                        fromFileURL: localURL,
                        maxPixelSize: request.maxPixelSize
                    )
                }
                if produced == nil, let remoteURL = request.remoteURL {
                    produced = await remoteThumbnail(
                        from: remoteURL,
                        maxPixelSize: request.maxPixelSize
                    )
                }

                if let produced {
                    cache.setObject(
                        produced,
                        forKey: key as NSString,
                        cost: produced.bytesPerRow * produced.height
                    )
                }

                lock.withLock { inFlight[key] = nil }
                return produced.map(SendablePreviewImage.init)
            }
            inFlight[key] = created
            return created
        }

        return await task.value?.image
    }

    private static func cacheKey(for request: PreviewImageRequest) -> String {
        if let localURL = request.localURL {
            return "file:\(localURL.path)#\(request.maxPixelSize)"
        }
        if let remoteURL = request.remoteURL {
            return "remote:\(remoteURL.absoluteString)#\(request.maxPixelSize)"
        }
        return "empty#\(request.maxPixelSize)"
    }

    private static func remoteThumbnail(from url: URL, maxPixelSize: Int) async -> CGImage? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue(
                "image/jpeg,image/jpg,image/png,image/webp,image/*,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            return PreviewImageDecoder.thumbnail(from: data, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }
}
