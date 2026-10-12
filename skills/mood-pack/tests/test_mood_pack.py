"""Tests for skills/mood-pack/scripts/mood_pack.py.

Run from the repository root:

    python3 -m unittest discover -s skills/mood-pack/tests
"""

from __future__ import annotations

import copy
import io
import json
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "scripts"))

import mood_pack  # noqa: E402

FIXTURES = HERE / "fixtures"
ITEM_1 = "AAAAAAAA-0000-4000-8000-000000000001"
ITEM_3 = "AAAAAAAA-0000-4000-8000-000000000003"


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class TraceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.essence = load("essence.json")
        self.items = mood_pack.load_items([str(FIXTURES / "items.json")])

    def trace(self, essence: dict | None = None) -> dict:
        return mood_pack.build_trace(essence or self.essence, self.items)

    def test_keeps_only_claims_that_reach_saved_items(self) -> None:
        trace = self.trace()
        kept = {entry["id"] for entry in trace["kept"]}
        dropped = {entry["id"]: entry["reason"] for entry in trace["dropped"]}
        self.assertEqual(kept, {"T1", "T2", "P1", "P2", "P3", "R1", "R5", "C1"})
        self.assertIn("no evidence", dropped["T3"])
        self.assertIn("cites no saved item", dropped["R2"])
        self.assertIn("no evidence", dropped["R3"])
        self.assertIn("only cites rejected", dropped["R4"])

    def test_must_avoid_may_rest_on_rejected_references(self) -> None:
        r5 = next(entry for entry in self.trace()["kept"] if entry["id"] == "R5")
        self.assertTrue(all(source["role"] == "negative" for source in r5["sources"]))

    def test_verdict_overrides_essence_role(self) -> None:
        essence = copy.deepcopy(self.essence)
        for reference in essence["source"]["references"]:
            reference["role"] = "positive"
        sources = {s["assetID"]: s for s in self.trace(essence)["sources"]}
        self.assertEqual(sources[ITEM_3]["role"], "negative")

    def test_note_citation_needs_a_note(self) -> None:
        self.items[ITEM_1].pop("note")
        essence = copy.deepcopy(self.essence)
        essence["invariants"][0]["statement"]["evidence"] = [
            {"assetID": ITEM_1, "kind": "note", "cue": "The user's note."},
        ]
        dropped = {entry["id"]: entry["reason"] for entry in self.trace(essence)["dropped"]}
        self.assertIn("has no note", dropped["P3"])

    def test_text_and_title_citations_quote_the_item(self) -> None:
        essence = copy.deepcopy(self.essence)
        essence["directive"]["prefer"][1]["evidence"] = [
            {"assetID": "AAAAAAAA-0000-4000-8000-000000000002", "kind": "text",
             "quote": "new  TABLE component", "cue": "Saved post text."},
            {"assetID": "AAAAAAAA-0000-4000-8000-000000000002", "kind": "title", "cue": "Title."},
        ]
        r3 = next(e for e in self.trace(essence)["kept"] if e["id"] == "R3")
        self.assertEqual([s["kind"] for s in r3["sources"]], ["text", "title"])
        self.assertEqual(r3["sources"][1]["quote"], "Dense table with hairlines")

    def test_quote_must_appear_in_the_cited_field(self) -> None:
        essence = copy.deepcopy(self.essence)
        essence["directive"]["prefer"][1]["evidence"] = [
            {"assetID": ITEM_1, "kind": "note", "quote": "I hate grey", "cue": "Note."},
        ]
        dropped = {entry["id"]: entry["reason"] for entry in self.trace(essence)["dropped"]}
        self.assertIn("quote not found", dropped["R3"])

    def test_unknown_evidence_kind_is_unresolved(self) -> None:
        essence = copy.deepcopy(self.essence)
        essence["directive"]["prefer"][1]["evidence"] = [
            {"assetID": ITEM_1, "kind": "vibe", "cue": "?"},
        ]
        dropped = {entry["id"]: entry["reason"] for entry in self.trace(essence)["dropped"]}
        self.assertIn("unknown evidence kind", dropped["R3"])

    def test_contradictions_become_open_questions(self) -> None:
        self.assertEqual(
            self.trace()["openQuestions"],
            ["Row density differs between the settings screen and the table."],
        )

    def test_rejects_other_schema_versions(self) -> None:
        essence = copy.deepcopy(self.essence)
        essence["schemaVersion"] = "2.0"
        with self.assertRaises(mood_pack.PackError):
            self.trace(essence)

    def test_accepts_single_item_and_list_payloads(self) -> None:
        payload = load("items.json")
        with tempfile.TemporaryDirectory() as tmp:
            single = Path(tmp, "one.json")
            single.write_text(json.dumps({"ok": True, "inspiration": payload["inspirations"][0]}))
            bare = Path(tmp, "list.json")
            bare.write_text(json.dumps(payload["inspirations"][1:]))
            items = mood_pack.load_items([str(single), str(bare)])
        self.assertEqual(len(items), 3)


class RenderAndCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.pack = Path(self.tmp.name, "pack")
        items = mood_pack.load_items([str(FIXTURES / "items.json")])
        self.trace = mood_pack.build_trace(load("essence.json"), items)
        mood_pack.render_pack(self.trace, self.pack, "Quiet tools", "design/gui", "ink")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def gui(self) -> str:
        return (self.pack / "GUI.md").read_text(encoding="utf-8")

    def test_rendered_pack_passes_check(self) -> None:
        self.assertEqual(mood_pack.check_pack(self.pack), [])

    def test_pack_layout(self) -> None:
        files = sorted(str(p.relative_to(self.pack)) for p in self.pack.rglob("*") if p.is_file())
        self.assertEqual(files, sorted([
            "GUI.md",
            "SETUP.md",
            "pack.json",
            "references/components.md",
            "references/composition.md",
            "references/light-dark.md",
            "references/sources.md",
            "skills/gui-apply/SKILL.md",
            "skills/gui-build/SKILL.md",
            "skills/gui-review/SKILL.md",
        ]))

    def test_gui_is_design_md_shaped(self) -> None:
        text = self.gui()
        self.assertTrue(text.startswith("---\nversion: alpha\n"))
        self.assertIn('  primary: "#1C1C1E"', text)
        self.assertIn('  secondary-text: "#8A8A8E"', text)
        canonical = [
            "Overview", "Colors", "Typography", "Layout",
            "Elevation & Depth", "Shapes", "Components", "Do's and Don'ts",
        ]
        headings = re.findall(r"^## (.+)$", text, re.M)
        positions = [headings.index(name) for name in canonical]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(len(headings), len(set(headings)))

    def test_gui_quotes_cited_notes_and_drops_untraced_rules(self) -> None:
        text = self.gui()
        self.assertIn('Your words on S1 "I love how calm this is.', text)
        self.assertNotIn('The user\'s note says', text)
        self.assertNotIn("generous outer margins", text)
        self.assertNotIn("single accent colour", text)
        self.assertNotIn("gradients for hero areas", text)
        dropped = json.loads((self.pack / "pack.json").read_text())["dropped"]
        self.assertEqual([d["id"] for d in dropped], ["T3", "R2", "R3", "R4"])

    def test_light_dark_marks_the_unshown_mode(self) -> None:
        text = (self.pack / "references/light-dark.md").read_text()
        self.assertIn("- [T1] `#F6F5F2` background", text)
        self.assertIn("- Not evidenced: no saved reference shows a dark ground.", text)

    def test_sources_never_include_media(self) -> None:
        text = (self.pack / "references/sources.md").read_text()
        self.assertIn("## S3 Glossy gradient dashboard", text)
        self.assertIn("- Role: rejected", text)
        self.assertNotIn("localImagePath", text)

    def test_check_rejects_untraced_guidance(self) -> None:
        path = self.pack / "references/components.md"
        path.write_text(path.read_text() + "\n- Use pill-shaped buttons.\n")
        problems = mood_pack.check_pack(self.pack)
        self.assertTrue(any("no entry ID" in problem for problem in problems), problems)

    def test_check_rejects_dropped_and_unknown_ids(self) -> None:
        path = self.pack / "GUI.md"
        path.write_text(path.read_text() + "\n- [R3] Prefer generous outer margins.\n- [R99] Made up.\n")
        problems = mood_pack.check_pack(self.pack)
        self.assertTrue(any("dropped entry R3" in problem for problem in problems), problems)
        self.assertTrue(any("unknown entry R99" in problem for problem in problems), problems)

    def test_check_rejects_missing_guideline_and_source(self) -> None:
        gui = self.pack / "GUI.md"
        gui.write_text(gui.read_text().replace("- [R1] Keep surfaces flat", "- Not evidenced: removed"))
        sources = self.pack / "references/sources.md"
        sources.write_text(sources.read_text().replace("## S2 ", "## Removed "))
        problems = mood_pack.check_pack(self.pack)
        self.assertIn("R1 is kept but does not appear in GUI.md.", problems)
        self.assertIn("references/sources.md does not list S2.", problems)

    def test_check_rejects_copied_media(self) -> None:
        (self.pack / "references/ref.png").write_bytes(b"\x89PNG")
        problems = mood_pack.check_pack(self.pack)
        self.assertTrue(any("never copy media" in problem for problem in problems), problems)

    def test_unknown_primary_is_refused(self) -> None:
        with self.assertRaises(mood_pack.PackError):
            mood_pack.render_pack(self.trace, self.pack, "Quiet tools", "design/gui", "accent")

    def test_without_primary_no_alias_is_invented(self) -> None:
        mood_pack.render_pack(self.trace, self.pack, "Quiet tools", "design/gui")
        self.assertNotIn("  primary:", self.gui())


class EmptyTraceTests(unittest.TestCase):
    def test_render_refuses_when_nothing_traces(self) -> None:
        essence = load("essence.json")
        trace = mood_pack.build_trace(essence, {})
        self.assertEqual(trace["kept"], [])
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(mood_pack.PackError):
                mood_pack.render_pack(trace, Path(tmp), "Empty", "design/gui")


class CommandLineTests(unittest.TestCase):
    def run_cli(self, *args: str) -> tuple[int, dict]:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            code = mood_pack.main(list(args))
        return code, json.loads(buffer.getvalue())

    def test_trace_render_check(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            trace_path = str(Path(tmp, "trace.json"))
            pack = str(Path(tmp, "pack"))
            code, result = self.run_cli(
                "trace", "--essence", str(FIXTURES / "essence.json"),
                "--items", str(FIXTURES / "items.json"), "--out", trace_path,
            )
            self.assertEqual(code, 0)
            self.assertEqual(result["kept"], 8)
            self.assertEqual(len(result["dropped"]), 4)
            code, _ = self.run_cli("render", "--trace", trace_path, "--out", pack, "--name", "Quiet tools")
            self.assertEqual(code, 0)
            code, result = self.run_cli("check", "--pack", pack)
            self.assertEqual((code, result["problems"]), (0, []))

    def test_errors_are_json(self) -> None:
        code, result = self.run_cli(
            "trace", "--essence", "/nonexistent.json",
            "--items", str(FIXTURES / "items.json"), "--out", "/tmp/unused.json",
        )
        self.assertEqual(code, 2)
        self.assertFalse(result["ok"])


if __name__ == "__main__":
    unittest.main()
