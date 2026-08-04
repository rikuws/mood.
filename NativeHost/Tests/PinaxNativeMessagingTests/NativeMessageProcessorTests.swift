import Foundation
import XCTest
@testable import PinaxNativeMessaging

final class NativeMessageProcessorTests: XCTestCase {
    func testValidCaptureOpensPinaxAndReturnsSuccess() throws {
        let opener = RecordingOpener(result: true)
        let acknowledgements = RecordingAcknowledgementWaiter(
            response: .success(itemId: "item-123", duplicate: false)
        )
        let processor = NativeMessageProcessor(
            opener: opener,
            acknowledgementWaiter: acknowledgements
        )

        let responseData = processor.process(validRequestData())
        let response = try JSONDecoder().decode(NativeHostResponse.self, from: responseData)

        XCTAssertTrue(response.ok)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.itemId, "item-123")
        XCTAssertEqual(response.duplicate, false)
        let responseObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
        XCTAssertEqual(Set(responseObject.keys), ["ok", "itemId", "duplicate"])
        let openedURL = try XCTUnwrap(opener.openedURLs.first)
        XCTAssertEqual(openedURL.scheme, "pinax")
        XCTAssertEqual(openedURL.host, "capture")
        XCTAssertEqual(acknowledgements.preparedRequestIDs, ["abc"])
        XCTAssertEqual(acknowledgements.waitedRequestIDs, ["abc"])
    }

    func testInvalidJSONReturnsStructuredFailure() throws {
        let processor = NativeMessageProcessor(opener: RecordingOpener(result: true))

        let response = try decode(processor.process(Data("not-json".utf8)))

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "invalid_request")
        let responseObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: processor.process(Data("not-json".utf8))) as? [String: Any]
        )
        XCTAssertEqual(Set(responseObject.keys), ["ok", "error"])
    }

    func testInvalidURLReturnsFailureWithoutOpening() throws {
        let opener = RecordingOpener(result: true)
        let processor = NativeMessageProcessor(opener: opener)
        let data = Data(
            #"{"protocolVersion":1,"type":"capture","requestId":"abc","item":{"source":"web","url":"file:///etc/passwd"}}"#.utf8
        )

        let response = try decode(processor.process(data))

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "invalid_url")
        XCTAssertTrue(opener.openedURLs.isEmpty)
    }

    func testUnsupportedProtocolReturnsFailure() throws {
        let processor = NativeMessageProcessor(opener: RecordingOpener(result: true))
        let data = Data(
            #"{"protocolVersion":2,"type":"capture","requestId":"abc","item":{"url":"https://example.com"}}"#.utf8
        )

        let response = try decode(processor.process(data))

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "unsupported_protocol")
    }

    func testOpenFailureIsReported() throws {
        let opener = RecordingOpener(result: false)
        let processor = NativeMessageProcessor(
            opener: opener,
            acknowledgementWaiter: RecordingAcknowledgementWaiter(response: .success())
        )

        let response = try decode(processor.process(validRequestData()))

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "open_failed")
        XCTAssertEqual(opener.openedURLs.count, 1)
    }

    func testMissingAppAcknowledgementReturnsTimeoutInsteadOfSuccess() throws {
        let opener = RecordingOpener(result: true)
        let processor = NativeMessageProcessor(
            opener: opener,
            acknowledgementWaiter: RecordingAcknowledgementWaiter(response: nil)
        )

        let response = try decode(processor.process(validRequestData()))

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "confirmation_timeout")
    }

    private func validRequestData() -> Data {
        Data(
            #"{"protocolVersion":1,"type":"capture","requestId":"abc","capturedAt":"2026-07-21T12:00:00Z","item":{"source":"x","url":"https://x.com/user/status/1","title":"Example","text":"Text"},"context":{"trigger":"toolbar","browser":"chromium-extension"}}"#.utf8
        )
    }

    private func decode(_ data: Data) throws -> NativeHostResponse {
        try JSONDecoder().decode(NativeHostResponse.self, from: data)
    }
}

final class NativeMessagingHostRunnerTests: XCTestCase {
    func testRunnerReadsAndWritesCompleteNativeMessageFrames() throws {
        let input = Pipe()
        let output = Pipe()
        let request = Data(
            #"{"protocolVersion":1,"type":"capture","requestId":"abc","item":{"source":"web","url":"https://example.com/inspiration"}}"#.utf8
        )
        try NativeMessageFramer().writeMessage(request, to: input.fileHandleForWriting)
        try input.fileHandleForWriting.close()

        let runner = NativeMessagingHostRunner(
            processor: NativeMessageProcessor(
                opener: RecordingOpener(result: true),
                acknowledgementWaiter: RecordingAcknowledgementWaiter(
                    response: .success(itemId: "item-123", duplicate: false)
                )
            )
        )
        let exitCode = runner.run(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting
        )
        try output.fileHandleForWriting.close()

        let responseData = try XCTUnwrap(
            NativeMessageFramer().readMessage(from: output.fileHandleForReading)
        )
        let response = try JSONDecoder().decode(NativeHostResponse.self, from: responseData)
        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(response.ok)
    }

    func testRunnerFramesAnOversizedMessageErrorAndTerminates() throws {
        let input = Pipe()
        let output = Pipe()
        try input.fileHandleForWriting.write(
            contentsOf: NativeMessageFramer.encodeLength(9)
        )
        try input.fileHandleForWriting.close()

        let runner = NativeMessagingHostRunner(
            framer: NativeMessageFramer(maximumInputSize: 8),
            processor: NativeMessageProcessor(opener: RecordingOpener(result: true))
        )
        let exitCode = runner.run(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting
        )
        try output.fileHandleForWriting.close()

        let responseData = try XCTUnwrap(
            NativeMessageFramer().readMessage(from: output.fileHandleForReading)
        )
        let response = try JSONDecoder().decode(NativeHostResponse.self, from: responseData)
        XCTAssertEqual(exitCode, 1)
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.error?.code, "message_too_large")
    }
}

private final class RecordingOpener: CaptureURLOpening {
    private(set) var openedURLs: [URL] = []
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return result
    }
}

private final class RecordingAcknowledgementWaiter: CaptureAcknowledgementWaiting {
    private(set) var preparedRequestIDs: [String] = []
    private(set) var waitedRequestIDs: [String] = []
    private let response: NativeHostResponse?

    init(response: NativeHostResponse?) {
        self.response = response
    }

    func prepare(for requestID: String) -> Bool {
        preparedRequestIDs.append(requestID)
        return true
    }

    func wait(for requestID: String) -> NativeHostResponse? {
        waitedRequestIDs.append(requestID)
        return response
    }
}
