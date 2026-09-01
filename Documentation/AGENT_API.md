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
newline. Successful calls exit `0`. Invalid input, missing records, invalid essence files,
and storage failures return a structured error and exit `2`. `--pretty` changes formatting
only.

The version number covers the executable's JSON wire contract. The public Swift symbols in
`PinaxCore` exist so the separate `mood-agent` target can reuse the implementation; they are
not a source-stable SDK. External integrations should invoke the helper and consume its
versioned JSON instead of switching over those Swift enums.

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

## Fetch one saved item

Use an exact item UUID returned by a project inspirations response, supplied separately, or
already known from a previous result. General items are not discoverable by title or
description through this API, but a General item can be fetched when its UUID is supplied;
in that case both `project` and the item's `projectID` are omitted.

```sh
/Applications/mood.app/Contents/Helpers/mood-agent \
  inspiration --id F168774A-16DB-4403-95BF-0D721EF2B72D --pretty
```

The response contains one `inspiration` record with the same media and provenance fields
as a project response.

## Extract design essence

The repository's `mood-distill` skill uses the project and single-item commands above to
inspect actual visual media and produce a versioned, evidence-grounded `DesignEssence`
object. Arbitrary image attachments or local image paths can be analyzed directly without
first saving them to mood.

The helper supplies source data but does not run a model, persist generated analysis, or
contact remote previews on its own. See [DESIGN_ESSENCE.md](DESIGN_ESSENCE.md) for the
contract and privacy boundary.

## Validate a design essence

Validate one JSON file containing a `DesignEssence` object before returning or exporting it:

```sh
/Applications/mood.app/Contents/Helpers/mood-agent \
  validate-essence --file /tmp/design-essence.json --pretty
```

Validation is read-only, accepts file input only, is limited to 10 MiB, and never writes to
the mood. library. A successful response exits `0`:

```json
{
  "apiVersion": 1,
  "ok": true,
  "referenceCount": 1,
  "schemaVersion": "1.0",
  "sourceKind": "image",
  "valid": true
}
```

Malformed JSON, unreadable input, and contract-validation failures return the normal error
envelope with stable code `invalid_essence` and exit `2`.

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
- `inspiration_not_found`
- `invalid_essence`
- `storage_error`
- `internal_error`

An agent skill should call `projects` when it needs to resolve user wording, then use the
returned UUID with `inspirations --project <uuid>`. Treat unknown response fields as
forward-compatible additions and reject an `apiVersion` it does not support.

## Distill a design essence

`mood-agent` is the read and validation path, not a synthesizer. Distilling observable
style, compositional grammar, semantic effects, invariants, and generation constraints is
an agent skill: fetch the source, inspect the visuals, validate the canonical object, then
write the useful portable reading.

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
