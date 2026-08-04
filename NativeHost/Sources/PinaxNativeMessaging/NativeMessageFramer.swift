import Foundation

/// Errors produced while reading or writing Chrome native-messaging frames.
public enum NativeMessageFramingError: Error, Equatable, LocalizedError {
    case incompleteHeader(actualByteCount: Int)
    case incompletePayload(expectedByteCount: Int, actualByteCount: Int)
    case payloadTooLarge(actualByteCount: Int, maximumByteCount: Int)
    case outputTooLarge(actualByteCount: Int, maximumByteCount: Int)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case let .incompleteHeader(actualByteCount):
            return "Expected a 4-byte native-messaging header, but received \(actualByteCount) bytes."
        case let .incompletePayload(expectedByteCount, actualByteCount):
            return "Expected a \(expectedByteCount)-byte native-messaging payload, but received \(actualByteCount) bytes."
        case let .payloadTooLarge(actualByteCount, maximumByteCount):
            return "The native-messaging payload is \(actualByteCount) bytes; the limit is \(maximumByteCount) bytes."
        case let .outputTooLarge(actualByteCount, maximumByteCount):
            return "The native-messaging response is \(actualByteCount) bytes; the limit is \(maximumByteCount) bytes."
        case let .ioFailure(message):
            return "Native-messaging I/O failed: \(message)"
        }
    }
}

/// Reads and writes Chrome's four-byte, little-endian native-messaging frames.
public struct NativeMessageFramer {
    /// Chrome permits much larger host-bound messages, but Pinax captures are deliberately bounded.
    public static let defaultMaximumInputSize = 1_048_576

    /// Chrome's documented host-to-browser message limit is 1 MiB.
    public static let defaultMaximumOutputSize = 1_048_576

    public let maximumInputSize: Int
    public let maximumOutputSize: Int

    public init(
        maximumInputSize: Int = Self.defaultMaximumInputSize,
        maximumOutputSize: Int = Self.defaultMaximumOutputSize
    ) {
        precondition(maximumInputSize >= 0)
        precondition(maximumOutputSize >= 0)
        self.maximumInputSize = maximumInputSize
        self.maximumOutputSize = maximumOutputSize
    }

    /// Returns `nil` only for a clean EOF before any header byte was received.
    public func readMessage(from handle: FileHandle) throws -> Data? {
        let header = try readExactly(4, from: handle, cleanEOFIsAllowed: true)
        guard let header else { return nil }

        let payloadLength = Self.decodeLength(header)
        guard Int(payloadLength) <= maximumInputSize else {
            throw NativeMessageFramingError.payloadTooLarge(
                actualByteCount: Int(payloadLength),
                maximumByteCount: maximumInputSize
            )
        }

        if payloadLength == 0 {
            return Data()
        }

        let expectedByteCount = Int(payloadLength)
        guard let payload = try readExactly(expectedByteCount, from: handle, cleanEOFIsAllowed: false) else {
            throw NativeMessageFramingError.incompletePayload(
                expectedByteCount: expectedByteCount,
                actualByteCount: 0
            )
        }
        return payload
    }

    public func writeMessage(_ payload: Data, to handle: FileHandle) throws {
        guard payload.count <= maximumOutputSize else {
            throw NativeMessageFramingError.outputTooLarge(
                actualByteCount: payload.count,
                maximumByteCount: maximumOutputSize
            )
        }
        guard payload.count <= Int(UInt32.max) else {
            throw NativeMessageFramingError.outputTooLarge(
                actualByteCount: payload.count,
                maximumByteCount: min(maximumOutputSize, Int(UInt32.max))
            )
        }

        var frame = Self.encodeLength(UInt32(payload.count))
        frame.append(payload)

        do {
            try handle.write(contentsOf: frame)
        } catch {
            throw NativeMessageFramingError.ioFailure(error.localizedDescription)
        }
    }

    public static func encodeLength(_ length: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: length),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 24)
        ])
    }

    public static func decodeLength(_ header: Data) -> UInt32 {
        precondition(header.count == 4)
        return header.enumerated().reduce(into: UInt32(0)) { result, element in
            result |= UInt32(element.element) << UInt32(element.offset * 8)
        }
    }

    private func readExactly(
        _ byteCount: Int,
        from handle: FileHandle,
        cleanEOFIsAllowed: Bool
    ) throws -> Data? {
        var result = Data()
        result.reserveCapacity(byteCount)

        do {
            while result.count < byteCount {
                let remaining = byteCount - result.count
                guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                    if result.isEmpty, cleanEOFIsAllowed {
                        return nil
                    }
                    if byteCount == 4 {
                        throw NativeMessageFramingError.incompleteHeader(actualByteCount: result.count)
                    }
                    throw NativeMessageFramingError.incompletePayload(
                        expectedByteCount: byteCount,
                        actualByteCount: result.count
                    )
                }
                result.append(chunk)
            }
        } catch let error as NativeMessageFramingError {
            throw error
        } catch {
            throw NativeMessageFramingError.ioFailure(error.localizedDescription)
        }

        return result
    }
}
