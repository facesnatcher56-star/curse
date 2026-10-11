#!/usr/bin/env python3
"""Write supported DS2 modifier tiers from the exact extracted baseline.
Refresh with extract_ds2_affixes.py. Legacy overflow tiers remain loadable, but cannot roll.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data/affixes"


def main():
    families = json.loads((ROOT / "data/reference/ds2_affixes.json").read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    for family, records in families.items():
        old_count = max((int(p.stem.rsplit("_", 1)[1]) for p in OUT.glob(family + "_*.tres")
                         if p.stem.rsplit("_", 1)[0] == family), default=0)
        for index in range(max(old_count, len(records))):
            record = records[min(index, len(records) - 1)]
            ident = f"{family}_{index + 1}"
            lines = ['[gd_resource type="Resource" script_class="AffixDef" load_steps=2 format=3]', '',
                     '[ext_resource type="Script" path="res://game/data/affix_def.gd" id="1"]', '', '[resource]',
                     'script = ExtResource("1")', f'id = "{ident}"', f'family = "{family}"', f'tier = {index + 1}']
            for key in ("stat", "title", "position"):
                lines.append(f'{key} = {json.dumps(record[key])}')
            for key in ("level", "value", "max_value", "value_ceiling"):
                lines.append(f'{key} = {record[key]}')
            lines.append(f'percent = {str(record["percent"]).lower()}')
            for key in ("slots", "classes"):
                values = record[key] if index < len(records) else []
                lines.append(f'{key} = Array[String]({json.dumps(values)})')
            (OUT / f"{ident}.tres").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("wrote", sum(map(len, families.values())), "exact DS2 modifier tiers; preserved legacy aliases")


if __name__ == "__main__":
    main()
