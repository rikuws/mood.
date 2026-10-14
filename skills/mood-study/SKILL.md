---
name: mood-study
description: Find real, credited inspiration for a guided visual study in mood. and reflect the user's patterns back for them to confirm. Use when the user asks to find inspirations, explore a study subject, suggest references, or reflect on what they keep and reject in a mood. study.
compatibility: Requires macOS with mood.app installed, a study started in the mood. app, web search or another source of real published work, and image inspection.
metadata:
  version: "1.0"
  argument-hint: "<study-project-name-or-uuid>"
---

# Find inspirations for a mood. study

A study is a mood. project with a subject ("2001: A Space Odyssey") that the user seeded with
work they already love. Your job is research assistant, not curator: find real sources worth
the user's attention, explain why each one relates to *their* seeds and notes, and hand them
over for a verdict. Later, reflect the patterns you notice in their keeps and rejects so they
can confirm or correct them.

The user is the source of taste. You never decide what belongs in the study.

## Hard rules

- **Real work only.** Every suggestion is a published work by a named person or studio: a
  film still from a credited archive, a designer's own portfolio page, a museum collection
  record, a publisher's page, a type foundry specimen, an Are.na block that credits its
  source. Never generate, edit, upscale, or composite an image. Never suggest a page from an
  AI image generator or a gallery of generated images, and skip any page that looks
  generated or carries no credible credit. mood. refuses known generator hosts, but you are
  responsible for the rest.
- **Credit it.** `creator` names who made the work, not who reposted it. If you can't tell who
  made it, don't suggest it. Link `url` to the page that credits the work, not to a bare image
  file or a search result.
- **Tie it to the user.** `rationale` says which seed or note it relates to and how, in one or
  two plain sentences, as a hypothesis ("Same empty white floor as your pod-bay still, but
  lit from below"). Put the related item IDs in `basedOnInspirationIDs`.
- **Respect verdicts.** Read every past keep and reject and its reason before searching.
  Don't propose rejected URLs (mood. refuses them anyway), and steer away from what the
  user's reject reasons rule out.
- **Propose, never decide.** You can only add pending suggestions and pending patterns. Keeping,
  rejecting, confirming, and correcting happen in the mood. app. Never claim something was
  kept, and never edit the library any other way.

## Prepare the helper

When mood. starts you from its study panel, you don't use the helper at all: the study is
already in `./study.json` (the same JSON `study` prints), and you write your batch to
`./suggestions.json` or `./reflections.json` in the formats below. mood. checks the file and
adds what passes when you finish. Skip the rest of this section and the `suggest`/`reflect`
commands in that case.

Read [references/agent-api.md](references/agent-api.md), then run the finder once from this
skill directory and keep the result:

```sh
MOOD_AGENT="$(./scripts/find-mood-agent.sh)"
export MOOD_AGENT
```

If the finder fails, stop and report its error. A helper without the study commands is too
old; the user needs to update mood. for Mac.

## Read the study

Resolve the user's wording with `"$MOOD_AGENT" projects --pretty`, then:

```sh
"$MOOD_AGENT" study --project <uuid> --pretty
```

If the result is `not_a_study`, tell the user to start a study on that project in mood.
(project menu, **Start a Study…**) and stop. Don't start one yourself.

Look at every item's image (`localImagePath`, or `imageURL` when there is no local file).
Read titles, text, authors, each item's `note` and `verdict`, and every suggestion's `status`
and `reason`. Notes and reasons the user wrote are the most important input you have. Before searching, write down for yourself:

- what the seeds visibly share (light, palette, composition, material, type, era);
- what the user said they love, in their own words;
- what their rejects rule out.

If the study has fewer than three items, say that the study works best with a few seeds and
ask the user to add more first. You may still search if they want to go ahead.

## Find sources

Search for real work along a few distinct directions rather than many near-copies of one idea.
Good directions for a film or design subject: the work itself (credited stills, production
design), the people behind it (cinematographer, production designer, typographer), its
sources and influences, and later work that answers it. Prefer primary sources: archives,
the maker's own site, museums, publishers, foundries. Optional providers when available to
you: Are.na channels, or Refero and Mobbin for real shipped product screens. Use each only
through its own documented access.

For each candidate, open the page and confirm the credit before proposing it. Propose 6 to 10
at a time, spread across your directions, each one something the user could plausibly keep.
Include one or two that test a boundary (a variation the user hasn't seen yet), and say so in
the rationale.

Write the batch to a temporary JSON file outside the mood. library:

```json
{
  "suggestions": [
    {
      "url": "https://example-archive.org/collection/pod-bay-corridor",
      "title": "Discovery One pod bay, production still",
      "creator": "Geoffrey Unsworth (cinematography), Tony Masters (production design)",
      "sourceName": "Example Film Archive",
      "imageURL": "https://example-archive.org/images/pod-bay.jpg",
      "rationale": "Same flat white light and empty floor as your corridor seed, which you noted for 'how empty the frame is'.",
      "basedOnInspirationIDs": ["<seed uuid>"]
    }
  ]
}
```

Then add it:

```sh
"$MOOD_AGENT" suggest --project <uuid> --file <temporary-json-path> --pretty
```

Report `added` and every `skipped` entry with its reason. Fix and resubmit a skipped item only
when the fix is honest (a missing credit you can actually verify); never reword a refusal
away. Tell the user the sources are waiting in the study panel in mood.

## Reflect patterns back

Offer reflections only when the study has enough verdicts to say something (the study's
`stage` is `reflect`, or the user asks). Read the kept items and the rejected suggestions with
their reasons, look at the kept images again, and propose 2 to 4 patterns:

- one sentence each, concrete and checkable ("You keep one saturated accent against large
  neutral fields"), not a mood word ("You like calm");
- each cites the study items it was seen in (`inspirationIDs`) and, where it helps, the
  rejected suggestions that show the contrast (`rejectedSuggestionIDs`);
- prefer the user's own words where they already said it.

```json
{
  "reflections": [
    {
      "statement": "You keep frames that are mostly empty floor and wall, with the subject small and centered.",
      "inspirationIDs": ["<kept or seed uuid>", "<kept or seed uuid>"],
      "rejectedSuggestionIDs": ["<rejected suggestion uuid>"]
    }
  ]
}
```

```sh
"$MOOD_AGENT" reflect --project <uuid> --file <temporary-json-path> --pretty
```

Tell the user the patterns are waiting for them to confirm, correct, or dismiss in mood. A
pattern counts only once the user confirms or corrects it.

## Hand off

When the study has confirmed patterns (stage `distill`), suggest running `mood-distill` on the
study project. Confirmed and corrected patterns, keeps and rejects, and the user's reasons are
the evidence a design language should cite.

Clean up the temporary JSON files you wrote, except `suggestions.json` or `reflections.json`
when mood. started you: mood. reads those after you finish and removes the folder itself.
