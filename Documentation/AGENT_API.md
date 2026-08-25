# mood. agent API

The macOS app bundles a read-only command-line API at:

```text
mood.app/Contents/Helpers/mood-agent
```

Older Mac builds may still ship `pinax-agent` at the same Helpers path. The JSON
contract is unchanged.

It reads the same coordinated App Group repository as the mood. UI. The app does not need
to be running, no network listener is opened, and the API never mutates the library. A
signed helper carries the `group.com.rikuwikman.pinax` entitlement so it can read the
production library. An unsigned Debug helper follows the app's normal development fallback
to `~/Library/Application Support/Pinax`; `PINAX_STORAGE_DIRECTORY` can override that path
in Debug builds.

All machine responses use API version `1`, write JSON to stdout, and terminate with a
newline. Successful calls exit `0`. Invalid input, missing projects, and storage failures
return a structured error and exit `2`. `--pretty` changes formatting only.

## Discover projects

```sh
/Applications/mood.app/Contents/Helpers/mood-agent projects --pretty
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

Pass either the project's name or UUID. Name matching trims whitespace and ignores case
and diacritics. Results are newest-first, matching the mood. library.

```sh
/Applications/mood.app/Contents/Helpers/mood-agent \
  inspirations --project "Website refresh" --pretty
```

```json
{
  "apiVersion": 1,
  "count": 1,
  "inspirations": [
    {
      "authorHandle": "designer",
      "authorName": "Example Designer",
      "canonicalURL": "https://x.com/designer/status/123",
      "captureCount": 1,
      "createdAt": "2026-08-01T09:05:00Z",
      "id": "F168774A-16DB-4403-A244-F87A49EE54D7",
      "imageURL": "https://images.example.com/reference.jpg",
      "lastCapturedAt": "2026-08-01T09:05:00Z",
      "localImagePath": "/Users/example/Library/Group Containers/group.com.rikuwikman.pinax/Media/F168774A-16DB-4403-A244-F87A49EE54D7.jpg",
      "projectID": "80D7254E-78FA-4BC3-95BF-0D721EF2B72D",
      "source": "x",
      "text": "A useful layout detail.",
      "title": "Navigation reference",
      "updatedAt": "2026-08-01T09:05:00Z",
      "url": "https://x.com/designer/status/123"
    }
  ],
  "ok": true,
  "project": {
    "colorHex": "#B45F78",
    "createdAt": "2026-08-01T09:00:00Z",
    "id": "80D7254E-78FA-4BC3-95BF-0D721EF2B72D",
    "inspirationCount": 1,
    "name": "Website refresh",
    "updatedAt": "2026-08-01T09:00:00Z"
  }
}
```

Remote preview images use `imageURL`. Locally persisted media uses `localImagePath`, which
is an absolute path suitable for an agent tool that can read local files. Either value may
be absent.

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

Stable error codes in version 1 are:

- `invalid_arguments`
- `project_not_found`
- `ambiguous_project`
- `storage_error`
- `internal_error`

An agent skill should call `projects` when it needs to resolve user wording, then use the
returned UUID with `inspirations --project <uuid>`. Treat unknown response fields as
forward-compatible additions and reject an `apiVersion` it does not support.

## Distill a project's mood

`mood-agent` is the read path, not a synthesizer. Distilling palette, atmosphere, and
creative direction is an agent skill: fetch the project, look at local images and text,
then write a portable brief.

The skill lives at [`skills/mood-distill`](../skills/mood-distill). It follows the
[Agent Skills](https://agentskills.io) format so Cursor, Claude Code, Codex, and other
compatible agents can load it. Install it into an agent's skill directory, or from this
repository:

```sh
npx skills add https://github.com/rikuws/mood. --skill mood-distill -g
```

```sh
cp -R skills/mood-distill ~/.cursor/skills/mood-distill
# or
cp -R skills/mood-distill ~/.agents/skills/mood-distill
```

The helper must be able to read the same Mac library as mood. Cloud agents cannot see a
user's local moodboards. The skill never writes `library.json` or `Media/`.
