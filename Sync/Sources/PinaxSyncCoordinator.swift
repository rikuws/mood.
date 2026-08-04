import Foundation
import Observation

public enum PinaxSyncStatus: Equatable, Sendable {
    case disabled
    case idle
    case syncing(startedAt: Date)
    case synced(PinaxSyncResult)
    case failed(at: Date, message: String)

    public var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

/// Observable facade intended for SwiftUI scene activation and an explicit
/// "Sync now" action. It does not observe platform lifecycle APIs itself, so it
/// is safe to compile into both apps and extensions.
@MainActor
@Observable
public final class PinaxSyncCoordinator {
    public var isEnabled: Bool {
        didSet {
            if !isEnabled {
                status = .disabled
                lastError = nil
            } else if status == .disabled {
                status = .idle
            }
        }
    }

    public private(set) var status: PinaxSyncStatus
    public private(set) var lastError: String?
    public private(set) var lastResult: PinaxSyncResult?

    @ObservationIgnored
    public let engine: PinaxSyncEngine

    @ObservationIgnored
    private let clock: @Sendable () -> Date

    @ObservationIgnored
    private let remoteChangeSubscriptionProvider:
        (any PinaxRemoteChangeSubscriptionProviding)?

    public init(
        engine: PinaxSyncEngine,
        remoteChangeSubscriptionProvider:
            (any PinaxRemoteChangeSubscriptionProviding)? = nil,
        isEnabled: Bool = true,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.engine = engine
        self.remoteChangeSubscriptionProvider = remoteChangeSubscriptionProvider
        self.isEnabled = isEnabled
        self.clock = clock
        status = isEnabled ? .idle : .disabled
    }

    /// Explicit synchronization. Errors remain visible in `status` and
    /// `lastError`, making this convenient for scene tasks and buttons.
    @discardableResult
    public func sync() async -> PinaxSyncResult? {
        await performSync(afterRemoteChange: false)
    }

    /// Call from a scene's active-phase handler. The returned task is owned by
    /// the coordinator's main-actor context and duplicate calls are coalesced.
    public func syncOnActivation() {
        guard isEnabled, !status.isSyncing else { return }
        Task { await sync() }
    }

    /// Handles a server-change hint without losing a change that committed
    /// after an already-running sync took its remote snapshot.
    @discardableResult
    public func syncAfterRemoteChange() async -> PinaxSyncResult? {
        await performSync(afterRemoteChange: true)
    }

    private func performSync(afterRemoteChange: Bool) async -> PinaxSyncResult? {
        guard isEnabled else {
            status = .disabled
            return nil
        }
        if !status.isSyncing {
            status = .syncing(startedAt: clock())
        }
        do {
            let result: PinaxSyncResult
            if afterRemoteChange {
                result = try await engine.syncAfterRemoteChange()
            } else {
                result = try await engine.sync()
            }
            lastResult = result
            lastError = nil
            status = .synced(result)
            // A launch-time subscription attempt can fail while offline or
            // while iCloud is temporarily unavailable. Every later successful
            // foreground sync is another safe, idempotent repair opportunity.
            _ = await prepareForRemoteChanges()
            return result
        } catch {
            let message = error.localizedDescription
            lastError = message
            status = .failed(at: clock(), message: message)
            return nil
        }
    }

    /// Installs the silent CloudKit zone subscription when the selected
    /// backend supports it. Failure does not disable local or foreground sync.
    @discardableResult
    public func prepareForRemoteChanges() async -> Bool {
        guard isEnabled else { return false }
        guard let remoteChangeSubscriptionProvider else { return true }
        do {
            try await remoteChangeSubscriptionProvider.ensureRemoteChangeSubscription()
            return true
        } catch {
            return false
        }
    }

    public func clearError() {
        lastError = nil
        if case .failed = status {
            status = isEnabled ? .idle : .disabled
        }
    }
}
