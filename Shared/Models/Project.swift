import Foundation

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var name: String
    public var colorHex: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ID = ID(),
        name: String,
        colorHex: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
