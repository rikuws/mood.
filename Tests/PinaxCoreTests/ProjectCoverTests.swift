import Foundation
import XCTest
@testable import PinaxCore

final class ProjectCoverTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testCoverIsTheFirstImageSavedToEachProject() {
        let dunes = Project(name: "Dunes")
        let lake = Project(name: "Lake")
        let later = item("later", in: dunes, at: 20, image: true)
        let first = item("first", in: dunes, at: 10, image: true)
        let textOnly = item("text", in: dunes, at: 0, image: false)
        let lakeImage = item("lake", in: lake, at: 30, image: true)
        let general = item("general", in: nil, at: 0, image: true)
        let snapshot = LibrarySnapshot(
            projects: [dunes, lake],
            inspirations: [later, textOnly, first, lakeImage, general]
        )

        let covers = snapshot.projectCovers()

        XCTAssertEqual(covers[dunes.id]?.id, first.id)
        XCTAssertEqual(covers[lake.id]?.id, lakeImage.id)
        XCTAssertEqual(covers.count, 2)
    }

    func testChosenBackgroundWinsAndRejectsAndImagelessProjectsAreSkipped() {
        var dunes = Project(name: "Dunes")
        let empty = Project(name: "Empty")
        var rejected = item("rejected", in: dunes, at: 0, image: true)
        rejected.verdict = .reject
        let first = item("first", in: dunes, at: 10, image: true)
        let chosen = item("chosen", in: dunes, at: 20, image: true)
        dunes.backgroundInspirationID = chosen.id
        let snapshot = LibrarySnapshot(
            projects: [dunes, empty],
            inspirations: [rejected, first, chosen, item("words", in: empty, at: 0, image: false)]
        )

        let covers = snapshot.projectCovers()

        XCTAssertEqual(covers[dunes.id]?.id, chosen.id)
        XCTAssertNil(covers[empty.id])
    }

    private func item(_ name: String, in project: Project?, at offset: TimeInterval, image: Bool) -> Inspiration {
        let url = URL(string: "https://example.com/\(name)")!
        return Inspiration(
            source: .web,
            url: url,
            canonicalURL: url,
            title: name,
            imageURL: image ? URL(string: "https://example.com/\(name).jpg") : nil,
            projectID: project?.id,
            createdAt: start.addingTimeInterval(offset)
        )
    }
}
