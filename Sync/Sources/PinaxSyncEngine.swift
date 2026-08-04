import Foundation
import PinaxCore

/// Local-first sync orchestration. Local reads and writes never depend on this
/// actor; a CloudKit failure leaves the JSON library fully usable offline.
public actor PinaxSyncEngine {
    public nonisolated let repository: LibraryRepository
    public nonisolated let stateStore: PinaxSyncStateStore

    private let backend: any PinaxSyncBackend
    private let clock: @Sendable () -> Date
    private struct ActiveSync {
        let id: UUID
        let task: Task<PinaxSyncResult, any Error>
    }

    private var activeSync: ActiveSync?

    public init(
        repository: LibraryRepository,
        backend: any PinaxSyncBackend,
        stateStore: PinaxSyncStateStore? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.repository = repository
        self.backend = backend
        self.stateStore = try stateStore ?? PinaxSyncStateStore(repository: repository)
        self.clock = clock
    }

    /// Reconciles one complete logical snapshot. Concurrent requests in the
    /// same process share one task, which is useful when activation and a
    /// capture notification arrive together.
    public func sync() async throws -> PinaxSyncResult {
        if let activeSync {
            return try await activeSync.task.value
        }

        let repository = repository
        let backend = backend
        let stateStore = stateStore
        let clock = clock
        let task = Task<PinaxSyncResult, any Error> {
            for attempt in 0..<2 {
                do {
                    try Task.checkCancellation()
                    let state = try await stateStore.load()
                    let remote = try await backend.fetchSnapshot()
                    try Task.checkCancellation()
                    let mergeDate = clock()
                    let merge = try await repository.withAtomicSnapshotMutation(
                        at: mergeDate
                    ) { latestLocal in
                        for index in latestLocal.inspirations.indices
                        where latestLocal.inspirations[index].localImageFilename != nil {
                            guard let url = repository.localImageURL(
                                for: latestLocal.inspirations[index]
                            ), FileManager.default.fileExists(atPath: url.path) else {
                                // A filename is only a device-local cache pointer.
                                // Removing a stale pointer must not advance the
                                // record's cloud conflict timestamp.
                                latestLocal.inspirations[index].localImageFilename = nil
                                continue
                            }
                        }

                        let merge = PinaxSyncMerger.merge(
                            local: latestLocal,
                            remote: remote,
                            state: state,
                            at: mergeDate
                        )
                        latestLocal = merge.snapshot
                        return merge
                    }

                    // Persist the new baseline and any deletion intent before
                    // making a fallible network write. Preserve the previous
                    // success date until CloudKit accepts the mutations. This
                    // closes the window where a pulled record could be deleted
                    // locally after a partial failure yet look "previously
                    // unknown" and be restored on the next attempt.
                    var pendingState = merge.state
                    pendingState.lastSuccessfulSyncAt = state.lastSuccessfulSyncAt
                    try await stateStore.save(pendingState)

                    if !merge.mutations.isEmpty {
                        try Task.checkCancellation()
                        try await backend.apply(merge.mutations)
                    }

                    // Mark success only after all idempotent remote mutations
                    // complete. Tombstones remain durable if this write fails.
                    try await stateStore.save(merge.state)

                    return PinaxSyncResult(
                        completedAt: mergeDate,
                        uploadedRecordCount: merge.mutations.recordCount,
                        projectCount: merge.snapshot.projects.count,
                        inspirationCount: merge.snapshot.inspirations.count,
                        tombstoneCount: merge.state.tombstones.count,
                        canonicalDuplicatesRemoved: merge.canonicalDuplicatesRemoved
                    )
                } catch let error as PinaxSyncBackendError {
                    if case .conflict = error, attempt == 0 {
                        continue
                    }
                    throw error
                }
            }

            preconditionFailure("The bounded Pinax sync retry loop did not return or throw.")
        }

        let id = UUID()
        activeSync = ActiveSync(id: id, task: task)
        defer {
            if activeSync?.id == id {
                activeSync = nil
            }
        }
        return try await task.value
    }

    /// Reconciles a remote-change hint after any work that was already in
    /// flight when the hint arrived. The fresh pass cannot be accidentally
    /// coalesced back into the older fetch.
    public func syncAfterRemoteChange() async throws -> PinaxSyncResult {
        if let precedingSync = activeSync {
            // A failed older attempt must not prevent the push from getting
            // its own fresh recovery attempt.
            _ = try? await precedingSync.task.value
            if activeSync?.id == precedingSync.id {
                activeSync = nil
            }
        }

        try Task.checkCancellation()
        return try await sync()
    }

    func cancelActiveSync() {
        activeSync?.task.cancel()
    }
}
