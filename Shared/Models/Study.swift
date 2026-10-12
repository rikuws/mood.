import Foundation

/// A guided visual study: a project with a subject the user wants to explore
/// ("2001: A Space Odyssey") and a record of how their taste responded to it.
///
/// The user seeds the study with work they already love. An agent may then
/// propose real, attributed sources and reflect patterns back, but only the
/// user keeps, rejects, confirms, or corrects. Every decision and the user's
/// reason for it stays in the study, so rejects remain taste data instead of
/// disappearing.
///
/// Stored as an optional key on `Project`; libraries without it keep their
/// schema version and decode unchanged.
public struct ProjectStudy: Codable, Hashable, Sendable {
    /// What the study is about, in the user's own words.
    public var subject: String
    /// Optional framing from the user: what they are after, or what to avoid.
    public var brief: String
    public var startedAt: Date
    public var suggestions: [StudySuggestion]
    public var reflections: [StudyReflection]

    public init(
        subject: String,
        brief: String = "",
        startedAt: Date = Date(),
        suggestions: [StudySuggestion] = [],
        reflections: [StudyReflection] = []
    ) {
        self.subject = subject
        self.brief = brief
        self.startedAt = startedAt
        self.suggestions = suggestions
        self.reflections = reflections
    }

    private enum CodingKeys: String, CodingKey {
        case subject
        case brief
        case startedAt
        case suggestions
        case reflections
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subject = try container.decode(String.self, forKey: .subject)
        brief = try container.decodeIfPresent(String.self, forKey: .brief) ?? ""
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        suggestions = try container.decodeIfPresent([StudySuggestion].self, forKey: .suggestions) ?? []
        reflections = try container.decodeIfPresent([StudyReflection].self, forKey: .reflections) ?? []
    }
}

/// A real, attributed source proposed for a study. It is not part of the
/// moodboard until the user keeps it; a rejected suggestion is retained with
/// the user's reason so it can inform later reflection and never be proposed
/// again.
public struct StudySuggestion: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = UUID

    public enum Status: String, Codable, Hashable, Sendable {
        case pending
        case kept
        case rejected
    }

    public var id: ID
    /// The page where the work is published and credited.
    public var url: URL
    public var canonicalURL: URL
    public var title: String
    /// The person or studio who made the work. Required: an unattributed image
    /// cannot be verified as real work.
    public var creator: String
    /// Where the work was found, such as an archive, publisher, or Are.na.
    public var sourceName: String?
    public var imageURL: URL?
    /// Why the agent proposed it, tied to the user's own seeds and notes.
    /// This is a hypothesis for the user to judge, not a conclusion.
    public var rationale: String
    /// Study items this suggestion builds on.
    public var basedOnInspirationIDs: [Inspiration.ID]
    public var suggestedAt: Date
    public var status: Status
    /// The user's own reason for keeping or rejecting it.
    public var reason: String?
    public var decidedAt: Date?
    /// The library item created or linked when the user kept the suggestion.
    public var savedInspirationID: Inspiration.ID?

    public init(
        id: ID = ID(),
        url: URL,
        canonicalURL: URL,
        title: String,
        creator: String,
        sourceName: String? = nil,
        imageURL: URL? = nil,
        rationale: String,
        basedOnInspirationIDs: [Inspiration.ID] = [],
        suggestedAt: Date = Date(),
        status: Status = .pending,
        reason: String? = nil,
        decidedAt: Date? = nil,
        savedInspirationID: Inspiration.ID? = nil
    ) {
        self.id = id
        self.url = url
        self.canonicalURL = canonicalURL
        self.title = title
        self.creator = creator
        self.sourceName = sourceName
        self.imageURL = imageURL
        self.rationale = rationale
        self.basedOnInspirationIDs = basedOnInspirationIDs
        self.suggestedAt = suggestedAt
        self.status = status
        self.reason = reason
        self.decidedAt = decidedAt
        self.savedInspirationID = savedInspirationID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case canonicalURL
        case title
        case creator
        case sourceName
        case imageURL
        case rationale
        case basedOnInspirationIDs
        case suggestedAt
        case status
        case reason
        case decidedAt
        case savedInspirationID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        canonicalURL = try container.decodeIfPresent(URL.self, forKey: .canonicalURL) ?? url
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        creator = try container.decodeIfPresent(String.self, forKey: .creator) ?? ""
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        basedOnInspirationIDs = try container.decodeIfPresent(
            [Inspiration.ID].self,
            forKey: .basedOnInspirationIDs
        ) ?? []
        suggestedAt = try container.decode(Date.self, forKey: .suggestedAt)
        // An unknown future status reads as pending so a newer client's
        // decision is never mistaken for a keep or a reject.
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status)
        status = rawStatus.flatMap(Status.init(rawValue:)) ?? .pending
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        decidedAt = try container.decodeIfPresent(Date.self, forKey: .decidedAt)
        savedInspirationID = try container.decodeIfPresent(Inspiration.ID.self, forKey: .savedInspirationID)
    }
}

/// A pattern an agent noticed across the user's choices, held until the user
/// confirms, corrects, or dismisses it. Each reflection cites the kept items
/// and rejected suggestions it was drawn from.
public struct StudyReflection: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = UUID

    public enum Status: String, Codable, Hashable, Sendable {
        case pending
        case confirmed
        case corrected
        case dismissed
    }

    public var id: ID
    public var statement: String
    /// Study items (seeds and keeps) the pattern was observed in.
    public var inspirationIDs: [Inspiration.ID]
    /// Rejected suggestions that support the pattern by contrast.
    public var rejectedSuggestionIDs: [StudySuggestion.ID]
    public var proposedAt: Date
    public var status: Status
    /// The user's own wording when they correct the pattern.
    public var correction: String?
    public var respondedAt: Date?

    public init(
        id: ID = ID(),
        statement: String,
        inspirationIDs: [Inspiration.ID] = [],
        rejectedSuggestionIDs: [StudySuggestion.ID] = [],
        proposedAt: Date = Date(),
        status: Status = .pending,
        correction: String? = nil,
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.statement = statement
        self.inspirationIDs = inspirationIDs
        self.rejectedSuggestionIDs = rejectedSuggestionIDs
        self.proposedAt = proposedAt
        self.status = status
        self.correction = correction
        self.respondedAt = respondedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case statement
        case inspirationIDs
        case rejectedSuggestionIDs
        case proposedAt
        case status
        case correction
        case respondedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        statement = try container.decodeIfPresent(String.self, forKey: .statement) ?? ""
        inspirationIDs = try container.decodeIfPresent([Inspiration.ID].self, forKey: .inspirationIDs) ?? []
        rejectedSuggestionIDs = try container.decodeIfPresent(
            [StudySuggestion.ID].self,
            forKey: .rejectedSuggestionIDs
        ) ?? []
        proposedAt = try container.decode(Date.self, forKey: .proposedAt)
        let rawStatus = try container.decodeIfPresent(String.self, forKey: .status)
        status = rawStatus.flatMap(Status.init(rawValue:)) ?? .pending
        correction = try container.decodeIfPresent(String.self, forKey: .correction)
        respondedAt = try container.decodeIfPresent(Date.self, forKey: .respondedAt)
    }

    /// The wording that should carry forward: the user's correction when
    /// they gave one, otherwise the confirmed statement.
    public var acceptedStatement: String? {
        switch status {
        case .confirmed: statement
        case .corrected: correction
        case .pending, .dismissed: nil
        }
    }
}

/// Where a study is in its guided flow. The app uses it to say what to do
/// next; nothing is locked behind a stage.
public enum StudyStage: String, Codable, Hashable, Sendable {
    /// Add a few pieces you already love.
    case seed
    /// Judge real sources proposed for the subject.
    case explore
    /// Confirm or correct the patterns reflected back.
    case reflect
    /// Enough confirmed taste to distill a design language.
    case distill
}

public extension ProjectStudy {
    static let minimumSeedCount = 3
    static let decisionsBeforeReflection = 6

    func stage(itemCount: Int) -> StudyStage {
        if reflections.contains(where: { $0.acceptedStatement != nil }) {
            return .distill
        }
        if itemCount < Self.minimumSeedCount {
            return .seed
        }
        if decidedSuggestions.count >= Self.decisionsBeforeReflection || !reflections.isEmpty {
            return .reflect
        }
        return .explore
    }

    var pendingSuggestions: [StudySuggestion] {
        suggestions.filter { $0.status == .pending }
    }

    var decidedSuggestions: [StudySuggestion] {
        suggestions.filter { $0.status != .pending }
    }

    var pendingReflections: [StudyReflection] {
        reflections.filter { $0.status == .pending }
    }
}

public extension ProjectStudy {
    /// Combines two copies of the same study, such as a project edited on two
    /// devices. Suggestions and reflections merge by ID, so independent
    /// decisions on different items both survive. For the same item, a keep
    /// beats any other state (keeping is final and has already saved an
    /// item), a decision beats pending, and otherwise the later decision wins.
    /// Subject and brief come from `preferred`, the copy whose project won.
    static func merged(preferring preferred: ProjectStudy?, with other: ProjectStudy?) -> ProjectStudy? {
        guard let preferred else { return other }
        guard let other else { return preferred }

        var result = preferred
        result.suggestions = mergedByID(
            preferred.suggestions,
            other.suggestions,
            prefer: StudySuggestion.mergePrecedes,
            order: { ($0.suggestedAt, $0.id.uuidString) < ($1.suggestedAt, $1.id.uuidString) }
        )
        result.reflections = mergedByID(
            preferred.reflections,
            other.reflections,
            prefer: StudyReflection.mergePrecedes,
            order: { ($0.proposedAt, $0.id.uuidString) < ($1.proposedAt, $1.id.uuidString) }
        )
        return result
    }

    private static func mergedByID<Element: Identifiable>(
        _ preferred: [Element],
        _ other: [Element],
        prefer: (Element, Element) -> Bool,
        order: (Element, Element) -> Bool
    ) -> [Element] {
        var byID: [Element.ID: Element] = [:]
        for element in preferred {
            byID[element.id] = element
        }
        for element in other {
            guard let existing = byID[element.id] else {
                byID[element.id] = element
                continue
            }
            // Ties keep the preferred copy.
            if prefer(element, existing) {
                byID[element.id] = element
            }
        }
        return byID.values.sorted(by: order)
    }
}

extension StudySuggestion {
    /// Whether `lhs` should replace `rhs` when both copies of one suggestion meet.
    static func mergePrecedes(_ lhs: StudySuggestion, _ rhs: StudySuggestion) -> Bool {
        let lhsRank = lhs.status.mergeRank
        let rhsRank = rhs.status.mergeRank
        if lhsRank != rhsRank { return lhsRank > rhsRank }
        return (lhs.decidedAt ?? lhs.suggestedAt) > (rhs.decidedAt ?? rhs.suggestedAt)
    }
}

private extension StudySuggestion.Status {
    var mergeRank: Int {
        switch self {
        case .pending: 0
        case .rejected: 1
        case .kept: 2
        }
    }
}

extension StudyReflection {
    /// Whether `lhs` should replace `rhs` when both copies of one reflection meet.
    static func mergePrecedes(_ lhs: StudyReflection, _ rhs: StudyReflection) -> Bool {
        let lhsDecided = lhs.status != .pending
        let rhsDecided = rhs.status != .pending
        if lhsDecided != rhsDecided { return lhsDecided }
        return (lhs.respondedAt ?? lhs.proposedAt) > (rhs.respondedAt ?? rhs.proposedAt)
    }
}

/// Agent-supplied proposal for a study suggestion. It becomes a pending
/// `StudySuggestion` only after `StudySourcePolicy` accepts it.
public struct StudySuggestionDraft: Codable, Equatable, Sendable {
    public var url: URL
    public var title: String
    public var creator: String
    public var sourceName: String?
    public var imageURL: URL?
    public var rationale: String
    public var basedOnInspirationIDs: [Inspiration.ID]?

    public init(
        url: URL,
        title: String,
        creator: String,
        sourceName: String? = nil,
        imageURL: URL? = nil,
        rationale: String,
        basedOnInspirationIDs: [Inspiration.ID]? = nil
    ) {
        self.url = url
        self.title = title
        self.creator = creator
        self.sourceName = sourceName
        self.imageURL = imageURL
        self.rationale = rationale
        self.basedOnInspirationIDs = basedOnInspirationIDs
    }
}

/// Agent-supplied proposal for a reflected pattern.
public struct StudyReflectionDraft: Codable, Equatable, Sendable {
    public var statement: String
    public var inspirationIDs: [Inspiration.ID]?
    public var rejectedSuggestionIDs: [StudySuggestion.ID]?

    public init(
        statement: String,
        inspirationIDs: [Inspiration.ID]? = nil,
        rejectedSuggestionIDs: [StudySuggestion.ID]? = nil
    ) {
        self.statement = statement
        self.inspirationIDs = inspirationIDs
        self.rejectedSuggestionIDs = rejectedSuggestionIDs
    }
}

/// A user's verdict on a suggestion.
public enum StudyVerdict: String, Codable, Hashable, Sendable {
    case keep
    case reject
}

/// A user's response to a reflected pattern.
public enum StudyReflectionResponse: Hashable, Sendable {
    case confirm
    case correct(String)
    case dismiss
}

/// Why a proposed suggestion was not added to the study.
public enum StudySuggestionSkipReason: String, Codable, Hashable, Sendable {
    /// The URL is not an http(s) page.
    case invalidURL = "invalid_url"
    /// The page or image is hosted by an AI image generator.
    case generatedImagery = "generated_imagery"
    /// No creator was named, so the work cannot be attributed.
    case missingCreator = "missing_creator"
    case missingTitle = "missing_title"
    /// No reason tied to the user's seeds was given.
    case missingRationale = "missing_rationale"
    /// `basedOnInspirationIDs` names an item outside this study.
    case unknownBasis = "unknown_basis"
    /// The user already saved this URL in the study.
    case alreadySaved = "already_saved"
    /// The URL is already waiting for the user's verdict.
    case alreadySuggested = "already_suggested"
    /// The user rejected this URL before. It is never proposed again.
    case previouslyRejected = "previously_rejected"
    case duplicateInBatch = "duplicate_in_batch"
}

public struct StudySuggestionSkip: Codable, Equatable, Sendable {
    public var url: String
    public var reason: StudySuggestionSkipReason

    public init(url: String, reason: StudySuggestionSkipReason) {
        self.url = url
        self.reason = reason
    }
}

public struct StudySuggestionBatchResult: Codable, Equatable, Sendable {
    public var added: [StudySuggestion]
    public var skipped: [StudySuggestionSkip]

    public init(added: [StudySuggestion], skipped: [StudySuggestionSkip]) {
        self.added = added
        self.skipped = skipped
    }
}

/// Guards the "real sources only" rule at the storage boundary. An agent can
/// still be wrong about a page, which is why every suggestion waits for the
/// user's verdict, but known image generators are refused outright.
public enum StudySourcePolicy {
    /// Hosts whose primary content is AI-generated imagery. Matching includes
    /// subdomains, so CDN hosts such as `cdn.midjourney.com` are covered.
    public static let generatedImageryHosts: Set<String> = [
        "midjourney.com",
        "lexica.art",
        "openart.ai",
        "playgroundai.com",
        "playground.com",
        "leonardo.ai",
        "nightcafe.studio",
        "civitai.com",
        "krea.ai",
        "ideogram.ai",
        "firefly.adobe.com",
        "labs.openai.com",
        "dreamstudio.ai",
        "craiyon.com",
        "stablediffusionweb.com",
        "artbreeder.com",
        "gencraft.com",
        "tensor.art",
        "seaart.ai",
        "starryai.com",
        "dream.ai",
        "getimg.ai",
        "imagine.art",
        "pixai.art",
        "nightcafe.com",
        "freepik.com/ai",
    ]

    public static func isGeneratedImageryHost(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        let path = url?.path.lowercased() ?? ""
        return generatedImageryHosts.contains { entry in
            let parts = entry.split(separator: "/", maxSplits: 1).map(String.init)
            let entryHost = parts[0]
            let hostMatches = host == entryHost || host.hasSuffix("." + entryHost)
            guard hostMatches else { return false }
            guard parts.count == 2 else { return true }
            return path.hasPrefix("/" + parts[1])
        }
    }
}
