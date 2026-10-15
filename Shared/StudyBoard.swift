import Foundation

/// Everything a study turned up, in one place: each source an agent found and
/// each pattern it reflected back, with the user's verdict on it.
///
/// The board is ordered by when things arrived, so a running agent's finds
/// land at the end and nothing already on screen moves when a new one pops in.
/// Judging changes how an entry looks, not where it sits.
public struct StudyBoard: Equatable, Sendable {
    public let entries: [StudyBoardEntry]

    public init(study: ProjectStudy) {
        let findings = study.suggestions.map(StudyBoardEntry.finding)
        let patterns = study.reflections.map(StudyBoardEntry.pattern)
        entries = (findings + patterns).sorted {
            ($0.arrivedAt, $0.id.uuidString) < ($1.arrivedAt, $1.id.uuidString)
        }
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    public func entry(id: StudyBoardEntry.ID) -> StudyBoardEntry? {
        entries.first { $0.id == id }
    }

    /// The entries a filter shows, narrowed to those mentioning `query` in
    /// their title, credit, source, reasoning, or the user's own words.
    public func entries(for filter: StudyBoardFilter, matching query: String = "") -> [StudyBoardEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            filter.includes(entry.verdict) && (query.isEmpty || entry.matches(query))
        }
    }

    public func count(for filter: StudyBoardFilter) -> Int {
        entries.reduce(0) { $0 + (filter.includes($1.verdict) ? 1 : 0) }
    }
}

/// One thing on the study board.
public enum StudyBoardEntry: Identifiable, Hashable, Sendable {
    case finding(StudySuggestion)
    case pattern(StudyReflection)

    public var id: UUID {
        switch self {
        case .finding(let suggestion): suggestion.id
        case .pattern(let reflection): reflection.id
        }
    }

    public var arrivedAt: Date {
        switch self {
        case .finding(let suggestion): suggestion.suggestedAt
        case .pattern(let reflection): reflection.proposedAt
        }
    }

    /// Patterns follow sources: a confirmed or corrected pattern counts as
    /// kept, a dismissed one as rejected.
    public var verdict: StudyBoardVerdict {
        switch self {
        case .finding(let suggestion):
            switch suggestion.status {
            case .pending: .pending
            case .kept: .kept
            case .rejected: .rejected
            }
        case .pattern(let reflection):
            switch reflection.status {
            case .pending: .pending
            case .confirmed, .corrected: .kept
            case .dismissed: .rejected
            }
        }
    }

    func matches(_ query: String) -> Bool {
        let fields: [String?] = switch self {
        case .finding(let suggestion):
            [
                suggestion.title,
                suggestion.creator,
                suggestion.sourceName,
                suggestion.rationale,
                suggestion.reason,
                suggestion.url.host(),
            ]
        case .pattern(let reflection):
            [reflection.statement, reflection.correction]
        }
        return fields.contains { field in
            field?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

public enum StudyBoardVerdict: Hashable, Sendable {
    case pending
    case kept
    case rejected
}

public enum StudyBoardFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case toJudge
    case kept
    case rejected

    public var title: String {
        switch self {
        case .all: "All"
        case .toJudge: "To judge"
        case .kept: "Kept"
        case .rejected: "Rejected"
        }
    }

    public func includes(_ verdict: StudyBoardVerdict) -> Bool {
        switch self {
        case .all: true
        case .toJudge: verdict == .pending
        case .kept: verdict == .kept
        case .rejected: verdict == .rejected
        }
    }
}

public extension StudySuggestion {
    /// The moodboard item this source would become if kept, so a finding on
    /// the study board looks like the card it could turn into: its image,
    /// title, and creator in the caption.
    func previewInspiration(projectID: Project.ID?) -> Inspiration {
        Inspiration(
            id: id,
            source: .web,
            url: url,
            canonicalURL: canonicalURL,
            title: title,
            authorName: creator,
            imageURL: imageURL,
            projectID: projectID,
            createdAt: suggestedAt
        )
    }
}

/// Which board entries just arrived while the board was open, so they can
/// develop into place instead of simply appearing. Whatever was already on
/// the board when it opened stays still.
public struct StudyBoardArrivals: Equatable, Sendable {
    private var known: Set<StudyBoardEntry.ID>?
    /// Entries that arrived and haven't settled yet.
    public private(set) var fresh: Set<StudyBoardEntry.ID> = []

    public init() {}

    /// Notes every entry now on the board and returns the ones that weren't
    /// there before. The first call only learns what's already there.
    @discardableResult
    public mutating func note(_ ids: [StudyBoardEntry.ID]) -> Set<StudyBoardEntry.ID> {
        let current = Set(ids)
        guard let known else {
            self.known = current
            return []
        }
        let arrived = current.subtracting(known)
        self.known = known.union(current)
        fresh.formUnion(arrived)
        return arrived
    }

    /// Lets entries that have finished arriving appear normally again, such
    /// as when a filter change brings them back.
    public mutating func settle(_ ids: Set<StudyBoardEntry.ID>) {
        fresh.subtract(ids)
    }

    /// Forgets the board, for when another study opens.
    public mutating func reset() {
        known = nil
        fresh = []
    }
}
