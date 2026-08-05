import Foundation

public struct CaptureRequest: Decodable, Equatable {
    public struct Item: Decodable, Equatable {
        public let source: String?
        public let url: String
        public let title: String?
        public let text: String?
        public let authorName: String?
        public let authorHandle: String?
        public let imageURL: String?

        public init(
            source: String?,
            url: String,
            title: String?,
            text: String?,
            authorName: String?,
            authorHandle: String?,
            imageURL: String?
        ) {
            self.source = source
            self.url = url
            self.title = title
            self.text = text
            self.authorName = authorName
            self.authorHandle = authorHandle
            self.imageURL = imageURL
        }
    }

    public struct Context: Decodable, Equatable {
        public let trigger: String?
        public let browser: String?

        public init(trigger: String?, browser: String?) {
            self.trigger = trigger
            self.browser = browser
        }
    }

    public let protocolVersion: Int
    public let type: String
    public let requestId: String?
    public let capturedAt: String?
    public let item: Item
    public let context: Context?

    public init(
        protocolVersion: Int,
        type: String,
        requestId: String?,
        capturedAt: String?,
        item: Item,
        context: Context?
    ) {
        self.protocolVersion = protocolVersion
        self.type = type
        self.requestId = requestId
        self.capturedAt = capturedAt
        self.item = item
        self.context = context
    }
}

public struct NativeHostErrorPayload: Codable, Equatable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct NativeHostResponse: Codable, Equatable {
    public let ok: Bool
    public let itemId: String?
    public let duplicate: Bool?
    public let error: NativeHostErrorPayload?

    public init(
        ok: Bool,
        itemId: String? = nil,
        duplicate: Bool? = nil,
        error: NativeHostErrorPayload? = nil
    ) {
        self.ok = ok
        self.itemId = itemId
        self.duplicate = duplicate
        self.error = error
    }

    public static func success(itemId: String? = nil, duplicate: Bool? = nil) -> Self {
        Self(ok: true, itemId: itemId, duplicate: duplicate)
    }

    public static func failure(code: String, message: String) -> Self {
        Self(
            ok: false,
            error: NativeHostErrorPayload(code: code, message: message)
        )
    }
}

public protocol CaptureURLOpening {
    @discardableResult
    func open(_ url: URL) -> Bool
}

public enum CaptureURLBuilderError: Error, Equatable, LocalizedError {
    case unsupportedScheme
    case missingHost
    case cannotConstructCaptureURL

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            return "Capture URLs must use HTTP or HTTPS."
        case .missingHost:
            return "The capture URL must include a host."
        case .cannotConstructCaptureURL:
            return "mood. could not construct its capture URL."
        }
    }
}

public struct CaptureURLBuilder {
    public init() {}

    public func build(from request: CaptureRequest) throws -> URL {
        let sourceURL = try validatedWebURL(request.item.url)

        var components = URLComponents()
        components.scheme = "pinax"
        components.host = "capture"

        var queryItems = [
            URLQueryItem(name: "url", value: sourceURL.absoluteString),
            URLQueryItem(name: "source", value: normalizedSource(request.item.source, sourceURL: sourceURL))
        ]

        appendIfPresent(name: "title", value: request.item.title, to: &queryItems)
        appendIfPresent(name: "text", value: request.item.text, to: &queryItems)
        appendIfPresent(name: "authorName", value: request.item.authorName, to: &queryItems)
        appendIfPresent(name: "authorHandle", value: request.item.authorHandle, to: &queryItems)

        if let imageURLString = nonempty(request.item.imageURL),
           let imageURL = try? validatedWebURL(imageURLString) {
            queryItems.append(URLQueryItem(name: "imageURL", value: imageURL.absoluteString))
        }

        appendIfPresent(name: "capturedAt", value: request.capturedAt, to: &queryItems)
        appendIfPresent(name: "trigger", value: request.context?.trigger, to: &queryItems)
        appendIfPresent(name: "browser", value: request.context?.browser, to: &queryItems)
        appendIfPresent(name: "requestId", value: request.requestId, to: &queryItems)

        components.queryItems = queryItems
        guard let url = components.url else {
            throw CaptureURLBuilderError.cannotConstructCaptureURL
        }
        return url
    }

    public func validatedWebURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw CaptureURLBuilderError.unsupportedScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw CaptureURLBuilderError.missingHost
        }
        guard let url = components.url else {
            throw CaptureURLBuilderError.cannotConstructCaptureURL
        }
        return url
    }

    private func normalizedSource(_ source: String?, sourceURL: URL) -> String {
        if let normalized = nonempty(source)?.lowercased(),
           normalized == "x" || normalized == "web" {
            return normalized
        }

        let host = sourceURL.host?.lowercased() ?? ""
        let isX = host == "x.com" || host.hasSuffix(".x.com")
            || host == "twitter.com" || host.hasSuffix(".twitter.com")
        return isX ? "x" : "web"
    }

    private func appendIfPresent(name: String, value: String?, to items: inout [URLQueryItem]) {
        guard let value = nonempty(value) else { return }
        items.append(URLQueryItem(name: name, value: value))
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
