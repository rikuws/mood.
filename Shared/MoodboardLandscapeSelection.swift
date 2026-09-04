import Foundation

/// Built-in landscapes that give every moodboard space a stable atmosphere.
///
/// Raw values intentionally match the Mac asset-catalog names. Keep the order
/// stable: changing it would remap existing projects to different landscapes.
public enum MoodboardLandscape: String, CaseIterable, Sendable {
    case citadel = "MoodLandscapeCitadel"
    case lake = "MoodLandscapeLake"
    case dunes = "MoodLandscapeDunes"
    case valley = "MoodLandscapeValley"
}

public enum MoodboardLandscapeSelection {
    public static func landscape(for scope: LibraryScope) -> MoodboardLandscape {
        switch scope {
        case .all:
            return .citadel
        case .general:
            return .dunes
        case .project(let projectID):
            return projectLandscape(for: projectID)
        }
    }

    private static func projectLandscape(for id: Project.ID) -> MoodboardLandscape {
        let roster = MoodboardLandscape.allCases
        let index = id.uuidString.lowercased().utf8.reduce(0) { partial, byte in
            ((partial * 31) + Int(byte)) % roster.count
        }
        return roster[index]
    }
}
