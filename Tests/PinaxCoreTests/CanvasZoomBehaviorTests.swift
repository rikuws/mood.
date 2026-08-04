import XCTest
@testable import PinaxCore

final class CanvasZoomBehaviorTests: XCTestCase {
    private let behavior = CanvasZoomBehavior(maximumColumnCount: 4)

    func testGracePeriodKeepsCurrentDensity() {
        XCTAssertEqual(
            behavior.targetColumnCount(from: 2, magnification: 1.31),
            2
        )
        XCTAssertEqual(
            behavior.targetColumnCount(from: 2, magnification: 0.77),
            2
        )
    }

    func testPreviouslySensitivePinchesRemainInsideGracePeriod() {
        let zoomIn = behavior.preview(from: 2, magnification: 1.18)
        let zoomOut = behavior.preview(from: 2, magnification: 0.85)

        XCTAssertFalse(zoomIn.shouldCommit)
        XCTAssertFalse(zoomOut.shouldCommit)
        XCTAssertLessThan(zoomIn.progress, 0.3)
        XCTAssertEqual(zoomOut.progress, 0.3, accuracy: 0.001)
    }

    func testSmallPinchesBarelyMoveTheLayout() {
        let zoomIn = behavior.preview(from: 2, magnification: 1.03)
        let zoomOut = behavior.preview(from: 2, magnification: 0.97)

        XCTAssertLessThan(zoomIn.progress, 0.08)
        XCTAssertLessThan(zoomOut.progress, 0.08)
        XCTAssertFalse(zoomIn.shouldCommit)
        XCTAssertFalse(zoomOut.shouldCommit)
    }

    func testGracePeriodPreviewsAdjacentDensityWithoutCommitting() {
        let zoomInMagnification = 1
            + ((CanvasZoomBehavior.zoomInCommitMagnification - 1) / 2)
        let zoomOutMagnification = 1
            - ((1 - CanvasZoomBehavior.zoomOutCommitMagnification) / 2)
        let zoomIn = behavior.preview(
            from: 2,
            magnification: zoomInMagnification
        )
        let zoomOut = behavior.preview(
            from: 2,
            magnification: zoomOutMagnification
        )

        XCTAssertEqual(zoomIn.targetColumnCount, 1)
        XCTAssertEqual(zoomIn.progress, 0.24, accuracy: 0.001)
        XCTAssertFalse(zoomIn.shouldCommit)
        XCTAssertEqual(zoomOut.targetColumnCount, 3)
        XCTAssertEqual(zoomOut.progress, 0.24, accuracy: 0.001)
        XCTAssertFalse(zoomOut.shouldCommit)
    }

    func testCrossingThresholdKeepsLivePreviewContinuous() {
        let atThreshold = behavior.preview(
            from: 2,
            magnification: CanvasZoomBehavior.zoomInCommitMagnification
        )
        let beyondThreshold = behavior.preview(from: 2, magnification: 1.64)

        XCTAssertEqual(atThreshold.targetColumnCount, 1)
        XCTAssertEqual(atThreshold.progress, 0.48, accuracy: 0.001)
        XCTAssertTrue(atThreshold.shouldCommit)
        XCTAssertGreaterThan(beyondThreshold.progress, atThreshold.progress)
        XCTAssertLessThanOrEqual(beyondThreshold.progress, 0.82)
    }

    func testCrossingThresholdCommitsOneDensityStep() {
        XCTAssertEqual(
            behavior.targetColumnCount(
                from: 3,
                magnification: CanvasZoomBehavior.zoomInCommitMagnification
            ),
            2
        )
        XCTAssertEqual(
            behavior.targetColumnCount(
                from: 2,
                magnification: CanvasZoomBehavior.zoomOutCommitMagnification
            ),
            3
        )
        XCTAssertEqual(
            behavior.targetColumnCount(from: 4, magnification: 2.5),
            3
        )
    }

    func testDensityNeverMovesPastItsBounds() {
        XCTAssertEqual(
            behavior.targetColumnCount(from: 1, magnification: 1.8),
            1
        )
        XCTAssertEqual(
            behavior.targetColumnCount(from: 4, magnification: 0.4),
            4
        )
        XCTAssertEqual(behavior.clampedColumnCount(-10), 1)
        XCTAssertEqual(behavior.clampedColumnCount(20), 4)
        XCTAssertEqual(
            behavior.preview(from: 1, magnification: 1.5).progress,
            0
        )
    }

    func testElasticScaleTracksDirectionAndStaysBounded() {
        let zoomedIn = behavior.elasticScale(
            for: 1.4,
            currentColumnCount: 2
        )
        let zoomedOut = behavior.elasticScale(
            for: 0.6,
            currentColumnCount: 2
        )

        XCTAssertGreaterThan(zoomedIn, 1)
        XCTAssertLessThan(zoomedIn, 1.18)
        XCTAssertLessThan(zoomedOut, 1)
        XCTAssertGreaterThan(zoomedOut, 0.82)
    }

    func testElasticScaleAddsResistanceAtDensityLimits() {
        let available = behavior.elasticScale(
            for: 1.5,
            currentColumnCount: 2
        )
        let atLimit = behavior.elasticScale(
            for: 1.5,
            currentColumnCount: 1
        )

        XCTAssertGreaterThan(available, atLimit)
        XCTAssertEqual(
            behavior.elasticScale(for: .nan, currentColumnCount: 2),
            1
        )
    }
}
