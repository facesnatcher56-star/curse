"""Focused checks for the CI Godot import guard."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from ci_check_imports import missing_imports, source_art_violations


class ImportGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def write(self, name: str, contents: str = "") -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def test_tracked_blend_in_importable_directory_fails(self) -> None:
        self.write("assets/model.blend")
        subprocess.run(["git", "-C", str(self.root), "add", "assets/model.blend"], check=True)
        self.assertEqual(source_art_violations(self.root), [Path("assets/model.blend")])

    def test_blend_below_gdignore_passes(self) -> None:
        self.write("assets/source/.gdignore")
        self.write("assets/source/model.blend")
        subprocess.run(["git", "-C", str(self.root), "add", "assets/source"], check=True)
        self.assertEqual(source_art_violations(self.root), [])

    def test_missing_destination_fails(self) -> None:
        self.write(
            "assets/icon.png.import",
            '[remap]\nimporter="texture"\npath="res://.godot/imported/icon.ctex"\n'
            '[deps]\ndest_files=["res://.godot/imported/icon.ctex"]\n',
        )
        self.assertEqual(
            missing_imports(self.root),
            [(Path("assets/icon.png.import"), "res://.godot/imported/icon.ctex")],
        )

    def test_present_destination_passes(self) -> None:
        self.write("assets/icon.png.import", '[deps]\ndest_files=["res://.godot/imported/icon.ctex"]\n')
        self.write(".godot/imported/icon.ctex")
        self.assertEqual(missing_imports(self.root), [])

    def test_path_fallback_and_skip_importer(self) -> None:
        self.write("assets/fallback.import", '[remap]\npath="res://.godot/imported/fallback.ctex"\n')
        self.write(
            "assets/skipped.import",
            '[remap]\nimporter="skip"\npath="res://.godot/imported/skipped.ctex"\n',
        )
        self.assertEqual(
            missing_imports(self.root),
            [(Path("assets/fallback.import"), "res://.godot/imported/fallback.ctex")],
        )


if __name__ == "__main__":
    unittest.main()
