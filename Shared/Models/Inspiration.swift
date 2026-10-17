import Foundation

/// The user's own judgment on a saved item. Keeps and rejects are both taste
/// signal: a reject is retained so it can later act as a negative reference.
public enum InspirationVerdict: String, Codable, CaseIterable, Hashable, Sendable {
    case keep
    case reject
}

public struct Inspiration: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var source: CaptureSource
    /// The URL as it was originally captured. Use `canonicalURL` for identity.
    public var url: URL
    public var canonicalURL: URL
    public var title: String
    /// Text captured with the item, such as an X post body or a page description.
    public var text: String
    /// The user's own words about why the item matters, kept separate from
    /// captured `text` so agents can cite them as the user's reasoning.
    public var note: String?
    public var verdict: InspirationVerdict?
    public var authorName: String?
    public var authorHandle: String?
    public var imageURL: URL?
    /// A filename relative to the repository's shared Media directory.
    public var localImageFilename: String?
    /// `nil` represents the General collection.
    public var projectID: Project.ID?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastCapturedAt: Date
    public var captureCount: Int

    public init(
        id: ID = ID(),
        source: CaptureSource,
        url: URL,
        canonicalURL: URL,
        title: String = "",
        text: String = "",
        note: String? = nil,
        verdict: InspirationVerdict? = nil,
        authorName: String? = nil,
        authorHandle: String? = nil,
        imageURL: URL? = nil,
        localImageFilename: String? = nil,
        projectID: Project.ID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastCapturedAt: Date? = nil,
        captureCount: Int = 1
    ) {
        self.id = id
        self.source = source
        self.url = url
        self.canonicalURL = canonicalURL
        self.title = title
        self.text = text
        self.note = note
        self.verdict = verdict
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.imageURL = imageURL
        self.localImageFilename = localImageFilename
        self.projectID = projectID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastCapturedAt = lastCapturedAt ?? createdAt
        self.captureCount = max(1, captureCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case url
        case canonicalURL
        case title
        case text
        case note
        case verdict
        case authorName
        case authorHandle
        case imageURL
        case localImageFilename
        case projectID
        case createdAt
        case updatedAt
        case lastCapturedAt
        case captureCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        source = try container.decode(CaptureSource.self, forKey: .source)
        url = try container.decode(URL.self, forKey: .url)
        canonicalURL = try container.decode(URL.self, forKey: .canonicalURL)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note)
        verdict = try container.decodeIfPresent(InspirationVerdict.self, forKey: .verdict)
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
        authorHandle = try container.decodeIfPresent(String.self, forKey: .authorHandle)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        localImageFilename = try container.decodeIfPresent(String.self, forKey: .localImageFilename)
        projectID = try container.decodeIfPresent(Project.ID.self, forKey: .projectID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastCapturedAt = try container.decodeIfPresent(Date.self, forKey: .lastCapturedAt) ?? updatedAt
        captureCount = max(1, try container.decodeIfPresent(Int.self, forKey: .captureCount) ?? 1)
    }
}

public extension Inspiration {
    /// The single account label used when presenting a saved X post.
    var xUsernameLabel: String? {
        guard source == .x else { return nil }

        if let handle = Self.cleanedXHandle(authorHandle) {
            return "@\(handle)"
        }

        let path = url.pathComponents.filter { $0 != "/" }
        if path.count >= 3,
           path[1].lowercased() == "status",
           path[0].lowercased() != "i",
           let handle = Self.cleanedXHandle(path[0]) {
            return "@\(handle)"
        }

        if let name = authorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        return nil
    }

    /// Whether there's a stored or remote image to show.
    var hasPreviewImage: Bool {
        localImageFilename != nil || imageURL != nil
    }

    /// The saved title worth printing on a card, or nil when it says nothing
    /// the picture doesn't: an empty title, the site's address, or the name
    /// of the image file, which is all a browser calls an image opened on its
    /// own ("IMG_2041.jpeg", "GxYz12 (1200×800)").
    var meaningfulTitle: String? {
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              !Self.isAddressTitle(title, for: url),
              !Self.isImageFileTitle(title, sources: [url, imageURL].compactMap { $0 }) else {
            return nil
        }
        return title
    }

    private static func isAddressTitle(_ title: String, for url: URL) -> Bool {
        let title = title.lowercased()
        let host = url.host()?.lowercased() ?? ""
        return title == host
            || (host.hasPrefix("www.") && title == String(host.dropFirst(4)))
            || title == url.absoluteString.lowercased()
            || title == "saved link"
    }

    private static func isImageFileTitle(_ title: String, sources: [URL]) -> Bool {
        // Chrome titles an image tab "name (1200×800)", Safari "name 1200×800
        // pixels", Firefox "name (JPEG Image, 1200 × 800 pixels)".
        let pixelSuffix = #"\s*(\(\s*\d+\s*[×xX]\s*\d+\s*\)|\(?[^()]*?[\d,]+\s*[×xX]\s*[\d,]+\s*pixels\)?)$"#
        if title.range(of: pixelSuffix, options: .regularExpression) != nil {
            return true
        }

        let imageExtension = #"\.(jpe?g|png|gif|webp|avif|heic|heif|tiff?|bmp|svg)$"#
        if title.range(of: imageExtension, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        let name = title.lowercased()
        return sources.contains { source in
            let file = source.lastPathComponent.lowercased()
            guard !file.isEmpty, file != "/" else { return false }
            return name == file
                || name == source.deletingPathExtension().lastPathComponent.lowercased()
        }
    }

    private static func cleanedXHandle(_ value: String?) -> String? {
        guard let handle = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
            !handle.isEmpty else {
            return nil
        }
        return handle
    }
}
