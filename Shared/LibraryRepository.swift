import Foundation
#if os(macOS)
import Security
#endif

public enum PinaxStorage {
    public static let appGroupIdentifier = "group.com.rikuwikman.pinax"
    public static let libraryFilename = "library.json"
    public static let mediaDirectoryName = "Media"
}

public enum LibraryRepositoryError: Error, Equatable, Sendable {
    case appGroupUnavailable(String)
    case invalidStorageFilename
    case unsupportedSchemaVersion(Int)
    case invalidProjectName
    case duplicateProjectName
    case projectNotFound(Project.ID)
    case inspirationNotFound(Inspiration.ID)
    case duplicateCanonicalURL(URL)
    case invalidLocalImageFilename
    case coordinatedAccessFailed(String)
    case coordinatedAccessDidNotRun
}

extension LibraryRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let identifier):
            "The shared Pinax container (\(identifier)) is unavailable. Check the App Group entitlement."
        case .invalidStorageFilename:
            "The library storage filename is invalid."
        case .unsupportedSchemaVersion(let version):
            "This Pinax library uses unsupported schema version \(version)."
        case .invalidProjectName:
            "A project name cannot be empty."
        case .duplicateProjectName:
            "A project with that name already exists."
        case .projectNotFound:
            "The selected project no longer exists."
        case .inspirationNotFound:
            "The selected inspiration no longer exists."
        case .duplicateCanonicalURL:
            "That URL is already saved in the library."
        case .invalidLocalImageFilename:
            "The local image filename is invalid."
        case .coordinatedAccessFailed(let message):
            "The shared Pinax library could not be accessed: \(message)"
        case .coordinatedAccessDidNotRun:
            "The shared Pinax library coordinator did not run its operation."
        }
    }
}

/// JSON-backed source of truth shared by the app and extensions.
///
/// The actor serializes operations inside one process; `NSFileCoordinator`
/// coordinates the read-modify-write transaction across app processes, and an
/// atomic file replacement prevents partially-written JSON from being visible.
public actor LibraryRepository {
    public nonisolated let storageDirectory: URL
    public nonisolated let libraryFileURL: URL
    public nonisolated let mediaDirectory: URL

    private let clock: @Sendable () -> Date

    public init(
        storageDirectory: URL,
        filename: String = PinaxStorage.libraryFilename,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        guard
            !filename.isEmpty,
            filename == URL(fileURLWithPath: filename).lastPathComponent,
            !filename.contains("/")
        else {
            throw LibraryRepositoryError.invalidStorageFilename
        }

        self.storageDirectory = storageDirectory
        libraryFileURL = storageDirectory.appendingPathComponent(filename, isDirectory: false)
        mediaDirectory = storageDirectory.appendingPathComponent(
            PinaxStorage.mediaDirectoryName,
            isDirectory: true
        )
        self.clock = clock

        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: mediaDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Production storage. Unsigned macOS development builds intentionally fall
    /// back to Application Support; iOS never falls back because doing so would
    /// make the app and share extension silently use different libraries.
    public static func appGroup(
        clock: @escaping @Sendable () -> Date = { Date() }
    ) throws -> LibraryRepository {
        #if os(macOS)
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PINAX_STORAGE_DIRECTORY"],
           override.hasPrefix("/"),
           !override.contains("\0") {
            return try LibraryRepository(
                storageDirectory: URL(fileURLWithPath: override, isDirectory: true),
                clock: clock
            )
        }
        #endif

        // `containerURL` can return a path for an unsigned development build,
        // but attempting to create files there may block indefinitely because
        // the process has no signed App Group entitlement. Only use the shared
        // container when the running code signature actually grants access.
        if hasApplicationGroupEntitlement,
           let container = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: PinaxStorage.appGroupIdentifier
           ) {
            return try LibraryRepository(storageDirectory: container, clock: clock)
        }

        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try LibraryRepository(
            storageDirectory: applicationSupport.appendingPathComponent("Pinax", isDirectory: true),
            clock: clock
        )
        #else
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PinaxStorage.appGroupIdentifier
        ) {
            return try LibraryRepository(storageDirectory: container, clock: clock)
        }
        throw LibraryRepositoryError.appGroupUnavailable(PinaxStorage.appGroupIdentifier)
        #endif
    }

    #if os(macOS)
    private nonisolated static var hasApplicationGroupEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.security.application-groups" as CFString,
                  nil
              ) as? [String] else {
            return false
        }
        return groups.contains(PinaxStorage.appGroupIdentifier)
    }
    #endif

    public func load() throws -> LibrarySnapshot {
        try coordinateReading { coordinatedURL in
            try Self.readSnapshot(at: coordinatedURL, missingDate: self.clock())
        }
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        _ = try coordinateWriting { coordinatedURL in
            var copy = snapshot
            try Self.prepareForPersistence(&copy, at: self.clock())
            try Self.writeSnapshot(copy, to: coordinatedURL)
            return ()
        }
    }

    /// Performs a read-transform-write transaction while holding the same
    /// cross-process file-coordination lock used by captures and edits.
    /// Network work should finish before entering this transaction; the
    /// transform then sees the newest on-disk state and cannot overwrite a
    /// concurrent app or extension capture with a stale full snapshot.
    @discardableResult
    public func withAtomicSnapshotMutation<Value: Sendable>(
        at date: Date,
        _ body: @escaping @Sendable (inout LibrarySnapshot) throws -> Value
    ) throws -> Value {
        try coordinateWriting { coordinatedURL in
            var snapshot = try Self.readSnapshot(at: coordinatedURL, missingDate: date)
            let value = try body(&snapshot)
            try Self.prepareForPersistence(&snapshot, at: date)
            try Self.writeSnapshot(snapshot, to: coordinatedURL)
            return value
        }
    }

    @discardableResult
    public func capture(
        _ payload: CapturePayload,
        imageData: Data? = nil,
        imageFileExtension: String? = nil
    ) throws -> CaptureResult {
        let canonicalURL = try CanonicalURL.canonicalize(payload.url)

        return try mutate { snapshot, now in
            if let projectID = payload.projectID,
               !snapshot.projects.contains(where: { $0.id == projectID }) {
                throw LibraryRepositoryError.projectNotFound(projectID)
            }

            if let index = snapshot.inspirations.firstIndex(where: {
                $0.canonicalURL.absoluteString == canonicalURL.absoluteString
            }) {
                var existing = snapshot.inspirations[index]
                if payload.overwriteMetadataOnDuplicate {
                    Self.replaceProvidedMetadata(on: &existing, from: payload)
                } else {
                    Self.fillMissingMetadata(on: &existing, from: payload)
                }
                if payload.assignProjectOnDuplicate || payload.projectID != nil {
                    existing.projectID = payload.projectID
                }
                if existing.localImageFilename == nil, let imageData, !imageData.isEmpty {
                    existing.localImageFilename = try self.persistImage(
                        imageData,
                        inspirationID: existing.id,
                        preferredExtension: imageFileExtension,
                        remoteURL: payload.imageURL
                    )
                }
                existing.lastCapturedAt = now
                existing.captureCount += 1
                existing.updatedAt = now
                snapshot.inspirations[index] = existing
                return CaptureResult(inspiration: existing, inserted: false)
            }

            let id = Inspiration.ID()
            let localImageFilename: String?
            if let imageData, !imageData.isEmpty {
                localImageFilename = try self.persistImage(
                    imageData,
                    inspirationID: id,
                    preferredExtension: imageFileExtension,
                    remoteURL: payload.imageURL
                )
            } else {
                localImageFilename = nil
            }

            let inspiration = Inspiration(
                id: id,
                source: payload.source,
                url: payload.url,
                canonicalURL: canonicalURL,
                title: Self.cleaned(payload.title),
                text: Self.cleaned(payload.text),
                authorName: Self.cleanedOptional(payload.authorName),
                authorHandle: Self.cleanedHandle(payload.authorHandle),
                imageURL: payload.imageURL,
                localImageFilename: localImageFilename,
                projectID: payload.projectID,
                createdAt: now
            )
            snapshot.inspirations.append(inspiration)
            return CaptureResult(inspiration: inspiration, inserted: true)
        }
    }

    /// Adds remotely-resolved preview fields without treating the repair as a
    /// second user capture or overwriting metadata the user has edited.
    @discardableResult
    public func enrichInspiration(
        id: Inspiration.ID,
        with preview: WebPreview
    ) throws -> Inspiration {
        try mutate { snapshot, now in
            guard let index = snapshot.inspirations.firstIndex(where: { $0.id == id }) else {
                throw LibraryRepositoryError.inspirationNotFound(id)
            }

            var inspiration = snapshot.inspirations[index]
            let original = inspiration
            if Self.isPlaceholderTitle(inspiration.title, for: inspiration.url),
               let title = Self.cleanedOptional(preview.title) {
                inspiration.title = title
            }
            if inspiration.text.isEmpty,
               let text = Self.cleanedOptional(preview.text) {
                inspiration.text = text
            }
            if inspiration.authorName == nil {
                inspiration.authorName = Self.cleanedOptional(preview.authorName)
            }
            if inspiration.authorHandle == nil {
                inspiration.authorHandle = Self.cleanedHandle(preview.authorHandle)
            }
            if inspiration.imageURL == nil {
                inspiration.imageURL = preview.imageURL
            }
            if inspiration.localImageFilename == nil,
               let imageData = preview.imageData,
               !imageData.isEmpty {
                inspiration.localImageFilename = try self.persistImage(
                    imageData,
                    inspirationID: inspiration.id,
                    preferredExtension: preview.imageFileExtension,
                    remoteURL: preview.imageURL
                )
            }
            if inspiration.source == .web, Self.isXURL(inspiration.url) {
                inspiration.source = .x
            }

            if inspiration != original {
                inspiration.updatedAt = now
                snapshot.inspirations[index] = inspiration
            }
            return inspiration
        }
    }

    @discardableResult
    public func createProject(name: String, colorHex: String? = nil) throws -> Project {
        try mutate { snapshot, now in
            let name = Self.cleaned(name)
            guard !name.isEmpty else { throw LibraryRepositoryError.invalidProjectName }
            guard !Self.hasProject(named: name, in: snapshot) else {
                throw LibraryRepositoryError.duplicateProjectName
            }

            let project = Project(
                name: name,
                colorHex: Self.cleanedOptional(colorHex),
                createdAt: now
            )
            snapshot.projects.append(project)
            return project
        }
    }

    @discardableResult
    public func updateProject(
        id: Project.ID,
        name: String,
        colorHex: String? = nil
    ) throws -> Project {
        try mutate { snapshot, now in
            guard let index = snapshot.projects.firstIndex(where: { $0.id == id }) else {
                throw LibraryRepositoryError.projectNotFound(id)
            }
            let name = Self.cleaned(name)
            guard !name.isEmpty else { throw LibraryRepositoryError.invalidProjectName }
            guard !Self.hasProject(named: name, excluding: id, in: snapshot) else {
                throw LibraryRepositoryError.duplicateProjectName
            }

            snapshot.projects[index].name = name
            snapshot.projects[index].colorHex = Self.cleanedOptional(colorHex)
            snapshot.projects[index].updatedAt = now
            return snapshot.projects[index]
        }
    }

    /// Deletes the project and moves its inspirations back to General.
    @discardableResult
    public func deleteProject(id: Project.ID) throws -> Project {
        try mutate { snapshot, now in
            guard let index = snapshot.projects.firstIndex(where: { $0.id == id }) else {
                throw LibraryRepositoryError.projectNotFound(id)
            }
            let removed = snapshot.projects.remove(at: index)
            for inspirationIndex in snapshot.inspirations.indices
            where snapshot.inspirations[inspirationIndex].projectID == id {
                snapshot.inspirations[inspirationIndex].projectID = nil
                snapshot.inspirations[inspirationIndex].updatedAt = now
            }
            return removed
        }
    }

    @discardableResult
    public func updateInspiration(_ inspiration: Inspiration) throws -> Inspiration {
        try mutate { snapshot, now in
            guard let index = snapshot.inspirations.firstIndex(where: { $0.id == inspiration.id }) else {
                throw LibraryRepositoryError.inspirationNotFound(inspiration.id)
            }
            if let projectID = inspiration.projectID,
               !snapshot.projects.contains(where: { $0.id == projectID }) {
                throw LibraryRepositoryError.projectNotFound(projectID)
            }
            if let filename = inspiration.localImageFilename,
               !Self.isSafeRelativeFilename(filename) {
                throw LibraryRepositoryError.invalidLocalImageFilename
            }

            let canonicalURL = try CanonicalURL.canonicalize(inspiration.url)
            if snapshot.inspirations.contains(where: {
                $0.id != inspiration.id && $0.canonicalURL == canonicalURL
            }) {
                throw LibraryRepositoryError.duplicateCanonicalURL(canonicalURL)
            }

            let old = snapshot.inspirations[index]
            var updated = inspiration
            updated.canonicalURL = canonicalURL
            updated.title = Self.cleaned(updated.title)
            updated.text = Self.cleaned(updated.text)
            updated.authorName = Self.cleanedOptional(updated.authorName)
            updated.authorHandle = Self.cleanedHandle(updated.authorHandle)
            updated.createdAt = old.createdAt
            updated.lastCapturedAt = old.lastCapturedAt
            updated.captureCount = old.captureCount
            updated.updatedAt = now
            snapshot.inspirations[index] = updated
            return updated
        }
    }

    @discardableResult
    public func moveInspiration(
        id: Inspiration.ID,
        to projectID: Project.ID?
    ) throws -> Inspiration {
        try mutate { snapshot, now in
            guard let index = snapshot.inspirations.firstIndex(where: { $0.id == id }) else {
                throw LibraryRepositoryError.inspirationNotFound(id)
            }
            if let projectID,
               !snapshot.projects.contains(where: { $0.id == projectID }) {
                throw LibraryRepositoryError.projectNotFound(projectID)
            }
            snapshot.inspirations[index].projectID = projectID
            snapshot.inspirations[index].updatedAt = now
            return snapshot.inspirations[index]
        }
    }

    @discardableResult
    public func deleteInspiration(id: Inspiration.ID) throws -> Inspiration {
        try mutate { snapshot, _ in
            guard let index = snapshot.inspirations.firstIndex(where: { $0.id == id }) else {
                throw LibraryRepositoryError.inspirationNotFound(id)
            }
            return snapshot.inspirations.remove(at: index)
        }
    }

    public func search(query: String = "", scope: LibraryScope = .all) throws -> [Inspiration] {
        let snapshot = try load()
        return Self.filteredInspirations(in: snapshot, query: query, scope: scope)
    }

    public func counts() throws -> ProjectCounts {
        Self.counts(in: try load())
    }

    public nonisolated func localImageURL(for inspiration: Inspiration) -> URL? {
        guard let filename = inspiration.localImageFilename,
              Self.isSafeRelativeFilename(filename) else {
            return nil
        }
        return mediaDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    public nonisolated static func filteredInspirations(
        in snapshot: LibrarySnapshot,
        query: String = "",
        scope: LibraryScope = .all
    ) -> [Inspiration] {
        let needle = searchKey(query)
        return snapshot.inspirations.filter { inspiration in
            let isInScope: Bool
            switch scope {
            case .all:
                isInScope = true
            case .general:
                isInScope = inspiration.projectID == nil
            case .project(let projectID):
                isInScope = inspiration.projectID == projectID
            }
            guard isInScope else { return false }
            guard !needle.isEmpty else { return true }

            let searchable = [
                inspiration.title,
                inspiration.text,
                inspiration.authorName ?? "",
                inspiration.authorHandle ?? "",
                inspiration.url.absoluteString
            ].joined(separator: "\n")
            return searchKey(searchable).contains(needle)
        }
        .sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public nonisolated static func counts(in snapshot: LibrarySnapshot) -> ProjectCounts {
        var byProject = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, 0) })
        var general = 0
        for inspiration in snapshot.inspirations {
            if let projectID = inspiration.projectID {
                byProject[projectID, default: 0] += 1
            } else {
                general += 1
            }
        }
        return ProjectCounts(
            total: snapshot.inspirations.count,
            general: general,
            byProject: byProject
        )
    }

    private func mutate<Value: Sendable>(
        _ body: @escaping @Sendable (inout LibrarySnapshot, Date) throws -> Value
    ) throws -> Value {
        try coordinateWriting { coordinatedURL in
            let now = self.clock()
            var snapshot = try Self.readSnapshot(at: coordinatedURL, missingDate: now)
            let value = try body(&snapshot, now)
            try Self.prepareForPersistence(&snapshot, at: now)
            try Self.writeSnapshot(snapshot, to: coordinatedURL)
            return value
        }
    }

    private nonisolated func persistImage(
        _ data: Data,
        inspirationID: Inspiration.ID,
        preferredExtension: String?,
        remoteURL: URL?
    ) throws -> String {
        let fileExtension = Self.safeImageExtension(
            preferredExtension ?? remoteURL?.pathExtension
        )
        let filename = "\(inspirationID.uuidString.lowercased()).\(fileExtension)"
        let destination = mediaDirectory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: destination, options: [.atomic])
        return filename
    }

    private func coordinateReading<Value: Sendable>(
        _ operation: @escaping @Sendable (URL) throws -> Value
    ) throws -> Value {
        let box = CoordinationResultBox<Value>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(
            readingItemAt: libraryFileURL,
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
        let box = CoordinationResultBox<Value>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(
            writingItemAt: libraryFileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            box.result = Result { try operation(coordinatedURL) }
        }
        return try Self.coordinationResult(from: box, error: coordinationError)
    }

    private nonisolated static func coordinationResult<Value>(
        from box: CoordinationResultBox<Value>,
        error: NSError?
    ) throws -> Value {
        if let error {
            throw LibraryRepositoryError.coordinatedAccessFailed(error.localizedDescription)
        }
        guard let result = box.result else {
            throw LibraryRepositoryError.coordinatedAccessDidNotRun
        }
        return try result.get()
    }

    private nonisolated static func readSnapshot(
        at url: URL,
        missingDate: Date
    ) throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty(at: missingDate)
        }
        let data = try Data(contentsOf: url)
        let snapshot = try makeDecoder().decode(LibrarySnapshot.self, from: data)
        guard snapshot.schemaVersion <= LibrarySnapshot.currentSchemaVersion else {
            throw LibraryRepositoryError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        return snapshot
    }

    private nonisolated static func writeSnapshot(_ snapshot: LibrarySnapshot, to url: URL) throws {
        let data = try makeEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    private nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private nonisolated static func prepareForPersistence(
        _ snapshot: inout LibrarySnapshot,
        at date: Date
    ) throws {
        snapshot.schemaVersion = LibrarySnapshot.currentSchemaVersion

        let projectIDs = Set(snapshot.projects.map(\.id))
        for index in snapshot.inspirations.indices {
            if let projectID = snapshot.inspirations[index].projectID,
               !projectIDs.contains(projectID) {
                snapshot.inspirations[index].projectID = nil
            }
            if let filename = snapshot.inspirations[index].localImageFilename,
               !isSafeRelativeFilename(filename) {
                throw LibraryRepositoryError.invalidLocalImageFilename
            }
            snapshot.inspirations[index].captureCount = max(
                1,
                snapshot.inspirations[index].captureCount
            )
        }

        snapshot.projects.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        snapshot.inspirations.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        snapshot.updatedAt = date
    }

    private nonisolated static func fillMissingMetadata(
        on inspiration: inout Inspiration,
        from payload: CapturePayload
    ) {
        if inspiration.title.isEmpty { inspiration.title = cleaned(payload.title) }
        if inspiration.text.isEmpty { inspiration.text = cleaned(payload.text) }
        if inspiration.authorName == nil {
            inspiration.authorName = cleanedOptional(payload.authorName)
        }
        if inspiration.authorHandle == nil {
            inspiration.authorHandle = cleanedHandle(payload.authorHandle)
        }
        if inspiration.imageURL == nil { inspiration.imageURL = payload.imageURL }
        if inspiration.source == .web && payload.source == .x { inspiration.source = .x }
    }

    private nonisolated static func replaceProvidedMetadata(
        on inspiration: inout Inspiration,
        from payload: CapturePayload
    ) {
        let title = cleaned(payload.title)
        let text = cleaned(payload.text)
        if !title.isEmpty { inspiration.title = title }
        if !text.isEmpty { inspiration.text = text }
        if let authorName = cleanedOptional(payload.authorName) {
            inspiration.authorName = authorName
        }
        if let authorHandle = cleanedHandle(payload.authorHandle) {
            inspiration.authorHandle = authorHandle
        }
        if let imageURL = payload.imageURL { inspiration.imageURL = imageURL }
        if inspiration.source == .web && payload.source == .x { inspiration.source = .x }
    }

    private nonisolated static func hasProject(
        named name: String,
        excluding excludedID: Project.ID? = nil,
        in snapshot: LibrarySnapshot
    ) -> Bool {
        let key = searchKey(name)
        return snapshot.projects.contains {
            $0.id != excludedID && searchKey($0.name) == key
        }
    }

    private nonisolated static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func cleanedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = cleaned(value)
        return cleaned.isEmpty ? nil : cleaned
    }

    private nonisolated static func cleanedHandle(_ value: String?) -> String? {
        guard var value = cleanedOptional(value) else { return nil }
        while value.hasPrefix("@") { value.removeFirst() }
        return value.isEmpty ? nil : value
    }

    private nonisolated static func isPlaceholderTitle(_ title: String, for url: URL) -> Bool {
        let normalized = cleaned(title).lowercased()
        guard !normalized.isEmpty else { return true }
        let host = url.host()?.lowercased() ?? ""
        return normalized == host
            || normalized == host.replacingOccurrences(of: "www.", with: "")
            || normalized == url.absoluteString.lowercased()
            || normalized == "saved link"
            || normalized == "x"
            || normalized == "twitter"
    }

    private nonisolated static func isXURL(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
    }

    private nonisolated static func searchKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private nonisolated static func safeImageExtension(_ proposed: String?) -> String {
        let cleaned = (proposed ?? "")
            .lowercased()
            .filter(\.isLetter)
            .prefix(5)
        return cleaned.isEmpty ? "jpg" : String(cleaned)
    }

    private nonisolated static func isSafeRelativeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && !filename.contains("/")
            && !filename.contains("\\")
    }
}

private final class CoordinationResultBox<Value>: @unchecked Sendable {
    var result: Result<Value, any Error>?
}
