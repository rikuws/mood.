import Foundation
import PinaxCore
import XCTest
@testable import PinaxCloudSync

final class SyncEngineTests: XCTestCase, @unchecked Sendable {
    private let firstDate = Date(timeIntervalSince1970: 1_710_000_000)
    private let syncDate = Date(timeIntervalSince1970: 1_710_000_100)

    func testEnginePullsRemoteSnapshotIntoLocalRepository() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory, clock: { self.syncDate })
        let project = Project(name: "Website", createdAt: firstDate)
        let inspiration = try makeInspiration(projectID: project.id)
        let backend = InMemoryPinaxSyncBackend(
            snapshot: PinaxRemoteSnapshot(
                projects: [project],
                inspirations: [inspiration]
            )
        )
        let engine = try PinaxSyncEngine(
            repository: repository,
            backend: backend,
            clock: { self.syncDate }
        )

        let result = try await engine.sync()
        let local = try await repository.load()

        XCTAssertEqual(local.projects, [project])
        XCTAssertEqual(local.inspirations, [inspiration])
        XCTAssertEqual(result.uploadedRecordCount, 0)
        let counts = await backend.callCounts()
        XCTAssertEqual(counts.fetches, 1)
        XCTAssertEqual(counts.applies, 0)
    }

    func testEnginePersistsBaselineAndUploadsLaterDeletion() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory, clock: { self.syncDate })
        let inspiration = try makeInspiration()
        try await repository.save(
            LibrarySnapshot(inspirations: [inspiration], updatedAt: firstDate)
        )
        let backend = InMemoryPinaxSyncBackend()
        let engine = try PinaxSyncEngine(
            repository: repository,
            backend: backend,
            clock: { self.syncDate }
        )

        _ = try await engine.sync()
        _ = try await repository.deleteInspiration(id: inspiration.id)
        let result = try await engine.sync()
        let remote = await backend.currentSnapshot()
        let state = try await engine.stateStore.load()

        XCTAssertEqual(result.tombstoneCount, 1)
        XCTAssertTrue(remote.inspirations.isEmpty)
        XCTAssertEqual(remote.tombstones.map(\.id), [inspiration.id])
        XCTAssertEqual(state.tombstones.map(\.id), [inspiration.id])
    }

    func testApplyFailurePersistsDeletionIntentWithoutAdvancingSuccessDate() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory, clock: { self.syncDate })
        let inspiration = try makeInspiration()
        try await repository.save(
            LibrarySnapshot(inspirations: [inspiration], updatedAt: firstDate)
        )
        let backend = InMemoryPinaxSyncBackend()
        let engine = try PinaxSyncEngine(
            repository: repository,
            backend: backend,
            clock: { self.syncDate }
        )
        _ = try await engine.sync()
        _ = try await repository.deleteInspiration(id: inspiration.id)
        await backend.failNext(.apply)

        await XCTAssertThrowsErrorAsync(try await engine.sync())
        let failedState = try await engine.stateStore.load()
        XCTAssertEqual(failedState.tombstones.map(\.id), [inspiration.id])
        XCTAssertEqual(failedState.lastSuccessfulSyncAt, syncDate)

        _ = try await engine.sync()
        let recovered = await backend.currentSnapshot()
        XCTAssertEqual(recovered.tombstones.map(\.id), [inspiration.id])
    }

    func testBestEffortUploadReturnsAtTimeout() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory)
        let backend = SlowSyncBackend()
        let engine = try PinaxSyncEngine(repository: repository, backend: backend)

        let result = await PinaxBestEffortSync.uploadAfterCapture(
            using: engine,
            timeout: .milliseconds(20)
        )

        XCTAssertEqual(result, .timedOut)
    }

    func testEngineRefetchesAndRetriesOneBackendConflict() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory, clock: { self.syncDate })
        let inspiration = try makeInspiration()
        try await repository.save(
            LibrarySnapshot(inspirations: [inspiration], updatedAt: firstDate)
        )
        let backend = InMemoryPinaxSyncBackend()
        await backend.failNext(.conflict)
        let engine = try PinaxSyncEngine(
            repository: repository,
            backend: backend,
            clock: { self.syncDate }
        )

        _ = try await engine.sync()

        let calls = await backend.callCounts()
        let remote = await backend.currentSnapshot()
        XCTAssertEqual(calls.fetches, 2)
        XCTAssertEqual(calls.applies, 2)
        XCTAssertEqual(remote.inspirations.map(\.id), [inspiration.id])
    }

    func testCaptureDuringRemoteFetchSurvivesAtomicMerge() async throws {
        let directory = try temporaryDirectory()
        let syncRepository = try LibraryRepository(
            storageDirectory: directory,
            clock: { self.syncDate }
        )
        let captureRepository = try LibraryRepository(
            storageDirectory: directory,
            clock: { self.syncDate }
        )
        let remoteURL = try XCTUnwrap(URL(string: "https://remote.example/design"))
        let remoteInspiration = Inspiration(
            source: .web,
            url: remoteURL,
            canonicalURL: try CanonicalURL.canonicalize(remoteURL),
            title: "Remote design",
            createdAt: firstDate
        )
        let backend = BlockingFetchBackend(
            snapshot: PinaxRemoteSnapshot(inspirations: [remoteInspiration])
        )
        let engine = try PinaxSyncEngine(
            repository: syncRepository,
            backend: backend,
            clock: { self.syncDate }
        )

        let syncTask = Task { try await engine.sync() }
        await backend.waitUntilFetchStarts()

        let capturedURL = try XCTUnwrap(URL(string: "https://local.example/inspiration"))
        let capture = try await captureRepository.capture(
            CapturePayload(source: .web, url: capturedURL, title: "Captured while syncing")
        )
        await backend.resumeFetch()
        _ = try await syncTask.value

        let final = try await syncRepository.load()
        XCTAssertEqual(
            Set(final.inspirations.map(\.id)),
            Set([remoteInspiration.id, capture.inspiration.id])
        )
    }

    @MainActor
    func testCoordinatorExposesFailureAndRecoveryStatus() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory)
        let backend = InMemoryPinaxSyncBackend()
        let engine = try PinaxSyncEngine(repository: repository, backend: backend)
        let coordinator = PinaxSyncCoordinator(engine: engine)
        await backend.failNext(.fetch)

        let failed = await coordinator.sync()
        XCTAssertNil(failed)
        XCTAssertNotNil(coordinator.lastError)
        if case .failed = coordinator.status {} else {
            XCTFail("Expected failed coordinator status")
        }

        let recovered = await coordinator.sync()
        XCTAssertNotNil(recovered)
        XCTAssertNil(coordinator.lastError)
        if case .synced = coordinator.status {} else {
            XCTFail("Expected synced coordinator status")
        }
    }

    @MainActor
    func testConcurrentCoordinatorCallsAwaitTheSameSync() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory)
        let backend = BlockingFetchBackend(snapshot: .empty)
        let engine = try PinaxSyncEngine(repository: repository, backend: backend)
        let coordinator = PinaxSyncCoordinator(engine: engine)

        let first = Task { @MainActor in await coordinator.sync() }
        await backend.waitUntilFetchStarts()
        let second = Task { @MainActor in await coordinator.sync() }
        await Task.yield()
        await backend.resumeFetch()

        let firstResult = await first.value
        let secondResult = await second.value
        let fetchCount = await backend.fetchCount()
        XCTAssertNotNil(firstResult)
        XCTAssertNotNil(secondResult)
        XCTAssertEqual(fetchCount, 1)
    }

    @MainActor
    func testRemoteChangeDuringFetchForcesFreshReconciliation() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory)
        let backend = RemoteChangeRaceBackend()
        let engine = try PinaxSyncEngine(repository: repository, backend: backend)
        let coordinator = PinaxSyncCoordinator(engine: engine)
        let remoteInspiration = try makeInspiration()

        let activationSync = Task { @MainActor in await coordinator.sync() }
        await backend.waitUntilFirstFetchStarts()
        await backend.replaceSnapshot(
            PinaxRemoteSnapshot(inspirations: [remoteInspiration])
        )
        let pushSync = Task { @MainActor in
            await coordinator.syncAfterRemoteChange()
        }
        await Task.yield()
        await backend.resumeFirstFetch()

        let activationResult = await activationSync.value
        let pushResult = await pushSync.value
        let local = try await repository.load()
        let fetchCount = await backend.fetchCount()
        XCTAssertNotNil(activationResult)
        XCTAssertNotNil(pushResult)
        XCTAssertEqual(local.inspirations.map(\.id), [remoteInspiration.id])
        XCTAssertEqual(fetchCount, 2)
    }

    @MainActor
    func testSuccessfulSyncRetriesSubscriptionAfterTransientPreparationFailure() async throws {
        let directory = try temporaryDirectory()
        let repository = try LibraryRepository(storageDirectory: directory)
        let backend = InMemoryPinaxSyncBackend()
        let engine = try PinaxSyncEngine(repository: repository, backend: backend)
        let subscriptionProvider = FailOnceRemoteChangeSubscriptionProvider()
        let coordinator = PinaxSyncCoordinator(
            engine: engine,
            remoteChangeSubscriptionProvider: subscriptionProvider
        )

        let launchPreparation = await coordinator.prepareForRemoteChanges()
        XCTAssertFalse(launchPreparation)

        let syncResult = await coordinator.sync()
        let preparationAttempts = await subscriptionProvider.attemptCount()
        XCTAssertNotNil(syncResult)
        XCTAssertEqual(preparationAttempts, 2)
    }

    private func makeInspiration(projectID: Project.ID? = nil) throws -> Inspiration {
        let url = try XCTUnwrap(URL(string: "https://example.com/design"))
        return Inspiration(
            source: .web,
            url: url,
            canonicalURL: try CanonicalURL.canonicalize(url),
            title: "Design",
            projectID: projectID,
            createdAt: firstDate
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinaxCloudSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private actor SlowSyncBackend: PinaxSyncBackend {
    func fetchSnapshot() async throws -> PinaxRemoteSnapshot {
        try await Task.sleep(for: .seconds(30))
        return .empty
    }

    func apply(_ mutations: PinaxSyncMutationBatch) async throws {}
}

private actor BlockingFetchBackend: PinaxSyncBackend {
    private let snapshot: PinaxRemoteSnapshot
    private var fetchStarted = false
    private var fetches = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var fetchContinuation: CheckedContinuation<PinaxRemoteSnapshot, Never>?

    init(snapshot: PinaxRemoteSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshot() async throws -> PinaxRemoteSnapshot {
        fetches += 1
        fetchStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            fetchContinuation = continuation
        }
    }

    func apply(_ mutations: PinaxSyncMutationBatch) async throws {}

    func waitUntilFetchStarts() async {
        guard !fetchStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeFetch() {
        fetchContinuation?.resume(returning: snapshot)
        fetchContinuation = nil
    }

    func fetchCount() -> Int {
        fetches
    }
}

private actor RemoteChangeRaceBackend: PinaxSyncBackend {
    private var snapshot: PinaxRemoteSnapshot = .empty
    private var fetches = 0
    private var firstFetchStarted = false
    private var firstFetchSnapshot: PinaxRemoteSnapshot = .empty
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstFetchContinuation: CheckedContinuation<PinaxRemoteSnapshot, Never>?

    func fetchSnapshot() async throws -> PinaxRemoteSnapshot {
        fetches += 1
        guard fetches == 1 else { return snapshot }

        firstFetchSnapshot = snapshot
        firstFetchStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            firstFetchContinuation = continuation
        }
    }

    func apply(_ mutations: PinaxSyncMutationBatch) async throws {}

    func waitUntilFirstFetchStarts() async {
        guard !firstFetchStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func replaceSnapshot(_ snapshot: PinaxRemoteSnapshot) {
        self.snapshot = snapshot
    }

    func resumeFirstFetch() {
        firstFetchContinuation?.resume(returning: firstFetchSnapshot)
        firstFetchContinuation = nil
    }

    func fetchCount() -> Int {
        fetches
    }
}

private actor FailOnceRemoteChangeSubscriptionProvider:
    PinaxRemoteChangeSubscriptionProviding {
    private var attempts = 0

    func ensureRemoteChangeSubscription() async throws {
        attempts += 1
        if attempts == 1 {
            throw RemoteChangeSubscriptionTestFailure.transient
        }
    }

    func attemptCount() -> Int {
        attempts
    }
}

private enum RemoteChangeSubscriptionTestFailure: Error {
    case transient
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}
