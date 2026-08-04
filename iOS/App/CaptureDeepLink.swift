import Foundation
import PinaxCore

enum IOSCaptureDeepLinkError: LocalizedError {
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

enum IOSCaptureDeepLink {
    static func payload(from deepLink: URL) throws -> CapturePayload {
        guard deepLink.scheme?.lowercased() == "pinax",
              deepLink.host()?.lowercased() == "capture" else {
            throw IOSCaptureDeepLinkError.unsupportedRoute
        }
        guard let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false) else {
            throw IOSCaptureDeepLinkError.unsupportedRoute
        }

        let values = Dictionary(
            components.queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        guard let rawURL = values["url"] else {
            throw IOSCaptureDeepLinkError.missingURL
        }
        guard let url = CaptureURL.validatedWebURL(rawURL) else {
            throw IOSCaptureDeepLinkError.invalidURL
        }

        return CapturePayload(
            source: values["source"].flatMap(CaptureSource.init(rawValue:))
                ?? CaptureURL.source(for: url),
            url: url,
            title: clean(values["title"], maximumLength: 500),
            text: clean(values["text"], maximumLength: 12_000),
            authorName: cleanOptional(values["authorName"], maximumLength: 200),
            authorHandle: cleanOptional(values["authorHandle"], maximumLength: 100),
            imageURL: values["imageURL"].flatMap(CaptureURL.validatedWebURL),
            projectID: values["projectID"].flatMap(UUID.init(uuidString:))
        )
    }

    private static func clean(_ value: String?, maximumLength: Int) -> String {
        cleanOptional(value, maximumLength: maximumLength) ?? ""
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

enum CaptureURL {
    static func validatedWebURL(_ value: String) -> URL? {
        guard value.utf8.count <= 16_384,
              let components = URLComponents(
                string: value.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }
        return components.url
    }

    static func source(for url: URL) -> CaptureSource {
        let host = url.host()?.lowercased() ?? ""
        return host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
            ? .x
            : .web
    }
}
