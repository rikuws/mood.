import Foundation
import XCTest
@testable import PinaxNativeMessaging

final class NativeMessageFramerTests: XCTestCase {
    func testLengthUsesFourByteLittleEndianEncoding() {
        XCTAssertEqual(
            NativeMessageFramer.encodeLength(0x7856_3412),
            Data([0x12, 0x34, 0x56, 0x78])
        )
        XCTAssertEqual(
            NativeMessageFramer.decodeLength(Data([0x12, 0x34, 0x56, 0x78])),
            0x7856_3412
        )
    }

    func testReadsAFramedPayload() throws {
        let payload = Data(#"{"type":"capture"}"#.utf8)
        let pipe = Pipe()
        var frame = NativeMessageFramer.encodeLength(UInt32(payload.count))
        frame.append(payload)
        try pipe.fileHandleForWriting.write(contentsOf: frame)
        try pipe.fileHandleForWriting.close()

        let result = try NativeMessageFramer().readMessage(from: pipe.fileHandleForReading)

        XCTAssertEqual(result, payload)
    }

    func testCleanEOFReturnsNil() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.close()

        XCTAssertNil(try NativeMessageFramer().readMessage(from: pipe.fileHandleForReading))
    }

    func testPartialHeaderIsRejected() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data([0x03, 0x00]))
        try pipe.fileHandleForWriting.close()

        XCTAssertThrowsError(
            try NativeMessageFramer().readMessage(from: pipe.fileHandleForReading)
        ) { error in
            XCTAssertEqual(
                error as? NativeMessageFramingError,
                .incompleteHeader(actualByteCount: 2)
            )
        }
    }

    func testPartialPayloadIsRejected() throws {
        let pipe = Pipe()
        var frame = NativeMessageFramer.encodeLength(5)
        frame.append(Data([0x01, 0x02]))
        try pipe.fileHandleForWriting.write(contentsOf: frame)
        try pipe.fileHandleForWriting.close()

        XCTAssertThrowsError(
            try NativeMessageFramer().readMessage(from: pipe.fileHandleForReading)
        ) { error in
            XCTAssertEqual(
                error as? NativeMessageFramingError,
                .incompletePayload(expectedByteCount: 5, actualByteCount: 2)
            )
        }
    }

    func testOversizedPayloadIsRejectedBeforeItIsRead() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: NativeMessageFramer.encodeLength(9))
        try pipe.fileHandleForWriting.close()

        XCTAssertThrowsError(
            try NativeMessageFramer(maximumInputSize: 8).readMessage(from: pipe.fileHandleForReading)
        ) { error in
            XCTAssertEqual(
                error as? NativeMessageFramingError,
                .payloadTooLarge(actualByteCount: 9, maximumByteCount: 8)
            )
        }
    }

    func testWritesAFramedPayload() throws {
        let payload = Data("hello".utf8)
        let pipe = Pipe()

        try NativeMessageFramer().writeMessage(payload, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()
        let frame = pipe.fileHandleForReading.readDataToEndOfFile()

        XCTAssertEqual(frame.prefix(4), NativeMessageFramer.encodeLength(5))
        XCTAssertEqual(frame.dropFirst(4), payload)
    }

    func testOversizedOutputIsRejected() {
        let pipe = Pipe()
        let payload = Data(repeating: 0, count: 9)

        XCTAssertThrowsError(
            try NativeMessageFramer(maximumOutputSize: 8)
                .writeMessage(payload, to: pipe.fileHandleForWriting)
        ) { error in
            XCTAssertEqual(
                error as? NativeMessageFramingError,
                .outputTooLarge(actualByteCount: 9, maximumByteCount: 8)
            )
        }
    }
}
