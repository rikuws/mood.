import Foundation

public enum CanonicalURLError: Error, Equatable, Sendable {
    case unsupportedURL
}

/// Produces stable URL identities for capture deduplication without performing
/// network requests. In particular, all public X/Twitter status URL variants
/// collapse to `https://x.com/i/status/<id>`.
public enum CanonicalURL {
    private static let xHosts: Set<String> = [
        "x.com", "www.x.com", "mobile.x.com", "m.x.com",
        "twitter.com", "www.twitter.com", "mobile.twitter.com", "m.twitter.com"
    ]

    private static let trackingQueryNames: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "igshid", "mc_cid", "mc_eid",
        "_hsenc", "_hsmi", "vero_conv", "vero_id", "ref", "ref_src"
    ]

    public static func canonicalize(_ string: String) throws -> URL {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CanonicalURLError.unsupportedURL
        }
        return try canonicalize(url)
    }

    public static func canonicalize(_ url: URL) throws -> URL {
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let rawScheme = components.scheme?.lowercased(),
            rawScheme == "http" || rawScheme == "https",
            var host = components.host?.lowercased(),
            !host.isEmpty
        else {
            throw CanonicalURLError.unsupportedURL
        }

        components.user = nil
        components.password = nil
        components.fragment = nil

        if xHosts.contains(host) {
            return try canonicalXURL(originalURL: url, components: &components)
        }

        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        components.host = host
        components.scheme = rawScheme
        if (rawScheme == "http" && components.port == 80)
            || (rawScheme == "https" && components.port == 443) {
            components.port = nil
        }
        components.percentEncodedPath = normalizedPath(components.percentEncodedPath)
        components.queryItems = normalizedQueryItems(components.queryItems, removingXShareItems: false)

        guard let result = components.url else {
            throw CanonicalURLError.unsupportedURL
        }
        return result
    }

    private static func canonicalXURL(
        originalURL: URL,
        components: inout URLComponents
    ) throws -> URL {
        components.scheme = "https"
        components.host = "x.com"
        components.port = nil

        let segments = originalURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let statusID = statusID(in: segments) {
            components.percentEncodedPath = "/i/status/\(statusID)"
            components.query = nil
        } else {
            var path = normalizedPath(components.percentEncodedPath)
            let decodedSegments = path.split(separator: "/", omittingEmptySubsequences: true)
            if decodedSegments.count == 1,
               let first = decodedSegments.first,
               !first.hasPrefix("%") {
                path = "/\(first.lowercased())"
            }
            components.percentEncodedPath = path
            components.queryItems = normalizedQueryItems(components.queryItems, removingXShareItems: true)
        }

        guard let result = components.url else {
            throw CanonicalURLError.unsupportedURL
        }
        return result
    }

    private static func statusID(in segments: [String]) -> String? {
        for index in segments.indices {
            let segment = segments[index].lowercased()
            guard segment == "status" || segment == "statuses" else { continue }
            let nextIndex = segments.index(after: index)
            guard nextIndex < segments.endIndex else { continue }
            let candidate = segments[nextIndex]
            if !candidate.isEmpty && candidate.allSatisfy(\.isNumber) {
                return candidate
            }
        }
        return nil
    }

    private static func normalizedPath(_ percentEncodedPath: String) -> String {
        guard !percentEncodedPath.isEmpty else { return "" }

        var parts: [Substring] = []
        for part in percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".":
                continue
            case "..":
                if !parts.isEmpty { parts.removeLast() }
            default:
                parts.append(part)
            }
        }

        guard !parts.isEmpty else { return "" }
        return "/" + parts.joined(separator: "/")
    }

    private static func normalizedQueryItems(
        _ items: [URLQueryItem]?,
        removingXShareItems: Bool
    ) -> [URLQueryItem]? {
        let filtered = (items ?? []).filter { item in
            let name = item.name.lowercased()
            if name.hasPrefix("utm_") || trackingQueryNames.contains(name) {
                return false
            }
            if removingXShareItems && (name == "s" || name == "t") {
                return false
            }
            return true
        }
        .sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return ($0.value ?? "") < ($1.value ?? "")
        }

        return filtered.isEmpty ? nil : filtered
    }
}
