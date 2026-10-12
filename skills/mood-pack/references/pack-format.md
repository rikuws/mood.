# mood. pack format (mood-pack/1)

```text
<pack>/
  GUI.md                      DESIGN.md-compatible single source of truth
  SETUP.md                    prompt the user pastes into any coding agent
  pack.json                   ID → sources map, dropped guidelines, essence provenance
  references/
    light-dark.md             only the modes the references show
    components.md             tokens applied to containers, text, layout, images
    composition.md            hierarchy, alignment, reading path, common core
    sources.md                every cited item: link, author, role, the user's note
  skills/
    gui-build/SKILL.md        build new UI in this language
    gui-apply/SKILL.md        restyle existing UI to it
    gui-review/SKILL.md       find and fix inconsistencies
```

## GUI.md and DESIGN.md

`GUI.md` follows the DESIGN.md format (version `alpha`, `@google/design.md`): YAML front
matter with `name`, `description` and `colors`, then `##` sections in the canonical order
Overview, Colors, Typography, Layout, Elevation & Depth, Shapes, Components, Do's and
Don'ts. mood. adds Imagery, Limits and Open Questions, and Sources after them, which DESIGN.md
consumers preserve.

Only palette colors become tokens. A DesignEssence describes type, spacing and corners
qualitatively, so `typography`, `spacing`, `rounded` and `components` are listed under
`omitted` with the reason, rather than inventing values. `primary` is an alias added only
when the user picks one with `--primary`.

## Entries

| Prefix | Comes from | Lands in |
|---|---|---|
| `P` | `summary.essence`, `summary.signatureTensions`, `invariants` | GUI.md Overview |
| `T` | `observables.*` | GUI.md token sections, light-dark.md, components.md |
| `R` | `directive.mustPreserve / prefer / mayVary / mustAvoid` | GUI.md Do's and Don'ts |
| `C` | `composition.*`, `projectVariation.commonCore / acceptedVariations` | composition.md |

Each guideline in GUI.md is a bullet `- [ID] text` with two sub-bullets:

- **Why:** the user's cited notes first ("Your words on S1 …"), then the observed cues,
  labelled by source and marked when the source was rejected.
- **From:** source IDs and titles, the claim's basis and confidence.

`summary.coherence`, `semanticAxes` and `cueEffects` are analysis, not guidance, and are not
exported. `projectVariation.contradictions` become open questions.

## Text evidence

Evidence `kind` is `image` (the default when absent), `note`, `text` or `title`, matching
`Evidence.kind` in `Shared/DesignEssence.swift`. A `note`, `text` or `title` citation resolves only when the item
has that field, and when the evidence carries a `quote`, the quote must appear in that field
(whitespace and case ignored). Notes are quoted in the Why line as the user's words; `text`
and `title` are quoted as text saved with the reference, since captured post text is not
necessarily the user's own. Any other kind is unresolved.

## What check enforces

- every required file exists, and nothing but Markdown and JSON ships (no media);
- every top-level bullet in GUI.md and the three guidance references cites at least one
  kept ID, or starts with `- Not evidenced:` or `- Open question:`;
- no file cites a dropped or unknown ID;
- every kept `P`, `T` and `R` entry appears in GUI.md;
- every kept entry has sources, and every source is listed in sources.md;
- GUI.md and each skill have front matter in the quoted YAML subset the renderer writes,
  and each skill's `name` matches its folder.

Prose paragraphs are framing only; guidance goes in bullets so it can be checked.

Saved titles, notes, authors, links and essence text are collapsed to one line and have
`` ` [ ] < > | \ `` escaped before they reach Markdown, so captured metadata can never start
its own bullet or heading or forge an entry ID. Background roles are matched as whole words
(`background`, `surface`, `canvas`, …) and roles with foreground words (`foreground`, `text`,
`ink`, `on-surface`) never evidence a mode.
