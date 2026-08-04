import Foundation
import XCTest
@testable import PinaxNativeMessaging

final class CaptureProtocolTests: XCTestCase {
    func testBuilderMapsCaptureMetadataIntoPinaxURL() throws {
        let request = makeRequest(
            item: .init(
                source: "x",
                url: "https://x.com/designer/status/123?ref=home",
                title: "A useful layout",
                text: "Spacing & rhythm",
                authorName: "A. Designer",
                authorHandle: "@designer",
                imageURL: "https://pbs.twimg.com/media/example.jpg"
            )
        )

        let url = try CaptureURLBuilder().build(from: request)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.scheme, "pinax")
        XCTAssertEqual(components.host, "capture")
        XCTAssertEqual(values["url"]!, "https://x.com/designer/status/123?ref=home")
        XCTAssertEqual(values["source"]!, "x")
        XCTAssertEqual(values["title"]!, "A useful layout")
        XCTAssertEqual(values["text"]!, "Spacing & rhythm")
        XCTAssertEqual(values["authorName"]!, "A. Designer")
        XCTAssertEqual(values["authorHandle"]!, "@designer")
        XCTAssertEqual(values["imageURL"]!, "https://pbs.twimg.com/media/example.jpg")
        XCTAssertEqual(values["capturedAt"]!, "2026-07-21T12:00:00Z")
        XCTAssertEqual(values["trigger"]!, "pinax_button")
        XCTAssertEqual(values["browser"]!, "chromium-extension")
        XCTAssertEqual(values["requestId"]!, "request-123")
    }

    func testBuilderInfersXAndDropsInvalidOptionalImageURL() throws {
        let request = makeRequest(
            item: .init(
                source: nil,
                url: " https://mobile.x.com/designer/status/123 ",
                title: nil,
                text: nil,
                authorName: nil,
                authorHandle: nil,
                imageURL: "file:///tmp/private.png"
            )
        )

        let url = try CaptureURLBuilder().build(from: request)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(values["source"]!, "x")
        XCTAssertNil(values["imageURL"] ?? nil)
    }

    func testBuilderRejectsNonHTTPURLs() {
        let request = makeRequest(
            item: .init(
                source: "web",
                url: "javascript:alert(1)",
                title: nil,
                text: nil,
                authorName: nil,
                authorHandle: nil,
                imageURL: nil
            )
        )

        XCTAssertThrowsError(try CaptureURLBuilder().build(from: request)) { error in
            XCTAssertEqual(error as? CaptureURLBuilderError, .unsupportedScheme)
        }
    }

    func testBuilderRejectsHTTPURLWithoutAHost() {
        let request = makeRequest(
            item: .init(
                source: "web",
                url: "https:///missing-host",
                title: nil,
                text: nil,
                authorName: nil,
                authorHandle: nil,
                imageURL: nil
            )
        )

        XCTAssertThrowsError(try CaptureURLBuilder().build(from: request)) { error in
            XCTAssertEqual(error as? CaptureURLBuilderError, .missingHost)
        }
    }

    func testAcknowledgementIdentifierRejectsUnsafeFilenames() {
        XCTAssertEqual(
            CaptureAcknowledgementIdentifier.normalized("request-123_ABC"),
            "request-123_ABC"
        )
        XCTAssertNil(CaptureAcknowledgementIdentifier.normalized("../request"))
        XCTAssertNil(CaptureAcknowledgementIdentifier.normalized("request.json"))
        XCTAssertNil(CaptureAcknowledgementIdentifier.normalized(String(repeating: "a", count: 129)))
    }

    func testFileAcknowledgementStoreRoundTripsAndConsumesResponse() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinax-ack-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = FileCaptureAcknowledgementStore(
            directoryURL: directory,
            timeout: 0.1,
            pollInterval: 0.001
        )
        let response = NativeHostResponse.success(itemId: "item-123", duplicate: true)

        XCTAssertTrue(store.prepare(for: "request-123"))
        try store.write(response, for: "request-123")
        XCTAssertEqual(store.wait(for: "request-123"), response)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    private func makeRequest(item: CaptureRequest.Item) -> CaptureRequest {
        CaptureRequest(
            protocolVersion: 1,
            type: "capture",
            requestId: "request-123",
            capturedAt: "2026-07-21T12:00:00Z",
            item: item,
            context: .init(trigger: "pinax_button", browser: "chromium-extension")
        )
    }
}
