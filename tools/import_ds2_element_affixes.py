#!/usr/bin/env python3
"""Add the ice / lightning / death damage and resistance modifier families to data/reference/ds2_affixes.json.

Source: the `affixes` list of data/reference/ds2_equipment_catalog.json (DS2 pcontent.gas, alterations
alter_custom_damage_{ice,lightning,death} and alter_{ice,lightning,death}_resistance). Fire is imported by
extract_ds2_affixes.py. Run, then tools/write_affix_defs.py writes the .tres tiers.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARMOUR_SLOTS = ["amulet", "body", "boots", "gloves", "helm", "ring", "shield"]   # spellbook is not a Curse slot
ELEMENTS = ("ice", "lightning", "death")


def main():
    catalog = json.loads((ROOT / "data/reference/ds2_equipment_catalog.json").read_text())
    path = ROOT / "data/reference/ds2_affixes.json"
    families = json.loads(path.read_text())
    for element in ELEMENTS:
        damage, resist = [], []
        for affix in catalog["affixes"]:
            for effect in affix["effects"]:
                name = effect["alteration"].lower()
                if name == f"alter_custom_damage_{element}":
                    value = float(effect["value"])
                    damage.append(dict(source=affix["id"], title=affix["screen_name"], level=int(affix["level"]), value=value,
                        max_value=float(effect.get("max_value", value)), value_ceiling=value, stat=f"{element}_added", percent=False,
                        position=affix["type"], slots=["weapon"], classes=affix["skill_types"].split(",")))
                elif name == f"alter_{element}_resistance":
                    value = round(float(effect["value"]) * 100, 6)
                    resist.append(dict(source=affix["id"], title=affix["screen_name"], level=int(affix["level"]), value=value,
                        max_value=value, value_ceiling=value, stat=f"{element}_resist", percent=True, position=affix["type"],
                        slots=list(ARMOUR_SLOTS), classes=affix["skill_types"].split(",")))
        damage.sort(key=lambda r: (r["classes"], r["level"]))
        resist.sort(key=lambda r: r["level"])
        families[f"{element}_added"] = damage
        families[f"{element}_resist"] = resist
    # Keep the four catalog-backed defensive families after the elemental families,
    # preserving the established reference-catalog order across full regeneration.
    for family in ("physical_resist", "melee_resist", "ranged_resist", "magical_resist"):
        families[family] = families.pop(family)
    path.write_text(json.dumps(families, indent=2) + "\n", newline="\n")
    print("imported", {k: len(v) for k, v in families.items() if k.split("_")[0] in ELEMENTS})


if __name__ == "__main__":
    main()
