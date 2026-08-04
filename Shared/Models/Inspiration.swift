import Foundation

public struct Inspiration: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var source: CaptureSource
    /// The URL as it was originally captured. Use `canonicalURL` for identity.
    public var url: URL
    public var canonicalURL: URL
    public var title: String
    public var text: String
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
