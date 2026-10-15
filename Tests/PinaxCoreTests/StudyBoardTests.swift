import Foundation
import XCTest
@testable import PinaxCore

final class StudyBoardTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testBoardKeepsArrivalOrderAcrossFindingsAndPatterns() {
        let first = suggestion("Pod bay", at: 0)
        let pattern = reflection("You keep empty floors.", at: 10)
        let later = suggestion("Moon base", at: 20, status: .kept)
        let study = ProjectStudy(
            subject: "2001",
            startedAt: start,
            suggestions: [later, first],
            reflections: [pattern]
        )

        let board = StudyBoard(study: study)

        XCTAssertEqual(board.entries.map(\.id), [first.id, pattern.id, later.id])
        XCTAssertEqual(board.entry(id: pattern.id), .pattern(pattern))
        XCTAssertFalse(board.isEmpty)
    }

    func testFiltersGroupSourcesAndPatternsByVerdict() {
        let pending = suggestion("Pending", at: 0)
        let kept = suggestion("Kept", at: 1, status: .kept)
        let rejected = suggestion("Rejected", at: 2, status: .rejected)
        let open = reflection("Open", at: 3)
        let confirmed = reflection("Confirmed", at: 4, status: .confirmed)
        let corrected = reflection("Corrected", at: 5, status: .corrected)
        let dismissed = reflection("Dismissed", at: 6, status: .dismissed)
        let board = StudyBoard(
            study: ProjectStudy(
                subject: "2001",
                startedAt: start,
                suggestions: [pending, kept, rejected],
                reflections: [open, confirmed, corrected, dismissed]
            )
        )

        XCTAssertEqual(board.entries(for: .all).count, 7)
        XCTAssertEqual(board.entries(for: .toJudge).map(\.id), [pending.id, open.id])
        XCTAssertEqual(board.entries(for: .kept).map(\.id), [kept.id, confirmed.id, corrected.id])
        XCTAssertEqual(board.entries(for: .rejected).map(\.id), [rejected.id, dismissed.id])
        XCTAssertEqual(
            StudyBoardFilter.allCases.map { board.count(for: $0) },
            [7, 2, 3, 2]
        )
    }

    func testSearchMatchesCreditReasoningAndTheUsersOwnWords() {
        var rejected = suggestion("Lunar module", at: 0, status: .rejected)
        rejected.creator = "Grumman"
        rejected.reason = "Too busy, too much chrome"
        let other = suggestion("Pod bay", at: 1)
        var corrected = reflection("You keep empty rooms.", at: 2, status: .corrected)
        corrected.correction = "Empty rooms, lit from the floor"
        let board = StudyBoard(
            study: ProjectStudy(
                subject: "2001",
                startedAt: start,
                suggestions: [rejected, other],
                reflections: [corrected]
            )
        )

        XCTAssertEqual(board.entries(for: .all, matching: "grumman").map(\.id), [rejected.id])
        XCTAssertEqual(board.entries(for: .all, matching: "CHROME").map(\.id), [rejected.id])
        XCTAssertEqual(board.entries(for: .all, matching: " lit from ").map(\.id), [corrected.id])
        XCTAssertEqual(board.entries(for: .all, matching: "example.org").count, 2)
        XCTAssertEqual(board.entries(for: .toJudge, matching: "grumman"), [])
        XCTAssertEqual(board.entries(for: .all, matching: "   ").count, 3)
    }

    func testArrivalsMarkOnlyWhatAppearsAfterTheBoardOpens() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var arrivals = StudyBoardArrivals()

        let opened = arrivals.note([first])
        XCTAssertEqual(opened, [])
        XCTAssertTrue(arrivals.fresh.isEmpty)

        let found = arrivals.note([first, second])
        XCTAssertEqual(found, [second])
        XCTAssertEqual(arrivals.fresh, [second])

        // Something that leaves the board and comes back is not an arrival.
        let shrunk = arrivals.note([first])
        let grown = arrivals.note([first, second, third])
        XCTAssertEqual(shrunk, [])
        XCTAssertEqual(grown, [third])
        XCTAssertEqual(arrivals.fresh, [second, third])

        arrivals.settle([second])
        XCTAssertEqual(arrivals.fresh, [third])

        arrivals.reset()
        XCTAssertTrue(arrivals.fresh.isEmpty)
        let reopened = arrivals.note([first, second, third])
        XCTAssertEqual(reopened, [])
    }

    func testFindingPreviewsAsTheCardItWouldBecome() {
        var finding = suggestion("Pod bay", at: 0)
        finding.creator = "Geoffrey Unsworth"
        finding.imageURL = URL(string: "https://example.org/pod-bay.jpg")
        let projectID = UUID()

        let preview = finding.previewInspiration(projectID: projectID)

        XCTAssertEqual(preview.id, finding.id)
        XCTAssertEqual(preview.source, .web)
        XCTAssertEqual(preview.url, finding.url)
        XCTAssertEqual(preview.title, "Pod bay")
        XCTAssertEqual(preview.authorName, "Geoffrey Unsworth")
        XCTAssertEqual(preview.imageURL, finding.imageURL)
        XCTAssertEqual(preview.projectID, projectID)
        XCTAssertEqual(preview.createdAt, finding.suggestedAt)
    }

    private func suggestion(
        _ title: String,
        at offset: TimeInterval,
        status: StudySuggestion.Status = .pending
    ) -> StudySuggestion {
        let url = URL(string: "https://example.org/\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")!
        return StudySuggestion(
            url: url,
            canonicalURL: url,
            title: title,
            creator: "Someone",
            rationale: "Like your seed.",
            suggestedAt: start.addingTimeInterval(offset),
            status: status
        )
    }

    private func reflection(
        _ statement: String,
        at offset: TimeInterval,
        status: StudyReflection.Status = .pending
    ) -> StudyReflection {
        StudyReflection(
            statement: statement,
            inspirationIDs: [UUID()],
            proposedAt: start.addingTimeInterval(offset),
            status: status
        )
    }
}
