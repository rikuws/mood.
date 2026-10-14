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
            return try LibraryRepository.appGroup()
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
}

public enum PinaxAgentLibraryLocationError: Error, Equatable, Sendable, LocalizedError {
    case invalidPath(String)
    case missingDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            "\(PinaxAgentLibraryLocation.environmentKey) must be an absolute path, not “\(path)”."
        case .missingDirectory(let path):
            "\(PinaxAgentLibraryLocation.environmentKey) points at “\(path)”, which isn't a folder mood-agent can see."
        }
    }
}
