#!/usr/bin/env python3
"""Validation tool for Dungeon Siege II alter_generic equipment script inventory.

Verifies completeness and consistency of:
    data/reference/ds2_generic_script_inventory.json
against the source catalog:
    data/reference/ds2_equipment_catalog.json

Run:
    python tools/check_ds2_generic_inventory.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = ROOT / "data/reference/ds2_equipment_catalog.json"
INVENTORY_PATH = ROOT / "data/reference/ds2_generic_script_inventory.json"

EXPECTED_TOTAL_OCCURRENCES = 92
EXPECTED_ITEM_OCCURRENCES = 89
EXPECTED_SET_TIER_OCCURRENCES = 3
EXPECTED_WEAPON_ENCHANT_COUNT = 88

REQUIRED_FIELDS = [
    "item_id",
    "item_name",
    "category",
    "weapon_family",
    "source_file",
    "is_set_bonus",
    "alteration",
    "raw_value",
    "duration",
    "verification_status",
    "mechanic_classification",
]


def validate() -> int:
    print("=" * 70)
    print("Dungeon Siege II alter_generic Script Inventory Validation")
    print("=" * 70)

    # 1. File existence
    if not CATALOG_PATH.exists():
        print(f"FAIL: Source catalog not found at {CATALOG_PATH}")
        return 1
    if not INVENTORY_PATH.exists():
        print(f"FAIL: Inventory not found at {INVENTORY_PATH}")
        return 1

    # 2. Parse JSON
    try:
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"FAIL: Failed to parse catalog JSON: {e}")
        return 1

    try:
        inventory = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"FAIL: Failed to parse inventory JSON: {e}")
        return 1

    # 3. Scan catalog for all alter_generic occurrences
    catalog_items = {}
    for item in catalog.get("items", []):
        for eff in item.get("effects", []):
            if eff.get("alteration") == "alter_generic":
                catalog_items[item["id"]] = item

    catalog_set_tiers = {}
    for s in catalog.get("sets", []):
        for total_key, eff_list in s.get("totals", {}).items():
            for eff in eff_list:
                if eff.get("alteration") == "alter_generic":
                    catalog_set_tiers[(s["id"], total_key)] = (s, eff)

    cat_item_count = len(catalog_items)
    cat_set_count = len(catalog_set_tiers)
    cat_total = cat_item_count + cat_set_count

    print(f"Source catalog scanned:")
    print(f"  - Item occurrences with alter_generic:     {cat_item_count:3d}")
    print(f"  - Set tier occurrences with alter_generic: {cat_set_count:3d}")
    print(f"  - Total catalog occurrences:               {cat_total:3d}")

    if cat_total != EXPECTED_TOTAL_OCCURRENCES:
        print(f"FAIL: Catalog alter_generic total ({cat_total}) does not match expected {EXPECTED_TOTAL_OCCURRENCES}")
        return 1

    # 4. Inventory structure and summary validation
    summary = inventory.get("summary", {})
    inv_occurrences = inventory.get("occurrences", [])
    inv_count = len(inv_occurrences)

    print(f"\nInventory structure scanned:")
    print(f"  - Recorded occurrences:                    {inv_count:3d}")
    print(f"  - Summary reported total:                  {summary.get('total_occurrences', 0):3d}")
    print(f"  - Summary reported items:                  {summary.get('total_item_occurrences', 0):3d}")
    print(f"  - Summary reported set tiers:              {summary.get('total_set_tier_occurrences', 0):3d}")

    if inv_count != EXPECTED_TOTAL_OCCURRENCES:
        print(f"FAIL: Inventory occurrence count ({inv_count}) != {EXPECTED_TOTAL_OCCURRENCES}")
        return 1
    if summary.get("total_occurrences") != EXPECTED_TOTAL_OCCURRENCES:
        print(f"FAIL: Inventory summary total ({summary.get('total_occurrences')}) != {EXPECTED_TOTAL_OCCURRENCES}")
        return 1
    if summary.get("total_item_occurrences") != EXPECTED_ITEM_OCCURRENCES:
        print(f"FAIL: Inventory summary items ({summary.get('total_item_occurrences')}) != {EXPECTED_ITEM_OCCURRENCES}")
        return 1
    if summary.get("total_set_tier_occurrences") != EXPECTED_SET_TIER_OCCURRENCES:
        print(f"FAIL: Inventory summary set tiers ({summary.get('total_set_tier_occurrences')}) != {EXPECTED_SET_TIER_OCCURRENCES}")
        return 1

    # 5. Check item mapping and field completeness
    inv_by_id = {}
    for idx, occ in enumerate(inv_occurrences):
        iid = occ.get("item_id")
        if not iid:
            print(f"FAIL: Occurrence at index {idx} missing item_id")
            return 1
        if iid in inv_by_id:
            print(f"FAIL: Duplicate item_id in inventory: {iid}")
            return 1
        inv_by_id[iid] = occ

        # Check required fields
        for rf in REQUIRED_FIELDS:
            if rf not in occ or occ[rf] is None:
                print(f"FAIL: Occurrence '{iid}' missing required field: {rf}")
                return 1

    # Check that all catalog items are in inventory
    missing_items = set(catalog_items.keys()) - set(inv_by_id.keys())
    if missing_items:
        print(f"FAIL: Catalog items missing from inventory: {missing_items}")
        return 1

    # Check set tier entries
    for (sid, tkey) in catalog_set_tiers.keys():
        expected_tier_id = f"{sid}_{tkey}"
        if expected_tier_id not in inv_by_id:
            print(f"FAIL: Set tier '{expected_tier_id}' missing from inventory")
            return 1

    # 6. Verify script groupings and mechanics breakdown
    weapon_enchant_count = 0
    crafted_range_count = 0
    mysterious_set_count = 0

    for iid, occ in inv_by_id.items():
        sid = occ.get("script_identifier")
        if sid == r"world\global\enchantments\weapon_enchant.skrit":
            weapon_enchant_count += 1
            if not occ.get("custom_effect"):
                print(f"FAIL: Item '{iid}' has weapon_enchant.skrit but missing custom_effect")
                return 1
            if not occ.get("custom_effect_skrit"):
                print(f"FAIL: Item '{iid}' has weapon_enchant.skrit but missing custom_effect_skrit")
                return 1
            if not occ.get("script_parameters"):
                print(f"FAIL: Item '{iid}' has weapon_enchant.skrit but empty script_parameters")
                return 1
            if occ.get("verification_status") != "verified":
                print(f"FAIL: Item '{iid}' with weapon_enchant.skrit not marked verified")
                return 1
        elif iid == "wpn_a1_vet_crafted_9":
            crafted_range_count += 1
            if occ.get("description") != "+5% Range":
                print(f"FAIL: wpn_a1_vet_crafted_9 expected '+5% Range' description, got {occ.get('description')}")
                return 1
            if occ.get("verification_status") != "verified":
                print(f"FAIL: wpn_a1_vet_crafted_9 not marked verified")
                return 1
        elif occ.get("is_set_bonus"):
            mysterious_set_count += 1
            if occ.get("set_id") != "mysterious":
                print(f"FAIL: Unexpected set bonus set_id: {occ.get('set_id')}")
                return 1
            if not occ.get("description"):
                print(f"FAIL: Set tier '{iid}' missing cipher description")
                return 1
        else:
            print(f"FAIL: Uncategorized occurrence '{iid}' with script {sid}")
            return 1

    print(f"\nMechanics validation:")
    print(f"  - weapon_enchant.skrit occurrences:        {weapon_enchant_count:3d} (expected {EXPECTED_WEAPON_ENCHANT_COUNT})")
    print(f"  - Crafted bow range descriptor:            {crafted_range_count:3d} (expected 1)")
    print(f"  - Mysterious set cipher tiers:             {mysterious_set_count:3d} (expected {EXPECTED_SET_TIER_OCCURRENCES})")

    if weapon_enchant_count != EXPECTED_WEAPON_ENCHANT_COUNT:
        print(f"FAIL: weapon_enchant.skrit count ({weapon_enchant_count}) != {EXPECTED_WEAPON_ENCHANT_COUNT}")
        return 1
    if crafted_range_count != 1:
        print(f"FAIL: crafted_range_count != 1")
        return 1
    if mysterious_set_count != EXPECTED_SET_TIER_OCCURRENCES:
        print(f"FAIL: mysterious_set_count != {EXPECTED_SET_TIER_OCCURRENCES}")
        return 1

    # 7. Check script_groups structure
    script_groups = inventory.get("script_groups", {})
    if r"world\global\enchantments\weapon_enchant.skrit" not in script_groups:
        print(f"FAIL: Missing weapon_enchant.skrit in script_groups")
        return 1
    we_group = script_groups[r"world\global\enchantments\weapon_enchant.skrit"]
    if we_group.get("occurrence_count") != EXPECTED_WEAPON_ENCHANT_COUNT:
        print(f"FAIL: weapon_enchant.skrit group count ({we_group.get('occurrence_count')}) != {EXPECTED_WEAPON_ENCHANT_COUNT}")
        return 1

    print("\n" + "=" * 70)
    print("PASS: All 92 alter_generic occurrences verified against source catalog.")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(validate())
