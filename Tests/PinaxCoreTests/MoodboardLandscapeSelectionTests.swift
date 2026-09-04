import XCTest
@testable import PinaxCore

final class MoodboardLandscapeSelectionTests: XCTestCase {
    func testLibraryScopesUseCanonicalLandscapes() {
        XCTAssertEqual(
            MoodboardLandscapeSelection.landscape(for: .all),
            .citadel
        )
        XCTAssertEqual(
            MoodboardLandscapeSelection.landscape(for: .general),
            .dunes
        )
    }

    func testFixedProjectIdentifiersHaveStableLandscapes() throws {
        let fixtures: [(String, MoodboardLandscape)] = [
            ("00000000-0000-0000-0000-000000000000", .citadel),
            ("00000000-0000-0000-0000-000000000001", .lake),
            ("00000000-0000-0000-0000-000000000002", .dunes),
            ("00000000-0000-0000-0000-000000000003", .valley),
        ]

        for (uuidString, expected) in fixtures {
            let id = try XCTUnwrap(UUID(uuidString: uuidString))
            XCTAssertEqual(
                MoodboardLandscapeSelection.landscape(for: .project(id)),
                expected
            )
        }
    }

    func testProjectSelectionIsRepeatable() throws {
        let id = try XCTUnwrap(UUID(uuidString: "3D146B06-279B-449E-B297-77E1661D6EDB"))
        let scope = LibraryScope.project(id)

        XCTAssertEqual(
            MoodboardLandscapeSelection.landscape(for: scope),
            MoodboardLandscapeSelection.landscape(for: scope)
        )
    }

    func testEveryLandscapeHasAUniqueAssetName() {
        let assetNames = MoodboardLandscape.allCases.map(\.rawValue)

        XCTAssertEqual(Set(assetNames).count, assetNames.count)
        XCTAssertTrue(assetNames.allSatisfy { !$0.isEmpty })
    }
}
