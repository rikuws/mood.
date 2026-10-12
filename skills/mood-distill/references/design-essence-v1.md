# DesignEssence 1.0 contract

Use this contract for both a single image and a mood. project. It separates observable style, inferred meaning, and executable direction. The canonical implementation lives in `Shared/DesignEssence.swift`.

## Shared rules

- `schemaVersion` must be `1.0`.
- Confidence values are finite numbers from `0` to `1`.
- Semantic-axis scores are finite numbers from `-1` (the left pole) to `1` (the right pole).
- Every evidence `assetID` must occur in `source.references`.
- Evidence cites the item's image unless it sets `kind`. Use `kind: "text"`, `"title"`, or `"note"` to cite the user's own words, and copy the words the claim relies on into `quote` whenever you can. Textual evidence takes no `region`; image evidence takes no `quote`. A `note` citation points at the item's `note`, the user's own reason for keeping or rejecting it; prefer it over `text` when the claim rests on why the user chose the item.
- A textual citation is a reason the user gave, not a visual observation. It can support an inferred claim; it never replaces looking at the image for palette, typography, geometry, or composition.
- Evidence regions use normalized coordinates. `x`, `y`, `width`, and `height` are each within `0...1`; width and height are positive; the rectangle must stay within the image.
- Every claim whose basis is `inferred` must include visible evidence.
- Use `measured` only for tool-derived values, `observed` for directly visible properties, and `inferred` for meanings, effects, or intent-like abstractions.
- A palette hex estimated visually is `observed` and requires a limitation stating that the value is approximate. A palette may be `measured` only after a pixel or color-analysis tool produced its values, with the measurement recorded in evidence.
- A project source requires `projectID`. A single-image source omits it and has exactly one reference. For an arbitrary image outside mood., create a synthetic UUID used only as extraction provenance.
- `summary.coherence` and `projectVariation` apply only to project sources.

## Minimal validator-valid instance

This is a concrete single-image `DesignEssence` 1.0 instance, not pseudocode. Optional sections may contain more evidence and detail, but emitted JSON must remain valid against `Shared/DesignEssence.swift`.

```json
{
  "schemaVersion": "1.0",
  "source": {
    "kind": "image",
    "references": [
      {
        "assetID": "11111111-1111-1111-1111-111111111111",
        "role": "positive"
      }
    ],
    "inputHash": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  },
  "provenance": {
    "extractedAt": "2026-08-31T08:00:00Z",
    "model": "agent-multimodal",
    "pipelineVersion": "mood-distill/2.0"
  },
  "scope": {
    "domain": "ui",
    "analyzedRegions": ["whole image"],
    "deliberatelyExcluded": ["exact copy", "logos", "subject matter", "brand identity"],
    "limitations": []
  },
  "summary": {
    "essence": {
      "value": "A concise content-independent visual direction.",
      "basis": "inferred",
      "confidence": 0.8,
      "evidence": [
        {
          "assetID": "11111111-1111-1111-1111-111111111111",
          "cue": "Wide margins, a restrained type scale, and low-chroma surfaces are directly visible."
        }
      ]
    },
    "signatureTensions": []
  },
  "invariants": [],
  "observables": {},
  "composition": {},
  "semanticAxes": [],
  "cueEffects": [],
  "directive": {
    "mustPreserve": [],
    "prefer": [],
    "mayVary": [],
    "mustAvoid": []
  }
}
```

Omit optional keys rather than writing `null` when that makes the payload clearer; decoding accepts absent optional values. Validate every internally created instance with `mood-agent validate-essence --file <path> [--pretty]` before delivery, whether or not full JSON will be shown to the user.

Textual evidence looks like this:

```json
{
  "assetID": "11111111-1111-1111-1111-111111111111",
  "kind": "text",
  "quote": "kept for the quiet spacing",
  "cue": "The user names spacing as the reason this reference was kept."
}
```

## Core semantic axes

Use only axes that materially describe the references. Keep this shared vocabulary comparable across extractions and add domain-specific axes sparingly.

- `ordered_expressive`
- `minimal_ornate`
- `sparse_dense`
- `warm_cool`
- `soft_hard`
- `muted_vivid`
- `geometric_organic`
- `flat_volumetric`
- `restrained_playful`
- `familiar_novel`
- `polished_raw`
- `calm_energetic`

## Project synthesis

Treat unlabeled project references as positive. If the user identifies near-misses or negatives, record those roles and use them contrastively. Discount exact matches and visual or perceptual near-duplicates, including resized, recompressed, and tightly cropped copies, before treating repeated presence as evidence. Duplicate references remain in source provenance but never increase confidence, coherence, evidence counts, or apparent support.

Do not force one essence when the project is internally inconsistent. Lower coherence, record contradictions, and return clusters whose `assetIDs` partition the competing directions. `commonCore` contains only properties supported across the relevant positive references; one-off traits belong in accepted variation or a cluster.
