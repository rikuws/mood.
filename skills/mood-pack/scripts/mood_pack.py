#!/usr/bin/env python3
"""Build a traceable GUI.md agent pack from a mood. DesignEssence.

Three subcommands, run in order:

  trace   Resolve every essence claim against saved mood. items. Claims whose
          evidence does not reach a saved item (or the user's note on one) are
          dropped, with the reason recorded.
  render  Write GUI.md, references/, skills/ and SETUP.md from a trace.
  check   Verify a pack: every guidance bullet cites a kept entry, every kept
          entry is in GUI.md, every cited source is listed, nothing else ships.

Standard library only, so it runs on the python3 that ships with Xcode's
Command Line Tools.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path

TRACE_FORMAT = "mood-pack-trace/1"
PACK_FORMAT = "mood-pack/1"
PIPELINE_VERSION = "mood-pack/1.0"

DIRECTIVE_GROUPS = [
    ("mustPreserve", "Must preserve"),
    ("prefer", "Prefer"),
    ("mayVary", "May vary"),
    ("mustAvoid", "Must avoid"),
]

OBSERVABLE_KINDS = [
    ("palette", "Palette"),
    ("typography", "Typography"),
    ("geometry", "Geometry"),
    ("spacing", "Spacing"),
    ("surface", "Surface"),
    ("imagery", "Imagery"),
]

COMPOSITION_KINDS = [
    ("hierarchy", "Hierarchy"),
    ("entryPoint", "Entry point"),
    ("readingPath", "Reading path"),
    ("alignment", "Alignment"),
    ("balance", "Balance"),
    ("grouping", "Grouping"),
    ("rhythm", "Rhythm"),
    ("scaleContrast", "Scale contrast"),
]

TAG_PATTERN = re.compile(r"\[([TPRC]\d+(?:\s*,\s*[TPRC]\d+)*)\]")
GUIDANCE_FILES = [
    "GUI.md",
    "references/light-dark.md",
    "references/components.md",
    "references/composition.md",
]
UNTAGGED_PREFIXES = ("- Not evidenced:", "- Open question:", "- Limit:")
SKILL_NAMES = ["gui-build", "gui-apply", "gui-review"]


class PackError(Exception):
    pass


# --------------------------------------------------------------------------
# Loading


def load_json(path: str) -> object:
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise PackError(f"Could not read JSON from {path}: {error}") from error


def normalize_id(value: object) -> str:
    return str(value or "").strip().upper()


def load_essence(path: str) -> dict:
    """Accept a DesignEssence document or a mood-agent `essence` response."""
    payload = load_json(path)
    if not isinstance(payload, dict):
        raise PackError("The essence file is not a JSON object.")
    if payload.get("ok") is False:
        raise PackError(f"{path} is a mood-agent error response.")
    if "schemaVersion" in payload:
        return payload
    if "essence" in payload or "revisionCount" in payload:
        if not isinstance(payload.get("essence"), dict):
            raise PackError(f"{path} is a mood-agent essence response with no saved essence.")
        return payload["essence"]
    raise PackError(f"{path} holds no design essence.")


def load_items(paths: list[str]) -> dict[str, dict]:
    """Accept mood-agent `inspirations`, `inspiration`, or a bare list."""
    items: dict[str, dict] = {}
    for path in paths:
        payload = load_json(path)
        if isinstance(payload, dict) and payload.get("ok") is False:
            raise PackError(f"{path} is a mood-agent error response.")
        if isinstance(payload, list):
            records = payload
        elif isinstance(payload, dict) and isinstance(payload.get("inspirations"), list):
            records = payload["inspirations"]
        elif isinstance(payload, dict) and isinstance(payload.get("inspiration"), dict):
            records = [payload["inspiration"]]
        else:
            raise PackError(f"{path} holds no mood. items.")
        for record in records:
            if isinstance(record, dict) and record.get("id"):
                items[normalize_id(record["id"])] = record
    return items


# --------------------------------------------------------------------------
# Trace


def reference_roles(essence: dict) -> dict[str, str]:
    references = (essence.get("source") or {}).get("references") or []
    return {
        normalize_id(ref.get("assetID")): ref.get("role", "positive")
        for ref in references
        if isinstance(ref, dict)
    }


def effective_role(asset_id: str, roles: dict[str, str], item: dict | None) -> str:
    verdict = (item or {}).get("verdict")
    if verdict == "reject":
        return "negative"
    if verdict == "keep":
        return "positive"
    return roles.get(asset_id, "positive")


def note_of(item: dict | None) -> str:
    return field_of(item, "note")


def field_of(item: dict | None, field: str) -> str:
    value = (item or {}).get(field)
    return value.strip() if isinstance(value, str) else ""


def squash(text: str) -> str:
    """Fold case, diacritics, width and whitespace runs, as `save-essence` does."""
    folded = unicodedata.normalize("NFKD", text.casefold())
    stripped = "".join(c for c in folded if not unicodedata.combining(c))
    return " ".join(stripped.split())


TEXT_KINDS = ("note", "text", "title")


def resolve_claim(
    claim: dict,
    items: dict[str, dict],
    roles: dict[str, str],
    negative_supports: bool,
) -> tuple[list[dict], str | None]:
    """Return (sources, drop_reason). A kept claim has drop_reason None."""
    evidence = claim.get("evidence") or []
    if not evidence:
        return [], "no evidence: the claim cites no saved item or note"

    sources: list[dict] = []
    unresolved: list[str] = []
    for entry in evidence:
        asset_id = normalize_id(entry.get("assetID"))
        item = items.get(asset_id)
        kind = entry.get("kind") or "image"
        if item is None:
            unresolved.append(asset_id)
            continue
        quoted = None
        if kind in TEXT_KINDS:
            field = field_of(item, kind)
            if not field:
                unresolved.append(f"{asset_id} ({kind} citation, but the item has no {kind})")
                continue
            quoted = (entry.get("quote") or "").strip() or field
            if squash(quoted) not in squash(field):
                unresolved.append(f"{asset_id} ({kind} quote not found in the item's {kind})")
                continue
        elif kind != "image":
            unresolved.append(f"{asset_id} (unknown evidence kind {kind!r})")
            continue
        sources.append({
            "assetID": asset_id,
            "kind": kind,
            "role": effective_role(asset_id, roles, item),
            "cue": entry.get("cue", ""),
            **({"quote": quoted} if quoted else {}),
            **({"measurement": entry["measurement"]} if entry.get("measurement") else {}),
        })

    if not sources:
        return [], "cites no saved item: " + ", ".join(unresolved)

    if not negative_supports and all(s["role"] == "negative" for s in sources):
        return sources, "only cites rejected references, which cannot support a positive rule"

    if unresolved:
        for source in sources:
            source.setdefault("unresolvedSiblings", unresolved)
    return sources, None


def iter_entries(essence: dict):
    """Yield (prefix, section, label, claim, text, extra, negative_supports)."""
    observables = essence.get("observables") or {}
    for key, label in OBSERVABLE_KINDS:
        claim = observables.get(key)
        if isinstance(claim, dict):
            yield "T", "tokens", label, claim, None, {"token": key, "value": claim.get("value")}, False

    summary = essence.get("summary") or {}
    if isinstance(summary.get("essence"), dict):
        claim = summary["essence"]
        yield "P", "essence", "Essence", claim, claim.get("value"), {}, False
    for claim in summary.get("signatureTensions") or []:
        yield "P", "tensions", "Signature tension", claim, claim.get("value"), {}, False
    for invariant in essence.get("invariants") or []:
        claim = invariant.get("statement") or {}
        yield (
            "P", "invariants", "Invariant", claim, claim.get("value"),
            {"importance": invariant.get("importance", "secondary")}, False,
        )

    directive = essence.get("directive") or {}
    for key, label in DIRECTIVE_GROUPS:
        for claim in directive.get(key) or []:
            yield "R", key, label, claim, claim.get("value"), {}, key == "mustAvoid"

    composition = essence.get("composition") or {}
    for key, label in COMPOSITION_KINDS:
        claim = composition.get(key)
        if isinstance(claim, dict):
            yield "C", "composition", label, claim, claim.get("value"), {"aspect": key}, False

    variation = essence.get("projectVariation") or {}
    for claim in variation.get("commonCore") or []:
        yield "C", "commonCore", "Common core", claim, claim.get("value"), {}, False
    for claim in variation.get("acceptedVariations") or []:
        yield "C", "acceptedVariations", "Accepted variation", claim, claim.get("value"), {}, False


def build_trace(essence: dict, items: dict[str, dict]) -> dict:
    if essence.get("schemaVersion") != "1.0":
        raise PackError("Only DesignEssence 1.0 is supported.")
    roles = reference_roles(essence)
    counters = {"T": 0, "P": 0, "R": 0, "C": 0}
    kept: list[dict] = []
    dropped: list[dict] = []

    for prefix, section, label, claim, text, extra, negative_supports in iter_entries(essence):
        counters[prefix] += 1
        entry_id = f"{prefix}{counters[prefix]}"
        sources, reason = resolve_claim(claim, items, roles, negative_supports)
        record = {
            "id": entry_id,
            "section": section,
            "label": label,
            "basis": claim.get("basis"),
            "confidence": claim.get("confidence"),
            **({"text": text} if text is not None else {}),
            **extra,
        }
        if reason is None:
            record["sources"] = sources
            kept.append(record)
        else:
            record["reason"] = reason
            dropped.append(record)

    cited = {s["assetID"] for entry in kept for s in entry["sources"]}
    source_list = []
    for index, asset_id in enumerate(sorted(cited, key=lambda a: order_key(a, essence)), start=1):
        item = items[asset_id]
        source_list.append({
            "sid": f"S{index}",
            "assetID": asset_id,
            "role": effective_role(asset_id, roles, item),
            "title": (item.get("title") or "").strip() or "Untitled",
            "url": item.get("canonicalURL") or item.get("url"),
            "authorName": item.get("authorName"),
            "authorHandle": item.get("authorHandle"),
            "source": item.get("source"),
            "note": note_of(item) or None,
            "text": (item.get("text") or "").strip() or None,
            "verdict": item.get("verdict"),
        })

    open_questions = [
        claim.get("value")
        for claim in (essence.get("projectVariation") or {}).get("contradictions") or []
        if claim.get("value")
    ]
    essence_bytes = json.dumps(essence, sort_keys=True, separators=(",", ":")).encode()
    return {
        "format": TRACE_FORMAT,
        "pipelineVersion": PIPELINE_VERSION,
        "essence": {
            "sha256": hashlib.sha256(essence_bytes).hexdigest(),
            "inputHash": (essence.get("source") or {}).get("inputHash"),
            "sourceKind": (essence.get("source") or {}).get("kind"),
            "projectID": (essence.get("source") or {}).get("projectID"),
            "provenance": essence.get("provenance"),
            "domain": (essence.get("scope") or {}).get("domain"),
            "limitations": (essence.get("scope") or {}).get("limitations") or [],
        },
        "kept": kept,
        "dropped": dropped,
        "sources": source_list,
        "openQuestions": open_questions,
    }


def order_key(asset_id: str, essence: dict) -> tuple[int, str]:
    order = [normalize_id(r.get("assetID")) for r in (essence.get("source") or {}).get("references") or []]
    return (order.index(asset_id) if asset_id in order else len(order), asset_id)


# --------------------------------------------------------------------------
# Render


def sid_map(trace: dict) -> dict[str, dict]:
    return {source["assetID"]: source for source in trace["sources"]}


MARKDOWN_SPECIALS = re.compile(r"([\\`\[\]<>|])")
STRUCTURAL_KEYS = {
    "id", "sid", "assetID", "section", "token", "kind", "role", "basis", "verdict", "importance",
}


def one_line(text: str) -> str:
    return " ".join(str(text).split())


def md_inline(text: str) -> str:
    """Saved metadata and essence text, made safe to interpolate into Markdown.

    Collapsing to one line stops a title or note from starting its own bullet or
    heading; escaping brackets stops it from forging an entry ID or a link.
    """
    return MARKDOWN_SPECIALS.sub(r"\\\1", one_line(text))


def markdown_safe(value: object, key: str | None = None) -> object:
    if isinstance(value, dict):
        return {k: markdown_safe(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [markdown_safe(v, key) for v in value]
    if isinstance(value, str) and key not in STRUCTURAL_KEYS:
        return md_inline(value)
    return value


def quote(text: str, limit: int = 240) -> str:
    text = " ".join(text.split())
    if len(text) > limit:
        text = text[: limit - 1].rstrip() + "…"
    return text.replace('"', "'")


def why_line(entry: dict, sources: dict[str, dict]) -> str:
    """The user's cited notes first, then saved text, then observed cues, each labelled."""
    notes: list[str] = []
    saved: list[str] = []
    seen: list[str] = []
    for source in entry["sources"]:
        info = sources[source["assetID"]]
        if source["kind"] in TEXT_KINDS:
            target = notes if source["kind"] == "note" else saved
            label = "" if source["kind"] == "note" else f"{source['kind']} of "
            quoted = f'{label}{info["sid"]} "{quote(source["quote"])}"'
            if quoted not in target:
                target.append(quoted)
        elif source.get("cue"):
            role = " (rejected)" if source["role"] == "negative" else ""
            seen.append(f'{info["sid"]}{role}: {quote(source["cue"], 200).rstrip(".")}')
    parts = []
    if notes:
        parts.append("Your words on " + "; ".join(notes) + ".")
    if saved:
        parts.append("Saved with the reference: " + "; ".join(saved) + ".")
    if seen:
        parts.append("Observed in " + "; ".join(seen) + ".")
    return " ".join(parts) or "Cited references only."


def from_line(entry: dict, sources: dict[str, dict]) -> str:
    sids = []
    for source in entry["sources"]:
        sid = sources[source["assetID"]]["sid"]
        if sid not in sids:
            sids.append(sid)
    titles = ", ".join(f'{sid} {sources_by_sid(sources)[sid]["title"]}' for sid in sids)
    basis = entry.get("basis") or "unknown"
    confidence = entry.get("confidence")
    meta = f"{basis}" + (f", confidence {confidence:.2f}" if isinstance(confidence, (int, float)) else "")
    return f"{titles} ({meta})"


def sources_by_sid(sources: dict[str, dict]) -> dict[str, dict]:
    return {info["sid"]: info for info in sources.values()}


def entry_block(entry: dict, text: str, sources: dict[str, dict]) -> list[str]:
    return [
        f"- [{entry['id']}] {text}",
        f"  - Why: {why_line(entry, sources)}",
        f"  - From: {from_line(entry, sources)}",
    ]


def token_text(entry: dict) -> list[str]:
    value = entry.get("value") or {}
    kind = entry.get("token")
    if kind == "palette":
        approx = entry.get("basis") != "measured"
        lines = []
        for color in value.get("colors") or []:
            coverage = color.get("coverage")
            cover = f", about {round(coverage * 100)}% coverage" if isinstance(coverage, (int, float)) else ""
            lines.append(f"`{color.get('hex')}` {color.get('role')}{cover}")
        head = (
            f"Palette: temperature {value.get('temperature')}; saturation {value.get('saturation')}; "
            f"contrast {value.get('contrastStrategy')}."
        )
        if approx:
            head += " Hex values were estimated by eye, so treat them as approximate."
        return [head] + lines
    fields = {k: v for k, v in value.items() if isinstance(v, str) and v}
    label = entry["label"]
    return [f"{label}: " + "; ".join(f"{humanize(k)} {v}" for k, v in fields.items()) + "."]


def humanize(key: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", " ", key).lower() + ":"


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-") or "color"


def color_tokens(trace: dict, primary: str | None) -> dict[str, str]:
    palette = next((e for e in trace["kept"] if e.get("token") == "palette"), None)
    tokens: dict[str, str] = {}
    for color in ((palette or {}).get("value") or {}).get("colors") or []:
        name, n = slug(color.get("role", "")), 2
        while name in tokens:
            name, n = f"{slug(color.get('role', ''))}-{n}", n + 1
        tokens[name] = color.get("hex", "")
    if primary:
        if primary not in tokens:
            raise PackError(
                f"--primary {primary!r} is not a palette token. Choose one of: {', '.join(tokens) or 'none'}."
            )
        tokens = {"primary": tokens[primary], **tokens}
    return tokens


def yaml_scalar(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render_front_matter(trace: dict, name: str, primary: str | None) -> list[str]:
    """DESIGN.md (Google Stitch, version alpha) front matter.

    Only colors become tokens: the essence describes type, spacing and shape
    qualitatively, so those sections are listed as omitted with the reason.
    """
    kept_tokens = {e.get("token") for e in trace["kept"]}
    essence = next((e for e in trace["kept"] if e["section"] == "essence"), None)
    lines = ["---", "version: alpha", f"name: {yaml_scalar(name)}"]
    if essence:
        lines.append(f"description: {yaml_scalar(one_line(essence['text']))}")
    colors = color_tokens(trace, primary)
    if colors:
        lines.append("colors:")
        lines += [f"  {token}: {yaml_scalar(hex_value)}" for token, hex_value in colors.items()]
    omitted = [
        ("typography", "typography", "The references show type behaviour, not font values; see ## Typography."),
        ("spacing", "spacing", "The references show density and grouping, not a measured scale; see ## Layout."),
        ("rounded", "geometry", "The references show corner character, not radii; see ## Shapes."),
        ("components", None, "Component guidance is prose in references/components.md."),
    ]
    lines.append("omitted:")
    for section, token, reason in omitted:
        if token and token not in kept_tokens:
            reason = "No saved reference informs this section."
        lines += [f"  - section: {section}", f"    reason: {yaml_scalar(reason)}"]
    lines.append("---")
    return lines


def render_gui(
    trace: dict,
    name: str,
    primary: str | None = None,
    front_matter: tuple[dict, str] | None = None,
) -> str:
    """GUI.md is a valid DESIGN.md with mood.'s traces layered on top."""
    sources = sid_map(trace)
    kept = trace["kept"]
    by_section = lambda section: [e for e in kept if e["section"] == section]
    tokens = {e["token"]: e for e in by_section("tokens")}
    provenance = trace["essence"].get("provenance") or {}

    raw_trace, plain_name = front_matter or (trace, name)
    lines = render_front_matter(raw_trace, plain_name, primary) + [
        "",
        f"# {name}",
        "",
        "This file is the single source of truth for this design language and follows the",
        "DESIGN.md format. It was generated by mood. from a design essence distilled from",
        "references the user chose. Every guideline starts with a bracketed ID: P for principles,",
        "T for tokens, R for do's and don'ts, C for composition. Its Why line quotes the user's",
        "own notes first, then what was observed in the references; its From line names the",
        "sources in references/sources.md. Do not add guidelines that are not here: when",
        "something is not covered or is marked Not evidenced, ask the user.",
        "",
        f"Distilled {provenance.get('extractedAt', 'at an unknown time')} from input "
        f"`{trace['essence'].get('inputHash')}`.",
        "",
    ]

    def token_section(title: str, token: str) -> None:
        nonlocal lines
        lines += [f"## {title}", ""]
        entry = tokens.get(token)
        if entry:
            text, *rest = token_text(entry)
            lines += entry_block(entry, text, sources)
            lines += [f"  - {line}" for line in rest]
        else:
            lines.append(f"- Not evidenced: no saved reference informs {title.lower()}.")
        lines.append("")

    lines += ["## Overview", ""]
    overview = by_section("essence") + by_section("tensions") + sorted(
        by_section("invariants"), key=lambda e: e.get("importance") != "primary"
    )
    for entry in overview:
        label = "" if entry["section"] == "invariants" else f"{entry['label']}: "
        lines += entry_block(entry, label + entry["text"], sources)
    if not overview:
        lines.append("- Not evidenced: no overall direction traces to a saved reference.")
    lines.append("")

    token_section("Colors", "palette")
    token_section("Typography", "typography")
    token_section("Layout", "spacing")
    token_section("Elevation & Depth", "surface")
    token_section("Shapes", "geometry")

    lines += [
        "## Components",
        "",
        "Component guidance lives in references/components.md, light and dark mode in",
        "references/light-dark.md, and layout and reading order in references/composition.md.",
        "",
        "## Do's and Don'ts",
        "",
    ]
    for key, label in DIRECTIVE_GROUPS:
        group = by_section(key)
        lines += [f"### {label}", ""]
        if group:
            for entry in group:
                lines += entry_block(entry, entry["text"], sources)
        else:
            lines.append(f"- Not evidenced: no {label.lower()} guideline traces to a saved reference.")
        lines.append("")

    token_section("Imagery", "imagery")

    limitations = trace["essence"].get("limitations") or []
    if limitations or trace["openQuestions"]:
        lines += ["## Limits and Open Questions", ""]
        for limitation in limitations:
            lines.append(f"- Limit: {limitation}")
        for question in trace["openQuestions"]:
            lines.append(f"- Open question: the references disagree here, so ask the user: {question}")
        lines.append("")

    lines += [
        "## Sources",
        "",
        "references/sources.md lists every cited reference with its link, author and the user's",
        "note. pack.json maps each ID to its sources and records the guidelines that were dropped",
        "because they did not trace to a saved reference.",
        "",
    ]
    return "\n".join(lines)


def relative_luminance(hex_value: str) -> float | None:
    match = re.fullmatch(r"#?([0-9a-fA-F]{6})", (hex_value or "").strip())
    if not match:
        return None
    channels = []
    for i in range(0, 6, 2):
        c = int(match.group(1)[i : i + 2], 16) / 255
        channels.append(c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4)
    r, g, b = channels
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


BACKGROUND_WORDS = {"background", "bg", "ground", "canvas", "surface", "paper", "base", "backdrop"}
FOREGROUND_WORDS = {"foreground", "fg", "text", "ink", "on", "label", "icon", "stroke", "border"}


def is_background_role(role: str) -> bool:
    """Whole-word match, so 'foreground' and 'on-surface' never count as grounds."""
    words = set(re.findall(r"[a-z]+", role.lower()))
    return bool(words & BACKGROUND_WORDS) and not words & FOREGROUND_WORDS


def render_light_dark(trace: dict) -> str:
    sources = sid_map(trace)
    palette = next((e for e in trace["kept"] if e.get("token") == "palette"), None)
    surface = next((e for e in trace["kept"] if e.get("token") == "surface"), None)
    lines = [
        "# Light and dark mode",
        "",
        "Only modes the references actually show are specified. A mode they do not show is",
        "marked Not evidenced; ask the user for references before designing it.",
        "",
    ]
    if palette is None:
        lines += ["- Not evidenced: no palette traces to a saved reference, so neither mode is specified.", ""]
        return "\n".join(lines)

    colors = (palette.get("value") or {}).get("colors") or []
    grounds = [c for c in colors if is_background_role(c.get("role", ""))]
    shown = set()
    for color in grounds:
        luminance = relative_luminance(color.get("hex", ""))
        if luminance is not None:
            shown.add("dark" if luminance < 0.2 else "light")

    for mode in ("light", "dark"):
        lines += [f"## {mode.capitalize()}", ""]
        if mode in shown:
            for color in colors:
                lines.append(f"- [{palette['id']}] `{color.get('hex')}` {color.get('role')}")
            value = palette.get("value") or {}
            lines.append(f"- [{palette['id']}] Contrast: {value.get('contrastStrategy')}")
            if surface:
                lighting = (surface.get("value") or {}).get("lighting")
                if lighting:
                    lines.append(f"- [{surface['id']}] Lighting: {lighting}")
            lines.append(
                f"  - This mode is read from the luminance of the background-role colors in "
                f"{palette['id']} ({from_line(palette, sources)})."
            )
        else:
            lines.append(
                f"- Not evidenced: no saved reference shows a {mode} ground. Do not derive one by "
                f"inverting the other mode; ask the user to add {mode} references first."
            )
        lines.append("")
    return "\n".join(lines)


def render_components(trace: dict) -> str:
    kept = {e.get("token"): e for e in trace["kept"] if e.get("token")}
    lines = [
        "# Components",
        "",
        "How the evidenced tokens apply to common components. Every bullet cites the entry it",
        "comes from. Component states the references do not show stay Not evidenced.",
        "",
    ]
    groups = [
        ("Containers and cards", [("geometry", ["shapeLanguage", "corners", "borders", "elevation"]),
                                  ("surface", ["texture", "depth"]),
                                  ("spacing", ["groupingStrategy", "negativeSpace"])]),
        ("Text", [("typography", ["hierarchy", "scaleBehavior", "weightRange", "rhythm"])]),
        ("Layout", [("spacing", ["density", "grid"])]),
        ("Images", [("imagery", ["treatment", "relationshipToTypography"])]),
    ]
    for title, specs in groups:
        lines += [f"## {title}", ""]
        wrote = False
        for token, fields in specs:
            entry = kept.get(token)
            if not entry:
                continue
            value = entry.get("value") or {}
            for field in fields:
                if value.get(field):
                    lines.append(f"- [{entry['id']}] {humanize(field).capitalize()} {value[field]}")
                    wrote = True
        if not wrote:
            lines.append(f"- Not evidenced: no saved reference informs {title.lower()}.")
        lines.append("")
    lines += [
        "## Interactive states",
        "",
        "- Not evidenced: hover, pressed, focus, disabled and error states are not visible in",
        "  still references. Follow platform conventions and ask the user to confirm.",
        "",
    ]
    return "\n".join(lines)


def render_composition(trace: dict) -> str:
    sources = sid_map(trace)
    lines = ["# Composition", ""]
    groups = [
        ("Layout and reading", "composition"),
        ("Shared across the references", "commonCore"),
        ("Accepted variation", "acceptedVariations"),
    ]
    for title, section in groups:
        entries = [e for e in trace["kept"] if e["section"] == section]
        lines += [f"## {title}", ""]
        if entries:
            for entry in entries:
                prefix = f"{entry['label']}: " if section == "composition" else ""
                lines += entry_block(entry, prefix + entry["text"], sources)
        else:
            lines.append(f"- Not evidenced: nothing under {title.lower()} traces to a saved reference.")
        lines.append("")
    return "\n".join(lines)


def render_sources(trace: dict) -> str:
    lines = [
        "# Sources",
        "",
        "Every reference a rule cites. These are the user's own picks, saved in mood.; media is",
        "not copied into this pack.",
        "",
    ]
    role_label = {"positive": "reference", "near_miss": "near miss", "negative": "negative reference"}
    verdict_label = {"keep": "kept", "reject": "rejected"}
    for source in trace["sources"]:
        lines.append(f"## {source['sid']} {source['title']}")
        lines.append("")
        if source.get("url"):
            lines.append(f"- Link: {source['url']}")
        author = source.get("authorName") or ""
        if source.get("authorHandle"):
            author = f"{author} (@{source['authorHandle'].lstrip('@')})".strip()
        if author:
            lines.append(f"- Author: {author}")
        role = verdict_label.get(source.get("verdict") or "") or role_label.get(source["role"], source["role"])
        lines.append(f"- Role: {role}")
        if source.get("note"):
            lines.append(f'- Your note: "{quote(source["note"], 600)}"')
        if source.get("text") and source.get("text") != source.get("note"):
            lines.append(f'- Saved text: "{quote(source["text"], 280)}"')
        lines.append(f"- mood. item: `{source['assetID']}`")
        lines.append("")
    return "\n".join(lines)


def render_skill(skill: str, name: str, install_path: str, plain_name: str | None = None) -> str:
    gui = f"{install_path}/GUI.md"
    bodies = {
        "gui-build": (
            f"Build new UI in the {name} design language.",
            [
                f"Read `{gui}` in full before writing any UI. It is the only source of design",
                "decisions; read the files under `references/` next to it when a screen needs",
                "light/dark, component or composition detail.",
                "",
                "1. Map the screen to the token sections (Colors through Shapes) and to Do's and",
                "   Don'ts. Use token values exactly as given.",
                "2. Honour every Must preserve and Must avoid rule. Use Prefer rules unless the",
                "   screen gives a concrete reason not to, and say what that reason is.",
                "3. May vary rules describe allowed range: use them where they help, not by default.",
                "4. When the screen needs something GUI.md marks Not evidenced or does not cover,",
                "   stop and ask the user rather than inventing a direction. If you cannot ask,",
                "   use the plainest option, mark it in the code as an assumption, and list it",
                "   as a question for the user.",
                "5. In your summary, list the rule IDs (for example [R2], [T1]) the new UI applies.",
            ],
        ),
        "gui-apply": (
            f"Restyle existing UI to follow the {name} design language.",
            [
                f"Read `{gui}` in full first, then the existing UI you were asked to change.",
                "",
                "1. List each place the current UI departs from a token or rule, with the rule ID.",
                "2. Change only what a cited rule calls for. Keep behaviour, copy and structure",
                "   unless a rule is about them.",
                "3. Do not apply rules marked May vary as fixes; they describe allowed range.",
                "4. Where GUI.md is silent or says Not evidenced, leave the existing UI as it is",
                "   and note it as a question for the user.",
                "5. Report every change with the rule ID that justifies it.",
            ],
        ),
        "gui-review": (
            f"Review UI against the {name} design language and fix inconsistencies.",
            [
                f"Read `{gui}` in full first.",
                "",
                "1. Check the UI against each Must preserve, Must avoid and Prefer guideline and each",
                "   token. Record a finding only when you can name the ID it breaks. May vary",
                "   rules describe allowed range and are never findings.",
                "2. Rank findings: Must avoid and Must preserve breaks first, then token drift,",
                "   then Prefer departures.",
                "3. Fix findings when asked to; otherwise list them with file, rule ID and the",
                "   smallest change that resolves each.",
                "4. Never report taste issues that no rule covers. Note gaps as questions for the",
                "   user, since only they can add rules (by saving references in mood.).",
            ],
        ),
    }
    description, steps = bodies[skill]
    if plain_name is not None:
        description = description.replace(name, plain_name, 1)
    return "\n".join([
        "---",
        f"name: {skill}",
        f"description: {yaml_scalar(description + ' Use GUI.md as the single source of truth.')}",
        "---",
        "",
        f"# {skill}",
        "",
        *steps,
        "",
        "Every rule in GUI.md traces to references and notes the user chose in mood. Treat it",
        "as their judgment: do not override it with your own taste.",
        "",
    ])


def render_setup(name: str, install_path: str) -> str:
    return "\n".join([
        f"# Set up the {name} design language",
        "",
        f"Copy this folder into your project at `{install_path}/`, then paste the prompt below",
        "into your coding agent.",
        "",
        "```text",
        f"This project has a design language in {install_path}/GUI.md. Treat it as the single",
        "source of truth for visual design: tokens, rules and the reasons behind them. Every",
        "rule traces to references I chose; do not add rules of your own.",
        "",
        f"Install the three skills in {install_path}/skills/ (gui-build, gui-apply,",
        "gui-review) where you load skills, or read them as instructions:",
        "- gui-build when creating new screens or components,",
        "- gui-apply when restyling existing UI,",
        "- gui-review when checking UI for inconsistencies.",
        "",
        "When GUI.md does not cover something or marks it Not evidenced, ask me instead of",
        "guessing. Cite rule IDs like [R2] when you explain design choices.",
        "```",
        "",
    ])


def render_pack(
    trace: dict,
    out_dir: Path,
    name: str,
    install_path: str,
    primary: str | None = None,
) -> list[Path]:
    if trace.get("format") != TRACE_FORMAT:
        raise PackError(f"Expected a {TRACE_FORMAT} trace.")
    if not trace["kept"]:
        raise PackError(
            "No essence claim traces to a saved item or note, so there is nothing to export. "
            "Distill from saved mood. items first."
        )
    plain_name = one_line(name)
    if not plain_name:
        raise PackError("--name must not be empty.")
    if not re.fullmatch(r"[A-Za-z0-9._/~-]+", install_path):
        raise PackError("--install-path must be a plain relative path without spaces or Markdown.")
    safe = markdown_safe(trace)
    md_name = md_inline(plain_name)
    files = {
        "GUI.md": render_gui(safe, md_name, primary, front_matter=(trace, plain_name)),
        "references/light-dark.md": render_light_dark(safe),
        "references/components.md": render_components(safe),
        "references/composition.md": render_composition(safe),
        "references/sources.md": render_sources(safe),
        "SETUP.md": render_setup(md_name, install_path),
    }
    for skill in SKILL_NAMES:
        files[f"skills/{skill}/SKILL.md"] = render_skill(skill, md_name, install_path, plain_name)
    manifest = {
        "format": PACK_FORMAT,
        "name": name,
        "installPath": install_path,
        "essence": trace["essence"],
        "entries": [
            {k: v for k, v in entry.items() if k in ("id", "section", "label", "basis", "confidence", "text", "token")}
            | {"sources": sorted({sid_map(trace)[s["assetID"]]["sid"] for s in entry["sources"]})}
            for entry in trace["kept"]
        ],
        "dropped": [
            {k: entry.get(k) for k in ("id", "section", "label", "text", "reason") if entry.get(k) is not None}
            for entry in trace["dropped"]
        ],
        "sources": [
            {k: s[k] for k in ("sid", "assetID", "title", "url", "role") if s.get(k) is not None}
            for s in trace["sources"]
        ],
    }
    files["pack.json"] = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"

    written = []
    for relative, content in files.items():
        path = out_dir / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        written.append(path)
    return written


# --------------------------------------------------------------------------
# Check


FRONT_MATTER_LINE = re.compile(r"^(?P<indent> *)(?:- )?(?P<key>[A-Za-z0-9_-]+):(?: (?P<value>.*))?$")
PLAIN_SCALAR = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._/-]*")


def front_matter_problems(text: str) -> tuple[dict[str, str], list[str]]:
    """Check the YAML subset mood-pack writes: keys with JSON-quoted or plain scalars.

    The renderer only emits this subset, so anything else (an unquoted value with
    ': ' or '#', a stray line) is a rendering bug a real YAML loader may reject.
    """
    lines = text.split("\n")
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        return {}, ["has no front matter block."]
    top: dict[str, str] = {}
    problems: list[str] = []
    for number, line in enumerate(lines[1 : lines.index("---", 1)], start=2):
        match = FRONT_MATTER_LINE.match(line)
        if not match:
            problems.append(f"front matter line {number} is not a key: value pair.")
            continue
        value = match.group("value")
        if value is None:
            continue
        if value.startswith('"'):
            try:
                parsed = json.loads(value)
            except json.JSONDecodeError:
                problems.append(f"front matter line {number} has a malformed quoted value.")
                continue
            if not isinstance(parsed, str):
                problems.append(f"front matter line {number} is not a string.")
                continue
            value = parsed
        elif not PLAIN_SCALAR.fullmatch(value):
            problems.append(f"front matter line {number} needs quoting to be valid YAML.")
            continue
        if not match.group("indent"):
            top[match.group("key")] = value
    return top, problems


def check_pack(out_dir: Path) -> list[str]:
    problems: list[str] = []
    manifest_path = out_dir / "pack.json"
    if not manifest_path.is_file():
        return ["pack.json is missing; render the pack before checking it."]
    manifest = load_json(str(manifest_path))
    if manifest.get("format") != PACK_FORMAT:
        problems.append(f"pack.json format is not {PACK_FORMAT}.")
    kept = {entry["id"]: entry for entry in manifest.get("entries", [])}
    dropped = {entry["id"] for entry in manifest.get("dropped", [])}
    known_sids = {source["sid"] for source in manifest.get("sources", [])}

    required = GUIDANCE_FILES + ["references/sources.md", "SETUP.md", "pack.json"]
    required += [f"skills/{skill}/SKILL.md" for skill in SKILL_NAMES]
    for relative in required:
        if not (out_dir / relative).is_file():
            problems.append(f"{relative} is missing.")

    for path in sorted(p for p in out_dir.rglob("*") if p.is_file()):
        if path.suffix not in (".md", ".json"):
            problems.append(f"{path.relative_to(out_dir)} is not Markdown or JSON; packs never copy media.")

    for entry in kept.values():
        if not entry.get("sources"):
            problems.append(f"{entry['id']} has no sources in pack.json.")
        for sid in entry.get("sources", []):
            if sid not in known_sids:
                problems.append(f"{entry['id']} cites unknown source {sid}.")

    for relative in ["GUI.md"] + [f"skills/{skill}/SKILL.md" for skill in SKILL_NAMES]:
        path = out_dir / relative
        if not path.is_file():
            continue
        top, issues = front_matter_problems(path.read_text(encoding="utf-8"))
        problems += [f"{relative} {issue}" for issue in issues]
        if relative.startswith("skills/"):
            skill = relative.split("/")[1]
            if top.get("name") != skill:
                problems.append(f"{relative} front matter name is not {skill}.")
            if not top.get("description"):
                problems.append(f"{relative} front matter has no description.")

    gui_tags: set[str] = set()
    for relative in GUIDANCE_FILES:
        path = out_dir / relative
        if not path.is_file():
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            tags = {tag.strip() for group in TAG_PATTERN.findall(line) for tag in group.split(",")}
            for tag in tags:
                if tag in dropped:
                    problems.append(f"{relative}:{number} cites dropped entry {tag}.")
                elif tag not in kept:
                    problems.append(f"{relative}:{number} cites unknown entry {tag}.")
            if relative == "GUI.md":
                gui_tags |= tags
            if line.startswith("- ") and not tags and not line.startswith(UNTAGGED_PREFIXES):
                problems.append(
                    f"{relative}:{number} is guidance with no entry ID; cite one, or mark it "
                    "'Not evidenced:', 'Open question:' or 'Limit:'."
                )

    for entry_id in kept:
        if entry_id not in gui_tags and kept[entry_id].get("section") not in (
            "composition", "commonCore", "acceptedVariations",
        ):
            problems.append(f"{entry_id} is kept but does not appear in GUI.md.")

    sources_path = out_dir / "references/sources.md"
    if sources_path.is_file():
        listed = set(re.findall(r"^## (S\d+) ", sources_path.read_text(encoding="utf-8"), re.M))
        for sid in known_sids - listed:
            problems.append(f"references/sources.md does not list {sid}.")
    return problems


# --------------------------------------------------------------------------
# CLI


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="mood_pack.py", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    trace = sub.add_parser("trace", help="Resolve essence claims against saved items.")
    trace.add_argument("--essence", required=True, help="DesignEssence 1.0 JSON file.")
    trace.add_argument("--items", required=True, action="append",
                       help="mood-agent inspirations/inspiration JSON. Repeatable.")
    trace.add_argument("--out", required=True, help="Where to write the trace JSON.")

    render = sub.add_parser("render", help="Write the pack from a trace.")
    render.add_argument("--trace", required=True)
    render.add_argument("--out", required=True, help="Pack directory to write.")
    render.add_argument("--name", required=True, help="Project or study name.")
    render.add_argument("--install-path", default="design/gui",
                        help="Where SETUP.md tells the user to place the pack.")
    render.add_argument("--primary",
                        help="Palette token the user chose as DESIGN.md's primary color.")

    check = sub.add_parser("check", help="Verify a rendered pack.")
    check.add_argument("--pack", required=True)

    args = parser.parse_args(argv)
    try:
        if args.command == "trace":
            essence = load_essence(args.essence)
            result = build_trace(essence, load_items(args.items))
            Path(args.out).write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            print(json.dumps({
                "ok": True,
                "kept": len(result["kept"]),
                "dropped": [
                    {"id": d["id"], "label": d["label"], "text": d.get("text"), "reason": d["reason"]}
                    for d in result["dropped"]
                ],
                "sources": len(result["sources"]),
            }, indent=2, ensure_ascii=False))
        elif args.command == "render":
            trace_data = load_json(args.trace)
            out_dir = Path(args.out)
            written = render_pack(
                trace_data, out_dir, args.name, args.install_path.rstrip("/"), args.primary,
            )
            print(json.dumps({"ok": True, "files": [str(p.relative_to(out_dir)) for p in written]}, indent=2))
        else:
            problems = check_pack(Path(args.pack))
            print(json.dumps({"ok": not problems, "problems": problems}, indent=2, ensure_ascii=False))
            return 0 if not problems else 2
    except PackError as error:
        print(json.dumps({"ok": False, "error": str(error)}, indent=2, ensure_ascii=False))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
