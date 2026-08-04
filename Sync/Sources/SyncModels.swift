import Foundation
import PinaxCore

/// The two user-owned model types mirrored into the private CloudKit database.
public enum PinaxSyncEntityKind: String, Codable, CaseIterable, Hashable, Sendable {
    case project
    case inspiration
}

/// A durable deletion marker. Tombstones participate in the same `updatedAt`
/// last-writer-wins comparison as live records, so an old offline copy cannot
/// silently recreate a deleted item on its next sync.
public struct PinaxSyncTombstone: Codable, Equatable, Hashable, Sendable {
    public var kind: PinaxSyncEntityKind
    public var id: UUID
    public var deletedAt: Date

    public init(kind: PinaxSyncEntityKind, id: UUID, deletedAt: Date) {
        self.kind = kind
        self.id = id
        self.deletedAt = deletedAt
    }

    public var key: PinaxSyncEntityKey {
        PinaxSyncEntityKey(kind: kind, id: id)
    }
}

public struct PinaxSyncEntityKey: Codable, Equatable, Hashable, Sendable {
    public var kind: PinaxSyncEntityKind
    public var id: UUID

    public init(kind: PinaxSyncEntityKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

/// A complete logical view of Pinax records in a sync backend.
///
/// `assetBackedInspirationIDs` is deliberately separate from the model. A
/// `localImageFilename` is a device-local pointer and is never used as cloud
/// identity; this set lets the engine upload a local image when the remote
/// record has metadata but no CKAsset yet.
public struct PinaxRemoteSnapshot: Equatable, Sendable {
    public var projects: [Project]
    public var inspirations: [Inspiration]
    public var tombstones: [PinaxSyncTombstone]
    public var assetBackedInspirationIDs: Set<Inspiration.ID>

    public init(
        projects: [Project] = [],
        inspirations: [Inspiration] = [],
        tombstones: [PinaxSyncTombstone] = [],
        assetBackedInspirationIDs: Set<Inspiration.ID> = []
    ) {
        self.projects = projects
        self.inspirations = inspirations
        self.tombstones = tombstones
        self.assetBackedInspirationIDs = assetBackedInspirationIDs
    }

    public static let empty = PinaxRemoteSnapshot()
}

/// The minimal set of records the backend needs to write after reconciliation.
public struct PinaxSyncMutationBatch: Equatable, Sendable {
    public var projects: [Project]
    public var inspirations: [Inspiration]
    public var tombstones: [PinaxSyncTombstone]

    public init(
        projects: [Project] = [],
        inspirations: [Inspiration] = [],
        tombstones: [PinaxSyncTombstone] = []
    ) {
        self.projects = projects
        self.inspirations = inspirations
        self.tombstones = tombstones
    }

    public var isEmpty: Bool {
        projects.isEmpty && inspirations.isEmpty && tombstones.isEmpty
    }

    public var recordCount: Int {
        projects.count + inspirations.count + tombstones.count
    }
}

/// Small persisted baseline used to distinguish a local deletion from a record
/// that simply has not reached this device yet.
public struct PinaxSyncState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var baselineProjectIDs: Set<Project.ID>
    public var baselineInspirationIDs: Set<Inspiration.ID>
    public var tombstones: [PinaxSyncTombstone]
    public var lastSuccessfulSyncAt: Date?

    public init(
        schemaVersion: Int = PinaxSyncState.currentSchemaVersion,
        baselineProjectIDs: Set<Project.ID> = [],
        baselineInspirationIDs: Set<Inspiration.ID> = [],
        tombstones: [PinaxSyncTombstone] = [],
        lastSuccessfulSyncAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.baselineProjectIDs = baselineProjectIDs
        self.baselineInspirationIDs = baselineInspirationIDs
        self.tombstones = tombstones
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    }

    public static let empty = PinaxSyncState()
}

public struct PinaxSyncMergeResult: Equatable, Sendable {
    public var snapshot: LibrarySnapshot
    public var state: PinaxSyncState
    public var mutations: PinaxSyncMutationBatch
    public var canonicalDuplicatesRemoved: Int

    public init(
        snapshot: LibrarySnapshot,
        state: PinaxSyncState,
        mutations: PinaxSyncMutationBatch,
        canonicalDuplicatesRemoved: Int
    ) {
        self.snapshot = snapshot
        self.state = state
        self.mutations = mutations
        self.canonicalDuplicatesRemoved = canonicalDuplicatesRemoved
    }
}

public struct PinaxSyncResult: Equatable, Sendable {
    public var completedAt: Date
    public var uploadedRecordCount: Int
    public var projectCount: Int
    public var inspirationCount: Int
    public var tombstoneCount: Int
    public var canonicalDuplicatesRemoved: Int

    public init(
        completedAt: Date,
        uploadedRecordCount: Int,
        projectCount: Int,
        inspirationCount: Int,
        tombstoneCount: Int,
        canonicalDuplicatesRemoved: Int
    ) {
        self.completedAt = completedAt
        self.uploadedRecordCount = uploadedRecordCount
        self.projectCount = projectCount
        self.inspirationCount = inspirationCount
        self.tombstoneCount = tombstoneCount
        self.canonicalDuplicatesRemoved = canonicalDuplicatesRemoved
    }
}
