# mood-agent (version 1)

Read-only JSON CLI bundled in mood. for Mac. It does not require the app process
to be running, opens no network listener, and never mutates the library.

Default helper path:

```text
/Applications/mood.app/Contents/Helpers/mood-agent
```

The finder also checks user-local `mood.app` installs and the explicit legacy paths
`/Applications/Pinax.app/Contents/Helpers/mood-agent` and
`/Applications/Pinax.app/Contents/Helpers/pinax-agent`. A candidate is compatible only when
its `--help` advertises both `inspiration --id` and `validate-essence --file`; an older helper
is rejected with an upgrade error rather than used for a partial workflow.

All successful responses include `apiVersion: 1` and `ok: true`. Invalid input,
missing records, invalid essence documents, and storage failures print a structured
error to stdout and exit `2`. `--pretty` changes formatting only. Reject an
`apiVersion` this skill does not support. Treat unknown fields as forward-compatible
additions.

## Discover projects

```sh
"$MOOD_AGENT" projects --pretty
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
"$MOOD_AGENT" inspirations --project "Website refresh" --pretty
```

Each inspiration may include:

- `localImagePath` — absolute path to media stored by mood.; prefer this for vision
- `imageURL` — remote preview when no local file was kept
- `title`, `text`, `authorName`, `authorHandle`, `source`, `url`, `canonicalURL`

Either image field may be absent. Text-only items are first-class references.

## Fetch one saved item

Use an exact item UUID returned by a project response or supplied separately. This
also supports General items, whose `project` and `projectID` fields are omitted.

```sh
"$MOOD_AGENT" inspiration --id F168774A-16DB-4403-A244-F87A49EE54D7 --pretty
```

The response contains one `inspiration` record with the same media and provenance
fields as a project response. The API does not search General by title or description.

## Validate DesignEssence 1.0

Validation reads one JSON file, checks the canonical source/evidence/schema rules,
and never opens or mutates the mood. library:

```sh
"$MOOD_AGENT" validate-essence --file /tmp/design-essence.json --pretty
```

A valid document returns `valid: true`, its `schemaVersion`, `sourceKind`, and
`referenceCount`. The JSON file is limited to 10 MiB. Keep temporary files outside
the App Group library.

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
`inspiration_not_found`, `invalid_essence`, `storage_error`, `internal_error`.

On `project_not_found` or `ambiguous_project`, call `projects` and resolve from
the returned names and UUIDs. Prefer the UUID for the `inspirations` call.
