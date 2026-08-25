---
name: mood-distill
description: Distill the mood, style, and creative direction from a mood. moodboard project using the local pinax-agent library. Use when the user wants to extract visual taste, palette, atmosphere, or direction from a moodboard, apply a mood. project to design or writing work, or asks to distill, capture the vibe, or turn saved references into portable creative context.
compatibility: Requires macOS with mood.app installed (bundled pinax-agent) and local read access to the mood. library. Does not mutate the library.
metadata:
  version: "1.0"
  argument-hint: "<project-name-or-uuid>"
---

# Distill a mood. project

Turn a curated mood. project into portable creative direction. mood. stores imagery, text, authorship, and source context; this skill reads that collection and synthesizes a brief a person or agent can apply. Distillation is a reading task—the CLI only fetches. Never write to the library.

The collection is open-ended. UI direction is one useful output, alongside brand, spatial, editorial, styling, travel, and other visual direction. Do not collapse a board into a generic UI kit, Tailwind palette, or Inter/SF Pro ramp unless those things are actually in the references.

## When to use

- Distill, extract, or summarize the mood, style, or vibe of a mood. project
- Apply a named moodboard to design, copy, spatial, or image-generation work
- Inspect what a mood. project contains before making something in that taste

If the user only asked to distill, stop after the brief. If they asked to make or change something in that taste, distill first, then do the work from the brief.

## Requirements

This is local and macOS-only. Cloud agents cannot see the user's mood. library.

1. Locate `pinax-agent` by running [scripts/find-pinax-agent.sh](scripts/find-pinax-agent.sh) from this skill directory. If the script is missing, try `/Applications/mood.app/Contents/Helpers/pinax-agent`, then `$HOME/Applications/mood.app/Contents/Helpers/pinax-agent`. `PINAX_AGENT` overrides the path.
2. Confirm the helper runs. A signed install reads the App Group library. An unsigned Debug helper falls back to `~/Library/Application Support/Pinax` unless `PINAX_STORAGE_DIRECTORY` is set.
3. Read [references/agent-api.md](references/agent-api.md) if you need response shapes or error codes.

## Resolve the project

If the user named a project, use that name or UUID. If they did not:

1. Run `"$PINAX_AGENT" projects --pretty`.
2. If there is exactly one project, use it.
3. If several projects exist, match against the user's wording (trim, case, and diacritics are ignored by the CLI). Prefer calling `inspirations` with the returned UUID.
4. If nothing matches or several names collide, list the project names and counts. Do not invent a board.

General is the unsorted catch-all and is not a project. Distill a curated project, not General, unless the user explicitly insists after seeing the project list.

## Fetch the board

```sh
"$PINAX_AGENT" inspirations --project "<name-or-uuid>" --pretty
```

Reject the payload if `ok` is not true or `apiVersion` is not `1`. On `project_not_found` or `ambiguous_project`, call `projects` and resolve again.

If the project has no inspirations, say so and stop. Do not fabricate a mood.

## Look at the references

Read the saved items. Imagery, quotations, source, author, and notes carry the meaning; titles alone are not the board.

1. Scan every item's `title`, `text`, `authorName`, `authorHandle`, `source`, and `url`.
2. Look at images. Prefer `localImagePath` (absolute path; use a local file-read tool). If that path is missing, try `imageURL`. If neither exists, treat the item as a text-only reference—those are first-class, not failures.
3. If more than 24 items have images, look at the 24 newest (the API is already newest-first) and note the truncation. Still use titles and notes from the rest.
4. Keep provenance attached to what you claim. Do not strip authors or sources.

## Distill

Read [references/direction-template.md](references/direction-template.md) and write the brief in that shape.

Rules:

- Observe before prescribing. Every color, material, type move, and constraint must be grounded in what you saw.
- Preserve tension. If the board mixes quiet rooms with sharp type, say that; do not average it into "minimal."
- Stay in the board's domain. A fashion board is not a dashboard. A landscape board is not a component library.
- Do not copy saved text verbatim into generated product copy except as a cited quotation.
- Do not mutate mood., upload the library, or rewrite `library.json`.

## Apply

When the user wants work done in this taste, keep the brief in mind and execute. Match atmosphere, palette, material, composition, and voice. Do not bolt the mood. product UI (white card mats, stepped caption cutouts, inverted-ink chrome) onto unrelated work unless the board itself is about mood.

Write a file only when the user asked to save the brief.
