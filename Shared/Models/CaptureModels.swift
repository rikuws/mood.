import Foundation

/// Where a capture originated. The raw values intentionally match the browser
/// extension's wire format.
public enum CaptureSource: String, Codable, CaseIterable, Sendable {
    case x
    case web
}

/// The small, stable payload shared by the Chromium extension, URL handlers,
/// and the iOS share extension.
public struct CapturePayload: Codable, Equatable, Sendable {
    public var source: CaptureSource
    public var url: URL
    public var title: String
    public var text: String
    public var authorName: String?
    public var authorHandle: String?
    public var imageURL: URL?
    public var projectID: Project.ID?
    /// When true, a duplicate capture explicitly assigns `projectID`,
    /// including `nil` for General. Automatic browser captures leave this
    /// false so they do not pull a curated item out of its project.
    public var assignProjectOnDuplicate: Bool
    /// When true, non-empty metadata supplied by an explicit user capture
    /// replaces the corresponding values on a duplicate. Automatic browser
    /// captures leave this false and only fill fields that are still missing.
    public var overwriteMetadataOnDuplicate: Bool

    public init(
        source: CaptureSource,
        url: URL,
        title: String = "",
        text: String = "",
        authorName: String? = nil,
        authorHandle: String? = nil,
        imageURL: URL? = nil,
        projectID: Project.ID? = nil,
        assignProjectOnDuplicate: Bool = false,
        overwriteMetadataOnDuplicate: Bool = false
    ) {
        self.source = source
        self.url = url
        self.title = title
        self.text = text
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.imageURL = imageURL
        self.projectID = projectID
        self.assignProjectOnDuplicate = assignProjectOnDuplicate
        self.overwriteMetadataOnDuplicate = overwriteMetadataOnDuplicate
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case url
        case title
        case text
        case authorName
        case authorHandle
        case imageURL
        case projectID
        case assignProjectOnDuplicate
        case overwriteMetadataOnDuplicate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(CaptureSource.self, forKey: .source)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName)
        authorHandle = try container.decodeIfPresent(String.self, forKey: .authorHandle)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        projectID = try container.decodeIfPresent(Project.ID.self, forKey: .projectID)
        assignProjectOnDuplicate = try container.decodeIfPresent(
            Bool.self,
            forKey: .assignProjectOnDuplicate
        ) ?? false
        overwriteMetadataOnDuplicate = try container.decodeIfPresent(
            Bool.self,
            forKey: .overwriteMetadataOnDuplicate
        ) ?? false
    }
}
