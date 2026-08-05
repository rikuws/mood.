import Foundation
import PinaxCore

public enum PinaxSyncStateStoreError: Error, Equatable, Sendable {
    case invalidFilename
    case unsupportedSchemaVersion(Int)
    case coordinatedAccessFailed(String)
    case coordinatedAccessDidNotRun
}

extension PinaxSyncStateStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidFilename:
            "The mood. sync-state filename is invalid."
        case .unsupportedSchemaVersion(let version):
            "mood. sync state uses unsupported schema version \(version)."
        case .coordinatedAccessFailed(let message):
            "mood. sync state could not be accessed: \(message)"
        case .coordinatedAccessDidNotRun:
            "The mood. sync-state coordinator did not run its operation."
        }
    }
}

/// App-group persisted deletion baseline, coordinated across the main app and
/// share extension processes.
public actor PinaxSyncStateStore {
    public static let defaultFilename = "pinax-cloud-sync-state.json"

    public nonisolated let fileURL: URL

    public init(
        storageDirectory: URL,
        filename: String = PinaxSyncStateStore.defaultFilename
    ) throws {
        guard
            !filename.isEmpty,
            filename == URL(fileURLWithPath: filename).lastPathComponent,
            !filename.contains("/"),
            !filename.contains("\\")
        else {
            throw PinaxSyncStateStoreError.invalidFilename
        }

        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        fileURL = storageDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    public init(repository: LibraryRepository) throws {
        try self.init(storageDirectory: repository.storageDirectory)
    }

    public func load() throws -> PinaxSyncState {
        try coordinateReading { coordinatedURL in
            guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                return .empty
            }
            let data = try Data(contentsOf: coordinatedURL)
            let state = try Self.decoder().decode(PinaxSyncState.self, from: data)
            guard state.schemaVersion <= PinaxSyncState.currentSchemaVersion else {
                throw PinaxSyncStateStoreError.unsupportedSchemaVersion(state.schemaVersion)
            }
            return state
        }
    }

    public func save(_ state: PinaxSyncState) throws {
        _ = try coordinateWriting { coordinatedURL in
            var state = state
            state.schemaVersion = PinaxSyncState.currentSchemaVersion
            state.tombstones = Self.normalizedTombstones(state.tombstones)
            let data = try Self.encoder().encode(state)
            try data.write(to: coordinatedURL, options: [.atomic])
            return ()
        }
    }

    private func coordinateReading<Value: Sendable>(
        _ operation: @escaping @Sendable (URL) throws -> Value
    ) throws -> Value {
        let box = SyncCoordinationResultBox<Value>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(
            readingItemAt: fileURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            box.result = Result { try operation(coordinatedURL) }
        }
        return try Self.coordinationResult(from: box, error: coordinationError)
    }

    private func coordinateWriting<Value: Sendable>(
        _ operation: @escaping @Sendable (URL) throws -> Value
    ) throws -> Value {
        let box = SyncCoordinationResultBox<Value>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            box.result = Result { try operation(coordinatedURL) }
        }
        return try Self.coordinationResult(from: box, error: coordinationError)
    }

    private nonisolated static func coordinationResult<Value>(
        from box: SyncCoordinationResultBox<Value>,
        error: NSError?
    ) throws -> Value {
        if let error {
            throw PinaxSyncStateStoreError.coordinatedAccessFailed(error.localizedDescription)
        }
        guard let result = box.result else {
            throw PinaxSyncStateStoreError.coordinatedAccessDidNotRun
        }
        return try result.get()
    }

    private nonisolated static func normalizedTombstones(
        _ tombstones: [PinaxSyncTombstone]
    ) -> [PinaxSyncTombstone] {
        var byKey: [PinaxSyncEntityKey: PinaxSyncTombstone] = [:]
        for tombstone in tombstones {
            if let existing = byKey[tombstone.key], existing.deletedAt >= tombstone.deletedAt {
                continue
            }
            byKey[tombstone.key] = tombstone
        }
        return byKey.values.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private final class SyncCoordinationResultBox<Value>: @unchecked Sendable {
    var result: Result<Value, any Error>?
}
