import Foundation

/// A portable, content-minimized description of the visual language expressed by
/// one moodboard item or synthesized from a project of references.
///
/// The canonical representation is deliberately immutable. Corrections and new
/// extraction runs should produce a new value rather than mutating an existing
/// result in place.
public struct DesignEssence: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = "1.0"

    public let schemaVersion: String
    public let source: Source
    public let provenance: Provenance
    public let scope: Scope
    public let summary: Summary
    public let invariants: [Invariant]
    public let observables: Observables
    public let composition: Composition
    public let semanticAxes: [SemanticAxis]
    public let cueEffects: [CueEffect]
    public let projectVariation: ProjectVariation?
    public let directive: Directive

    public init(
        schemaVersion: String = DesignEssence.currentSchemaVersion,
        source: Source,
        provenance: Provenance,
        scope: Scope,
        summary: Summary,
        invariants: [Invariant] = [],
        observables: Observables = Observables(),
        composition: Composition = Composition(),
        semanticAxes: [SemanticAxis] = [],
        cueEffects: [CueEffect] = [],
        projectVariation: ProjectVariation? = nil,
        directive: Directive = Directive()
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.provenance = provenance
        self.scope = scope
        self.summary = summary
        self.invariants = invariants
        self.observables = observables
        self.composition = composition
        self.semanticAxes = semanticAxes
        self.cueEffects = cueEffects
        self.projectVariation = projectVariation
        self.directive = directive
    }
}

public extension DesignEssence {
    struct Source: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable {
            case image
            case project
        }

        public struct Reference: Codable, Hashable, Sendable {
            public enum Role: String, Codable, Hashable, Sendable {
                case positive
                case nearMiss = "near_miss"
                case negative
            }

            public let assetID: Inspiration.ID
            public let role: Role

            public init(assetID: Inspiration.ID, role: Role = .positive) {
                self.assetID = assetID
                self.role = role
            }
        }

        public let kind: Kind
        public let projectID: Project.ID?
        public let references: [Reference]
        public let inputHash: String

        public init(
            kind: Kind,
            projectID: Project.ID? = nil,
            references: [Reference],
            inputHash: String
        ) {
            self.kind = kind
            self.projectID = projectID
            self.references = references
            self.inputHash = inputHash
        }

        public var assetIDs: [Inspiration.ID] {
            references.map(\.assetID)
        }
    }

    struct Provenance: Codable, Hashable, Sendable {
        public let extractedAt: Date
        public let model: String
        public let pipelineVersion: String

        public init(extractedAt: Date, model: String, pipelineVersion: String) {
            self.extractedAt = extractedAt
            self.model = model
            self.pipelineVersion = pipelineVersion
        }

        private enum CodingKeys: String, CodingKey {
            case extractedAt
            case model
            case pipelineVersion
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let timestamp = try container.decode(String.self, forKey: .extractedAt)
            guard let date = Self.date(from: timestamp) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .extractedAt,
                    in: container,
                    debugDescription: "Expected an ISO-8601 timestamp."
                )
            }
            extractedAt = date
            model = try container.decode(String.self, forKey: .model)
            pipelineVersion = try container.decode(String.self, forKey: .pipelineVersion)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Self.string(from: extractedAt), forKey: .extractedAt)
            try container.encode(model, forKey: .model)
            try container.encode(pipelineVersion, forKey: .pipelineVersion)
        }

        private static func string(from date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            var wholeSeconds = floor(date.timeIntervalSince1970)
            var nanoseconds = Int(
                ((date.timeIntervalSince1970 - wholeSeconds) * 1_000_000_000).rounded()
            )
            if nanoseconds == 1_000_000_000 {
                wholeSeconds += 1
                nanoseconds = 0
            }

            let base = formatter.string(
                from: Date(timeIntervalSince1970: wholeSeconds)
            )
            guard nanoseconds != 0 else { return base }
            return String(base.dropLast()) + String(format: ".%09dZ", nanoseconds)
        }

        private static func date(from value: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }

            if value.hasSuffix("Z"),
               let decimalPoint = value.lastIndex(of: ".") {
                let fractionStart = value.index(after: decimalPoint)
                let fractionEnd = value.index(before: value.endIndex)
                let digits = value[fractionStart..<fractionEnd]
                guard (1...9).contains(digits.count),
                      digits.allSatisfy(\.isNumber),
                      let fraction = Double("0." + String(digits)),
                      let wholeSeconds = formatter.date(
                        from: String(value[..<decimalPoint]) + "Z"
                      ) else {
                    return nil
                }
                return wholeSeconds.addingTimeInterval(fraction)
            }

            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value)
        }
    }

    struct Scope: Codable, Hashable, Sendable {
        public enum Domain: String, Codable, Hashable, Sendable {
            case userInterface = "ui"
            case editorial
            case brand
            case interior
            case photography
            case mixed
            case other
        }

        public let domain: Domain
        public let analyzedRegions: [String]
        public let deliberatelyExcluded: [String]
        public let limitations: [String]

        public init(
            domain: Domain,
            analyzedRegions: [String] = [],
            deliberatelyExcluded: [String] = [],
            limitations: [String] = []
        ) {
            self.domain = domain
            self.analyzedRegions = analyzedRegions
            self.deliberatelyExcluded = deliberatelyExcluded
            self.limitations = limitations
        }
    }

    enum ClaimBasis: String, Codable, Hashable, Sendable {
        case measured
        case observed
        case inferred
    }

    struct Claim<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        public let value: Value
        public let basis: ClaimBasis
        public let confidence: Double
        public let evidence: [Evidence]

        public init(
            value: Value,
            basis: ClaimBasis,
            confidence: Double,
            evidence: [Evidence] = []
        ) {
            self.value = value
            self.basis = basis
            self.confidence = confidence
            self.evidence = evidence
        }
    }

    struct Evidence: Codable, Hashable, Sendable {
        public struct NormalizedRegion: Codable, Hashable, Sendable {
            public let x: Double
            public let y: Double
            public let width: Double
            public let height: Double

            public init(x: Double, y: Double, width: Double, height: Double) {
                self.x = x
                self.y = y
                self.width = width
                self.height = height
            }
        }

        public let assetID: Inspiration.ID
        public let region: NormalizedRegion?
        public let cue: String
        public let measurement: String?

        public init(
            assetID: Inspiration.ID,
            region: NormalizedRegion? = nil,
            cue: String,
            measurement: String? = nil
        ) {
            self.assetID = assetID
            self.region = region
            self.cue = cue
            self.measurement = measurement
        }
    }

    struct Summary: Codable, Hashable, Sendable {
        public let essence: Claim<String>
        public let signatureTensions: [Claim<String>]
        /// Project-level agreement in the closed interval `0...1`.
        public let coherence: Claim<Double>?

        public init(
            essence: Claim<String>,
            signatureTensions: [Claim<String>] = [],
            coherence: Claim<Double>? = nil
        ) {
            self.essence = essence
            self.signatureTensions = signatureTensions
            self.coherence = coherence
        }
    }

    struct Invariant: Codable, Hashable, Sendable {
        public enum Importance: String, Codable, Hashable, Sendable {
            case primary
            case secondary
        }

        public let statement: Claim<String>
        public let importance: Importance

        public init(statement: Claim<String>, importance: Importance) {
            self.statement = statement
            self.importance = importance
        }
    }

    struct Observables: Codable, Hashable, Sendable {
        public let palette: Claim<Palette>?
        public let typography: Claim<Typography>?
        public let geometry: Claim<Geometry>?
        public let spacing: Claim<Spacing>?
        public let surface: Claim<Surface>?
        public let imagery: Claim<Imagery>?

        public init(
            palette: Claim<Palette>? = nil,
            typography: Claim<Typography>? = nil,
            geometry: Claim<Geometry>? = nil,
            spacing: Claim<Spacing>? = nil,
            surface: Claim<Surface>? = nil,
            imagery: Claim<Imagery>? = nil
        ) {
            self.palette = palette
            self.typography = typography
            self.geometry = geometry
            self.spacing = spacing
            self.surface = surface
            self.imagery = imagery
        }
    }

    struct Palette: Codable, Hashable, Sendable {
        public struct Color: Codable, Hashable, Sendable {
            public let hex: String
            public let role: String
            /// Relative coverage in the closed interval `0...1`, when measured.
            public let coverage: Double?

            public init(hex: String, role: String, coverage: Double? = nil) {
                self.hex = hex
                self.role = role
                self.coverage = coverage
            }
        }

        public let colors: [Color]
        public let temperature: String
        public let saturation: String
        public let contrastStrategy: String

        public init(
            colors: [Color],
            temperature: String,
            saturation: String,
            contrastStrategy: String
        ) {
            self.colors = colors
            self.temperature = temperature
            self.saturation = saturation
            self.contrastStrategy = contrastStrategy
        }
    }

    struct Typography: Codable, Hashable, Sendable {
        public let hierarchy: String
        public let scaleBehavior: String
        public let weightRange: String
        public let rhythm: String

        public init(
            hierarchy: String,
            scaleBehavior: String,
            weightRange: String,
            rhythm: String
        ) {
            self.hierarchy = hierarchy
            self.scaleBehavior = scaleBehavior
            self.weightRange = weightRange
            self.rhythm = rhythm
        }
    }

    struct Geometry: Codable, Hashable, Sendable {
        public let shapeLanguage: String
        public let corners: String
        public let borders: String
        public let elevation: String

        public init(
            shapeLanguage: String,
            corners: String,
            borders: String,
            elevation: String
        ) {
            self.shapeLanguage = shapeLanguage
            self.corners = corners
            self.borders = borders
            self.elevation = elevation
        }
    }

    struct Spacing: Codable, Hashable, Sendable {
        public let density: String
        public let grid: String
        public let groupingStrategy: String
        public let negativeSpace: String

        public init(
            density: String,
            grid: String,
            groupingStrategy: String,
            negativeSpace: String
        ) {
            self.density = density
            self.grid = grid
            self.groupingStrategy = groupingStrategy
            self.negativeSpace = negativeSpace
        }
    }

    struct Surface: Codable, Hashable, Sendable {
        public let texture: String
        public let depth: String
        public let lighting: String

        public init(texture: String, depth: String, lighting: String) {
            self.texture = texture
            self.depth = depth
            self.lighting = lighting
        }
    }

    struct Imagery: Codable, Hashable, Sendable {
        public let treatment: String
        public let relationshipToTypography: String

        public init(treatment: String, relationshipToTypography: String) {
            self.treatment = treatment
            self.relationshipToTypography = relationshipToTypography
        }
    }

    struct Composition: Codable, Hashable, Sendable {
        public let hierarchy: Claim<String>?
        public let entryPoint: Claim<String>?
        public let readingPath: Claim<String>?
        public let alignment: Claim<String>?
        public let balance: Claim<String>?
        public let grouping: Claim<String>?
        public let rhythm: Claim<String>?
        public let scaleContrast: Claim<String>?

        public init(
            hierarchy: Claim<String>? = nil,
            entryPoint: Claim<String>? = nil,
            readingPath: Claim<String>? = nil,
            alignment: Claim<String>? = nil,
            balance: Claim<String>? = nil,
            grouping: Claim<String>? = nil,
            rhythm: Claim<String>? = nil,
            scaleContrast: Claim<String>? = nil
        ) {
            self.hierarchy = hierarchy
            self.entryPoint = entryPoint
            self.readingPath = readingPath
            self.alignment = alignment
            self.balance = balance
            self.grouping = grouping
            self.rhythm = rhythm
            self.scaleContrast = scaleContrast
        }
    }

    struct SemanticAxis: Codable, Hashable, Sendable {
        public let axis: String
        /// Position on a bipolar semantic scale in the closed interval `-1...1`.
        public let score: Double
        public let confidence: Double
        public let evidence: [Evidence]

        public init(axis: String, score: Double, confidence: Double, evidence: [Evidence]) {
            self.axis = axis
            self.score = score
            self.confidence = confidence
            self.evidence = evidence
        }
    }

    struct CueEffect: Codable, Hashable, Sendable {
        public let cues: [Evidence]
        public let likelyEffect: String
        public let confidence: Double
        public let context: String?

        public init(
            cues: [Evidence],
            likelyEffect: String,
            confidence: Double,
            context: String? = nil
        ) {
            self.cues = cues
            self.likelyEffect = likelyEffect
            self.confidence = confidence
            self.context = context
        }
    }

    struct ProjectVariation: Codable, Hashable, Sendable {
        public struct Cluster: Codable, Hashable, Sendable {
            public let label: String
            public let assetIDs: [Inspiration.ID]
            public let summary: Claim<String>

            public init(label: String, assetIDs: [Inspiration.ID], summary: Claim<String>) {
                self.label = label
                self.assetIDs = assetIDs
                self.summary = summary
            }
        }

        public let commonCore: [Claim<String>]
        public let acceptedVariations: [Claim<String>]
        public let contradictions: [Claim<String>]
        public let clusters: [Cluster]

        public init(
            commonCore: [Claim<String>] = [],
            acceptedVariations: [Claim<String>] = [],
            contradictions: [Claim<String>] = [],
            clusters: [Cluster] = []
        ) {
            self.commonCore = commonCore
            self.acceptedVariations = acceptedVariations
            self.contradictions = contradictions
            self.clusters = clusters
        }
    }

    struct Directive: Codable, Hashable, Sendable {
        public let mustPreserve: [Claim<String>]
        public let prefer: [Claim<String>]
        public let mayVary: [Claim<String>]
        public let mustAvoid: [Claim<String>]

        public init(
            mustPreserve: [Claim<String>] = [],
            prefer: [Claim<String>] = [],
            mayVary: [Claim<String>] = [],
            mustAvoid: [Claim<String>] = []
        ) {
            self.mustPreserve = mustPreserve
            self.prefer = prefer
            self.mayVary = mayVary
            self.mustAvoid = mustAvoid
        }
    }
}

public struct DesignEssenceValidationIssue: Codable, Hashable, Sendable {
    public enum Code: String, Codable, Hashable, Sendable {
        case unsupportedSchemaVersion
        case invalidSource
        case invalidInputHash
        case duplicateAssetReference
        case unknownAssetReference
        case invalidNormalizedRegion
        case confidenceOutOfRange
        case scoreOutOfRange
        case coverageOutOfRange
        case missingEvidenceForInferredClaim
        case missingMeasurementForMeasuredClaim
        case invalidPaletteBasis
        case missingPaletteApproximationDisclosure
        case blankValue
        case invalidPaletteColor
        case duplicateSemanticAxis
        case invalidClusterPartition
    }

    public let code: Code
    public let path: String
    public let message: String

    public init(code: Code, path: String, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}

public struct DesignEssenceValidationError: Error, Equatable, Sendable {
    public let issues: [DesignEssenceValidationIssue]

    public init(issues: [DesignEssenceValidationIssue]) {
        self.issues = issues
    }
}

extension DesignEssenceValidationError: LocalizedError {
    public var errorDescription: String? {
        issues
            .map { "\($0.path): \($0.message)" }
            .joined(separator: "\n")
    }
}

/// Validates relationships and numeric invariants that Codable cannot express.
public enum DesignEssenceValidator {
    public static func validate(_ essence: DesignEssence) throws {
        let foundIssues = issues(in: essence)
        guard foundIssues.isEmpty else {
            throw DesignEssenceValidationError(issues: foundIssues)
        }
    }

    public static func issues(in essence: DesignEssence) -> [DesignEssenceValidationIssue] {
        var accumulator = DesignEssenceValidationAccumulator(essence: essence)
        accumulator.validate()
        return accumulator.issues
    }
}

public extension DesignEssence {
    /// Returns the same immutable value after validation, enabling validation at
    /// decoding or persistence boundaries without introducing mutable state.
    func validated() throws -> DesignEssence {
        try DesignEssenceValidator.validate(self)
        return self
    }
}

private struct DesignEssenceValidationAccumulator {
    typealias Issue = DesignEssenceValidationIssue

    let essence: DesignEssence
    let sourceAssetIDs: Set<Inspiration.ID>
    var issues: [Issue] = []

    init(essence: DesignEssence) {
        self.essence = essence
        sourceAssetIDs = Set(essence.source.assetIDs)
    }

    mutating func validate() {
        validateSchema()
        validateSource()
        validateProvenance()
        validateSummary()
        validateInvariants()
        validateObservables()
        validateComposition()
        validateSemanticAxes()
        validateCueEffects()
        validateProjectVariation()
        validateDirective()
    }

    private mutating func validateSchema() {
        guard essence.schemaVersion == DesignEssence.currentSchemaVersion else {
            append(
                .unsupportedSchemaVersion,
                path: "schemaVersion",
                message: "Expected schema version \(DesignEssence.currentSchemaVersion), got \(essence.schemaVersion)."
            )
            return
        }
    }

    private mutating func validateSource() {
        if essence.source.references.isEmpty {
            append(
                .invalidSource,
                path: "source.references",
                message: "At least one source reference is required."
            )
        }

        if essence.source.inputHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            append(
                .invalidSource,
                path: "source.inputHash",
                message: "A source input hash cannot be empty."
            )
        } else if !Self.isSHA256Fingerprint(essence.source.inputHash) {
            append(
                .invalidInputHash,
                path: "source.inputHash",
                message: "The input fingerprint must use sha256:<64 hexadecimal characters>."
            )
        }

        switch essence.source.kind {
        case .image:
            if essence.source.references.count != 1 {
                append(
                    .invalidSource,
                    path: "source.references",
                    message: "A single-image essence must contain exactly one source reference."
                )
            }
            if essence.source.projectID != nil {
                append(
                    .invalidSource,
                    path: "source.projectID",
                    message: "A single-image essence must not identify a project."
                )
            }
            if essence.summary.coherence != nil {
                append(
                    .invalidSource,
                    path: "summary.coherence",
                    message: "Coherence is defined only for a project essence."
                )
            }
            if essence.projectVariation != nil {
                append(
                    .invalidSource,
                    path: "projectVariation",
                    message: "Project variation is defined only for a project essence."
                )
            }
        case .project:
            if essence.source.projectID == nil {
                append(
                    .invalidSource,
                    path: "source.projectID",
                    message: "A project essence must identify its source project."
                )
            }
        }

        var seenAssetIDs = Set<Inspiration.ID>()
        for (index, reference) in essence.source.references.enumerated() {
            guard seenAssetIDs.insert(reference.assetID).inserted else {
                append(
                    .duplicateAssetReference,
                    path: "source.references[\(index)].assetID",
                    message: "Each source asset may appear only once."
                )
                continue
            }
        }
    }

    private mutating func validateSummary() {
        validateClaim(essence.summary.essence, path: "summary.essence")
        validateClaims(essence.summary.signatureTensions, path: "summary.signatureTensions")

        if let coherence = essence.summary.coherence {
            validateClaim(coherence, path: "summary.coherence")
            validateUnitScore(coherence.value, path: "summary.coherence.value")
        }
    }

    private mutating func validateProvenance() {
        validateNonBlank(
            essence.provenance.model,
            path: "provenance.model",
            label: "Model identifier"
        )
        validateNonBlank(
            essence.provenance.pipelineVersion,
            path: "provenance.pipelineVersion",
            label: "Pipeline version"
        )
    }

    private mutating func validateInvariants() {
        for (index, invariant) in essence.invariants.enumerated() {
            validateClaim(invariant.statement, path: "invariants[\(index)].statement")
        }
    }

    private mutating func validateObservables() {
        if let palette = essence.observables.palette {
            let path = "observables.palette"
            validateClaim(palette, path: path)
            if palette.basis == .inferred {
                append(
                    .invalidPaletteBasis,
                    path: "\(path).basis",
                    message: "A palette basis must be observed or measured, not inferred."
                )
            }
            if palette.basis == .observed,
               !palette.value.colors.isEmpty,
               !Self.hasPaletteApproximationDisclosure(essence.scope.limitations) {
                append(
                    .missingPaletteApproximationDisclosure,
                    path: "scope.limitations",
                    message: "An observed palette with estimated hex values must disclose that the values are approximate."
                )
            }
            validateNonBlank(
                palette.value.temperature,
                path: "\(path).value.temperature",
                label: "Palette temperature"
            )
            validateNonBlank(
                palette.value.saturation,
                path: "\(path).value.saturation",
                label: "Palette saturation"
            )
            validateNonBlank(
                palette.value.contrastStrategy,
                path: "\(path).value.contrastStrategy",
                label: "Palette contrast strategy"
            )
            for (index, color) in palette.value.colors.enumerated() {
                let colorPath = "\(path).value.colors[\(index)]"
                if !Self.isHexColor(color.hex) {
                    append(
                        .invalidPaletteColor,
                        path: "\(colorPath).hex",
                        message: "Palette colors must use #RRGGBB or #RRGGBBAA syntax."
                    )
                }
                validateNonBlank(color.role, path: "\(colorPath).role", label: "Palette role")
                guard let coverage = color.coverage else { continue }
                if !isInClosedRange(coverage, lower: 0, upper: 1) {
                    append(
                        .coverageOutOfRange,
                        path: "\(colorPath).coverage",
                        message: "Color coverage must be finite and within 0...1."
                    )
                }
            }
        }

        if let typography = essence.observables.typography {
            let path = "observables.typography"
            validateClaim(typography, path: path)
            validateStructuredStrings(
                [
                    ("hierarchy", typography.value.hierarchy),
                    ("scaleBehavior", typography.value.scaleBehavior),
                    ("weightRange", typography.value.weightRange),
                    ("rhythm", typography.value.rhythm),
                ],
                under: "\(path).value"
            )
        }
        if let geometry = essence.observables.geometry {
            let path = "observables.geometry"
            validateClaim(geometry, path: path)
            validateStructuredStrings(
                [
                    ("shapeLanguage", geometry.value.shapeLanguage),
                    ("corners", geometry.value.corners),
                    ("borders", geometry.value.borders),
                    ("elevation", geometry.value.elevation),
                ],
                under: "\(path).value"
            )
        }
        if let spacing = essence.observables.spacing {
            let path = "observables.spacing"
            validateClaim(spacing, path: path)
            validateStructuredStrings(
                [
                    ("density", spacing.value.density),
                    ("grid", spacing.value.grid),
                    ("groupingStrategy", spacing.value.groupingStrategy),
                    ("negativeSpace", spacing.value.negativeSpace),
                ],
                under: "\(path).value"
            )
        }
        if let surface = essence.observables.surface {
            let path = "observables.surface"
            validateClaim(surface, path: path)
            validateStructuredStrings(
                [
                    ("texture", surface.value.texture),
                    ("depth", surface.value.depth),
                    ("lighting", surface.value.lighting),
                ],
                under: "\(path).value"
            )
        }
        if let imagery = essence.observables.imagery {
            let path = "observables.imagery"
            validateClaim(imagery, path: path)
            validateStructuredStrings(
                [
                    ("treatment", imagery.value.treatment),
                    ("relationshipToTypography", imagery.value.relationshipToTypography),
                ],
                under: "\(path).value"
            )
        }
    }

    private mutating func validateComposition() {
        let fields: [(String, DesignEssence.Claim<String>?)] = [
            ("hierarchy", essence.composition.hierarchy),
            ("entryPoint", essence.composition.entryPoint),
            ("readingPath", essence.composition.readingPath),
            ("alignment", essence.composition.alignment),
            ("balance", essence.composition.balance),
            ("grouping", essence.composition.grouping),
            ("rhythm", essence.composition.rhythm),
            ("scaleContrast", essence.composition.scaleContrast),
        ]

        for (name, claim) in fields {
            guard let claim else { continue }
            validateClaim(claim, path: "composition.\(name)")
        }
    }

    private mutating func validateSemanticAxes() {
        var seenAxes = Set<String>()
        for (index, axis) in essence.semanticAxes.enumerated() {
            let path = "semanticAxes[\(index)]"
            let normalizedAxis = axis.axis.trimmingCharacters(in: .whitespacesAndNewlines)
            validateNonBlank(axis.axis, path: "\(path).axis", label: "Semantic axis")
            if !normalizedAxis.isEmpty, !seenAxes.insert(normalizedAxis).inserted {
                append(
                    .duplicateSemanticAxis,
                    path: "\(path).axis",
                    message: "Each semantic axis may appear only once."
                )
            }
            validateBipolarScore(axis.score, path: "\(path).score")
            validateConfidence(axis.confidence, path: "\(path).confidence")
            if axis.evidence.isEmpty {
                append(
                    .missingEvidenceForInferredClaim,
                    path: "\(path).evidence",
                    message: "A semantic-axis inference must cite visible evidence."
                )
            }
            validateEvidence(axis.evidence, path: "\(path).evidence")
        }
    }

    private mutating func validateCueEffects() {
        for (index, cueEffect) in essence.cueEffects.enumerated() {
            let path = "cueEffects[\(index)]"
            validateNonBlank(
                cueEffect.likelyEffect,
                path: "\(path).likelyEffect",
                label: "Likely effect"
            )
            validateConfidence(cueEffect.confidence, path: "\(path).confidence")
            if cueEffect.cues.isEmpty {
                append(
                    .missingEvidenceForInferredClaim,
                    path: "\(path).cues",
                    message: "A cue-to-effect inference must cite visible evidence."
                )
            }
            validateEvidence(cueEffect.cues, path: "\(path).cues")
        }
    }

    private mutating func validateProjectVariation() {
        guard let variation = essence.projectVariation else { return }

        validateClaims(variation.commonCore, path: "projectVariation.commonCore")
        validateClaims(variation.acceptedVariations, path: "projectVariation.acceptedVariations")
        validateClaims(variation.contradictions, path: "projectVariation.contradictions")

        var clusteredAssetIDs = Set<Inspiration.ID>()
        for (clusterIndex, cluster) in variation.clusters.enumerated() {
            let path = "projectVariation.clusters[\(clusterIndex)]"
            validateNonBlank(cluster.label, path: "\(path).label", label: "Cluster label")
            validateClaim(cluster.summary, path: "\(path).summary")
            if cluster.assetIDs.isEmpty {
                append(
                    .invalidClusterPartition,
                    path: "\(path).assetIDs",
                    message: "A project cluster must contain at least one positive source asset."
                )
            }
            for (assetIndex, assetID) in cluster.assetIDs.enumerated() {
                let assetPath = "\(path).assetIDs[\(assetIndex)]"
                guard sourceAssetIDs.contains(assetID) else {
                    append(
                        .unknownAssetReference,
                        path: assetPath,
                        message: "Cluster asset \(assetID.uuidString) is not present in source.references."
                    )
                    continue
                }
                guard essence.source.references.first(where: { $0.assetID == assetID })?.role == .positive else {
                    append(
                        .invalidClusterPartition,
                        path: assetPath,
                        message: "Only positive source references may be assigned to project direction clusters."
                    )
                    continue
                }
                if !clusteredAssetIDs.insert(assetID).inserted {
                    append(
                        .invalidClusterPartition,
                        path: assetPath,
                        message: "A positive source asset may appear in only one project cluster."
                    )
                }
            }
        }

        if !variation.clusters.isEmpty {
            let positiveAssetIDs = Set(
                essence.source.references
                    .filter { $0.role == .positive }
                    .map(\.assetID)
            )
            let missingAssetIDs = positiveAssetIDs.subtracting(clusteredAssetIDs)
            if !missingAssetIDs.isEmpty {
                append(
                    .invalidClusterPartition,
                    path: "projectVariation.clusters",
                    message: "Project clusters must partition every positive source reference exactly once."
                )
            }
        }
    }

    private mutating func validateDirective() {
        validateClaims(essence.directive.mustPreserve, path: "directive.mustPreserve")
        validateClaims(essence.directive.prefer, path: "directive.prefer")
        validateClaims(essence.directive.mayVary, path: "directive.mayVary")
        validateClaims(essence.directive.mustAvoid, path: "directive.mustAvoid")
    }

    private mutating func validateClaims<Value>(
        _ claims: [DesignEssence.Claim<Value>],
        path: String
    ) where Value: Codable & Hashable & Sendable {
        for (index, claim) in claims.enumerated() {
            validateClaim(claim, path: "\(path)[\(index)]")
        }
    }

    private mutating func validateClaim<Value>(
        _ claim: DesignEssence.Claim<Value>,
        path: String
    ) where Value: Codable & Hashable & Sendable {
        validateConfidence(claim.confidence, path: "\(path).confidence")

        if let stringValue = claim.value as? String {
            validateNonBlank(stringValue, path: "\(path).value", label: "Claim value")
        }

        if claim.basis == .inferred, claim.evidence.isEmpty {
            append(
                .missingEvidenceForInferredClaim,
                path: "\(path).evidence",
                message: "An inferred claim must cite visible evidence."
            )
        }

        if claim.basis == .measured,
           !claim.evidence.contains(where: {
               guard let measurement = $0.measurement else { return false }
               return !measurement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           }) {
            append(
                .missingMeasurementForMeasuredClaim,
                path: "\(path).evidence",
                message: "A measured claim must cite at least one tool-derived measurement."
            )
        }

        validateEvidence(claim.evidence, path: "\(path).evidence")
    }

    private mutating func validateEvidence(_ evidence: [DesignEssence.Evidence], path: String) {
        for (index, item) in evidence.enumerated() {
            let itemPath = "\(path)[\(index)]"
            validateNonBlank(item.cue, path: "\(itemPath).cue", label: "Evidence cue")
            if let measurement = item.measurement {
                validateNonBlank(
                    measurement,
                    path: "\(itemPath).measurement",
                    label: "Evidence measurement"
                )
            }
            if !sourceAssetIDs.contains(item.assetID) {
                append(
                    .unknownAssetReference,
                    path: "\(itemPath).assetID",
                    message: "Evidence asset \(item.assetID.uuidString) is not present in source.references."
                )
            }

            guard let region = item.region else { continue }
            let valuesAreFinite = region.x.isFinite
                && region.y.isFinite
                && region.width.isFinite
                && region.height.isFinite
            let hasValidOriginAndSize = region.x >= 0
                && region.y >= 0
                && region.width > 0
                && region.height > 0
            let fitsInsideImage = region.x + region.width <= 1
                && region.y + region.height <= 1

            if !valuesAreFinite || !hasValidOriginAndSize || !fitsInsideImage {
                append(
                    .invalidNormalizedRegion,
                    path: "\(itemPath).region",
                    message: "A normalized region must have a non-negative origin, positive size, and fit within 0...1."
                )
            }
        }
    }

    private mutating func validateConfidence(_ value: Double, path: String) {
        guard isInClosedRange(value, lower: 0, upper: 1) else {
            append(
                .confidenceOutOfRange,
                path: path,
                message: "Confidence must be finite and within 0...1."
            )
            return
        }
    }

    private mutating func validateUnitScore(_ value: Double, path: String) {
        guard isInClosedRange(value, lower: 0, upper: 1) else {
            append(
                .scoreOutOfRange,
                path: path,
                message: "The score must be finite and within 0...1."
            )
            return
        }
    }

    private mutating func validateBipolarScore(_ value: Double, path: String) {
        guard isInClosedRange(value, lower: -1, upper: 1) else {
            append(
                .scoreOutOfRange,
                path: path,
                message: "A semantic-axis score must be finite and within -1...1."
            )
            return
        }
    }

    private func isInClosedRange(_ value: Double, lower: Double, upper: Double) -> Bool {
        value.isFinite && value >= lower && value <= upper
    }

    private static func isHexColor(_ value: String) -> Bool {
        let pattern = #"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isSHA256Fingerprint(_ value: String) -> Bool {
        let pattern = #"^sha256:[0-9A-Fa-f]{64}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func hasPaletteApproximationDisclosure(_ limitations: [String]) -> Bool {
        let paletteMarkers = ["palette", "color", "colour", "hex"]
        let approximationMarkers = [
            "approx",
            "estimat",
            "by eye",
            "not measured",
            "not pixel",
            "not sampled",
        ]
        return limitations.contains { limitation in
            let normalized = limitation.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            return paletteMarkers.contains { normalized.contains($0) }
                && approximationMarkers.contains { normalized.contains($0) }
        }
    }

    private mutating func validateStructuredStrings(
        _ fields: [(name: String, value: String)],
        under path: String
    ) {
        for field in fields {
            validateNonBlank(
                field.value,
                path: "\(path).\(field.name)",
                label: field.name
            )
        }
    }

    private mutating func validateNonBlank(_ value: String, path: String, label: String) {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        append(.blankValue, path: path, message: "\(label) cannot be blank.")
    }

    private mutating func append(_ code: Issue.Code, path: String, message: String) {
        issues.append(Issue(code: code, path: path, message: message))
    }
}
