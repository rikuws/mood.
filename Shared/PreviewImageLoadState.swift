import Foundation

/// The stable part of a preview request. Pixel-size changes can reuse the
/// current image while a new decode runs, but a source change must immediately
/// invalidate the previous image.
public struct PreviewImageSourceIdentity: Equatable, Hashable, Sendable {
    public var localURL: URL?
    public var remoteURL: URL?

    public init(localURL: URL?, remoteURL: URL?) {
        self.localURL = localURL
        self.remoteURL = remoteURL
    }
}

/// Tracks which source is allowed to publish preview-image results. This keeps
/// a slow or failed replacement request from leaving another project's image
/// visible in the same SwiftUI view identity.
public struct PreviewImageLoadState: Equatable, Sendable {
    public private(set) var activeSource: PreviewImageSourceIdentity?

    public init(activeSource: PreviewImageSourceIdentity? = nil) {
        self.activeSource = activeSource
    }

    /// Returns `true` when callers must clear their previously rendered image.
    @discardableResult
    public mutating func activate(_ source: PreviewImageSourceIdentity) -> Bool {
        guard activeSource != source else { return false }
        activeSource = source
        return true
    }

    public func isCurrent(_ source: PreviewImageSourceIdentity) -> Bool {
        activeSource == source
    }
}
