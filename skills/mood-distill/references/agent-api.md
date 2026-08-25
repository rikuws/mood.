# pinax-agent (version 1)

Read-only JSON CLI bundled in mood. for Mac. It does not require the app process
to be running, opens no network listener, and never mutates the library.

Default helper path:

```text
/Applications/mood.app/Contents/Helpers/pinax-agent
```

All successful responses include `apiVersion: 1` and `ok: true`. Invalid input,
missing projects, and storage failures print a structured error to stdout and
exit `2`. `--pretty` changes formatting only. Reject an `apiVersion` this skill
does not support. Treat unknown fields as forward-compatible additions.

## Discover projects

```sh
"$PINAX_AGENT" projects --pretty
```

```json
{
  "apiVersion": 1,
  "count": 1,
  "ok": true,
  "projects": [
    {
      "colorHex": "#B45F78",
      "createdAt": "2026-08-01T09:00:00Z",
      "id": "80D7254E-78FA-4BC3-95BF-0D721EF2B72D",
      "inspirationCount": 2,
      "name": "Website refresh",
      "updatedAt": "2026-08-01T09:00:00Z"
    }
  ]
}
```

## Fetch a project's inspirations

Pass a project name or UUID. Name matching trims whitespace and ignores case
and diacritics. Results are newest-first.

```sh
"$PINAX_AGENT" inspirations --project "Website refresh" --pretty
```

Each inspiration may include:

- `localImagePath` — absolute path to media stored by mood.; prefer this for vision
- `imageURL` — remote preview when no local file was kept
- `title`, `text`, `authorName`, `authorHandle`, `source`, `url`, `canonicalURL`

Either image field may be absent. Text-only items are first-class references.

## Errors

```json
{
  "apiVersion": 1,
  "error": {
    "code": "project_not_found",
    "message": "No mood. project matches \"Unknown\". Call `projects` to list available projects."
  },
  "ok": false
}
```

Stable codes: `invalid_arguments`, `project_not_found`, `ambiguous_project`,
`storage_error`, `internal_error`.

On `project_not_found` or `ambiguous_project`, call `projects` and resolve from
the returned names and UUIDs. Prefer the UUID for the `inspirations` call.
