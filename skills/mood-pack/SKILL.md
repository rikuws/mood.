---
name: mood-pack
description: Export a mood. design essence as an agent-ready GUI.md pack (DESIGN.md-compatible GUI.md, light/dark, component and composition references, sources, build/apply/review skills, SETUP.md). Every guideline traces to the user's saved references and notes; untraceable rules are dropped. Use when the user wants their mood. taste packaged for a coding agent.
compatibility: Requires python3 (ships with Xcode Command Line Tools). Saved essences and items require macOS with mood.app installed. Reads the mood. library; writes only the pack directory the user chose.
metadata:
  version: "1.0"
  argument-hint: "<project-name-or-uuid> [output-directory]"
---

# Package a mood. design language for coding agents

Turn one validated `DesignEssence` into a folder another coding agent can follow. The pack is
only as good as its trace: every guideline must point at references the user saved in mood.
and, where they wrote one, the user's own note. The user is the source of taste. This skill
packages their judgment; it never adds taste of its own.

Never write into the mood. library, copy media into the pack, or edit generated guideline
text to say something the essence does not.

## Prepare the helper

This skill ships beside `mood-distill` and reuses its finder. From this skill directory:

```sh
MOOD_AGENT="$(../mood-distill/scripts/find-mood-agent.sh)"
export MOOD_AGENT
```

Stop and report the finder's error if it fails. Then check whether the helper can return
saved essences: `"$MOOD_AGENT" --help` lists `essence --project` when it can.

## Get the essence

Resolve the project with `projects --pretty`, then use its UUID everywhere.

1. **Saved essence (preferred).** When the helper supports it, run
   `"$MOOD_AGENT" essence --project <uuid> --pretty` and take the latest essence. If the
   response marks it stale (the project's items changed since it was distilled), tell the
   user what changed and ask whether to re-distill first or package the stale one. Do not
   decide for them.
2. **Essence file.** Otherwise use a `DesignEssence` 1.0 JSON file the user supplies, or run
   `mood-distill` for the project first and use its validated output. Validate any file you
   did not just produce: `"$MOOD_AGENT" validate-essence --file <path> --pretty`.

A single-image essence for an image that is not saved in mood. cannot be packaged: none of its
rules can trace to a saved item. Say so and offer to distill from saved items instead.

Fetch the items the essence cites, into a temporary directory outside the library:

```sh
"$MOOD_AGENT" inspirations --project <uuid> --pretty > "$TMP/items.json"
```

For a saved-item essence, use `inspiration --id <uuid> --pretty` instead. Pass several
`--items` files when references span a project and General.

## Trace

```sh
python3 scripts/mood_pack.py trace \
  --essence <essence.json> --items "$TMP/items.json" --out "$TMP/trace.json"
```

`trace` gives every claim an ID (`P` principles, `T` tokens, `R` do's and don'ts, `C`
composition) and keeps it only when its evidence reaches a saved item, or an item's note for
evidence marked `"kind": "note"`. It drops a claim with:

- no evidence;
- evidence that cites no saved item (for example a deleted item or an unsaved image);
- only rejected or negative references as support, unless it is a Must avoid rule, where a
  reject is exactly the right support.

An item's `verdict` (`keep` or `reject`) overrides the essence's reference role. Project
contradictions become open questions, never rules.

## Confirm with the user

Before rendering, show the user what was kept and dropped, in their terms: the count of
guidelines kept, then each dropped one with its text and reason. Dropped rules are not
failures to hide; they show where the user's references or notes do not yet support a
direction. Offer the paths that keep the user in charge: save or note more references and
re-distill, or package as is. Never paraphrase a dropped rule back in.

DESIGN.md tools expect a `primary` color. If the essence has a palette, ask the user which
palette color is primary (list the token names the trace shows) and pass it as `--primary`.
If they don't choose, omit the flag; the pack stays valid without an alias.

## Render and check

Ask where the pack should go if the user has not said. Then:

```sh
python3 scripts/mood_pack.py render --trace "$TMP/trace.json" \
  --out <pack-dir> --name "<project name>" [--primary <token>] [--install-path design/gui]
python3 scripts/mood_pack.py check --pack <pack-dir>
```

`--install-path` is where `SETUP.md` tells the user to place the pack inside their own
codebase. Fix every problem `check` reports before delivery. If `npx` is available, also run
`npx @google/design.md lint <pack-dir>/GUI.md` and report any errors; errors there mean the
pack is not valid DESIGN.md.

See [references/pack-format.md](references/pack-format.md) for what each file holds and the
rules `check` enforces.

## Optional application notes

The rendered references are complete on their own. You may add application notes to
`references/components.md`, `references/light-dark.md` or `references/composition.md` only
when they apply an existing entry, and every added bullet must cite its ID, for example
`- [T2] Table headers use the heavier of the two weights.` Mark gaps with
`- Not evidenced:` and questions with `- Open question:`. Do not edit `GUI.md` by hand; change
the essence or the user's references and re-render. Run `check` again after any edit.

## Deliver

Tell the user where the pack is, how many guidelines it holds, what was dropped and why, and
that `SETUP.md` has the prompt to hand the pack to any coding agent.
