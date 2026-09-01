import Foundation
import XCTest
@testable import PinaxCore

final class DesignEssenceTests: XCTestCase {
    private let assetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherAssetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let projectID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    func testCanonicalEssenceValidatesAndRoundTrips() throws {
        let essence = makeEssence()

        XCTAssertNoThrow(try DesignEssenceValidator.validate(essence))
        XCTAssertEqual(try essence.validated(), essence)

        let encoded = try JSONEncoder().encode(essence)
        let decoded = try JSONDecoder().decode(DesignEssence.self, from: encoded)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let provenance = try XCTUnwrap(json["provenance"] as? [String: Any])

        XCTAssertEqual(decoded, essence)
        XCTAssertEqual(decoded.schemaVersion, DesignEssence.currentSchemaVersion)
        XCTAssertEqual(decoded.source.assetIDs, [assetID])
        XCTAssertEqual(provenance["extractedAt"] as? String, "2023-11-14T22:13:20Z")
    }

    func testProvenanceRoundTripsFractionalSecondsWithoutPrecisionLoss() throws {
        let extractedAt = Date(timeIntervalSince1970: 1_700_000_000.123456)
        let essence = makeEssence(extractedAt: extractedAt)

        let encoded = try JSONEncoder().encode(essence)
        let decoded = try JSONDecoder().decode(DesignEssence.self, from: encoded)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(decoded.provenance.extractedAt, extractedAt)
        XCTAssertTrue(json.contains("2023-11-14T22:13:20.123456"))
    }

    func testValidatorRejectsUnsupportedSchemaVersion() {
        let essence = makeEssence(schemaVersion: "2.0")

        XCTAssertTrue(validationCodes(for: essence).contains(.unsupportedSchemaVersion))
    }

    func testValidatorRejectsConfidenceAndScoreOutsideTheirRanges() {
        let essence = makeEssence(summaryConfidence: 1.01, semanticScore: -1.01)
        let codes = validationCodes(for: essence)

        XCTAssertTrue(codes.contains(.confidenceOutOfRange))
        XCTAssertTrue(codes.contains(.scoreOutOfRange))
    }

    func testValidatorRejectsEvidenceFromAnAssetOutsideTheSource() {
        let essence = makeEssence(evidenceAssetID: otherAssetID)

        XCTAssertTrue(validationCodes(for: essence).contains(.unknownAssetReference))
    }

    func testValidatorRejectsRegionThatExtendsOutsideNormalizedBounds() {
        let region = DesignEssence.Evidence.NormalizedRegion(
            x: 0.8,
            y: 0.2,
            width: 0.3,
            height: 0.4
        )
        let essence = makeEssence(region: region)

        XCTAssertTrue(validationCodes(for: essence).contains(.invalidNormalizedRegion))
    }

    func testValidatorRequiresEvidenceForInferredClaim() {
        let essence = makeEssence(includeSummaryEvidence: false)
        let issues = DesignEssenceValidator.issues(in: essence)

        XCTAssertTrue(
            issues.contains {
                $0.code == .missingEvidenceForInferredClaim
                    && $0.path == "summary.essence.evidence"
            }
        )
    }

    func testProjectSourceRequiresProjectID() {
        let essence = makeEssence(
            sourceKind: .project,
            referenceAssetIDs: [assetID, otherAssetID]
        )
        let issues = DesignEssenceValidator.issues(in: essence)

        XCTAssertTrue(
            issues.contains {
                $0.code == .invalidSource && $0.path == "source.projectID"
            }
        )
    }

    func testProjectSourceAllowsMultipleReferencesAndProjectOnlyFields() {
        let essence = makeEssence(
            sourceKind: .project,
            projectID: projectID,
            referenceAssetIDs: [assetID, otherAssetID],
            includeProjectOnlyFields: true
        )

        XCTAssertNoThrow(try DesignEssenceValidator.validate(essence))
    }

    func testImageSourceRejectsProjectMetadataAndProjectOnlyFields() {
        let essence = makeEssence(
            projectID: projectID,
            includeProjectOnlyFields: true
        )
        let invalidPaths = Set(
            DesignEssenceValidator.issues(in: essence)
                .filter { $0.code == .invalidSource }
                .map(\.path)
        )

        XCTAssertTrue(invalidPaths.contains("source.projectID"))
        XCTAssertTrue(invalidPaths.contains("summary.coherence"))
        XCTAssertTrue(invalidPaths.contains("projectVariation"))
    }

    func testProjectClustersMustPartitionPositiveReferences() {
        let evidence = DesignEssence.Evidence(
            assetID: assetID,
            cue: "The first reference carries the quieter direction"
        )
        let essence = makeEssence(
            sourceKind: .project,
            projectID: projectID,
            referenceAssetIDs: [assetID, otherAssetID],
            includeProjectOnlyFields: true,
            projectClusters: [
                DesignEssence.ProjectVariation.Cluster(
                    label: "Quiet direction",
                    assetIDs: [assetID],
                    summary: DesignEssence.Claim(
                        value: "Restrained and spacious",
                        basis: .inferred,
                        confidence: 0.8,
                        evidence: [evidence]
                    )
                )
            ]
        )

        XCTAssertTrue(validationCodes(for: essence).contains(.invalidClusterPartition))
    }

    func testValidatorRejectsBlankInputHash() {
        let essence = makeEssence(inputHash: "  \n")
        let issues = DesignEssenceValidator.issues(in: essence)

        XCTAssertTrue(
            issues.contains {
                $0.code == .invalidSource && $0.path == "source.inputHash"
            }
        )
    }

    func testValidatorRejectsMalformedInputHash() {
        let essence = makeEssence(inputHash: "sha256:not-a-content-fingerprint")

        XCTAssertTrue(validationCodes(for: essence).contains(.invalidInputHash))
    }

    func testValidatorRejectsBlankEvidenceCue() {
        let essence = makeEssence(evidenceCue: "  \n")
        let issues = DesignEssenceValidator.issues(in: essence)

        XCTAssertTrue(
            issues.contains {
                $0.code == .blankValue && $0.path == "summary.essence.evidence[0].cue"
            }
        )
    }

    func testValidatorRejectsInvalidPaletteHexAndDuplicateAxis() {
        let essence = makeEssence(paletteHex: "warm white", duplicateSemanticAxis: true)
        let codes = validationCodes(for: essence)

        XCTAssertTrue(codes.contains(.invalidPaletteColor))
        XCTAssertTrue(codes.contains(.duplicateSemanticAxis))
    }

    func testMeasuredPaletteRequiresToolDerivedMeasurement() {
        let essence = makeEssence(includePaletteMeasurement: false)

        XCTAssertTrue(
            validationCodes(for: essence).contains(.missingMeasurementForMeasuredClaim)
        )
    }

    func testValidatorRejectsInferredPaletteBasis() {
        let essence = makeEssence(
            paletteBasis: .inferred,
            includePaletteMeasurement: false
        )
        let issues = DesignEssenceValidator.issues(in: essence)

        XCTAssertTrue(
            issues.contains {
                $0.code == .invalidPaletteBasis
                    && $0.path == "observables.palette.basis"
            }
        )
    }

    func testObservedPaletteRequiresApproximationDisclosure() {
        let missingDisclosure = makeEssence(
            paletteBasis: .observed,
            includePaletteMeasurement: false
        )
        let unrelatedDisclosure = makeEssence(
            paletteBasis: .observed,
            includePaletteMeasurement: false,
            scopeLimitations: ["Visual hierarchy is approximate at small sizes."]
        )
        let disclosed = makeEssence(
            paletteBasis: .observed,
            includePaletteMeasurement: false,
            scopeLimitations: ["Palette hex values are visual approximations, not pixel samples."]
        )

        XCTAssertTrue(
            validationCodes(for: missingDisclosure)
                .contains(.missingPaletteApproximationDisclosure)
        )
        XCTAssertTrue(
            validationCodes(for: unrelatedDisclosure)
                .contains(.missingPaletteApproximationDisclosure)
        )
        XCTAssertFalse(
            validationCodes(for: disclosed)
                .contains(.missingPaletteApproximationDisclosure)
        )
        XCTAssertNoThrow(try DesignEssenceValidator.validate(disclosed))
    }

    private func validationCodes(
        for essence: DesignEssence
    ) -> Set<DesignEssenceValidationIssue.Code> {
        Set(DesignEssenceValidator.issues(in: essence).map(\.code))
    }

    private func makeEssence(
        schemaVersion: String = DesignEssence.currentSchemaVersion,
        summaryConfidence: Double = 0.9,
        semanticScore: Double = -0.7,
        evidenceAssetID: UUID? = nil,
        region: DesignEssence.Evidence.NormalizedRegion? = nil,
        includeSummaryEvidence: Bool = true,
        sourceKind: DesignEssence.Source.Kind = .image,
        projectID: Project.ID? = nil,
        referenceAssetIDs: [Inspiration.ID]? = nil,
        inputHash: String = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        includeProjectOnlyFields: Bool = false,
        evidenceCue: String = "Wide margins and a restrained type scale",
        paletteHex: String = "#F5F0E8",
        duplicateSemanticAxis: Bool = false,
        projectClusters: [DesignEssence.ProjectVariation.Cluster]? = nil,
        extractedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        paletteBasis: DesignEssence.ClaimBasis = .measured,
        includePaletteMeasurement: Bool = true,
        scopeLimitations: [String] = []
    ) -> DesignEssence {
        let evidence = DesignEssence.Evidence(
            assetID: evidenceAssetID ?? assetID,
            region: region ?? DesignEssence.Evidence.NormalizedRegion(
                x: 0.1,
                y: 0.1,
                width: 0.5,
                height: 0.4
            ),
            cue: evidenceCue
        )
        let paletteEvidence = DesignEssence.Evidence(
            assetID: evidenceAssetID ?? assetID,
            region: region ?? DesignEssence.Evidence.NormalizedRegion(
                x: 0.1,
                y: 0.1,
                width: 0.5,
                height: 0.4
            ),
            cue: evidenceCue,
            measurement: includePaletteMeasurement
                ? "Pixel sampler: sRGB values sampled from the source image"
                : nil
        )
        let inferredEvidence = includeSummaryEvidence ? [evidence] : []
        let references = (referenceAssetIDs ?? [assetID]).map {
            DesignEssence.Source.Reference(assetID: $0)
        }
        let coherence = includeProjectOnlyFields
            ? DesignEssence.Claim(
                value: 0.82,
                basis: .inferred,
                confidence: 0.8,
                evidence: [evidence]
            )
            : nil
        let projectVariation = includeProjectOnlyFields
            ? DesignEssence.ProjectVariation(
                commonCore: [
                    DesignEssence.Claim(
                        value: "Low-chroma surfaces",
                        basis: .inferred,
                        confidence: 0.81,
                        evidence: [evidence]
                    )
                ],
                clusters: projectClusters ?? []
            )
            : nil

        return DesignEssence(
            schemaVersion: schemaVersion,
            source: DesignEssence.Source(
                kind: sourceKind,
                projectID: projectID,
                references: references,
                inputHash: inputHash
            ),
            provenance: DesignEssence.Provenance(
                extractedAt: extractedAt,
                model: "fixture-model",
                pipelineVersion: "1"
            ),
            scope: DesignEssence.Scope(
                domain: .userInterface,
                analyzedRegions: ["whole image"],
                deliberatelyExcluded: ["product copy", "logos"],
                limitations: scopeLimitations
            ),
            summary: DesignEssence.Summary(
                essence: DesignEssence.Claim(
                    value: "Quiet editorial precision",
                    basis: .inferred,
                    confidence: summaryConfidence,
                    evidence: inferredEvidence
                ),
                coherence: coherence
            ),
            invariants: [
                DesignEssence.Invariant(
                    statement: DesignEssence.Claim(
                        value: "Preserve generous negative space",
                        basis: .inferred,
                        confidence: 0.86,
                        evidence: [evidence]
                    ),
                    importance: .primary
                )
            ],
            observables: DesignEssence.Observables(
                palette: DesignEssence.Claim(
                    value: DesignEssence.Palette(
                        colors: [
                            .init(hex: paletteHex, role: "canvas", coverage: 0.8),
                            .init(hex: "#22211F", role: "text", coverage: 0.2),
                        ],
                        temperature: "warm-neutral",
                        saturation: "low",
                        contrastStrategy: "dark text on a light canvas"
                    ),
                    basis: paletteBasis,
                    confidence: 0.94,
                    evidence: [paletteEvidence]
                )
            ),
            composition: DesignEssence.Composition(
                hierarchy: DesignEssence.Claim(
                    value: "One dominant typographic entry point",
                    basis: .observed,
                    confidence: 0.88,
                    evidence: [evidence]
                )
            ),
            semanticAxes: [
                DesignEssence.SemanticAxis(
                    axis: "ordered_expressive",
                    score: semanticScore,
                    confidence: 0.89,
                    evidence: [evidence]
                )
            ] + (duplicateSemanticAxis
                ? [
                    DesignEssence.SemanticAxis(
                        axis: "ordered_expressive",
                        score: 0.2,
                        confidence: 0.7,
                        evidence: [evidence]
                    )
                ]
                : []),
            cueEffects: [
                DesignEssence.CueEffect(
                    cues: [evidence],
                    likelyEffect: "Calm and deliberate",
                    confidence: 0.78,
                    context: "Contemporary consumer software"
                )
            ],
            projectVariation: projectVariation,
            directive: DesignEssence.Directive(
                mustPreserve: [
                    DesignEssence.Claim(
                        value: "Keep component chrome subordinate to content",
                        basis: .inferred,
                        confidence: 0.84,
                        evidence: [evidence]
                    )
                ]
            )
        )
    }
}
