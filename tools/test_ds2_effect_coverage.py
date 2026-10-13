#!/usr/bin/env python3
"""
Unit tests for Dungeon Siege II effect coverage manifest completeness,
deterministic generation, and validation checker.
"""

import json
import os
import sys
import unittest

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)
TOOLS_DIR = os.path.join(BASE_DIR, "tools")
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

from check_ds2_effect_coverage import validate_coverage, verify_consumer_or_test_path, VALID_STATUSES
from generate_ds2_effect_manifest import build_manifest_data, CATALOG_PATH, MANIFEST_PATH


class TestDS2EffectCoverage(unittest.TestCase):
    def setUp(self):
        self.assertTrue(os.path.exists(CATALOG_PATH), f"Catalog file not found: {CATALOG_PATH}")
        with open(CATALOG_PATH, "r", encoding="utf-8") as f:
            self.catalog = json.load(f)

    def test_catalog_source_counts(self):
        """Validate catalog has exact expected counts from DS2 gap audit."""
        self.assertEqual(len(self.catalog.get("items", [])), 768)
        self.assertEqual(len(self.catalog.get("affixes", [])), 304)
        self.assertEqual(len(self.catalog.get("sets", [])), 27)

    def test_distinct_alterations_count(self):
        """Verify exactly 58 distinct alterations exist across items, affixes, and sets."""
        alts = set()
        for it in self.catalog.get("items", []):
            for e in it.get("effects", []):
                alts.add(e["alteration"])
        for af in self.catalog.get("affixes", []):
            for e in af.get("effects", []):
                alts.add(e["alteration"])
        for s in self.catalog.get("sets", []):
            for effs in s.get("totals", {}).values():
                for e in effs:
                    alts.add(e["alteration"])
        self.assertEqual(len(alts), 58)

    def test_manifest_validation_clean(self):
        """Run automated validator and assert zero errors on real repository files."""
        errors = validate_coverage(CATALOG_PATH, MANIFEST_PATH)
        self.assertEqual(errors, [], f"Validation errors found: {errors}")

    def test_deterministic_generation(self):
        """Verify generate_ds2_effect_manifest produces identical manifest content."""
        generated = build_manifest_data(self.catalog)
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            existing = json.load(f)
        self.assertEqual(generated, existing)

    def test_classification_categories(self):
        """Verify each category has expected number of alterations and valid statuses."""
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        alts = manifest.get("alterations", {})
        self.assertEqual(len(alts), 58)

        status_counts = {"supported": 0, "untested": 0, "unsupported": 0, "unresolved": 0, "cosmetic_only": 0, "excluded": 0}
        for alt_id, data in alts.items():
            st = data.get("status")
            self.assertIn(st, VALID_STATUSES)
            status_counts[st] += 1

            if st == "supported":
                self.assertIsNotNone(data.get("runtime_consumer"))
                self.assertIsNotNone(data.get("test_path"))
                self.assertIsNotNone(data.get("runtime_key"))
            elif st == "untested":
                self.assertIsNotNone(data.get("runtime_consumer"))
                self.assertIsNone(data.get("test_path"))
                self.assertIsNotNone(data.get("runtime_key"))
            elif st in ("unsupported", "unresolved"):
                self.assertIsNone(data.get("runtime_consumer"))
                self.assertIsNone(data.get("test_path"))

        self.assertEqual(status_counts["supported"], 42)
        self.assertEqual(status_counts["untested"], 0)
        self.assertEqual(status_counts["unsupported"], 15)
        self.assertEqual(status_counts["unresolved"], 0)
        self.assertEqual(status_counts["cosmetic_only"], 1)
        self.assertEqual(status_counts["excluded"], 0)

    def test_alter_generic_classified_as_cosmetic_only(self):
        """Ensure alter_generic is accurately classified as cosmetic_only without fabricated gameplay."""
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        alter_generic = manifest["alterations"].get("alter_generic")
        self.assertIsNotNone(alter_generic)
        self.assertEqual(alter_generic["status"], "cosmetic_only")
        self.assertIsNone(alter_generic["runtime_consumer"])
        self.assertIsNone(alter_generic["test_path"])

    def test_template_properties_coverage(self):
        """Ensure all 24 template and attack properties are accounted for."""
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        template_props = manifest.get("template_properties", {})
        self.assertEqual(len(template_props), 24)

    def test_requirement_patterns_coverage(self):
        """Ensure all 7 requirement syntax classes are accounted for."""
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        patterns = manifest.get("requirement_patterns", {})
        self.assertEqual(len(patterns), 7)
        self.assertEqual(patterns["discipline_offset"]["status"], "supported")
        self.assertEqual(patterns["discipline_fixed"]["status"], "supported")
        self.assertEqual(patterns["alternative_or"]["status"], "supported")
        self.assertEqual(patterns["conjunction_and"]["status"], "supported")
        self.assertEqual(patterns["passive_rank"]["status"], "supported")
        self.assertEqual(patterns["character_level_uber"]["status"], "supported")
        self.assertEqual(patterns["attribute_threshold"]["status"], "supported")

    def test_validation_fails_on_missing_property(self):
        """Test that validator catches and flags omitted alterations."""
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        del manifest["alterations"]["alter_strength"]
        temp_manifest_path = os.path.join(BASE_DIR, "data", "reference", "_temp_test_missing_alt.json")
        try:
            with open(temp_manifest_path, "w", encoding="utf-8") as f:
                json.dump(manifest, f)
            errors = validate_coverage(CATALOG_PATH, temp_manifest_path)
            self.assertTrue(len(errors) > 0)
            self.assertTrue(any("alter_strength" in e for e in errors))
        finally:
            if os.path.exists(temp_manifest_path):
                os.remove(temp_manifest_path)

    def test_validation_rejects_nonexistent_test_file(self):
        """Test that validator rejects nonexistent test suite paths."""
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        manifest["alterations"]["alter_strength"]["test_path"] = "tests/test_stats.gd"
        temp_manifest_path = os.path.join(BASE_DIR, "data", "reference", "_temp_test_nonexistent_file.json")
        try:
            with open(temp_manifest_path, "w", encoding="utf-8") as f:
                json.dump(manifest, f)
            errors = validate_coverage(CATALOG_PATH, temp_manifest_path)
            self.assertTrue(len(errors) > 0)
            self.assertTrue(any("tests/test_stats.gd" in e for e in errors))
        finally:
            if os.path.exists(temp_manifest_path):
                os.remove(temp_manifest_path)

    def test_validation_rejects_nonexistent_symbol(self):
        """Test that validator rejects nonexistent function/method symbol in real file."""
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        manifest["alterations"]["alter_strength"]["runtime_consumer"] = "game/player/player_stats.gd:fake_method_does_not_exist()"
        temp_manifest_path = os.path.join(BASE_DIR, "data", "reference", "_temp_test_nonexistent_sym.json")
        try:
            with open(temp_manifest_path, "w", encoding="utf-8") as f:
                json.dump(manifest, f)
            errors = validate_coverage(CATALOG_PATH, temp_manifest_path)
            self.assertTrue(len(errors) > 0)
            self.assertTrue(any("fake_method_does_not_exist" in e for e in errors))
        finally:
            if os.path.exists(temp_manifest_path):
                os.remove(temp_manifest_path)

    def test_validation_rejects_untested_with_claimed_test_path(self):
        """Test that validator rejects untested status if a test path is claimed."""
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        manifest["alterations"]["alter_intelligence"]["status"] = "untested"
        manifest["alterations"]["alter_intelligence"]["test_path"] = "game/dev/suites/ds2_tests.gd:_test_ds2_items()"
        temp_manifest_path = os.path.join(BASE_DIR, "data", "reference", "_temp_test_untested_claim.json")
        try:
            with open(temp_manifest_path, "w", encoding="utf-8") as f:
                json.dump(manifest, f)
            errors = validate_coverage(CATALOG_PATH, temp_manifest_path)
            self.assertTrue(len(errors) > 0)
            self.assertTrue(any("alter_intelligence" in e and "must be null" in e for e in errors))
        finally:
            if os.path.exists(temp_manifest_path):
                os.remove(temp_manifest_path)


if __name__ == "__main__":
    unittest.main()
