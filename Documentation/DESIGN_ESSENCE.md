# Design essence

mood. can turn a single visual reference or a project into portable creative direction through its `mood-distill` agent skill. The extraction is evidence-grounded and content-minimized: it describes observable visual tokens, compositional rules, semantic effects, invariants, permissible variation, and explicit generation constraints.

The native app remains local-first and does not embed a model provider, API key, or inference service. Instead:

1. `mood-agent` reads the same coordinated library as the UI and exposes project items or one exact saved item as versioned JSON.
2. A multimodal agent inspects the referenced local media, falling back to a remote preview only when local media is absent and remote retrieval is available.
3. The `mood-distill` skill separates evidence, abstraction, and directive generation, then produces the canonical `DesignEssence` 1.0 shape defined in `Shared/DesignEssence.swift`.

This boundary keeps extraction read-only. Results are never written into `library.json` or CloudKit, and remote-only images are not downloaded into the library's `Media/` directory. A project essence is saved, as a separate file, only when the user asks (see "Saved essences").

## Sources

For a project, resolve the project and fetch all of its references:

```sh
/Applications/mood.app/Contents/Helpers/mood-agent projects --pretty
/Applications/mood.app/Contents/Helpers/mood-agent \
  inspirations --project <project-uuid> --pretty
```

For one saved item, use an exact UUID supplied separately or already known from a previous
result:

```sh
/Applications/mood.app/Contents/Helpers/mood-agent \
  inspiration --id <item-uuid> --pretty
```

Project inspiration responses expose their item UUIDs. General items are not discoverable
by title or description through the current API, so a General item requires a separately
supplied or previously known UUID.

An arbitrary user-provided image does not need to enter the mood. library. The skill analyzes the attachment or explicit local path directly.

Before synthesis, exact matches are removed by local content hash or identical remote URL,
then resized, recompressed, cropped, and other perceptual near-duplicates are clustered.
Duplicate references remain in provenance but cannot increase confidence, coherence,
evidence counts, or apparent support.

## What the result means

`DesignEssence` is an artifact profile. For one image it describes the direction expressed in that image; it does not claim to know the creator's hidden intent or a person's stable taste. For a project it describes the expressed direction of that selection, including contradictions and clusters when the references do not support one coherent style.

The canonical result contains:

- source IDs, roles, input fingerprint, model, pipeline version, exclusions, and limitations;
- evidence-linked observables for palette, typography, geometry, spacing, surfaces, imagery, and composition;
- confidence-bearing semantic axes and cue-to-effect reasoning;
- signature tensions and invariants that survive changed copy, subject matter, workflow, and branding;
- project common core, accepted variation, contradictions, and optional clusters;
- `mustPreserve`, `prefer`, `mayVary`, and `mustAvoid` directives.

Exact copy, logos, brand identity, named people or products, artist identity, and incidental subject matter are excluded by default. Accessibility or legibility problems can be recorded as limitations but are never promoted into portable directives.

Evidence cites an item's image by default. It can instead cite the user's own words with `kind` (`title`, `text`, or `note`), ideally with the exact `quote`, so a rule can point at "the user said this" rather than a model's paraphrase. Textual evidence takes no region. This is the same `kind` marker the `mood-pack` skill reads. Today the note a user types in the item editor is stored in `text`; `note` is reserved for the separate per-item note being added to the library and is rejected by `save-essence` until it exists. These fields are optional additions, so the schema stays 1.0 and earlier documents remain valid.

Palette hex values estimated visually are marked `observed` and accompanied by a limitation
that they are approximate. `measured` is reserved for values produced by pixel or color-analysis
tools, with the measurement recorded in evidence.

The skill creates the canonical object internally on every extraction. For an ordinary request
it presents the useful prose reading without dumping the object; full JSON is emitted only for
structured output, export, downstream generation context, or other machine use. Every delivery
uses the exact accounting labels `inspected`, `duplicatesRemoved`, `remoteOnlyInspected`, and
`skipped`.

Before delivery, generated JSON is checked without modifying the library:

```sh
/Applications/mood.app/Contents/Helpers/mood-agent \
  validate-essence --file <path> --pretty
```

See [AGENT_API.md](AGENT_API.md) for the success envelope and `invalid_essence` error.

## Saved essences

`mood-agent save-essence --file <path>` stores a validated project essence as an append-only revision at `Essences/<project-uuid>/<sequence>-<fingerprint>.json`, beside `library.json` and never inside it. Before writing, it checks that every reference is a saved item in that project and that every quote appears in the cited item, so a saved essence can only trace back to work the user chose and words the user wrote.

The earlier open questions are answered narrowly:

- **Revision history:** each save is a new immutable file; the folder is the history. Nothing is overwritten or deleted.
- **Staleness:** `mood-agent essence --project <ref>` returns the latest saved revision with the items added, removed, or changed since. Each revision records a content fingerprint of its source items, so an edit that syncs in late from another device with an older timestamp still counts. Staleness is reported, never acted on; re-distilling is the user's call.
- **User edits:** a correction is a new revision, not an edit in place, and the most recently saved revision is the latest.
- **CloudKit:** essences are local to the Mac for now and are not synced, which avoids merging generated analysis across devices.
- **Model provenance:** each revision keeps its own `provenance.model` and `pipelineVersion`.

There is no native UI for saved essences yet. Deleting a project leaves its `Essences/` folder in place.
