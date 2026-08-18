import CoreGraphics
import Foundation
import ImageIO

/// Decodes catalog preview bitmaps at the pixel size they will occupy on screen.
///
/// Drawing a full-resolution capture into a small card lets the GPU downsample
/// in one pass, which aliases fine detail and reads as pixelation. Image I/O
/// thumbnails use a higher-quality filter and keep the working set bounded.
public enum PreviewImageDecoder {
    public static let maximumPixelSize = 2_048
    private static let bucketSize = 256
    nonisolated(unsafe) private static let pixelSizeCache: NSCache<NSURL, CachedPixelSize> = {
        let cache = NSCache<NSURL, CachedPixelSize>()
        cache.countLimit = 2_000
        return cache
    }()

    /// Rounds a requested longest edge up to a stable cache bucket, capped at
    /// `maximumPixelSize`. Small layout jitter then reuses the same thumbnail.
    public static func thumbnailPixelSize(forLongestSide longestSide: CGFloat) -> Int {
        guard longestSide.isFinite, longestSide > 0 else { return bucketSize }
        let requested = min(max(Int(longestSide.rounded(.up)), 1), maximumPixelSize)
        let bucket = ((requested + bucketSize - 1) / bucketSize) * bucketSize
        return min(bucket, maximumPixelSize)
    }

    public static func thumbnail(fromFileURL url: URL, maxPixelSize: Int) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            return nil
        }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    public static func thumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    public static func pixelSize(at url: URL) -> CGSize? {
        let cacheKey = url as NSURL
        if let cached = pixelSizeCache.object(forKey: cacheKey) {
            return cached.size
        }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0,
              height.doubleValue > 0 else {
            return nil
        }

        let encoded = CGSize(width: width.doubleValue, height: height.doubleValue)
        let displayed = displayedSize(
            encoded,
            orientation: properties[kCGImagePropertyOrientation]
        )
        pixelSizeCache.setObject(CachedPixelSize(displayed), forKey: cacheKey)
        return displayed
    }

    public static func aspectRatio(
        at url: URL,
        clampedTo range: ClosedRange<CGFloat>
    ) -> CGFloat? {
        guard let size = pixelSize(at: url), size.height > 0 else { return nil }
        let ratio = size.width / size.height
        return min(max(ratio, range.lowerBound), range.upperBound)
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let pixelSize = min(max(maxPixelSize, 1), maximumPixelSize)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func displayedSize(_ size: CGSize, orientation: Any?) -> CGSize {
        let value: Int
        if let number = orientation as? NSNumber {
            value = number.intValue
        } else {
            value = 1
        }
        // EXIF orientations 5...8 rotate the image a quarter turn.
        if (5...8).contains(value) {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }
}

private final class CachedPixelSize: @unchecked Sendable {
    let size: CGSize

    init(_ size: CGSize) {
        self.size = size
    }
}
