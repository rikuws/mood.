import XCTest
@testable import PinaxCore

final class PreviewImageLoadStateTests: XCTestCase {
    func testSourceChangeInvalidatesPriorImageBeforeReplacementFailure() throws {
        let first = PreviewImageSourceIdentity(
            localURL: URL(fileURLWithPath: "/tmp/first.jpg"),
            remoteURL: nil
        )
        let replacement = PreviewImageSourceIdentity(
            localURL: URL(fileURLWithPath: "/tmp/missing.jpg"),
            remoteURL: URL(string: "https://example.com/missing.jpg")
        )
        var state = PreviewImageLoadState()

        XCTAssertTrue(state.activate(first))
        XCTAssertTrue(state.isCurrent(first))

        XCTAssertTrue(state.activate(replacement))
        XCTAssertFalse(state.isCurrent(first))
        XCTAssertTrue(state.isCurrent(replacement))
    }

    func testPixelSizeReloadKeepsImageForTheSameSource() {
        let source = PreviewImageSourceIdentity(
            localURL: URL(fileURLWithPath: "/tmp/image.jpg"),
            remoteURL: nil
        )
        var state = PreviewImageLoadState()

        XCTAssertTrue(state.activate(source))
        XCTAssertFalse(state.activate(source))
    }
}
