import Foundation

/// How a study agent exchanges data with mood. without touching the library.
/// mood. writes the study into the agent's scratch folder before the run.
/// While the agent works it saves each proposal as its own file in
/// `suggestions/` or `reflections/`, and mood. adds every file as it appears
/// through the same checks as `mood-agent suggest`/`reflect`, so the user can
/// judge the first finds while the agent keeps looking. The agent needs no
/// library access, so sandboxed agents work and only mood. writes the library.
public enum StudyAgentHandoff {
    public static let studyFilename = "study.json"
    /// One batch written at the end, the format `suggest --file` reads. Still
    /// accepted from agents that don't save findings one at a time.
    public static let suggestionsFilename = "suggestions.json"
    public static let reflectionsFilename = "reflections.json"
    /// Folders holding one proposal per file, added as each one appears.
    public static let suggestionsDirectoryName = "suggestions"
    public static let reflectionsDirectoryName = "reflections"
    /// Every study item's image, copied in as `<item id>.<ext>` so an agent
    /// can look at it without network or library access.
    public static let imagesDirectoryName = "images"
    private static let maximumImageBytes = 25 * 1_024 * 1_024

    /// Downloads one remote image. Injected so tests stay offline.
    public typealias ImageFetcher = @Sendable (URL) async -> Data?

    public static let urlSessionFetcher: ImageFetcher = { url in
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return result.0
    }

    public static func proposalsFilename(for task: StudyAgentTask) -> String {
        switch task {
        case .findSources: suggestionsFilename
        case .reflect: reflectionsFilename
        }
    }

    public static func proposalsDirectoryName(for task: StudyAgentTask) -> String {
        switch task {
        case .findSources: suggestionsDirectoryName
        case .reflect: reflectionsDirectoryName
        }
    }

    /// Writes the study as `mood-agent study` prints it, copies each item's
    /// image into `images/` (the stored file when there is one, otherwise a
    /// best-effort download of its `imageURL`), and creates the empty
    /// proposal folders. Returns how many images were staged.
    @discardableResult
    public static func prepare(
        api: PinaxAgentAPI,
        projectID: Project.ID,
        in directory: URL,
        fetchImage: @escaping ImageFetcher = urlSessionFetcher
    ) async throws -> Int {
        let response = try await api.study(project: projectID.uuidString)
        for folder in [suggestionsDirectoryName, reflectionsDirectoryName] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let staged = await stageImages(for: response.study.items, in: directory, fetchImage: fetchImage)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(response).write(
            to: directory.appendingPathComponent(studyFilename, isDirectory: false),
            options: .atomic
        )
        return staged
    }

    private static func stageImages(
        for items: [PinaxAgentInspiration],
        in directory: URL,
        fetchImage: @escaping ImageFetcher
    ) async -> Int {
        let imagesDirectory = directory.appendingPathComponent(imagesDirectoryName, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)) != nil else {
            return 0
        }
        return await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for item in items {
                group.addTask {
                    let data: Data?
                    var fileExtension: String?
                    if let path = item.localImagePath {
                        data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                        fileExtension = URL(fileURLWithPath: path).pathExtension
                    } else if let remote = item.imageURL {
                        data = await fetchImage(remote)
                        fileExtension = remote.pathExtension
                    } else {
                        data = nil
                    }
                    guard let data, !data.isEmpty, data.count <= maximumImageBytes else { return false }
                    let name = item.id.uuidString.lowercased()
                        + "." + imageExtension(for: data, fallback: fileExtension)
                    return (try? data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)) != nil
                }
            }
            var count = 0
            for await staged in group where staged { count += 1 }
            return count
        }
    }

    /// Names files by their bytes, so an agent's image viewer accepts them.
    private static func imageExtension(for data: Data, fallback: String?) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "gif" }
        if bytes.count >= 12, bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], bytes[8..<12] == [0x57, 0x45, 0x42, 0x50] {
            return "webp"
        }
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) { return "heic" }
        let fallback = fallback?.lowercased() ?? ""
        return fallback.isEmpty || fallback.count > 5 ? "img" : fallback
    }

    /// Adds everything the agent proposed for `task` in one pass, as after
    /// the agent exits. A running agent's files are added as they appear with
    /// `StudyAgentProposalCollector` instead.
    public static func collect(
        api: PinaxAgentAPI,
        projectID: Project.ID,
        task: StudyAgentTask,
        from directory: URL
    ) async throws -> StudyAgentHandoffResult {
        let collector = StudyAgentProposalCollector(
            api: api,
            projectID: projectID,
            task: task,
            directory: directory
        )
        return try await collector.collect(final: true)
    }
}

/// Adds a running agent's proposals as it saves them. Each call reads the
/// files that appeared since the last one. A file that isn't complete JSON
/// yet is left for the next call, because the agent may still be writing it;
/// the `final` call, made once the agent has exited, reports it instead.
public actor StudyAgentProposalCollector {
    /// The most one run may propose, the same as one `suggest`/`reflect`
    /// batch, so a runaway agent can't flood the study.
    public static let maximumProposalsPerRun = 50

    private let api: PinaxAgentAPI
    private let projectID: Project.ID
    private let task: StudyAgentTask
    private let directory: URL
    /// Files in the proposal folder already added or reported, by name.
    private var handledFiles: Set<String> = []
    /// Entries of the end-of-run batch file already added, which an agent
    /// may rewrite as it grows.
    private var handledBatchEntries: Set<String> = []
    private var submittedCount = 0
    /// Everything added from this run so far.
    public private(set) var total = StudyAgentHandoffResult(foundProposals: false)

    public init(api: PinaxAgentAPI, projectID: Project.ID, task: StudyAgentTask, directory: URL) {
        self.api = api
        self.projectID = projectID
        self.task = task
        self.directory = directory
    }

    /// Adds what appeared since the last call and returns what this call
    /// added. Throws only when the library can't take the proposals, such as
    /// when the study was deleted; the files involved are retried next call.
    @discardableResult
    public func collect(final: Bool = false) async throws -> StudyAgentHandoffResult {
        var pass = StudyAgentHandoffResult(foundProposals: false)
        let folder = StudyAgentHandoff.proposalsDirectoryName(for: task)

        for file in proposalFiles(in: folder) where !handledFiles.contains(file.lastPathComponent) {
            let name = "\(folder)/\(file.lastPathComponent)"
            pass.foundProposals = true
            switch read(file) {
            case .incomplete:
                guard final else { continue }
                handledFiles.insert(file.lastPathComponent)
                pass.unusableFiles.append(StudyAgentUnusableFile(name: name, reason: "It isn't complete JSON."))
            case .unusable(let reason):
                handledFiles.insert(file.lastPathComponent)
                pass.unusableFiles.append(StudyAgentUnusableFile(name: name, reason: reason))
            case .complete(let data):
                handledFiles.insert(file.lastPathComponent)
                do {
                    pass.add(try await submit(data, from: name, onlyNew: false, reportsShapeMismatch: true))
                } catch {
                    // What this pass already added is in the library; count it.
                    handledFiles.remove(file.lastPathComponent)
                    total.add(pass)
                    throw error
                }
            }
        }

        let batchName = StudyAgentHandoff.proposalsFilename(for: task)
        let batch = directory.appendingPathComponent(batchName, isDirectory: false)
        if FileManager.default.fileExists(atPath: batch.path) {
            pass.foundProposals = true
            switch read(batch) {
            case .incomplete:
                if final {
                    pass.unusableFiles.append(StudyAgentUnusableFile(name: batchName, reason: "It isn't complete JSON."))
                }
            case .unusable(let reason):
                if final {
                    pass.unusableFiles.append(StudyAgentUnusableFile(name: batchName, reason: reason))
                }
            case .complete(let data):
                // The batch may still grow, so only its new entries are added
                // and a mismatched shape is reported once the agent is done.
                do {
                    pass.add(try await submit(data, from: batchName, onlyNew: true, reportsShapeMismatch: final))
                } catch {
                    total.add(pass)
                    throw error
                }
            }
        }

        total.add(pass)
        return pass
    }

    private enum FileContents {
        /// Not parseable yet; the agent may be writing it.
        case incomplete
        case unusable(String)
        case complete(Data)
    }

    private func proposalFiles(in folder: String) -> [URL] {
        let url = directory.appendingPathComponent(folder, isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending
            }
    }

    private func read(_ file: URL) -> FileContents {
        let data: Data
        do {
            data = try PinaxAgentAPI.readBoundedJSONFile(
                filePath: file.path,
                currentDirectory: directory,
                invalid: PinaxAgentAPIError.invalidStudyInput
            )
        } catch {
            return .unusable(error.localizedDescription)
        }
        guard (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
            return .incomplete
        }
        return .complete(data)
    }

    /// Adds one file's proposals. A file can hold a single proposal, a list,
    /// or the `{"suggestions": [...]}`/`{"reflections": [...]}` batch shape.
    /// With `onlyNew`, entries settled by an earlier pass are left out, and
    /// the entries this call settles are remembered, unless the library
    /// couldn't take them.
    private func submit(
        _ data: Data,
        from name: String,
        onlyNew: Bool,
        reportsShapeMismatch: Bool
    ) async throws -> StudyAgentHandoffResult {
        var piece = StudyAgentHandoffResult(foundProposals: true)
        let mismatch = StudyAgentUnusableFile(name: name, reason: Self.shapeMismatch)
        var settledKeys: [String] = []
        do {
            switch task {
            case .findSources:
                guard var drafts = Self.suggestionDrafts(from: data) else {
                    if reportsShapeMismatch { piece.unusableFiles.append(mismatch) }
                    return piece
                }
                if onlyNew {
                    drafts = drafts.filter { !handledBatchEntries.contains(Self.batchKey($0)) }
                    settledKeys = drafts.map { Self.batchKey($0) }
                }
                let accepted = takeRoom(for: drafts, overflow: &piece.overLimit)
                if !accepted.isEmpty {
                    let response = try await api.suggest(project: projectID.uuidString, drafts: accepted)
                    submittedCount += accepted.count
                    piece.addedSuggestions = response.added.count
                    piece.skipped = response.skipped
                }
            case .reflect:
                guard var drafts = Self.reflectionDrafts(from: data) else {
                    if reportsShapeMismatch { piece.unusableFiles.append(mismatch) }
                    return piece
                }
                if onlyNew {
                    drafts = drafts.filter { !handledBatchEntries.contains(Self.batchKey($0)) }
                    settledKeys = drafts.map { Self.batchKey($0) }
                }
                let accepted = takeRoom(for: drafts, overflow: &piece.overLimit)
                if !accepted.isEmpty {
                    let response = try await api.reflect(project: projectID.uuidString, drafts: accepted)
                    submittedCount += accepted.count
                    piece.addedReflections = response.added.count
                }
            }
        } catch PinaxAgentAPIError.invalidStudyInput(let message) {
            // A pattern that cites something outside the study refuses its
            // whole file; the agent's other files still count.
            piece.unusableFiles.append(StudyAgentUnusableFile(name: name, reason: message))
        }
        handledBatchEntries.formUnion(settledKeys)
        return piece
    }

    private func takeRoom<Draft>(for drafts: [Draft], overflow: inout Int) -> [Draft] {
        let room = max(0, Self.maximumProposalsPerRun - submittedCount)
        overflow += max(0, drafts.count - room)
        return Array(drafts.prefix(room))
    }

    private static func batchKey(_ draft: StudySuggestionDraft) -> String {
        draft.url.absoluteString
    }

    private static func batchKey(_ draft: StudyReflectionDraft) -> String {
        draft.statement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let shapeMismatch =
        "It doesn't hold a proposal in the `suggest --file`/`reflect --file` entry format."

    static func suggestionDrafts(from data: Data) -> [StudySuggestionDraft]? {
        let decoder = JSONDecoder()
        if let batch = try? decoder.decode(PinaxAgentSuggestInput.self, from: data) {
            return batch.suggestions
        }
        if let list = try? decoder.decode([StudySuggestionDraft].self, from: data) {
            return list
        }
        return (try? decoder.decode(StudySuggestionDraft.self, from: data)).map { [$0] }
    }

    static func reflectionDrafts(from data: Data) -> [StudyReflectionDraft]? {
        let decoder = JSONDecoder()
        if let batch = try? decoder.decode(PinaxAgentReflectInput.self, from: data) {
            return batch.reflections
        }
        if let list = try? decoder.decode([StudyReflectionDraft].self, from: data) {
            return list
        }
        return (try? decoder.decode(StudyReflectionDraft.self, from: data)).map { [$0] }
    }
}

/// A file the agent wrote that mood. couldn't add, and why.
public struct StudyAgentUnusableFile: Equatable, Sendable {
    public var name: String
    public var reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

public struct StudyAgentHandoffResult: Equatable, Sendable {
    public var foundProposals: Bool
    public var addedSuggestions: Int
    public var addedReflections: Int
    public var skipped: [StudySuggestionSkip]
    public var unusableFiles: [StudyAgentUnusableFile]
    /// Proposals left out because the run reached
    /// `StudyAgentProposalCollector.maximumProposalsPerRun`.
    public var overLimit: Int

    public init(
        foundProposals: Bool,
        addedSuggestions: Int = 0,
        addedReflections: Int = 0,
        skipped: [StudySuggestionSkip] = [],
        unusableFiles: [StudyAgentUnusableFile] = [],
        overLimit: Int = 0
    ) {
        self.foundProposals = foundProposals
        self.addedSuggestions = addedSuggestions
        self.addedReflections = addedReflections
        self.skipped = skipped
        self.unusableFiles = unusableFiles
        self.overLimit = overLimit
    }

    public var addedCount: Int {
        addedSuggestions + addedReflections
    }

    public mutating func add(_ other: StudyAgentHandoffResult) {
        foundProposals = foundProposals || other.foundProposals
        addedSuggestions += other.addedSuggestions
        addedReflections += other.addedReflections
        skipped += other.skipped
        unusableFiles += other.unusableFiles
        overLimit += other.overLimit
    }

    /// One plain sentence for the study panel.
    public var summary: String {
        guard foundProposals else { return "It didn't propose anything." }
        var parts: [String] = []
        if addedSuggestions > 0 {
            parts.append("Added \(addedSuggestions) source\(addedSuggestions == 1 ? "" : "s") for you to judge.")
        }
        if addedReflections > 0 {
            parts.append("Added \(addedReflections) pattern\(addedReflections == 1 ? "" : "s") for you to check.")
        }
        if !skipped.isEmpty {
            let reasons = Set(skipped.map { $0.reason.rawValue.replacingOccurrences(of: "_", with: " ") })
                .sorted()
                .joined(separator: ", ")
            parts.append("Skipped \(skipped.count) (\(reasons)).")
        }
        if overLimit > 0 {
            parts.append("Left out \(overLimit) past the limit of \(StudyAgentProposalCollector.maximumProposalsPerRun) a run.")
        }
        if let file = unusableFiles.first {
            parts.append(
                unusableFiles.count == 1
                    ? "Couldn't use \(file.name): \(file.reason)"
                    : "Couldn't use \(unusableFiles.count) files it wrote (\(unusableFiles.map(\.name).joined(separator: ", ")))."
            )
        }
        return parts.isEmpty ? "Nothing new was added." : parts.joined(separator: " ")
    }
}
