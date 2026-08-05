import CloudKit
import Foundation
import PinaxCore

/// CloudKit transport backed exclusively by the current user's private
/// database. A custom zone is created lazily; no account, server, or API-key
/// setup is needed beyond the app's iCloud/CloudKit capability.
public actor CloudKitSyncBackend: PinaxSyncBackend, PinaxRemoteChangeSubscriptionProviding {
    public static let defaultZoneName = "PinaxLibrary"
    public static let remoteChangeSubscriptionID =
        "com.rikuwikman.pinax.library-changes.v1"

    private enum RecordType {
        static let project = "PinaxProject"
        static let inspiration = "PinaxInspiration"
    }

    private enum Field {
        static let schemaVersion = "schemaVersion"
        static let entityID = "entityID"
        static let updatedAt = "updatedAt"
        static let isDeleted = "isDeleted"
        static let payload = "payload"
        static let canonicalURL = "canonicalURL"
        static let image = "image"
        static let imageFileExtension = "imageFileExtension"
    }

    private static let recordSchemaVersion = 1
    private static let maximumAssetBytes: Int64 = 45 * 1_024 * 1_024

    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let remoteChangeSubscriptionRegistrar: CloudKitRemoteChangeSubscriptionRegistrar
    private let mediaDirectory: URL?
    private var zoneIsReady = false
    private var cachedRecords: [CKRecord.ID: CKRecord] = [:]

    public init(
        containerIdentifier: String? = nil,
        mediaDirectory: URL? = nil,
        zoneName: String = CloudKitSyncBackend.defaultZoneName
    ) {
        let container = containerIdentifier.map(CKContainer.init(identifier:)) ?? CKContainer.default()
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        self.database = database
        self.zoneID = zoneID
        remoteChangeSubscriptionRegistrar = CloudKitRemoteChangeSubscriptionRegistrar(
            database: database,
            zoneID: zoneID,
            subscriptionID: Self.remoteChangeSubscriptionID
        )
        self.mediaDirectory = mediaDirectory
    }

    public func ensureRemoteChangeSubscription() async throws {
        try await ensureZone()
        try await remoteChangeSubscriptionRegistrar.ensure()
    }

    public func fetchSnapshot() async throws -> PinaxRemoteSnapshot {
        try await ensureZone()

        cachedRecords.removeAll(keepingCapacity: true)
        var projects: [Project] = []
        var inspirations: [Inspiration] = []
        var tombstones: [PinaxSyncTombstone] = []
        var assetIDs: Set<Inspiration.ID> = []
        var token: CKServerChangeToken?
        var moreComing = false

        repeat {
            let page: (
                modificationResultsByID: [
                    CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>
                ],
                deletions: [CKDatabase.RecordZoneChange.Deletion],
                changeToken: CKServerChangeToken,
                moreComing: Bool
            )
            do {
                page = try await database.recordZoneChanges(
                    inZoneWith: zoneID,
                    since: token,
                    desiredKeys: nil,
                    resultsLimit: 200
                )
            } catch {
                throw translated(error)
            }

            for recordID in page.modificationResultsByID.keys.sorted(by: recordIDOrder) {
                guard let result = page.modificationResultsByID[recordID] else { continue }
                let modification: CKDatabase.RecordZoneChange.Modification
                do {
                    modification = try result.get()
                } catch {
                    throw translated(error)
                }
                let record = modification.record
                cachedRecords[recordID] = record
                switch try decode(record) {
                case .project(let project):
                    projects.append(project)
                case .inspiration(let inspiration, let hasAsset):
                    inspirations.append(inspiration)
                    if hasAsset { assetIDs.insert(inspiration.id) }
                case .tombstone(let tombstone):
                    tombstones.append(tombstone)
                case .ignored:
                    break
                }
            }

            // Pinax never physically deletes records (it overwrites them with
            // tombstones), but honor unexpected dashboard deletions in the
            // in-memory cache while reading a page.
            for deletion in page.deletions {
                cachedRecords.removeValue(forKey: deletion.recordID)
            }
            token = page.changeToken
            moreComing = page.moreComing
        } while moreComing

        return PinaxRemoteSnapshot(
            projects: projects,
            inspirations: inspirations,
            tombstones: tombstones,
            assetBackedInspirationIDs: assetIDs
        )
    }

    public func apply(_ mutations: PinaxSyncMutationBatch) async throws {
        guard !mutations.isEmpty else { return }
        try await ensureZone()

        let targetIDs = Set(
            mutations.projects.map { recordID(kind: .project, id: $0.id) }
                + mutations.inspirations.map { recordID(kind: .inspiration, id: $0.id) }
                + mutations.tombstones.map { recordID(kind: $0.kind, id: $0.id) }
        )
        try await primeCache(for: targetIDs.filter { cachedRecords[$0] == nil })

        var recordsByID: [CKRecord.ID: CKRecord] = [:]
        for project in mutations.projects {
            let record = try record(for: project)
            recordsByID[record.recordID] = record
        }
        for inspiration in mutations.inspirations {
            let record = try record(for: inspiration)
            recordsByID[record.recordID] = record
        }
        for tombstone in mutations.tombstones {
            let record = record(for: tombstone)
            recordsByID[record.recordID] = record
        }

        let records = recordsByID.values.sorted { recordIDOrder($0.recordID, $1.recordID) }
        for start in stride(from: 0, to: records.count, by: 200) {
            let end = min(start + 200, records.count)
            let batch = Array(records[start..<end])
            let results: (
                saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
                deleteResults: [CKRecord.ID: Result<Void, any Error>]
            )
            do {
                results = try await database.modifyRecords(
                    saving: batch,
                    deleting: [],
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: false
                )
            } catch {
                throw translated(error)
            }

            for recordID in results.saveResults.keys.sorted(by: recordIDOrder) {
                guard let result = results.saveResults[recordID] else { continue }
                do {
                    cachedRecords[recordID] = try result.get()
                } catch {
                    throw translated(error)
                }
            }
        }
    }

    private func ensureZone() async throws {
        guard !zoneIsReady else { return }

        do {
            let results = try await database.recordZones(for: [zoneID])
            if let result = results[zoneID] {
                do {
                    _ = try result.get()
                    zoneIsReady = true
                    return
                } catch let error as CKError
                    where error.code == .unknownItem || error.code == .zoneNotFound {
                    // Continue into the idempotent create below.
                }
            }
        } catch let error as CKError
            where error.code == .unknownItem || error.code == .zoneNotFound {
            // Continue into the idempotent create below.
        } catch {
            throw translated(error)
        }

        do {
            let zone = CKRecordZone(zoneID: zoneID)
            let results = try await database.modifyRecordZones(
                saving: [zone],
                deleting: []
            )
            guard let result = results.saveResults[zoneID] else {
                throw PinaxSyncBackendError.operationFailed(
                    "CloudKit returned no result while creating the mood. record zone."
                )
            }
            _ = try result.get()
            zoneIsReady = true
        } catch {
            throw translated(error)
        }
    }

    private func primeCache(for recordIDs: [CKRecord.ID]) async throws {
        guard !recordIDs.isEmpty else { return }
        let sortedIDs = recordIDs.sorted(by: recordIDOrder)
        for start in stride(from: 0, to: sortedIDs.count, by: 200) {
            let end = min(start + 200, sortedIDs.count)
            let results: [CKRecord.ID: Result<CKRecord, any Error>]
            do {
                results = try await database.records(for: Array(sortedIDs[start..<end]))
            } catch {
                throw translated(error)
            }
            for recordID in results.keys.sorted(by: recordIDOrder) {
                guard let result = results[recordID] else { continue }
                do {
                    cachedRecords[recordID] = try result.get()
                } catch let error as CKError where error.code == .unknownItem {
                    continue
                } catch {
                    throw translated(error)
                }
            }
        }
    }

    private enum DecodedRecord {
        case project(Project)
        case inspiration(Inspiration, hasAsset: Bool)
        case tombstone(PinaxSyncTombstone)
        case ignored
    }

    private func decode(_ record: CKRecord) throws -> DecodedRecord {
        let schemaVersion = (record[Field.schemaVersion] as? NSNumber)?.intValue ?? 1
        guard schemaVersion <= Self.recordSchemaVersion else {
            throw PinaxSyncBackendError.operationFailed(
                "CloudKit record \(record.recordID.recordName) uses unsupported schema version \(schemaVersion)."
            )
        }

        let kind: PinaxSyncEntityKind
        switch record.recordType {
        case RecordType.project:
            kind = .project
        case RecordType.inspiration:
            kind = .inspiration
        default:
            return .ignored
        }

        guard let id = entityID(from: record) else {
            throw PinaxSyncBackendError.operationFailed(
                "CloudKit record \(record.recordID.recordName) has no valid entity ID."
            )
        }
        let isDeleted = (record[Field.isDeleted] as? NSNumber)?.boolValue ?? false
        if isDeleted {
            guard let deletedAt = record[Field.updatedAt] as? Date else {
                throw PinaxSyncBackendError.operationFailed(
                    "CloudKit tombstone \(record.recordID.recordName) has no deletion date."
                )
            }
            return .tombstone(
                PinaxSyncTombstone(kind: kind, id: id, deletedAt: deletedAt)
            )
        }

        guard let payload = record[Field.payload] as? Data else {
            throw PinaxSyncBackendError.operationFailed(
                "CloudKit record \(record.recordID.recordName) has no payload."
            )
        }

        switch kind {
        case .project:
            let project = try Self.decoder().decode(Project.self, from: payload)
            guard project.id == id else {
                throw PinaxSyncBackendError.operationFailed(
                    "CloudKit project ID does not match its record ID."
                )
            }
            return .project(project)

        case .inspiration:
            var inspiration = try Self.decoder().decode(Inspiration.self, from: payload)
            guard inspiration.id == id else {
                throw PinaxSyncBackendError.operationFailed(
                    "CloudKit inspiration ID does not match its record ID."
                )
            }
            inspiration.localImageFilename = nil
            let asset = record[Field.image] as? CKAsset
            if let asset,
               let filename = materialize(asset: asset, for: id, record: record) {
                inspiration.localImageFilename = filename
            }
            return .inspiration(inspiration, hasAsset: asset != nil)
        }
    }

    private func record(for project: Project) throws -> CKRecord {
        let record = liveRecord(kind: .project, id: project.id, updatedAt: project.updatedAt)
        record[Field.payload] = try Self.encoder().encode(project) as NSData
        record[Field.canonicalURL] = nil
        record[Field.image] = nil
        record[Field.imageFileExtension] = nil
        return record
    }

    private func record(for inspiration: Inspiration) throws -> CKRecord {
        let record = liveRecord(
            kind: .inspiration,
            id: inspiration.id,
            updatedAt: inspiration.updatedAt
        )
        var cloudCopy = inspiration
        cloudCopy.localImageFilename = nil
        record[Field.payload] = try Self.encoder().encode(cloudCopy) as NSData
        record[Field.canonicalURL] = inspiration.canonicalURL.absoluteString as NSString

        if let assetURL = localAssetURL(for: inspiration) {
            record[Field.image] = CKAsset(fileURL: assetURL)
            record[Field.imageFileExtension] = safeImageExtension(
                inspiration.localImageFilename.flatMap { URL(fileURLWithPath: $0).pathExtension }
            ) as NSString
        } else if record[Field.image] == nil {
            // A device-local filename may be absent even though another device
            // already uploaded an asset. Preserve that cached CKAsset during a
            // metadata-only edit instead of accidentally deleting it.
            record[Field.imageFileExtension] = nil
        }
        return record
    }

    private func record(for tombstone: PinaxSyncTombstone) -> CKRecord {
        let id = recordID(kind: tombstone.kind, id: tombstone.id)
        let record = cachedRecords[id] ?? CKRecord(
            recordType: recordType(for: tombstone.kind),
            recordID: id
        )
        record[Field.schemaVersion] = NSNumber(value: Self.recordSchemaVersion)
        record[Field.entityID] = tombstone.id.uuidString.lowercased() as NSString
        record[Field.updatedAt] = tombstone.deletedAt as NSDate
        record[Field.isDeleted] = NSNumber(value: true)
        record[Field.payload] = nil
        record[Field.canonicalURL] = nil
        record[Field.image] = nil
        record[Field.imageFileExtension] = nil
        return record
    }

    private func liveRecord(
        kind: PinaxSyncEntityKind,
        id: UUID,
        updatedAt: Date
    ) -> CKRecord {
        let id = recordID(kind: kind, id: id)
        let record = cachedRecords[id] ?? CKRecord(
            recordType: recordType(for: kind),
            recordID: id
        )
        record[Field.schemaVersion] = NSNumber(value: Self.recordSchemaVersion)
        record[Field.entityID] = entityID(from: id).uuidString.lowercased() as NSString
        record[Field.updatedAt] = updatedAt as NSDate
        record[Field.isDeleted] = NSNumber(value: false)
        return record
    }

    private func recordID(kind: PinaxSyncEntityKind, id: UUID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "\(kind.rawValue).\(id.uuidString.lowercased())",
            zoneID: zoneID
        )
    }

    private func recordType(for kind: PinaxSyncEntityKind) -> String {
        switch kind {
        case .project: RecordType.project
        case .inspiration: RecordType.inspiration
        }
    }

    private func entityID(from record: CKRecord) -> UUID? {
        if let value = record[Field.entityID] as? String, let id = UUID(uuidString: value) {
            return id
        }
        return entityID(from: record.recordID)
    }

    private func entityID(from recordID: CKRecord.ID) -> UUID {
        let suffix = recordID.recordName.split(separator: ".").last.map(String.init) ?? ""
        // This helper is only used for IDs constructed locally and therefore
        // always contains a UUID. Keep a deterministic fallback for resilience.
        return UUID(uuidString: suffix) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    private func localAssetURL(for inspiration: Inspiration) -> URL? {
        guard let mediaDirectory,
              let filename = inspiration.localImageFilename,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              !filename.contains("/"),
              !filename.contains("\\") else {
            return nil
        }
        let url = mediaDirectory.appendingPathComponent(filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size > 0,
              Int64(size) <= Self.maximumAssetBytes else {
            return nil
        }
        return url
    }

    private func materialize(
        asset: CKAsset,
        for id: Inspiration.ID,
        record: CKRecord
    ) -> String? {
        guard let mediaDirectory, let source = asset.fileURL else { return nil }
        let proposedExtension = (record[Field.imageFileExtension] as? String)
            ?? source.pathExtension
        let fileExtension = safeImageExtension(proposedExtension)
        let filename = "\(id.uuidString.lowercased()).\(fileExtension)"
        let destination = mediaDirectory.appendingPathComponent(filename, isDirectory: false)
        do {
            try FileManager.default.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: true
            )
            let data = try Data(contentsOf: source, options: [.mappedIfSafe])
            guard !data.isEmpty else { return nil }
            try data.write(to: destination, options: [.atomic])
            return filename
        } catch {
            // Image transfer is optional; never block metadata synchronization.
            return nil
        }
    }

    private func safeImageExtension(_ proposed: String?) -> String {
        let cleaned = (proposed ?? "")
            .lowercased()
            .filter(\.isLetter)
            .prefix(5)
        return cleaned.isEmpty ? "jpg" : String(cleaned)
    }

    private func translated(_ error: any Error) -> any Error {
        if let error = error as? PinaxSyncBackendError {
            return error
        }
        if let cloudError = error as? CKError,
           cloudError.code == .serverRecordChanged
                || cloudError.code == .batchRequestFailed {
            return PinaxSyncBackendError.conflict(cloudError.localizedDescription)
        }
        return PinaxSyncBackendError.operationFailed(error.localizedDescription)
    }

    private nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private nonisolated func recordIDOrder(_ lhs: CKRecord.ID, _ rhs: CKRecord.ID) -> Bool {
        lhs.recordName < rhs.recordName
    }
}
