"""Focused extraction regressions. Run: python -m unittest discover -s tools -p test_ds2_catalog.py"""
import json
import unittest
from extract_ds2_catalog import ROOT, build, effects, merge, parse, section


class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / "data/reference/ds2_equipment_catalog.json").read_text())
        cls.items = {item["id"]: item for item in cls.catalog["items"]}
        cls.affixes = {item["id"]: item for item in cls.catalog["affixes"]}

    def test_parser_preserves_quotes_comments_and_repeated_effects(self):
        node = parse('[magic] { [*] { value=2; description="a; { // b"; } '
                     '/* ignored [*] {} */ [*] { value=4; } }')
        entries = section(node, "magic")["children"]["*"]
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0]["fields"]["description"], "a; { // b")
        self.assertEqual(entries[1]["fields"]["value"], "4")

    def test_inherited_effect_fields_are_merged_not_dropped(self):
        parent = parse('[strength] { alteration=alter_strength; value=1; }')
        child = parse('[strength] { value=3; }')
        self.assertEqual(effects(merge(parent, child)), [{"alteration": "alter_strength", "value": "3"}])
        sturdy = self.affixes["ofsturdiness"]
        self.assertEqual(sturdy["object_types"], "weapon,armor,ring,amulet")
        self.assertEqual(sturdy["effects"][0]["alteration"], "alter_strength")
        self.assertEqual(sturdy["effects"][0]["value"], "3")

    def test_source_counts_and_completeness_markers(self):
        self.assertFalse(self.catalog["runtime_imported"])
        self.assertEqual(self.catalog["unresolved_parents"], [])
        self.assertEqual(len(self.affixes), 304)
        self.assertEqual(len(self.catalog["sets"]), 27)
        self.assertEqual(sum(i["category"] == "set" for i in self.items.values()), 105)
        self.assertEqual(sum(i["category"] == "crafted" for i in self.items.values()), 239)
        self.assertEqual(len(self.items), len(self.catalog["items"]))

    def test_original_levels_requirements_ranges_and_multiple_enchantments(self):
        short_sword = self.items["sd_1h_ss"]
        self.assertEqual([float(v["item_level"]) for v in short_sword["variants"]], [2, 13, 32, 42, 51])
        self.assertEqual(short_sword["requirements"], "melee:#item_level - 2.0")
        self.assertEqual(short_sword["attack"]["reload_delay"], "0.67")
        claw = self.items["sd_1h_ss_unq_01"]
        mods = {e["alteration"]: e for e in claw["effects"]}
        self.assertEqual(mods["alter_melee_damage_min"]["value"], "7")
        self.assertEqual(mods["alter_magic_find_chance"]["min_value_ceiling"], "20")
        self.assertEqual(len(claw["effects"]), 5)
        self.assertIn("quest_staff_a1_tower", self.items)  # no item-level variant, not silently omitted
        self.assertEqual(self.items["quest_staff_a1_tower"]["variants"], [])

    def test_set_totals_and_source_typo_are_explicit(self):
        night = next(s for s in self.catalog["sets"] if s["id"] == "DWS1_set")
        two = {e["alteration"]: e["value"] for e in night["totals"]["total_2"]}
        self.assertEqual(two["alter_life_steal"], "3")
        self.assertEqual(two["alter_magic_find_chance"], "20")
        self.assertIn("missing opening brace", self.catalog["source_notes"][0])
        self.assertTrue(all(len(digest) == 64 for digest in self.catalog["source_sha256"].values()))

    def test_snapshot_reproduces_from_local_source(self):
        source = ROOT / ".agentbridge/ds2_catalog_source"
        if not source.exists():
            self.skipTest("Installed DS2 sources not extracted on this machine")
        rebuilt = build(source)
        for key, value in rebuilt.items():
            self.assertEqual(value, self.catalog[key], key)


if __name__ == "__main__":
    unittest.main()
