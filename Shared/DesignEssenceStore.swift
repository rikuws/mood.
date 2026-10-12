import CryptoKit
import Foundation

public enum DesignEssenceStorage {
    /// Saved essences live beside `library.json`, never inside it, so the
    /// user's collection and generated analysis stay separate.
    public static let directoryName = "Essences"
}

/// One saved, immutable essence file.
public struct DesignEssenceRevision: Codable, Hashable, Sendable {
    /// The filename without its extension: the extraction time followed by a
    /// content fingerprint, so revisions sort chronologically by name.
    public let id: String
    public let projectID: Project.ID
    public let extractedAt: Date
    public let path: String

    public init(id: String, projectID: Project.ID, extractedAt: Date, path: String) {
        self.id = id
        self.projectID = projectID
        self.extractedAt = extractedAt
        self.path = path
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

    /// Stores a validated project essence as a new revision. Saving the same
    /// document twice is idempotent and reports `alreadySaved`.
    public func save(
        _ essence: DesignEssence
    ) throws -> (revision: DesignEssenceRevision, outcome: DesignEssenceSaveOutcome) {
        guard essence.source.kind == .project,
              let projectID = essence.source.projectID else {
            throw DesignEssenceStoreError.unsupportedSource
        }
        try DesignEssenceValidator.validate(essence)

        let data: Data
        do {
            data = try Self.makeEncoder().encode(essence)
        } catch {
            throw DesignEssenceStoreError.writeFailed(error.localizedDescription)
        }

        let id = Self.revisionID(extractedAt: essence.provenance.extractedAt, data: data)
        let folder = projectDirectory(for: projectID)
        let destination = folder.appendingPathComponent("\(id).json", isDirectory: false)
        let revision = DesignEssenceRevision(
            id: id,
            projectID: projectID,
            extractedAt: essence.provenance.extractedAt,
            path: destination.path
        )

        if let existing = try? Data(contentsOf: destination) {
            guard existing == data else {
                throw DesignEssenceStoreError.revisionConflict(id)
            }
            return (revision, .alreadySaved)
        }

        let temporary = folder.appendingPathComponent(
            ".\(id).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: temporary, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw DesignEssenceStoreError.writeFailed(error.localizedDescription)
        }

        do {
            // Moving fails instead of replacing when the destination already
            // exists, which keeps a concurrent save from overwriting a revision.
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if let existing = try? Data(contentsOf: destination) {
                guard existing == data else {
                    throw DesignEssenceStoreError.revisionConflict(id)
                }
                return (revision, .alreadySaved)
            }
            throw DesignEssenceStoreError.writeFailed(error.localizedDescription)
        }
        return (revision, .saved)
    }

    /// Revision identifiers for a project, oldest first.
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

    /// The most recently extracted revision for a project, if any.
    public func latest(
        projectID: Project.ID
    ) throws -> (revision: DesignEssenceRevision, essence: DesignEssence)? {
        guard let id = try revisionIDs(projectID: projectID).last else { return nil }
        let fileURL = projectDirectory(for: projectID)
            .appendingPathComponent("\(id).json", isDirectory: false)

        let essence: DesignEssence
        do {
            let data = try Data(contentsOf: fileURL)
            essence = try JSONDecoder().decode(DesignEssence.self, from: data)
        } catch {
            throw DesignEssenceStoreError.unreadableRevision(id, error.localizedDescription)
        }
        let revision = DesignEssenceRevision(
            id: id,
            projectID: projectID,
            extractedAt: essence.provenance.extractedAt,
            path: fileURL.path
        )
        return (revision, essence)
    }

    private static let revisionFilenamePattern = #"^[0-9]{8}T[0-9]{6}\.[0-9]{3}Z-[0-9a-f]{12}\.json$"#

    private static func revisionID(extractedAt: Date, data: Data) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(formatter.string(from: extractedAt))-\(digest.prefix(12))"
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
