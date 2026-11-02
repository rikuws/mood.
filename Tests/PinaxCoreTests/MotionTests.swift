import Foundation
import XCTest
@testable import PinaxCore

final class MotionTests: XCTestCase, @unchecked Sendable {
    func testCaptureKeepsMotionAndARecaptureFillsItIn() async throws {
        let repository = try makeRepository()
        let post = URL(string: "https://x.com/designer/status/1")!

        let still = try await repository.capture(CapturePayload(source: .x, url: post, title: "Loop"))
        XCTAssertNil(still.inspiration.motion)

        let again = try await repository.capture(CapturePayload(source: .x, url: post, title: "Loop", motion: .gif))
        XCTAssertFalse(again.inserted)
        XCTAssertEqual(again.inspiration.motion, .gif)

        let video = try await repository.capture(
            CapturePayload(source: .x, url: URL(string: "https://x.com/designer/status/2")!, motion: .video)
        )
        XCTAssertEqual(video.inspiration.motion, .video)

        let response = try await PinaxAgentAPI(repository: repository).inspiration(id: video.inspiration.id.uuidString)
        XCTAssertEqual(response.inspiration.motion, .video)
    }

    func testUnknownOrMissingMotionReadsAsStill() throws {
        let json = """
        {"id":"7D3C9A51-1D1B-4F3E-9C7B-0B9A3D0E2F11","source":"x","url":"https://x.com/a/status/1",
         "canonicalURL":"https://x.com/a/status/1","createdAt":0,"motion":"hologram"}
        """
        let inspiration = try JSONDecoder().decode(Inspiration.self, from: Data(json.utf8))
        XCTAssertNil(inspiration.motion)

        var gif = inspiration
        gif.motion = .gif
        let data = try JSONEncoder().encode(gif)
        XCTAssertEqual(try JSONDecoder().decode(Inspiration.self, from: data).motion, .gif)
    }

    private func makeRepository() throws -> LibraryRepository {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxMotionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return try LibraryRepository(storageDirectory: directory)
    }
}
