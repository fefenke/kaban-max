"""Behavioral checks for the documentation gate; no third-party dependencies."""
import importlib.util
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("project_docs", ROOT / "scripts/check-project-docs.py")
docs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(docs)


class DocumentationGateTests(unittest.TestCase):
    def test_code_change_requires_state_and_its_component_document(self):
        manifest = {"global_updates": ["docs/PROJECT_STATE.md"], "components": [
            {"id": "core", "patterns": ["core/*"], "docs": ["docs/ARCHITECTURE.md"]}]}
        self.assertEqual(len(docs.required_updates(["core/UPSTREAM"], manifest)), 2)
        self.assertEqual(docs.required_updates([
            "core/UPSTREAM", "docs/PROJECT_STATE.md", "docs/ARCHITECTURE.md"], manifest), [])

    def test_every_matching_component_is_checked(self):
        manifest = {"global_updates": [], "components": [
            {"id": "frontend", "patterns": ["fe-app-kabanmax/*"], "docs": ["docs/COMPONENTS.md"]},
            {"id": "autoroute", "patterns": ["*/autoRouting.ts"], "docs": ["docs/AUTO_ROUTING_STORAGE.md"]}]}
        missing = docs.required_updates(["fe-app-kabanmax/src/autoRouting.ts", "docs/COMPONENTS.md"], manifest)
        self.assertEqual(len(missing), 1)
        self.assertIn("autoroute", missing[0])

    def test_doc_only_changes_do_not_demand_product_tests_or_state_churn(self):
        manifest = {"global_updates": ["docs/PROJECT_STATE.md"], "components": []}
        self.assertEqual(docs.required_updates(["docs/WORKFLOW.md"], manifest), [])

    def test_private_markdown_is_not_exempted_as_a_documentation_only_change(self):
        manifest = {"global_updates": [], "components": []}
        self.assertTrue(docs.required_updates([".local/private.md"], manifest))

    def test_unknown_source_requires_a_component_map_update(self):
        manifest = {"global_updates": [], "components": []}
        self.assertTrue(docs.required_updates(["new-engine/entry.go"], manifest))
        self.assertEqual(docs.required_updates([
            "new-engine/entry.go", "docs/COMPONENTS.md", "docs/PROJECT_MAP.json"], manifest), [])

    def test_links_support_unicode_and_ignore_external_and_code_examples(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "docs").mkdir()
            (root / "docs/файл с пробелами.md").write_text("# Example\n", encoding="utf-8")
            page = root / "docs/ENTRY.md"
            page.write_text("[local](<файл с пробелами.md>) [web](https://example.invalid)\n"
                            "```md\n[example](missing.md)\n```\n", encoding="utf-8")
            self.assertEqual(docs.link_errors(root, ["docs/ENTRY.md"]), [])
            page.write_text("[bad](absent.md)\n", encoding="utf-8")
            self.assertTrue(docs.link_errors(root, ["docs/ENTRY.md"]))

    def test_links_must_not_escape_the_repository(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "ENTRY.md").write_text("[outside](../outside.md)", encoding="utf-8")
            self.assertTrue(docs.link_errors(root, ["ENTRY.md"]))

    def test_current_generated_facts_are_derived_from_the_source(self):
        facts = docs.generated_facts(ROOT)
        upstream = (ROOT / "core/UPSTREAM").read_text(encoding="utf-8")
        self.assertIn(next(line.split("=", 1)[1] for line in upstream.splitlines()
                           if line.startswith("package_version=")), facts)
        self.assertIn(str(len(list((ROOT / "core/patches").glob("*.patch")))), facts)

    def test_archived_history_cannot_be_modified_without_detection(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            snapshot = root / "history.md.txt"
            snapshot.write_bytes(b"old evidence\n")
            manifest = {"files": [{"snapshot": snapshot.name, "bytes": snapshot.stat().st_size,
                                   "sha256": hashlib.sha256(snapshot.read_bytes()).hexdigest()}]}
            (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            self.assertEqual(docs.archive_errors(root, "manifest.json"), [])
            snapshot.write_bytes(b"new evidence\n")
            self.assertTrue(docs.archive_errors(root, "manifest.json"))


if __name__ == "__main__":
    unittest.main()
