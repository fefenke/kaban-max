#!/usr/bin/env python3
"""Offline documentation integrity, generated facts, and change coverage gate."""
import argparse
import fnmatch
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
START = "<!-- BEGIN GENERATED PROJECT FACTS -->"
END = "<!-- END GENERATED PROJECT FACTS -->"


def is_document(path):
    return path.endswith((".md", ".md.txt")) or path in {"docs/PROJECT_MAP.json"} or path.startswith("docs/archive/")


def required_updates(changed, manifest):
    changed = set(changed)
    errors = []
    if any(path.startswith(".local/") for path in changed):
        errors.append("Private .local files must not be included in the changeset")
    source = sorted(path for path in changed if not is_document(path))
    if not source:
        return errors
    errors += [f"Source changes require an update to {path}"
               for path in manifest.get("global_updates", []) if path not in changed]
    mapped = set()
    for component in manifest["components"]:
        matches = [path for path in source if any(fnmatch.fnmatchcase(path, pattern)
                                                  for pattern in component["patterns"])]
        if matches:
            mapped.update(matches)
            if not changed.intersection(component["docs"]):
                errors.append(f"{component['id']}: update one of {', '.join(component['docs'])} "
                              f"for {matches[0]}")
    unknown = sorted(set(source) - mapped)
    if unknown and not {"docs/COMPONENTS.md", "docs/PROJECT_MAP.json"}.issubset(changed):
        errors.append("Unmapped source changes: update COMPONENTS.md and PROJECT_MAP.json: "
                      + ", ".join(unknown[:5]))
    return errors


def generated_facts(root):
    source = dict(line.split("=", 1) for line in (root / "core/UPSTREAM").read_text(
        encoding="utf-8").splitlines() if "=" in line and not line.startswith("#"))
    constants = (root / "kabanmax/files/usr/lib/core/constants.uc").read_text(encoding="utf-8")
    minimum = re.search(r'SB_REQUIRED_VERSION:\s*"([^"]+)"', constants).group(1)
    validator = (root / "kabanmax/files/usr/lib/config/validator.uc").read_text(encoding="utf-8")
    automatic = re.search(
        r'auto_routing_enabled[^\n]*version_at_least\(binary_version,\s*"(\d+\.\d+\.\d+-r\d+)"',
        validator).group(1)
    patches = len(list((root / "core/patches").glob("*.patch")))
    rows = [("Upstream", f"`{source['repository']}`"),
            ("Закреплённый commit", f"`{source['commit']}`"),
            ("Версия локального ядра", f"`{source['package_version']}`"),
            ("Go toolchain", f"`{source['go_version']}`"),
            ("Количество core patches", str(patches)),
            ("Общий minimum core", f"`{minimum}`"),
            ("Minimum core авторутинга", f"`{automatic}`")]
    return "\n".join([START, "| Факт из исходников | Значение |", "| --- | --- |"]
                     + [f"| {key} | {value} |" for key, value in rows] + [END])


def without_code(text):
    text = re.sub(r"(?ms)^\s*(`{3,}|~{3,})[^\n]*\n.*?^\s*\1\s*$", "", text)
    return re.sub(r"`[^`\n]+`", "", text)


def link_errors(root, paths):
    errors = []
    for relative in paths:
        page = root / relative
        try:
            text = page.read_text(encoding="utf-8")
        except (UnicodeError, OSError) as error:
            errors.append(f"{relative}: cannot read UTF-8: {error}")
            continue
        if "\ufffd" in text or re.search(r"\?{4,}", text):
            errors.append(f"{relative}: damaged encoding placeholder")
        for match in re.finditer(r"!?\[[^\]\n]*\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)", without_code(text)):
            target = match.group(1).strip("<>")
            if target.startswith("#") or urlsplit(target).scheme or target.startswith("//"):
                continue
            target = unquote(target.split("#", 1)[0].split("?", 1)[0])
            resolved = (root / target.lstrip("/") if target.startswith("/") else page.parent / target).resolve()
            if not resolved.is_relative_to(root.resolve()):
                errors.append(f"{relative}: link escapes repository: {target}")
            elif not resolved.exists():
                errors.append(f"{relative}: missing link target: {target}")
    return errors


def git_paths(root, base):
    args = ["git", "diff", "--name-only", "--no-renames", "-z", f"{base}...HEAD" if base else "HEAD", "--"]
    output = subprocess.check_output(args, cwd=root)
    if not base:
        output += subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=root)
    return sorted(set(path.decode("utf-8") for path in output.split(b"\0") if path))


def archive_errors(root, manifest_path):
    manifest_file = root / manifest_path
    archive = json.loads(manifest_file.read_text(encoding="utf-8"))
    errors = []
    for entry in archive["files"]:
        snapshot = (manifest_file.parent / entry["snapshot"]).resolve()
        if not snapshot.is_relative_to(manifest_file.parent.resolve()):
            errors.append(f"{manifest_path}: snapshot escapes archive")
        elif not snapshot.is_file() or snapshot.stat().st_size != entry["bytes"]:
            errors.append(f"{manifest_path}: missing/changed snapshot {entry['snapshot']}")
        elif hashlib.sha256(snapshot.read_bytes()).hexdigest() != entry["sha256"]:
            errors.append(f"{manifest_path}: SHA256 mismatch {entry['snapshot']}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Compare committed changes against BASE...HEAD (CI)")
    parser.add_argument("--no-diff", action="store_true", help="Check integrity/facts only, without change coverage")
    parser.add_argument("--write-facts", action="store_true", help="Refresh only the generated PROJECT_STATE fact table")
    args = parser.parse_args()
    try:
        manifest = json.loads((ROOT / "docs/PROJECT_MAP.json").read_text(encoding="utf-8"))
        errors = []
        if manifest.get("schema_version") != 1:
            raise ValueError("Unsupported PROJECT_MAP schema")
        for component in manifest["components"]:
            for entry in component["entrypoints"] + component["docs"]:
                if entry.startswith(".local/") or not (ROOT / entry).exists():
                    errors.append(f"{component['id']}: missing or private entrypoint/document: {entry}")
        for path, maximum in manifest["entrypoint_max_bytes"].items():
            if (ROOT / path).stat().st_size > maximum:
                errors.append(f"{path}: exceeds {maximum} bytes; move details out of the startup context")
        page = ROOT / "docs/PROJECT_STATE.md"
        current = page.read_text(encoding="utf-8")
        expected = generated_facts(ROOT)
        pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.S)
        if not pattern.search(current):
            errors.append("PROJECT_STATE: generated fact markers missing")
        elif args.write_facts:
            page.write_text(pattern.sub(lambda _match: expected, current), encoding="utf-8", newline="\n")
        elif pattern.search(current).group() != expected:
            errors.append("PROJECT_STATE: source facts changed; run python scripts/check-project-docs.py --write-facts")
        errors += link_errors(ROOT, manifest["maintained_docs"])
        for archive in manifest.get("archives", []):
            errors += archive_errors(ROOT, archive)
        changed = [] if args.no_diff else git_paths(ROOT, args.base)
        errors += required_updates(changed, manifest)
    except (OSError, ValueError, KeyError, AttributeError, subprocess.CalledProcessError) as error:
        print(f"Documentation check could not complete: {error}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"Documentation PASS: {len(manifest['maintained_docs'])} maintained documents; "
          f"source facts, paths, UTF-8, startup budgets; {len(changed)} changed paths checked.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
