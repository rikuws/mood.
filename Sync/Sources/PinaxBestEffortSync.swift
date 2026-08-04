import Foundation

public enum PinaxBestEffortSyncResult: Equatable, Sendable {
    case uploaded(PinaxSyncResult)
    case timedOut
    case failed(String)
}

/// App-extension-friendly entry point for requesting a bounded sync after the
/// capture has already been committed to the shared local repository.
public enum PinaxBestEffortSync {
    public static func uploadAfterCapture(
        using engine: PinaxSyncEngine,
        timeout: Duration = .seconds(5)
    ) async -> PinaxBestEffortSyncResult {
        let gate = BestEffortResultGate<PinaxBestEffortSyncResult>()
        let syncTask = Task {
            do {
                let result = try await engine.sync()
                gate.resolve(.uploaded(result))
            } catch is CancellationError {
                // The timeout path already owns the visible result.
            } catch {
                gate.resolve(.failed(error.localizedDescription))
            }
        }

        Task {
            do {
                if timeout > .zero {
                    try await Task.sleep(for: timeout)
                }
            } catch {
                return
            }
            if gate.resolve(.timedOut) {
                syncTask.cancel()
                await engine.cancelActiveSync()
            }
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
            }
        } onCancel: {
            if gate.resolve(.timedOut) {
                syncTask.cancel()
                Task { await engine.cancelActiveSync() }
            }
        }
    }
}

private final class BestEffortResultGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var resolvedValue: Value?

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        let immediateValue = lock.withLock { () -> Value? in
            if let resolvedValue {
                return resolvedValue
            }
            self.continuation = continuation
            return nil
        }
        if let immediateValue {
            continuation.resume(returning: immediateValue)
        }
    }

    @discardableResult
    func resolve(_ value: Value) -> Bool {
        let outcome = lock.withLock { () -> (Bool, CheckedContinuation<Value, Never>?) in
            guard resolvedValue == nil else { return (false, nil) }
            resolvedValue = value
            let continuation = self.continuation
            self.continuation = nil
            return (true, continuation)
        }
        outcome.1?.resume(returning: value)
        return outcome.0
    }
}
