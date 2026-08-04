import Foundation
import PinaxCore

/// Pure, deterministic reconciliation. It contains no CloudKit or filesystem
/// calls, which keeps conflict and deletion behavior directly unit-testable.
public enum PinaxSyncMerger {
    public static func merge(
        local: LibrarySnapshot,
        remote: PinaxRemoteSnapshot,
        state: PinaxSyncState,
        at now: Date
    ) -> PinaxSyncMergeResult {
        let normalizedLocalInspirations = local.inspirations.map(normalizedCanonicalURL)
        let normalizedRemoteInspirations = remote.inspirations.map(normalizedCanonicalURL)

        var tombstones: [PinaxSyncEntityKey: PinaxSyncTombstone] = [:]
        for tombstone in state.tombstones + remote.tombstones {
            keepNewest(tombstone, in: &tombstones)
        }

        let currentProjectIDs = Set(local.projects.map(\.id))
        for id in state.baselineProjectIDs.subtracting(currentProjectIDs) {
            keepNewest(
                PinaxSyncTombstone(kind: .project, id: id, deletedAt: now),
                in: &tombstones
            )
        }

        let currentInspirationIDs = Set(normalizedLocalInspirations.map(\.id))
        for id in state.baselineInspirationIDs.subtracting(currentInspirationIDs) {
            keepNewest(
                PinaxSyncTombstone(kind: .inspiration, id: id, deletedAt: now),
                in: &tombstones
            )
        }

        let localProjects = newestProjectsByID(local.projects)
        let remoteProjects = newestProjectsByID(remote.projects)
        var mergedProjects: [Project] = []
        for id in Set(localProjects.keys).union(remoteProjects.keys) {
            guard let candidate = latest(localProjects[id], remoteProjects[id]) else { continue }
            let key = PinaxSyncEntityKey(kind: .project, id: id)
            if let tombstone = tombstones[key], tombstone.deletedAt >= candidate.updatedAt {
                continue
            }
            tombstones.removeValue(forKey: key)
            mergedProjects.append(candidate)
        }

        let localInspirations = newestInspirationsByID(normalizedLocalInspirations)
        let remoteInspirations = newestInspirationsByID(normalizedRemoteInspirations)
        var mergedInspirations: [Inspiration] = []
        for id in Set(localInspirations.keys).union(remoteInspirations.keys) {
            guard let candidate = latest(localInspirations[id], remoteInspirations[id]) else {
                continue
            }
            let key = PinaxSyncEntityKey(kind: .inspiration, id: id)
            if let tombstone = tombstones[key], tombstone.deletedAt >= candidate.updatedAt {
                continue
            }
            tombstones.removeValue(forKey: key)
            mergedInspirations.append(candidate)
        }

        let deduplication = deduplicateByCanonicalURL(
            mergedInspirations,
            at: now,
            tombstones: &tombstones
        )
        mergedInspirations = deduplication.inspirations

        let validProjectIDs = Set(mergedProjects.map(\.id))
        for index in mergedInspirations.indices {
            guard let projectID = mergedInspirations[index].projectID,
                  !validProjectIDs.contains(projectID) else {
                continue
            }

            mergedInspirations[index].projectID = nil
            let projectKey = PinaxSyncEntityKey(kind: .project, id: projectID)
            if let deletedAt = tombstones[projectKey]?.deletedAt,
               deletedAt > mergedInspirations[index].updatedAt {
                mergedInspirations[index].updatedAt = deletedAt
            }
        }

        mergedProjects.sort(by: projectOrder)
        mergedInspirations.sort(by: inspirationOrder)
        let sortedTombstones = tombstones.values.sorted(by: tombstoneOrder)

        let snapshot = LibrarySnapshot(
            schemaVersion: local.schemaVersion,
            projects: mergedProjects,
            inspirations: mergedInspirations,
            updatedAt: now
        )
        let nextState = PinaxSyncState(
            baselineProjectIDs: Set(mergedProjects.map(\.id)),
            baselineInspirationIDs: Set(mergedInspirations.map(\.id)),
            tombstones: sortedTombstones,
            lastSuccessfulSyncAt: now
        )
        let mutations = mutations(
            projects: mergedProjects,
            inspirations: mergedInspirations,
            tombstones: sortedTombstones,
            comparedWith: remote
        )

        return PinaxSyncMergeResult(
            snapshot: snapshot,
            state: nextState,
            mutations: mutations,
            canonicalDuplicatesRemoved: deduplication.removedCount
        )
    }

    private static func keepNewest(
        _ tombstone: PinaxSyncTombstone,
        in tombstones: inout [PinaxSyncEntityKey: PinaxSyncTombstone]
    ) {
        guard let existing = tombstones[tombstone.key] else {
            tombstones[tombstone.key] = tombstone
            return
        }
        if tombstone.deletedAt > existing.deletedAt {
            tombstones[tombstone.key] = tombstone
        }
    }

    private static func newestProjectsByID(_ projects: [Project]) -> [Project.ID: Project] {
        projects.reduce(into: [:]) { result, project in
            result[project.id] = latest(result[project.id], project)
        }
    }

    private static func newestInspirationsByID(
        _ inspirations: [Inspiration]
    ) -> [Inspiration.ID: Inspiration] {
        inspirations.reduce(into: [:]) { result, inspiration in
            result[inspiration.id] = latest(result[inspiration.id], inspiration)
        }
    }

    private static func latest(_ lhs: Project?, _ rhs: Project?) -> Project? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        return stableData(lhs).lexicographicallyPrecedes(stableData(rhs)) ? rhs : lhs
    }

    private static func latest(
        _ lhs: Inspiration?,
        _ rhs: Inspiration?
    ) -> Inspiration? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        var selected: Inspiration
        if lhs.updatedAt != rhs.updatedAt {
            selected = lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        } else {
            selected = stableData(cloudComparable(lhs)).lexicographicallyPrecedes(
                stableData(cloudComparable(rhs))
            ) ? rhs : lhs
        }

        // The filename is device-local rather than conflict metadata. Keep any
        // usable pointer supplied by either side (including a freshly
        // materialized CKAsset) even when the other side wins metadata LWW.
        if selected.localImageFilename == nil {
            selected.localImageFilename = lhs.localImageFilename ?? rhs.localImageFilename
        }
        return selected
    }

    private static func normalizedCanonicalURL(_ inspiration: Inspiration) -> Inspiration {
        var inspiration = inspiration
        if let canonical = try? CanonicalURL.canonicalize(inspiration.url) {
            inspiration.canonicalURL = canonical
        } else if let canonical = try? CanonicalURL.canonicalize(inspiration.canonicalURL) {
            inspiration.canonicalURL = canonical
        }
        return inspiration
    }

    private static func deduplicateByCanonicalURL(
        _ inspirations: [Inspiration],
        at now: Date,
        tombstones: inout [PinaxSyncEntityKey: PinaxSyncTombstone]
    ) -> (inspirations: [Inspiration], removedCount: Int) {
        let groups = Dictionary(grouping: inspirations) {
            $0.canonicalURL.absoluteString
        }
        var result: [Inspiration] = []
        var removedCount = 0

        for key in groups.keys.sorted() {
            guard let group = groups[key] else { continue }
            let ranked = group.sorted(by: canonicalWinnerOrder)
            guard var winner = ranked.first else { continue }

            for loser in ranked.dropFirst() {
                fillMissingMetadata(on: &winner, from: loser)
                let deletedAt = max(now, max(winner.updatedAt, loser.updatedAt))
                keepNewest(
                    PinaxSyncTombstone(
                        kind: .inspiration,
                        id: loser.id,
                        deletedAt: deletedAt
                    ),
                    in: &tombstones
                )
                removedCount += 1
            }
            result.append(winner)
        }
        return (result, removedCount)
    }

    private static func canonicalWinnerOrder(
        _ lhs: Inspiration,
        _ rhs: Inspiration
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func fillMissingMetadata(
        on winner: inout Inspiration,
        from other: Inspiration
    ) {
        if winner.title.isEmpty { winner.title = other.title }
        if winner.text.isEmpty { winner.text = other.text }
        if winner.authorName == nil { winner.authorName = other.authorName }
        if winner.authorHandle == nil { winner.authorHandle = other.authorHandle }
        if winner.imageURL == nil { winner.imageURL = other.imageURL }
        if winner.localImageFilename == nil {
            winner.localImageFilename = other.localImageFilename
        }
        if winner.source == .web, other.source == .x { winner.source = .x }
        winner.lastCapturedAt = max(winner.lastCapturedAt, other.lastCapturedAt)
        winner.captureCount = max(winner.captureCount, other.captureCount)
    }

    private static func mutations(
        projects: [Project],
        inspirations: [Inspiration],
        tombstones: [PinaxSyncTombstone],
        comparedWith remote: PinaxRemoteSnapshot
    ) -> PinaxSyncMutationBatch {
        let remoteProjects = newestProjectsByID(remote.projects)
        let remoteInspirations = newestInspirationsByID(
            remote.inspirations.map(normalizedCanonicalURL)
        )
        let remoteTombstones = remote.tombstones.reduce(into: [:]) { result, tombstone in
            keepNewest(tombstone, in: &result)
        }

        let changedProjects = projects.filter { project in
            let key = PinaxSyncEntityKey(kind: .project, id: project.id)
            return remoteProjects[project.id] != project || remoteTombstones[key] != nil
        }
        let changedInspirations = inspirations.filter { inspiration in
            let key = PinaxSyncEntityKey(kind: .inspiration, id: inspiration.id)
            let metadataChanged = remoteInspirations[inspiration.id].map(cloudComparable)
                != cloudComparable(inspiration)
            let needsAsset = inspiration.localImageFilename != nil
                && !remote.assetBackedInspirationIDs.contains(inspiration.id)
            return metadataChanged || needsAsset || remoteTombstones[key] != nil
        }
        let changedTombstones = tombstones.filter { tombstone in
            guard remoteTombstones[tombstone.key] == tombstone else { return true }
            switch tombstone.kind {
            case .project:
                return remoteProjects[tombstone.id] != nil
            case .inspiration:
                return remoteInspirations[tombstone.id] != nil
            }
        }

        return PinaxSyncMutationBatch(
            projects: changedProjects.sorted(by: projectOrder),
            inspirations: changedInspirations.sorted(by: inspirationOrder),
            tombstones: changedTombstones.sorted(by: tombstoneOrder)
        )
    }

    private static func cloudComparable(_ inspiration: Inspiration) -> Inspiration {
        var copy = inspiration
        copy.localImageFilename = nil
        return copy
    }

    private static func stableData<Value: Encodable>(_ value: Value) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)) ?? Data()
    }

    private static func projectOrder(_ lhs: Project, _ rhs: Project) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func inspirationOrder(_ lhs: Inspiration, _ rhs: Inspiration) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func tombstoneOrder(
        _ lhs: PinaxSyncTombstone,
        _ rhs: PinaxSyncTombstone
    ) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
