import Foundation
import PinaxNativeMessaging
import PinaxCore

enum CaptureDeepLinkError: LocalizedError {
    case unsupportedRoute
    case missingURL
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unsupportedRoute:
            "Pinax received an unsupported link."
        case .missingURL:
            "The capture did not include a web link."
        case .invalidURL:
            "The captured link must use HTTP or HTTPS."
        }
    }
}

enum CaptureDeepLink {
    static func requestID(from deepLink: URL) -> String? {
        guard let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              let rawValue = components.queryItems?.first(where: { $0.name == "requestId" })?.value else {
            return nil
        }
        return CaptureAcknowledgementIdentifier.normalized(rawValue)
    }

    static func payload(from deepLink: URL) throws -> CapturePayload {
        guard deepLink.scheme?.lowercased() == "pinax", deepLink.host()?.lowercased() == "capture" else {
            throw CaptureDeepLinkError.unsupportedRoute
        }
        guard let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false) else {
            throw CaptureDeepLinkError.unsupportedRoute
        }

        let values = Dictionary(
            components.queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        guard let urlString = values["url"] else {
            throw CaptureDeepLinkError.missingURL
        }
        guard let url = validatedWebURL(urlString) else {
            throw CaptureDeepLinkError.invalidURL
        }

        let inferredSource: CaptureSource = isXURL(url) ? .x : .web
        let source = values["source"].flatMap(CaptureSource.init(rawValue:)) ?? inferredSource
        let imageURL = values["imageURL"].flatMap(validatedWebURL)

        return CapturePayload(
            source: source,
            url: url,
            title: clean(values["title"], maximumLength: 500),
            text: clean(values["text"], maximumLength: 12_000),
            authorName: cleanOptional(values["authorName"], maximumLength: 200),
            authorHandle: cleanOptional(values["authorHandle"], maximumLength: 100),
            imageURL: imageURL
        )
    }

    private static func validatedWebURL(_ value: String) -> URL? {
        guard value.utf8.count <= 16_384,
              let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        return components.url
    }

    private static func isXURL(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com")
    }

    private static func clean(_ value: String?, maximumLength: Int) -> String {
        String(cleanOptional(value, maximumLength: maximumLength) ?? "")
    }

    private static func cleanOptional(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maximumLength))
    }
}
