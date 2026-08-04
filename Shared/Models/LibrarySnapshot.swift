import Foundation

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var projects: [Project]
    public var inspirations: [Inspiration]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = LibrarySnapshot.currentSchemaVersion,
        projects: [Project] = [],
        inspirations: [Inspiration] = [],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.inspirations = inspirations
        self.updatedAt = updatedAt
    }

    public static func empty(at date: Date = Date()) -> LibrarySnapshot {
        LibrarySnapshot(updatedAt: date)
    }

    public func project(id: Project.ID) -> Project? {
        projects.first { $0.id == id }
    }

    public func inspiration(id: Inspiration.ID) -> Inspiration? {
        inspirations.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projects
        case inspirations
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        inspirations = try container.decodeIfPresent([Inspiration].self, forKey: .inspirations) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

public enum LibraryScope: Hashable, Sendable {
    case all
    case general
    case project(Project.ID)
}

public struct ProjectCounts: Equatable, Sendable {
    public var total: Int
    public var general: Int
    public var byProject: [Project.ID: Int]

    public init(total: Int, general: Int, byProject: [Project.ID: Int]) {
        self.total = total
        self.general = general
        self.byProject = byProject
    }

    public subscript(projectID: Project.ID) -> Int {
        byProject[projectID, default: 0]
    }
}

public struct CaptureResult: Equatable, Sendable {
    public var inspiration: Inspiration
    public var inserted: Bool

    public init(inspiration: Inspiration, inserted: Bool) {
        self.inspiration = inspiration
        self.inserted = inserted
    }
}
