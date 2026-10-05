#!/usr/bin/env python3
"""Writes res://data/items/*.tres (ItemDef resources): the base items. Slot: 0 weapon, 1 armor, 2 trinket. Edit and re-run.

Models and icons come from tools/blender/make_items.py (assets/models/items/<id>/model.glb, assets/icons/items/<id>.png).
Weapons trade speed against damage; armour trades protection against mobility. Stats are at tier 1; `tier_mult` grows a stat by a
fraction per tier above 1, `tier_add` by a flat amount.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "items"

ITEMS = [
    # id, display name, slot, stats, tier_mult, tier_add
    ("falchion", "Falchion", 0, {"damage": 0.9, "speed": 1.18}, {"damage": 0.08}, {}),
    ("longsword", "Longsword", 0, {"damage": 1.0, "speed": 1.0}, {"damage": 0.08}, {}),
    ("greatsword", "Greatsword", 0, {"damage": 1.35, "speed": 0.82}, {"damage": 0.08}, {}),
    ("leather_jerkin", "Leather Jerkin", 1, {"armor": 15.0, "roll_cost": 0.8, "roll_speed": 1.1}, {}, {"armor": 6.0}),
    ("mail_hauberk", "Mail Hauberk", 1, {"armor": 35.0, "roll_cost": 1.0, "roll_speed": 1.0}, {}, {"armor": 6.0}),
    ("plate_cuirass", "Plate Cuirass", 1, {"armor": 60.0, "roll_cost": 1.4, "roll_speed": 0.9}, {}, {"armor": 6.0}),
    ("charm", "Charm", 2, {}, {}, {}),
    ("signet", "Signet", 2, {}, {}, {}),
    ("talisman", "Talisman", 2, {}, {}, {}),
]


def fmt(v) -> str:
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n%s\n}" % ",\n".join('"%s": %s' % (k, fmt(x)) for k, x in v.items())
    return str(v)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for order, (ident, name, slot, stats, mult, add) in enumerate(ITEMS):
        wanted.add(ident + ".tres")
        lines = [
            '[gd_resource type="Resource" script_class="ItemDef" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://game/data/item_def.gd" id="1"]', "", "[resource]",
            'script = ExtResource("1")', 'id = "%s"' % ident, 'display_name = "%s"' % name, "slot = %d" % slot, "order = %d" % order,
            'model_path = "res://assets/models/items/%s/model.glb"' % ident, 'icon_path = "res://assets/icons/items/%s.png"' % ident,
            "stats = %s" % fmt(stats), "tier_mult = %s" % fmt(mult), "tier_add = %s" % fmt(add),
        ]
        (OUT / (ident + ".tres")).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for old in OUT.glob("*.tres"):
        if old.name not in wanted:
            old.unlink()   # an item removed from the table leaves no file behind
    print("wrote", len(ITEMS), "items")


if __name__ == "__main__":
    main()
