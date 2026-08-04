import Foundation
import PinaxCore

public enum PinaxSyncBackendError: Error, Equatable, Sendable {
    /// The remote record changed after it was fetched. The engine retries from
    /// a fresh snapshot so `updatedAt` reconciliation, rather than upload order,
    /// decides the winner.
    case conflict(String)
    case operationFailed(String)
}

extension PinaxSyncBackendError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .conflict(let message):
            "Pinax cloud data changed during sync: \(message)"
        case .operationFailed(let message):
            "Pinax cloud sync failed: \(message)"
        }
    }
}

/// Backend boundary for deterministic merge tests and alternative transports.
/// The production implementation uses only the user's private CloudKit database.
public protocol PinaxSyncBackend: Sendable {
    func fetchSnapshot() async throws -> PinaxRemoteSnapshot
    func apply(_ mutations: PinaxSyncMutationBatch) async throws
}

/// A deterministic, CloudKit-free backend suitable for unit tests and previews.
public actor InMemoryPinaxSyncBackend: PinaxSyncBackend {
    public enum Failure: Error, Equatable, Sendable {
        case fetch
        case apply
        case conflict
    }

    private var snapshot: PinaxRemoteSnapshot
    private var nextFailure: Failure?
    private var fetches = 0
    private var applies = 0

    public init(snapshot: PinaxRemoteSnapshot = .empty) {
        self.snapshot = snapshot
    }

    public func fetchSnapshot() throws -> PinaxRemoteSnapshot {
        fetches += 1
        if nextFailure == .fetch {
            nextFailure = nil
            throw Failure.fetch
        }
        return snapshot
    }

    public func apply(_ mutations: PinaxSyncMutationBatch) throws {
        applies += 1
        if nextFailure == .apply {
            nextFailure = nil
            throw Failure.apply
        }
        if nextFailure == .conflict {
            nextFailure = nil
            throw PinaxSyncBackendError.conflict("Injected in-memory backend conflict.")
        }

        var projects = snapshot.projects.reduce(into: [PinaxCore.Project.ID: PinaxCore.Project]()) {
            $0[$1.id] = $1
        }
        var inspirations = snapshot.inspirations.reduce(
            into: [PinaxCore.Inspiration.ID: PinaxCore.Inspiration]()
        ) {
            $0[$1.id] = $1
        }
        var tombstones = snapshot.tombstones.reduce(
            into: [PinaxSyncEntityKey: PinaxSyncTombstone]()
        ) {
            if $0[$1.key, default: $1].deletedAt <= $1.deletedAt {
                $0[$1.key] = $1
            }
        }
        var assetIDs = snapshot.assetBackedInspirationIDs

        for project in mutations.projects {
            projects[project.id] = project
            tombstones.removeValue(
                forKey: PinaxSyncEntityKey(kind: .project, id: project.id)
            )
        }
        for inspiration in mutations.inspirations {
            inspirations[inspiration.id] = inspiration
            tombstones.removeValue(
                forKey: PinaxSyncEntityKey(kind: .inspiration, id: inspiration.id)
            )
            if inspiration.localImageFilename != nil {
                assetIDs.insert(inspiration.id)
            }
        }
        for tombstone in mutations.tombstones {
            tombstones[tombstone.key] = tombstone
            switch tombstone.kind {
            case .project:
                projects.removeValue(forKey: tombstone.id)
            case .inspiration:
                inspirations.removeValue(forKey: tombstone.id)
                assetIDs.remove(tombstone.id)
            }
        }

        snapshot = PinaxRemoteSnapshot(
            projects: projects.values.sorted(by: Self.projectOrder),
            inspirations: inspirations.values.sorted(by: Self.inspirationOrder),
            tombstones: tombstones.values.sorted(by: Self.tombstoneOrder),
            assetBackedInspirationIDs: assetIDs
        )
    }

    public func replaceSnapshot(_ snapshot: PinaxRemoteSnapshot) {
        self.snapshot = snapshot
    }

    public func failNext(_ failure: Failure) {
        nextFailure = failure
    }

    public func currentSnapshot() -> PinaxRemoteSnapshot {
        snapshot
    }

    public func callCounts() -> (fetches: Int, applies: Int) {
        (fetches, applies)
    }

    private static func projectOrder(_ lhs: PinaxCore.Project, _ rhs: PinaxCore.Project) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func inspirationOrder(
        _ lhs: PinaxCore.Inspiration,
        _ rhs: PinaxCore.Inspiration
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func tombstoneOrder(
        _ lhs: PinaxSyncTombstone,
        _ rhs: PinaxSyncTombstone
    ) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
