# Guided visual studies

A visual study is how mood. helps someone explore a subject ("I want to do a visual study on
*2001: A Space Odyssey*") and turn their reactions into taste data. It follows
[issue #7](https://github.com/rikuws/mood./issues/7): the person seeds it, real sources are
suggested, the person judges each one and says why, patterns are reflected back for the person
to confirm, and the result feeds `mood-distill`.

AI is a research assistant here. It finds real, credited work and notices patterns. It never
generates imagery and never decides what belongs in the study.

## A study is a project with a guided start

A study is an ordinary project with an optional `study` record. Capture, search, sync, the
agent API and `mood-distill` keep working on it unchanged, and any existing project can become
a study, with its items as the seeds.

- **Mac:** **More → New Visual Study…** in the sidebar, or **Start a Study…** in a project's
  context menu. When a study is open, the **Study** button above the moodboard opens the study
  panel.
- **iOS:** **+ → New visual study**, or **Start a study on …** for the selected project. The
  **Study** button in the toolbar opens the panel.

## Flow

| Stage | When | What the person does |
|---|---|---|
| `seed` | fewer than 3 items | Add things they already love, with a note on what they love about each. |
| `explore` | 3+ items | Keep or reject suggested sources, and say why. |
| `reflect` | 6+ verdicts, or patterns proposed | Confirm, correct, or dismiss the patterns reflected back. |
| `distill` | a pattern confirmed or corrected | Run `mood-distill` on the study. |

Stages only guide the panel's prompt. Nothing is locked behind one.

Finding sources runs in the person's coding agent with the
[`mood-study`](../skills/mood-study) skill: the study panel copies a ready prompt. The agent
reads the study with `mood-agent study`, searches for real work, and adds it with
`mood-agent suggest`. The app shows each suggestion with its thumbnail, credit, source, and the
agent's reason, and the person keeps or rejects it.

## What is stored

All of it lives in `Project.study`, an optional key in `library.json` (schema version 1). It
syncs with the project record. When two devices change the same study, suggestions and
reflections merge by ID rather than by the project's last write, so decisions made on
different devices all survive. For the same suggestion, a keep wins, then any decision over
pending, then the later decision.

- `subject`, `brief`: the person's own framing.
- `suggestions[]`: every proposed source with `url`, `title`, `creator`, `sourceName`,
  `imageURL`, the agent's `rationale`, the study items it was `basedOn`, and the person's
  `status` (`pending`, `kept`, `rejected`), `reason` and `decidedAt`.
  - **Keep** saves the source to the study's moodboard as a normal item
    (`savedInspirationID`). If the URL was already saved elsewhere in the library, that item
    moves into the study instead of being duplicated, the same as an explicit capture. The
    item's `verdict` becomes `keep`, and the reason becomes its `note` unless the item
    already has one, so essences can cite the person's own words.
  - **Reject** keeps the suggestion in the study with its reason. Rejects are taste data:
    they are shown to the agent, can be cited by patterns, and the same URL is never proposed
    again. A reject can be reconsidered and kept later.
- `reflections[]`: patterns with the study items and rejected suggestions they cite, and the
  person's response (`confirmed`, `corrected` with their own wording, or `dismissed`).

## Real sources only

The storage layer enforces what it can:

- every suggestion needs an http(s) page, a title, a named creator, and a rationale;
- pages and images on known AI image generators (`StudySourcePolicy`) are refused;
- `basedOn` and pattern citations must point at items and rejects in the same study;
- rejected, already pending, and already saved URLs are refused.

What it can't check, such as whether a credited page really shows real work, is the skill's
job and, finally, the person's: nothing reaches the moodboard until they keep it.

## Not yet

- `mood-distill` doesn't yet read a study's rejected suggestions and confirmed patterns as
  evidence; it sees kept items with their notes and verdicts like any other project.
- Built-in providers (Are.na, Refero, Mobbin) are not wired in; the skill can use them when the
  person's agent has access.
