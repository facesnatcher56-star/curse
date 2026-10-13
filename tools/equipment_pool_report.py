#!/usr/bin/env python3
"""Report and validate ordinary item-base coverage in the midgame loot windows."""
from collections import defaultdict
import json
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]
SLOT_NAMES = ["weapon", "body", "ring", "shield", "helm", "gloves", "boots", "amulet"]
LEVELS = (30, 35, 40, 45, 50)
ADDITIONS = {
    "chain_mail", "heater_shield", "dragon_helm", "carved_cap", "studded_gloves",
    "sorcerer_boots", "gold_ring", "jeweled_ring", "gold_amulet",
}
SOURCE_IDS = {
    "chain_mail": "amr_bdy_ftr_chain",
    "heater_shield": "amr_shd_htr",
    "dragon_helm": "amr_hlm_nmg_dragon",
    "carved_cap": "amr_hlm_rng_carved",
    "studded_gloves": "amr_glv_ftr_studded",
    "sorcerer_boots": "amr_bot_cmg_sorcerer",
    "gold_ring": "ring_02",
    "jeweled_ring": "ring_03",
    "gold_amulet": "amulet_01",
}


def main() -> None:
    items = runpy.run_path(str(ROOT / "tools" / "write_item_defs.py"))["ITEMS"]
    if len({row[0] for row in items}) != len(items):
        raise SystemExit("duplicate base item IDs")
    if not ADDITIONS.issubset({row[0] for row in items}):
        raise SystemExit("one or more Wave 1 additions are missing")

    print("Ordinary item pool coverage (monster level; item window = level -5..+1)")
    for monster_level in LEVELS:
        low, high = monster_level - 5, monster_level + 1
        by_slot: dict[int, dict[str, list[int]]] = defaultdict(lambda: defaultdict(list))
        for ident, _name, slot, _kind, _armor, item_levels, _stats in items:
            for item_level in item_levels:
                if low <= item_level <= high:
                    by_slot[slot][ident].append(item_level)
        fields = []
        for slot, name in enumerate(SLOT_NAMES):
            bases = by_slot.get(slot, {})
            variants = sum(len(values) for values in bases.values())
            fields.append(f"{name} {len(bases)} bases/{variants} variants")
            if not bases:
                raise SystemExit(f"no in-window base for {name} at monster level {monster_level}")
        print(f"  {monster_level} ({low}..{high}): " + "; ".join(fields))

    writer = runpy.run_path(str(ROOT / "tools" / "write_item_defs.py"))
    item_rows = {row[0]: row for row in items}
    catalog = json.loads((ROOT / "data" / "reference" / "ds2_equipment_catalog.json").read_text(encoding="utf-8"))
    catalog_rows = {row["id"]: row for row in catalog["items"]}
    for ident in ADDITIONS:
        row = item_rows[ident]
        source = catalog_rows[SOURCE_IDS[ident]]
        source_levels = [int(float(variant["item_level"])) for variant in source["variants"]]
        if (source["category"] != "normal" or source["pcontent_allowed"] != "true"
                or source["name"] != row[1] or source_levels != row[5]
                or source["requirements"] != writer["SOURCE_REQUIREMENTS"].get(ident, "")):
            raise SystemExit(f"source mismatch for {ident} against catalog row {SOURCE_IDS[ident]}")
        resource = ROOT / "data" / "items" / f"{ident}.tres"
        if not resource.exists() or f'id = "{ident}"' not in resource.read_text(encoding="utf-8"):
            raise SystemExit(f"missing or mismatched generated resource: {resource}")
        model, icon = writer["CUSTOM_PATHS"][ident]
        for asset in (model, icon):
            if not (ROOT / asset.removeprefix("res://")).is_file():
                raise SystemExit(f"missing aliased asset for {ident}: {asset}")
    print(f"Validated {len(ADDITIONS)} additions, generated resources, and model/icon aliases.")


if __name__ == "__main__":
    main()
