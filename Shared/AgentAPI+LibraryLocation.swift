import Foundation

/// Where `mood-agent` finds the library. mood. sets `MOOD_LIBRARY_DIRECTORY`
/// when it starts a study agent, so the helper opens the same library as the
/// app even inside an agent sandbox where the App Group lookup fails and
/// would otherwise fall back to an empty library.
public enum PinaxAgentLibraryLocation {
    public static let environmentKey = "MOOD_LIBRARY_DIRECTORY"

    public static func repository(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LibraryRepository {
        guard let path = environment[environmentKey], !path.isEmpty else {
            let repository = try LibraryRepository.appGroup()
            try refuseFallback(from: repository.storageDirectory, whileSharedLibraryIsAt: sharedLibraryDirectory)
            return repository
        }
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw PinaxAgentLibraryLocationError.invalidPath(path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PinaxAgentLibraryLocationError.missingDirectory(path)
        }
        return try LibraryRepository(storageDirectory: URL(fileURLWithPath: path, isDirectory: true))
    }

    /// The App Group folder the signed apps share, found by its path rather
    /// than by the App Group lookup, which fails inside agent sandboxes.
    static var sharedLibraryDirectory: URL? {
        #if os(macOS)
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(PinaxStorage.appGroupIdentifier, isDirectory: true)
        #else
        nil
        #endif
    }

    /// When the App Group lookup fails, `LibraryRepository.appGroup()` falls
    /// back to a folder with no library in it, and `mood-agent` would answer
    /// as if the user had saved nothing. If the user's library exists in the
    /// shared folder, report that it is out of reach instead.
    static func refuseFallback(from storageDirectory: URL, whileSharedLibraryIsAt sharedDirectory: URL?) throws {
        guard let sharedDirectory,
              storageDirectory.standardizedFileURL.path != sharedDirectory.standardizedFileURL.path else {
            return
        }
        let fileManager = FileManager.default
        let sharedLibrary = sharedDirectory.appendingPathComponent(PinaxStorage.libraryFilename, isDirectory: false)
        let fallbackLibrary = storageDirectory.appendingPathComponent(PinaxStorage.libraryFilename, isDirectory: false)
        if fileManager.fileExists(atPath: sharedLibrary.path), !fileManager.fileExists(atPath: fallbackLibrary.path) {
            throw PinaxAgentLibraryLocationError.sharedLibraryUnreachable(sharedDirectory.path)
        }
    }
}

public enum PinaxAgentLibraryLocationError: Error, Equatable, Sendable, LocalizedError {
    case invalidPath(String)
    case missingDirectory(String)
    case sharedLibraryUnreachable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            "\(PinaxAgentLibraryLocation.environmentKey) must be an absolute path, not “\(path)”."
        case .missingDirectory(let path):
            "\(PinaxAgentLibraryLocation.environmentKey) points at “\(path)”, which isn't a folder mood-agent can see."
        case .sharedLibraryUnreachable(let path):
            "mood-agent can't open the mood. library in “\(path)” from here, so it would only see an empty "
                + "library. This usually means it runs inside an agent sandbox: run it outside the sandbox, or "
                + "start the agent from the study panel in mood., which hands the study over without library access."
        }
    }
}
