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
    @State private var image: CGImage?
    @State private var didFail = false

    var body: some View {
        GeometryReader { geometry in
            let request = PreviewImageRequest(
                localURL: localURL,
                remoteURL: remoteURL,
                maxPixelSize: pixelSize(for: geometry.size)
            )

            ZStack {
                if let image {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(.opacity)
                } else if didFail {
                    failure()
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

    private func load(_ request: PreviewImageRequest) async {
        guard request.maxPixelSize > 0 else { return }
        guard request.localURL != nil || request.remoteURL != nil else {
            if image == nil { didFail = true }
            return
        }

        let loaded = await PreviewImageLoading.image(for: request)
        guard !Task.isCancelled else { return }

        if let loaded {
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
                didFail = false
            }
        } else if image == nil {
            didFail = true
        }
    }
}

private struct PreviewImageRequest: Equatable, Hashable, Sendable {
    var localURL: URL?
    var remoteURL: URL?
    var maxPixelSize: Int
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
                let produced: CGImage?
                if let localURL = request.localURL {
                    produced = PreviewImageDecoder.thumbnail(
                        fromFileURL: localURL,
                        maxPixelSize: request.maxPixelSize
                    )
                } else if let remoteURL = request.remoteURL {
                    produced = await remoteThumbnail(
                        from: remoteURL,
                        maxPixelSize: request.maxPixelSize
                    )
                } else {
                    produced = nil
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
