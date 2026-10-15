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
  context menu (**Open Study** once it is one). When a study is open, **Moodboard | Study
  board** at the top of the canvas switches between its moodboard and its study board.
- **iOS:** **+ → New visual study**, or **Start a study on …** for the selected project. The
  same **Moodboard | Study board** switch sits under the project bar.

## The study board

The study board shows everything the study turned up at once, on the same masonry canvas as
the moodboard: every source an agent found, as the card it would become if kept, and every
pattern it reflected back, as a serif quotation. It reads like a taste board the agent fills
for you, from real, credited work.

- **At a glance.** The subject and brief, what to do next, the agent's controls, and filters
  with counts: **All**, **To judge**, **Kept**, **Rejected**. Kept cards carry a small badge;
  rejected ones step back in grayscale. Pinch, or ⌘+ and ⌘−, to see more or fewer at once.
  Search filters the board by title, creator, source, reasoning, and your own reasons.
- **Up close.** Click a card (tap on iOS) for its close look: the whole image, credit and
  source link, why the agent thinks it relates to your seeds (with those seeds), and your
  verdict with a reason. ⌘[ and ⌘] step through the board; after a verdict the close look moves
  on to the next thing to judge. On the Mac, hovering a find offers **Keep** and **Reject**
  right on the card; context menus have them everywhere.
- **Live.** While the agent works, its finds appear on the board as soon as their credit
  checks out, so you can judge the first ones while it keeps looking. Grain tiles at the end
  hold the slots it's still filling, and each new find develops into place out of noise, like
  a diffusion model resolving an image (a plain fade with Reduce Motion).

The board is ordered by arrival, so new finds land at the end and nothing you're looking at
moves. Judging changes how a card looks, not where it sits.

## Flow

| Stage | When | What the person does |
|---|---|---|
| `seed` | fewer than 3 items | Add things they already love, with a note on what they love about each. |
| `explore` | 3+ items | Keep or reject suggested sources, and say why. |
| `reflect` | 6+ verdicts, or patterns proposed | Confirm, correct, or dismiss the patterns reflected back. |
| `distill` | a pattern confirmed or corrected | Run `mood-distill` on the study. |

Stages only guide the board's prompt. Nothing is locked behind one.

Finding sources and reflecting patterns run in a coding agent the person connects. The agent
follows the [`mood-study`](../skills/mood-study) skill: it reads the study with
`mood-agent study`, searches for real work, and adds it with `mood-agent suggest` (or proposes
patterns with `mood-agent reflect`). The study board shows each suggestion with its image,
credit, source, and the agent's reason, and the person keeps or rejects it.

### Connecting an agent (Mac)

There is nothing to set up if Claude Code or Codex is installed and signed in: mood. finds it
and uses it. Commands are looked up on the login shell's `PATH` plus common install folders
(`~/.local/bin`, `/opt/homebrew/bin`, …). Without an agent, the study board offers
**Get Claude Code** and **Check Again**. When both are installed, Claude Code is used; the
board's **Using …** menu switches between installed agents.

No agent gets access to the library. Before a run, mood. writes the study into a fresh scratch
folder as `study.json` (the same JSON `mood-agent study` prints), and copies each item's image
into `images/<item id>.<ext>`: the stored file, or a download of its image URL, since sandboxed
agents often have no network for commands. The agent follows the bundled `mood-study` skill
and saves each proposal the moment it's ready as its own file, `suggestions/01.json`,
`suggestions/02.json`, … (or `reflections/…`), each holding one entry in the
`suggest --file`/`reflect --file` format. mood. checks the folder every second and a half and
adds each new file through the same checks as `mood-agent` (credit, rationale, generator
hosts, past rejects), so finds reach the board while the agent keeps looking. A file that
isn't complete JSON yet is read again on the next pass; one that still isn't when the agent
exits, or that doesn't hold a proposal, is reported and the rest still count. A single
`suggestions.json` or `reflections.json` batch also works, from agents that write one at the
end. A run adds at most 50 proposals. So sandboxed agents work, and only mood. writes the
library.

How each one is started:

- **Claude Code:** `claude -p` with `--permission-mode acceptEdits` and
  `--allowedTools Read,Glob,Grep,WebSearch,WebFetch`. It can read the study and its images,
  search and open web pages, and write in its scratch folder. It can't run other programs or
  write anywhere else; those need an approval nobody can give in this unattended run.
- **Codex:** `codex exec --sandbox workspace-write` with live web search. Its sandbox has no
  network for commands and only lets it write to the scratch folder.
- **Other command** (Settings → Study Agent): any executable plus an argument line with the
  placeholders `{prompt}`, `{moodAgent}`, `{skill}`, `{project}` and `{workdir}`. Without
  `{prompt}`, the prompt goes to the agent's standard input. The same values are also in the
  `MOOD_AGENT`, `MOOD_STUDY_SKILL`, `MOOD_STUDY_PROJECT`, `MOOD_STUDY_TASK`,
  `MOOD_STUDY_PROMPT` and `MOOD_LIBRARY_DIRECTORY` environment variables. Its permissions are
  the agent's own to configure.

The study board's **Find sources** (from the `explore` stage) and **Reflect patterns** (after
the first verdict) buttons start the agent with a prompt that points at the `mood-study` skill
bundled inside mood.app (`Contents/Resources/Skills/mood-study`), so nothing needs to be
installed besides the agent. While it runs, the board says how much it has found so far,
offers its **Output** and **Stop**, and shows each find as it's added. When it finishes, the
board says what was added and skipped, and the library syncs. Stopping or a failed run keeps
what was already found. Runs continue if you switch to the moodboard or another project.
**Copy prompt for another agent** still works for agents mood. doesn't start; those use
`mood-agent` directly.

On iOS, the board copies a ready prompt for an agent on another machine, and finds from a Mac
run appear when the library syncs (pull to refresh).

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
