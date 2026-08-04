import Foundation
import XCTest
@testable import PinaxCore

final class ModelCodableTests: XCTestCase {
    func testCapturePayloadDecodesBrowserWireFormat() throws {
        let json = #"""
        {
          "source": "x",
          "url": "https://x.com/example/status/123",
          "title": "A beautiful interface",
          "text": "Notice the spacing",
          "authorName": "Example Designer",
          "authorHandle": "example",
          "imageURL": "https://images.example.com/shot.jpg"
        }
        """#.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CapturePayload.self, from: json)

        XCTAssertEqual(payload.source, .x)
        XCTAssertEqual(payload.url.absoluteString, "https://x.com/example/status/123")
        XCTAssertEqual(payload.title, "A beautiful interface")
        XCTAssertEqual(payload.authorHandle, "example")
        XCTAssertEqual(payload.imageURL?.absoluteString, "https://images.example.com/shot.jpg")
        XCTAssertNil(payload.projectID)
    }

    func testCapturePayloadAllowsBrowserToOmitOptionalTextFields() throws {
        let json = #"{"source":"web","url":"https://example.com/inspiration"}"#
            .data(using: .utf8)!

        let payload = try JSONDecoder().decode(CapturePayload.self, from: json)

        XCTAssertEqual(payload.title, "")
        XCTAssertEqual(payload.text, "")
        XCTAssertNil(payload.authorName)
    }

    func testOlderInspirationDefaultsCaptureTrackingFields() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let dateValue = String(Int(date.timeIntervalSince1970 * 1_000))
        let json = """
        {
          "id":"\(id.uuidString)",
          "source":"web",
          "url":"https://example.com/a",
          "canonicalURL":"https://example.com/a",
          "createdAt":\(dateValue)
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let inspiration = try decoder.decode(Inspiration.self, from: json)

        XCTAssertEqual(inspiration.title, "")
        XCTAssertEqual(inspiration.text, "")
        XCTAssertEqual(inspiration.captureCount, 1)
        XCTAssertEqual(inspiration.lastCapturedAt, date)
        XCTAssertNil(inspiration.localImageFilename)
    }

    func testLibrarySnapshotDecodesMissingCollections() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(
            LibrarySnapshot.self,
            from: #"{"schemaVersion":1,"updatedAt":0}"#.data(using: .utf8)!
        )

        XCTAssertTrue(snapshot.projects.isEmpty)
        XCTAssertTrue(snapshot.inspirations.isEmpty)
    }
}
