import Foundation

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var name: String
    public var colorHex: String?
    /// Optional project item used as the stable artwork behind its moodboard.
    /// Older libraries omit this key and continue to use automatic selection.
    public var backgroundInspirationID: Inspiration.ID?
    /// Present when the project is a guided visual study. Older libraries
    /// omit this key and read as ordinary projects.
    public var study: ProjectStudy?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ID = ID(),
        name: String,
        colorHex: String? = nil,
        backgroundInspirationID: Inspiration.ID? = nil,
        study: ProjectStudy? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.backgroundInspirationID = backgroundInspirationID
        self.study = study
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public extension Project {
    var isStudy: Bool {
        study != nil
    }
}
