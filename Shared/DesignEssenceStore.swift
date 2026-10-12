import CryptoKit
import Foundation

public enum DesignEssenceStorage {
    /// Saved essences live beside `library.json`, never inside it, so the
    /// user's collection and generated analysis stay separate.
    public static let directoryName = "Essences"
}

/// One saved, immutable essence file.
public struct DesignEssenceRevision: Codable, Hashable, Sendable {
    /// The filename without its extension: a zero-padded save sequence
    /// followed by a fingerprint of the essence, so revisions sort in the
    /// order they were saved.
    public let id: String
    /// Save order within the project, starting at 1. A correction saved later
    /// always has a higher sequence, whatever its `extractedAt`.
    public let sequence: Int
    public let projectID: Project.ID
    public let extractedAt: Date
    public let savedAt: Date
    public let path: String

    public init(
        id: String,
        sequence: Int,
        projectID: Project.ID,
        extractedAt: Date,
        savedAt: Date,
        path: String
    ) {
        self.id = id
        self.sequence = sequence
        self.projectID = projectID
        self.extractedAt = extractedAt
        self.savedAt = savedAt
        self.path = path
    }
}

/// A fingerprint of one source item as it was when the essence was saved.
public struct DesignEssenceSourceFingerprint: Codable, Hashable, Sendable {
    public let assetID: Inspiration.ID
    public let fingerprint: String

    public init(assetID: Inspiration.ID, fingerprint: String) {
        self.assetID = assetID
        self.fingerprint = fingerprint
    }
}

/// The on-disk shape of a revision: the essence exactly as validated, plus
/// what the library looked like when it was saved.
public struct DesignEssenceRecord: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let savedAt: Date
    public let sources: [DesignEssenceSourceFingerprint]
    public let essence: DesignEssence

    public init(
        savedAt: Date,
        sources: [DesignEssenceSourceFingerprint],
        essence: DesignEssence
    ) {
        formatVersion = Self.currentFormatVersion
        self.savedAt = savedAt
        self.sources = sources
        self.essence = essence
    }
}

public enum DesignEssenceSaveOutcome: String, Codable, Hashable, Sendable {
    case saved
    /// The identical document was already stored; nothing was written.
    case alreadySaved = "already_saved"
}

public enum DesignEssenceStoreError: Error, Equatable, Sendable {
    case unsupportedSource
    case revisionConflict(String)
    case unreadableRevision(String, String)
    case writeFailed(String)
}

extension DesignEssenceStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            "Only a project essence can be saved to the mood. library."
        case .revisionConflict(let id):
            "A different essence is already stored as revision \(id)."
        case .unreadableRevision(let id, let message):
            "The saved essence revision \(id) could not be read: \(message)"
        case .writeFailed(let message):
            "The essence could not be saved: \(message)"
        }
    }
}

/// Append-only, local-only storage for project essences at
/// `Essences/<project-uuid>/<revision>.json`.
///
/// A revision is never rewritten or deleted, so the folder is the revision
/// history. Essences are not synced through CloudKit yet.
public actor DesignEssenceStore {
    public nonisolated let directory: URL

    public init(storageDirectory: URL) {
        directory = storageDirectory.appendingPathComponent(
            DesignEssenceStorage.directoryName,
            isDirectory: true
        )
    }

    public nonisolated func projectDirectory(for projectID: Project.ID) -> URL {
        directory.appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    /// Stores a validated project essence as a new revision with the next
    /// save sequence. Saving the same essence again is idempotent and reports
    /// `alreadySaved` with the original revision.
    public func save(
        _ essence: DesignEssence,
        sources: [DesignEssenceSourceFingerprint],
        savedAt: Date = Date()
    ) throws -> (revision: DesignEssenceRevision, outcome: DesignEssenceSaveOutcome) {
        guard essence.source.kind == .project,
              let projectID = essence.source.projectID else {
            throw DesignEssenceStoreError.unsupportedSource
        }
        try DesignEssenceValidator.validate(essence)

        let essenceData: Data
        do {
            essenceData = try Self.makeEncoder().encode(essence)
        } catch {
            throw DesignEssenceStoreError.writeFailed(error.localizedDescription)
        }
        let fingerprint = Self.fingerprint(of: essenceData)

        let existingIDs = try revisionIDs(projectID: projectID)
        for id in existingIDs where id.hasSuffix("-\(fingerprint)") {
            let stored = try readRevision(id: id, projectID: projectID)
            guard (try? Self.makeEncoder().encode(stored.record.essence)) == essenceData else {
                throw DesignEssenceStoreError.revisionConflict(id)
            }
            return (stored.revision, .alreadySaved)
        }

        let sequence = (existingIDs.compactMap(Self.sequence(of:)).max() ?? 0) + 1
        let id = String(format: "%06ld", sequence) + "-\(fingerprint)"
        let folder = projectDirectory(for: projectID)
        let destination = folder.appendingPathComponent("\(id).json", isDirectory: false)
        // Whole seconds, so the returned revision matches what is read back.
        let record = DesignEssenceRecord(
            savedAt: Date(timeIntervalSince1970: savedAt.timeIntervalSince1970.rounded(.down)),
            sources: sources,
            essence: essence
        )

        let temporary = folder.appendingPathComponent(
            ".\(id).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            let recordData = try Self.makeEncoder().encode(record)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try recordData.write(to: temporary, options: .atomic)
            // Moving fails instead of replacing when the destination already
            // exists, which keeps a concurrent save from overwriting a revision.
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw DesignEssenceStoreError.writeFailed(error.localizedDescription)
        }

        return (
            Self.revision(id: id, projectID: projectID, record: record, path: destination.path),
            .saved
        )
    }

    /// Revision identifiers for a project, in save order.
    public func revisionIDs(projectID: Project.ID) throws -> [String] {
        let folder = projectDirectory(for: projectID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }

        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            throw DesignEssenceStoreError.unreadableRevision(
                projectID.uuidString,
                error.localizedDescription
            )
        }
        return names
            .filter { $0.range(of: Self.revisionFilenamePattern, options: .regularExpression) != nil }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }

    /// The most recently saved revision for a project, if any.
    public func latest(
        projectID: Project.ID
    ) throws -> (revision: DesignEssenceRevision, record: DesignEssenceRecord)? {
        guard let id = try revisionIDs(projectID: projectID).last else { return nil }
        return try readRevision(id: id, projectID: projectID)
    }

    private func readRevision(
        id: String,
        projectID: Project.ID
    ) throws -> (revision: DesignEssenceRevision, record: DesignEssenceRecord) {
        let fileURL = projectDirectory(for: projectID)
            .appendingPathComponent("\(id).json", isDirectory: false)
        let record: DesignEssenceRecord
        do {
            let data = try Data(contentsOf: fileURL)
            record = try Self.makeDecoder().decode(DesignEssenceRecord.self, from: data)
        } catch {
            throw DesignEssenceStoreError.unreadableRevision(id, error.localizedDescription)
        }
        return (
            Self.revision(id: id, projectID: projectID, record: record, path: fileURL.path),
            record
        )
    }

    private static let revisionFilenamePattern = #"^[0-9]{6}-[0-9a-f]{12}\.json$"#

    private static func revision(
        id: String,
        projectID: Project.ID,
        record: DesignEssenceRecord,
        path: String
    ) -> DesignEssenceRevision {
        DesignEssenceRevision(
            id: id,
            sequence: sequence(of: id) ?? 0,
            projectID: projectID,
            extractedAt: record.essence.provenance.extractedAt,
            savedAt: record.savedAt,
            path: path
        )
    }

    private static func sequence(of id: String) -> Int? {
        Int(id.prefix(6))
    }

    private static func fingerprint(of data: Data) -> String {
        String(
            SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
                .prefix(12)
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
