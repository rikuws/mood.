import Foundation

public struct NativeMessageProcessor {
    private let opener: CaptureURLOpening
    private let urlBuilder: CaptureURLBuilder
    private let acknowledgementWaiter: any CaptureAcknowledgementWaiting
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        opener: CaptureURLOpening,
        urlBuilder: CaptureURLBuilder = CaptureURLBuilder(),
        acknowledgementWaiter: any CaptureAcknowledgementWaiting = FileCaptureAcknowledgementStore()
    ) {
        self.opener = opener
        self.urlBuilder = urlBuilder
        self.acknowledgementWaiter = acknowledgementWaiter
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    public func process(_ payload: Data) -> Data {
        let response: NativeHostResponse

        do {
            let request = try decoder.decode(CaptureRequest.self, from: payload)

            guard request.protocolVersion == 1 else {
                response = .failure(
                    code: "unsupported_protocol",
                    message: "mood. native messaging supports protocolVersion 1."
                )
                return encode(response)
            }

            guard request.type == "capture" else {
                response = .failure(
                    code: "unsupported_message",
                    message: "mood. native messaging supports capture messages only."
                )
                return encode(response)
            }

            guard let requestID = CaptureAcknowledgementIdentifier.normalized(request.requestId) else {
                response = .failure(
                    code: "invalid_request_id",
                    message: "mood. capture requests require a valid request ID."
                )
                return encode(response)
            }

            let captureURL: URL
            do {
                captureURL = try urlBuilder.build(from: request)
            } catch let error as CaptureURLBuilderError {
                response = .failure(
                    code: "invalid_url",
                    message: error.localizedDescription
                )
                return encode(response)
            }

            guard acknowledgementWaiter.prepare(for: requestID) else {
                response = .failure(
                    code: "confirmation_unavailable",
                    message: "mood. could not prepare capture confirmation."
                )
                return encode(response)
            }

            guard opener.open(captureURL) else {
                response = .failure(
                    code: "open_failed",
                    message: "macOS could not open mood. for this capture."
                )
                return encode(response)
            }

            guard let confirmedResponse = acknowledgementWaiter.wait(for: requestID) else {
                response = .failure(
                    code: "confirmation_timeout",
                    message: "mood. did not confirm the save in time. Open mood. to check your library."
                )
                return encode(response)
            }

            response = confirmedResponse
        } catch {
            response = .failure(
                code: "invalid_request",
                message: "The native-messaging request is not valid capture JSON."
            )
        }

        return encode(response)
    }

    public func encodedFailure(
        code: String,
        message: String
    ) -> Data {
        encode(.failure(code: code, message: message))
    }

    private func encode(_ response: NativeHostResponse) -> Data {
        // These fixed response structures are always JSON-encodable.
        (try? encoder.encode(response)) ?? Data(#"{"ok":false,"error":{"code":"encoding_failed","message":"mood. could not encode the native host response."}}"#.utf8)
    }
}

public struct NativeMessagingHostRunner {
    private let framer: NativeMessageFramer
    private let processor: NativeMessageProcessor

    public init(framer: NativeMessageFramer = NativeMessageFramer(), processor: NativeMessageProcessor) {
        self.framer = framer
        self.processor = processor
    }

    /// Processes messages until Chrome closes stdin. A framing error receives one structured
    /// error response and terminates because the stream can no longer be safely synchronized.
    @discardableResult
    public func run(input: FileHandle, output: FileHandle) -> Int32 {
        while true {
            do {
                guard let payload = try framer.readMessage(from: input) else {
                    return 0
                }
                let response = processor.process(payload)
                try framer.writeMessage(response, to: output)
            } catch let error as NativeMessageFramingError {
                let code: String
                switch error {
                case .payloadTooLarge:
                    code = "message_too_large"
                case .outputTooLarge:
                    code = "response_too_large"
                default:
                    code = "framing_error"
                }

                let response = processor.encodedFailure(
                    code: code,
                    message: error.localizedDescription
                )
                try? framer.writeMessage(response, to: output)
                return 1
            } catch {
                let response = processor.encodedFailure(
                    code: "internal_error",
                    message: "mood. native messaging encountered an internal error."
                )
                try? framer.writeMessage(response, to: output)
                return 1
            }
        }
    }
}
