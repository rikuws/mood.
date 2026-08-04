import Foundation

/// Shared, deterministic state math for the discrete card-canvas zoom gesture.
///
/// The gesture deliberately has two phases: cards first follow the pinch with
/// rubber-band resistance, then the column layout either commits by one step or
/// springs back when the gesture ends inside the grace period.
public struct CanvasZoomBehavior: Equatable, Sendable {
    public static let zoomInCommitMagnification: CGFloat = 1.32
    public static let zoomOutCommitMagnification: CGFloat = 0.76

    public let minimumColumnCount: Int
    public let maximumColumnCount: Int

    public init(
        minimumColumnCount: Int = 1,
        maximumColumnCount: Int
    ) {
        let minimum = max(1, minimumColumnCount)
        self.minimumColumnCount = minimum
        self.maximumColumnCount = max(minimum, maximumColumnCount)
    }

    /// Returns the adjacent density only after the pinch crosses its grace
    /// threshold. A single gesture changes at most one density level so the
    /// release animation stays spatially understandable.
    public func targetColumnCount(
        from currentColumnCount: Int,
        magnification: CGFloat
    ) -> Int {
        let preview = preview(
            from: currentColumnCount,
            magnification: magnification
        )
        return preview.shouldCommit
            ? preview.targetColumnCount
            : clampedColumnCount(currentColumnCount)
    }

    /// Describes the live reflow while the fingers are still down. Before the
    /// commit threshold the layout travels just under halfway to the adjacent
    /// density; beyond it, extra movement keeps flowing with increasing
    /// resistance. Releasing uses `shouldCommit` to choose the spring endpoint.
    public func preview(
        from currentColumnCount: Int,
        magnification: CGFloat
    ) -> CanvasZoomPreview {
        let current = clampedColumnCount(currentColumnCount)
        guard magnification.isFinite, magnification > 0, magnification != 1 else {
            return CanvasZoomPreview(
                targetColumnCount: current,
                progress: 0,
                shouldCommit: false
            )
        }

        let target: Int
        let normalizedDistance: CGFloat
        let shouldCommit: Bool
        if magnification > 1, current > minimumColumnCount {
            target = current - 1
            normalizedDistance = (magnification - 1)
                / (Self.zoomInCommitMagnification - 1)
            shouldCommit = magnification >= Self.zoomInCommitMagnification
        } else if magnification < 1, current < maximumColumnCount {
            target = current + 1
            normalizedDistance = (1 - magnification)
                / (1 - Self.zoomOutCommitMagnification)
            shouldCommit = magnification <= Self.zoomOutCommitMagnification
        } else {
            return CanvasZoomPreview(
                targetColumnCount: current,
                progress: 0,
                shouldCommit: false
            )
        }

        let progress: CGFloat
        if normalizedDistance <= 1 {
            progress = max(0, normalizedDistance) * 0.48
        } else {
            let excess = normalizedDistance - 1
            progress = 0.48 + (0.34 * (1 - exp(-excess * 1.5)))
        }

        return CanvasZoomPreview(
            targetColumnCount: target,
            progress: min(0.82, max(0, progress)),
            shouldCommit: shouldCommit
        )
    }

    /// A scale that tracks the fingers but asymptotically resists them, like an
    /// over-scrolled iOS list. At either density limit the resistance increases.
    public func elasticScale(
        for magnification: CGFloat,
        currentColumnCount: Int
    ) -> CGFloat {
        guard magnification.isFinite, magnification > 0 else { return 1 }

        let current = clampedColumnCount(currentColumnCount)
        let delta = magnification - 1
        guard delta != 0 else { return 1 }

        let canContinueInDirection = delta > 0
            ? current > minimumColumnCount
            : current < maximumColumnCount
        let limit: CGFloat = canContinueInDirection ? 0.18 : 0.09
        let curve: CGFloat = canContinueInDirection ? 4.2 : 5.2
        let resistedDistance = limit * (1 - exp(-abs(delta) * curve))
        return 1 + (delta.sign == .minus ? -resistedDistance : resistedDistance)
    }

    public func clampedColumnCount(_ columnCount: Int) -> Int {
        min(maximumColumnCount, max(minimumColumnCount, columnCount))
    }
}

public struct CanvasZoomPreview: Equatable, Sendable {
    public let targetColumnCount: Int
    public let progress: CGFloat
    public let shouldCommit: Bool

    public init(
        targetColumnCount: Int,
        progress: CGFloat,
        shouldCommit: Bool
    ) {
        self.targetColumnCount = targetColumnCount
        self.progress = progress
        self.shouldCommit = shouldCommit
    }
}
