# mood-agent study commands (API version 1)

The helper is bundled in mood. for Mac at
`/Applications/mood.app/Contents/Helpers/mood-agent`. It needs no running app and opens no
network listener. The finder accepts a helper only when its `--help` advertises
`study --project`, `suggest --project` and `reflect --project`.

Successful responses include `apiVersion: 1` and `ok: true`. Errors print
`{"apiVersion": 1, "ok": false, "error": {"code", "message"}}` to stdout and exit `2`. Treat
unknown fields as forward-compatible additions. Dates are ISO 8601.

`suggest` and `reflect` are the helper's only writes. They add **pending** proposals to a study
the user started; nothing else in the library changes. No command keeps, rejects, confirms or
corrects anything.

## Read a study

```sh
"$MOOD_AGENT" study --project <name-or-uuid> --pretty
```

```json
{
  "apiVersion": 1,
  "ok": true,
  "project": { "id": "…", "name": "2001", "inspirationCount": 3, "…": "…" },
  "study": {
    "subject": "2001: A Space Odyssey",
    "brief": "the coldness of the white",
    "startedAt": "2026-10-12T08:00:00Z",
    "stage": "explore",
    "items": [
      { "id": "…", "title": "…", "text": "…", "authorName": "…", "localImagePath": "/…/Media/….jpg", "imageURL": "https://…", "url": "https://…", "…": "…" }
    ],
    "suggestions": [
      {
        "id": "…",
        "url": "https://…",
        "canonicalURL": "https://…",
        "title": "…",
        "creator": "…",
        "sourceName": "…",
        "imageURL": "https://…",
        "rationale": "…",
        "basedOnInspirationIDs": ["…"],
        "suggestedAt": "…",
        "status": "rejected",
        "reason": "too warm, I want the cold version",
        "decidedAt": "…",
        "savedInspirationID": null
      }
    ],
    "reflections": [
      {
        "id": "…",
        "statement": "…",
        "inspirationIDs": ["…"],
        "rejectedSuggestionIDs": ["…"],
        "proposedAt": "…",
        "status": "corrected",
        "correction": "the user's wording",
        "respondedAt": "…"
      }
    ]
  }
}
```

- `items` is everything on the study's moodboard: the user's seeds plus kept suggestions.
  A kept suggestion's `savedInspirationID` is its item.
- `status` is `pending`, `kept` or `rejected` for suggestions, and `pending`, `confirmed`,
  `corrected` or `dismissed` for reflections. For a corrected reflection, the user's
  `correction` replaces the `statement`.
- `stage` is `seed` (fewer than three items), `explore`, `reflect` (six or more verdicts, or
  patterns already proposed) or `distill` (at least one confirmed or corrected pattern).
- `not_a_study` means the project exists but the user hasn't started a study on it.

## Propose sources

```sh
"$MOOD_AGENT" suggest --project <name-or-uuid> --file <path> --pretty
```

The file holds `{"suggestions": [ … ]}` with 1 to 50 entries:

| Field | Required | Notes |
|---|---|---|
| `url` | yes | http(s) page that credits the work |
| `title` | yes | |
| `creator` | yes | who made the work |
| `rationale` | yes | why it relates to the user's seeds and notes |
| `sourceName` | no | archive, publisher, Are.na, … |
| `imageURL` | no | http(s) image of the work, shown as a thumbnail |
| `basedOnInspirationIDs` | no | item IDs from this study |

The response lists `added` suggestions and `skipped` entries `{url, reason}`. Each entry is
checked on its own, so one bad entry doesn't block the batch. Skip reasons:

| Reason | Meaning |
|---|---|
| `invalid_url` | `url` or `imageURL` is not an http(s) URL |
| `generated_imagery` | `url` or `imageURL` is on a known AI image generator |
| `missing_title`, `missing_creator`, `missing_rationale` | required text is empty |
| `unknown_basis` | a `basedOnInspirationIDs` entry is not an item in this study |
| `previously_rejected` | the user rejected this URL before |
| `already_saved` | the URL is already on the study's moodboard |
| `already_suggested` | the URL is already waiting for a verdict |
| `duplicate_in_batch` | the same URL appears earlier in the file |

URLs are compared after mood.'s canonicalization (no `www.`, no tracking parameters).

## Propose patterns

```sh
"$MOOD_AGENT" reflect --project <name-or-uuid> --file <path> --pretty
```

The file holds `{"reflections": [ … ]}` with 1 to 50 entries of `statement`,
`inspirationIDs` and `rejectedSuggestionIDs`. Each pattern must cite at least one study item
or rejected suggestion; `inspirationIDs` must be items in the study and
`rejectedSuggestionIDs` must be suggestions the user rejected. Unlike `suggest`, an invalid
pattern fails the whole call with `invalid_study_input`, and nothing is added.

## Errors

| Code | Meaning |
|---|---|
| `invalid_arguments` | wrong flags |
| `project_not_found`, `ambiguous_project` | resolve the project with `projects` first |
| `not_a_study` | the user hasn't started a study on this project |
| `invalid_study_input` | unreadable file, wrong JSON shape, empty or oversized batch, or an invalid pattern |
| `storage_error` | the library couldn't be read or written |
