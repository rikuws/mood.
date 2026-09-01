---
name: mood-distill
description: Extract an evidence-grounded, content-minimized design essence from a mood. project, one saved mood. item, or a single image. Use for visual style, expressed taste, design intent, creative direction, portable design rules, or applying references to later design work.
compatibility: Requires image inspection. Saved mood. sources require macOS with mood.app installed and local library access. Extraction is read-only.
metadata:
  version: "2.0"
  argument-hint: "<project-name-or-uuid | item-uuid | image-path>"
---

# Distill design essence with mood.

Turn visual references into portable creative direction. Treat the result as an artifact
profile: what the selection visibly expresses. Do not claim to recover a creator's hidden
intent or a person's complete, stable taste.

Keep the workflow read-only. Never write analysis into the mood. library, download remote
media into its `Media/` directory, or add an inference service or API credential.

## Prepare the helper

Read [references/agent-api.md](references/agent-api.md), then run the finder once from this
skill directory before choosing a source branch. Keep its result for every later command:

```sh
MOOD_AGENT="$(./scripts/find-mood-agent.sh)"
export MOOD_AGENT
```

The finder accepts only a helper whose `--help` advertises both `inspiration --id` and
`validate-essence --file`. Do not bypass its incompatibility error: a helper that only
supports project listing is too old for this skill and mood. must be upgraded.

For a mood. project or saved item, stop if preparation fails and report the finder's error.
For an arbitrary image, analysis may continue without the helper, but canonical validation
cannot be claimed; disclose that limitation in the result.

## Resolve the source

Choose one source shape from the user's request:

- **Project:** call `projects --pretty`, resolve the user's wording, then call
  `inspirations --project <uuid> --pretty`. Use the UUID after resolution.
- **Saved item:** call `inspiration --id <uuid> --pretty` only when the exact item UUID was
  supplied or is already known from a project response. A General item needs a separately
  supplied or previously known UUID; do not invent title-based discovery.
- **Single image:** inspect the user attachment or explicit local path directly. It does not
  need to be saved in mood.

For a saved record, prefer a readable `localImagePath`. Use `imageURL` only when local media
is absent and remote retrieval is available within the user's request. Never infer visual
properties from title, note, author, or URL when the image itself could not be inspected.

If the project is empty, say so and stop. Text-only items may inform voice and provenance,
but they are not visual evidence. Report every skipped or unavailable visual.

## Consolidate references

Deduplicate identical local media by content hash and identical remote URLs. Also cluster
visual near-duplicates such as resized, recompressed, or tightly cropped copies. Analyze one
representative per duplicate cluster while preserving every original mood. item ID in source
provenance. Exact and near-duplicates never increase evidence counts, confidence, coherence,
or apparent support.

Inspect every unique available visual. When a large set must be handled in batches, retain
per-asset evidence before synthesis and disclose every uninspected reference. A remote fallback
must be a public HTTPS image response with bounded payload and no credentials or cookies.

## Analyze in three passes

Read [references/design-essence-v1.md](references/design-essence-v1.md) before producing a
result.

1. **Evidence:** record only observable palette behavior, typography, geometry, spacing,
   surfaces, imagery treatment, hierarchy, alignment, grouping, rhythm, balance, and reading
   path. Do not infer mood, quality, audience, or intent yet.
2. **Abstraction:** map observations to semantic axes, signature tensions, likely effects, and
   candidate invariants. Every inferred claim cites asset IDs and visible cues. For projects,
   separate common core, accepted variation, contradictions, and clusters instead of averaging
   incompatible directions.
3. **Directive:** test candidate invariants against changed copy, subject matter, workflow,
   and branding. Sort portable rules into `mustPreserve`, `prefer`, `mayVary`, and
   `mustAvoid`.

Exclude exact copy, logos, brand identity, named products, people, artist identity, and
specific subject matter unless one is necessary to explain a compositional relationship. Do
not emit generator-specific prompt jargon. Record accessibility or legibility problems as
limitations, never as directives.

Palette hex values estimated by eye are `observed`, not `measured`, and require an explicit
approximation limitation. Use `measured` only after a pixel or color-analysis tool produced
the values, with that measurement recorded in evidence.

For one image, say "expressed in this image," lower confidence for inferred semantics, and
omit project coherence. For a project, describe the expressed direction of this selection,
not stable personal taste.

## Validate and deliver

Create a canonical `DesignEssence` 1.0 object on every run. Use a content hash for one local
image. For a project, derive `inputHash` from ordered source tuples containing asset ID, role,
and local content hash or canonical remote-image URL.

Write the candidate only to a temporary file outside the mood. library, then validate it:

```sh
"$MOOD_AGENT" validate-essence --file <temporary-json-path> --pretty
```

Correct every issue before delivery. Validation never persists the essence or changes the
library. If an arbitrary image is analyzed and the installed helper is unavailable, report
that canonical validation could not run rather than claiming it passed.

Lead with the concise reading described in
[references/direction-template.md](references/direction-template.md). Keep the canonical
object internal for an ordinary prose request. Include full JSON when the user asks for
structured output, export, machine use, or downstream generation context.

Always disclose source accounting with these exact labels:

- `inspected`: unique visuals actually analyzed after duplicate consolidation;
- `duplicatesRemoved`: exact or perceptual near-duplicate references discounted;
- `remoteOnlyInspected`: the subset inspected remotely because no local media was available;
- `skipped`: references that could not be inspected.

If the user asked to make or change something in this taste, distill first and then do that
work from the validated direction. Never bolt mood.'s own product chrome onto unrelated work
unless the references themselves support it.
