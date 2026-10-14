"""Fail CI early for importable source art and incomplete Godot imports."""

from __future__ import annotations

import argparse
import ast
from pathlib import Path
import subprocess


SOURCE_ART_SUFFIXES = {".blend", ".blend1", ".psd", ".kra", ".xcf", ".ma", ".mb", ".max"}
IMPORTED_PREFIX = "res://.godot/imported/"


def is_importable(path: Path, root: Path) -> bool:
    """Whether Godot can see a file through every parent directory."""
    for directory in (path.parent, *path.parent.parents):
        if not directory.is_relative_to(root):
            break
        if (directory / ".gdignore").is_file():
            return False
    return True


def source_art_violations(root: Path) -> list[Path]:
    tracked = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--cached", "-z"],
        check=True,
        capture_output=True,
    ).stdout
    violations = []
    for name in tracked.split(b"\0"):
        if not name:
            continue
        path = root / Path(name.decode("utf-8", errors="surrogateescape"))
        if path.suffix.lower() in SOURCE_ART_SUFFIXES and is_importable(path, root):
            violations.append(path.relative_to(root))
    return sorted(violations)


def _setting(contents: str, key: str) -> str | None:
    for line in contents.splitlines():
        left, separator, right = line.partition("=")
        if separator and left.strip() == key:
            return right.strip()
    return None


def _quoted(value: str | None) -> str | None:
    if value is None:
        return None
    try:
        parsed = ast.literal_eval(value)
    except (SyntaxError, ValueError):
        return None
    return parsed if isinstance(parsed, str) else None


def missing_imports(root: Path) -> list[tuple[Path, str]]:
    missing = []
    for metadata in root.rglob("*.import"):
        if not is_importable(metadata, root):
            continue
        contents = metadata.read_text(encoding="utf-8-sig")
        if _quoted(_setting(contents, "importer")) in {"keep", "skip"}:
            continue
        destinations = []
        raw_destinations = _setting(contents, "dest_files")
        if raw_destinations is not None:
            try:
                parsed = ast.literal_eval(raw_destinations)
            except (SyntaxError, ValueError):
                parsed = None
            if isinstance(parsed, list):
                destinations = [item for item in parsed if isinstance(item, str)]
        if not destinations:
            fallback = _quoted(_setting(contents, "path"))
            if fallback:
                destinations = [fallback]
        for destination in destinations:
            if destination.startswith(IMPORTED_PREFIX):
                target = root / destination.removeprefix("res://")
                if not target.is_file():
                    missing.append((metadata.relative_to(root), destination))
    return sorted(missing)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--source-art", action="store_true", help="check tracked source art only")
    modes.add_argument("--missing-imports", action="store_true", help="check generated import targets only")
    args = parser.parse_args()
    root = args.root.resolve()
    failed = False

    if not args.missing_imports:
        violations = source_art_violations(root)
        for path in violations:
            print(f"Source art under importable res://: {path.as_posix()} - move into a folder containing .gdignore")
        print(f"Source-art guard: {len(violations)} offending tracked file(s)")
        failed |= bool(violations)

    if not args.source_art:
        missing = missing_imports(root)
        for metadata, destination in missing:
            print(f"Missing Godot import: {destination} (declared by {metadata.as_posix()})")
        print(f"Missing-import check: {len(missing)} missing target(s)")
        failed |= bool(missing)

    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
