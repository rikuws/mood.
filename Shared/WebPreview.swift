import Foundation

/// Metadata and an optional locally-cacheable image resolved from a shared web URL.
public struct WebPreview: Equatable, Sendable {
    public var title: String?
    public var text: String?
    public var authorName: String?
    public var authorHandle: String?
    public var imageURL: URL?
    public var imageData: Data?
    public var imageFileExtension: String?

    public init(
        title: String? = nil,
        text: String? = nil,
        authorName: String? = nil,
        authorHandle: String? = nil,
        imageURL: URL? = nil,
        imageData: Data? = nil,
        imageFileExtension: String? = nil
    ) {
        self.title = title
        self.text = text
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.imageURL = imageURL
        self.imageData = imageData
        self.imageFileExtension = imageFileExtension
    }

    public var hasContent: Bool {
        title != nil
            || text != nil
            || authorName != nil
            || authorHandle != nil
            || imageURL != nil
            || imageData != nil
    }
}

public protocol WebPreviewFetching: Sendable {
    func fetchPreview(for url: URL) async -> WebPreview?
}

/// Fetches public Open Graph/Twitter Card metadata and caches a bounded preview image.
/// Failures are intentionally non-fatal: saving the original URL remains useful offline.
public struct WebPreviewFetcher: WebPreviewFetching, Sendable {
    public let requestTimeout: TimeInterval
    public let maximumHTMLBytes: Int
    public let maximumImageBytes: Int

    public init(
        requestTimeout: TimeInterval = 10,
        maximumHTMLBytes: Int = 2 * 1_024 * 1_024,
        maximumImageBytes: Int = 20 * 1_024 * 1_024
    ) {
        self.requestTimeout = requestTimeout
        self.maximumHTMLBytes = maximumHTMLBytes
        self.maximumImageBytes = maximumImageBytes
    }

    public func fetchPreview(for url: URL) async -> WebPreview? {
        guard Self.isWebURL(url) else { return nil }

        do {
            let session = makeSession()
            defer { session.finishTasksAndInvalidate() }

            var request = URLRequest(url: url)
            request.timeoutInterval = requestTimeout
            request.cachePolicy = .reloadRevalidatingCacheData
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")

            let (data, response) = try await session.data(for: request)
            guard Self.isSuccessfulHTMLResponse(response),
                  !data.isEmpty,
                  data.count <= maximumHTMLBytes,
                  let html = Self.decodeHTML(data, response: response) else {
                return nil
            }

            var preview = WebPreviewHTMLParser.parse(html, pageURL: url)
            if let imageURL = preview.imageURL,
               let image = await fetchImage(from: imageURL, using: session) {
                preview.imageData = image.data
                preview.imageFileExtension = image.fileExtension
            }
            return preview.hasContent ? preview : nil
        } catch {
            return nil
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        configuration.urlCache = URLCache(
            memoryCapacity: 4 * 1_024 * 1_024,
            diskCapacity: 0
        )
        return URLSession(configuration: configuration)
    }

    private func fetchImage(
        from url: URL,
        using session: URLSession
    ) async -> (data: Data, fileExtension: String)? {
        guard Self.isWebURL(url) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = requestTimeout
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  response.mimeType?.lowercased().hasPrefix("image/") == true,
                  !data.isEmpty,
                  data.count <= maximumImageBytes else {
                return nil
            }
            return (data, Self.imageFileExtension(response: response, url: url))
        } catch {
            return nil
        }
    }

    private static func isSuccessfulHTMLResponse(_ response: URLResponse) -> Bool {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            return false
        }
        return response.mimeType?.lowercased().contains("html") ?? true
    }

    private static func decodeHTML(_ data: Data, response: URLResponse) -> String? {
        if let encodingName = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                if let decoded = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) {
                    return decoded
                }
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func imageFileExtension(response: HTTPURLResponse, url: URL) -> String {
        switch response.mimeType?.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic", "image/heif": return "heic"
        case "image/avif": return "avif"
        default:
            let candidate = url.pathExtension.lowercased().filter(\.isLetter)
            return candidate.isEmpty ? "jpg" : String(candidate.prefix(5))
        }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host() != nil else { return false }
        return scheme == "http" || scheme == "https"
    }
}

/// A small dependency-free HTML metadata parser kept separate from networking
/// so X's public response format can be covered with deterministic tests.
public enum WebPreviewHTMLParser {
    public static func parse(_ html: String, pageURL: URL) -> WebPreview {
        let metadata = metaValues(in: html)
        let rawTitle = firstValue(
            for: ["og:title", "twitter:title", "title"],
            in: metadata
        ) ?? titleElement(in: html)
        let title = clean(rawTitle)
        let text = clean(firstValue(
            for: ["og:description", "twitter:description", "description"],
            in: metadata
        ))
        var authorName = clean(firstValue(
            for: ["author", "article:author:name"],
            in: metadata
        ))
        var authorHandle = clean(firstValue(for: ["twitter:creator"], in: metadata))?
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        if let xAuthor = xAuthor(from: title) {
            authorName = authorName ?? xAuthor.name
            authorHandle = authorHandle ?? xAuthor.handle
        }

        let rawImageURL = firstValue(
            for: ["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"],
            in: metadata
        )
        let imageURL = rawImageURL
            .map(decodeHTMLEntities)
            .flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL }
            .flatMap(validatedWebURL)

        return WebPreview(
            title: title,
            text: text,
            authorName: authorName,
            authorHandle: authorHandle,
            imageURL: imageURL
        )
    }

    private static func metaValues(in html: String) -> [String: String] {
        let tags = matches(pattern: #"<meta\b[^>]*>"#, in: html, options: [.caseInsensitive])
        var result: [String: String] = [:]
        for tag in tags {
            let attributes = attributeValues(in: tag)
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let value = attributes["content"],
                  !value.isEmpty,
                  result[key] == nil else {
                continue
            }
            result[key] = decodeHTMLEntities(value)
        }
        return result
    }

    private static func attributeValues(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var result: [String: String] = [:]
        for match in expression.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let valueRange = (2...4)
                .lazy
                .map { match.range(at: $0) }
                .first { $0.location != NSNotFound }
                .flatMap { Range($0, in: tag) }
            guard let valueRange else { continue }
            result[String(tag[nameRange]).lowercased()] = String(tag[valueRange])
        }
        return result
    }

    private static func titleElement(in html: String) -> String? {
        matches(
            pattern: #"<title\b[^>]*>([\s\S]*?)</title\s*>"#,
            in: html,
            options: [.caseInsensitive]
        ).first.flatMap { tag in
            guard let start = tag.range(of: ">"),
                  let end = tag.range(of: "</", options: .backwards),
                  start.upperBound <= end.lowerBound else {
                return nil
            }
            return String(tag[start.upperBound..<end.lowerBound])
        }
    }

    private static func firstValue(
        for keys: [String],
        in values: [String: String]
    ) -> String? {
        keys.lazy.compactMap { values[$0] }.first
    }

    private static func xAuthor(from title: String?) -> (name: String, handle: String)? {
        guard let title,
              let expression = try? NSRegularExpression(
                pattern: #"^(.+?)\s+\(@([A-Za-z0-9_]{1,20})\)\s+on\s+X$"#,
                options: [.caseInsensitive]
              ) else {
            return nil
        }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let match = expression.firstMatch(in: title, range: range),
              let nameRange = Range(match.range(at: 1), in: title),
              let handleRange = Range(match.range(at: 2), in: title) else {
            return nil
        }
        return (String(title[nameRange]), String(title[handleRange]))
    }

    private static func clean(_ value: String?) -> String? {
        guard var value else { return nil }
        value = decodeHTMLEntities(value)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{000B}", with: " ")
            .replacingOccurrences(of: "\u{000C}", with: " ")
        value = replacing(pattern: #"[\t ]+"#, in: value, with: " ")
        value = replacing(pattern: #" *\n *"#, in: value, with: "\n")
        value = replacing(pattern: #"\n{3,}"#, in: value, with: "\n\n")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")

        guard let expression = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return result
        }
        let matches = expression.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            let raw = String(result[valueRange])
            let radix = raw.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(raw.dropFirst()) : raw
            guard let scalarValue = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            result.replaceSubrange(wholeRange, with: String(Character(scalar)))
        }
        return result
    }

    private static func matches(
        pattern: String,
        in value: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            Range(match.range(at: 0), in: value).map { String(value[$0]) }
        }
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: replacement
        )
    }

    private static func validatedWebURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), url.host() != nil,
              scheme == "http" || scheme == "https" else {
            return nil
        }
        if url.host()?.lowercased() == "abs.twimg.com",
           url.path.lowercased().contains("/rweb/ssr/default/") {
            return nil
        }
        return url
    }
}
