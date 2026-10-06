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


# Weapons beyond damage and speed (see ItemDef.profile). The longsword is the baseline: its moveset is what the game always had.
PROFILES = {
    "falchion": {"throw": {"charge_time": 0.85, "min_range": 5.0, "max_range": 17.0, "speed": 36.0, "recall_speed": 35.0, "recall_accel": 80.0,
                           "damage": 1.9, "mass": 0.7, "prop_force": 0.8, "spin": 15.0, "swing_speed": 1.3, "catch_time": 0.28,
                           "catch_recover": 0.1, "rip_time": 0.3, "sweep_radius": 0.4, "pitch": 1.0},
                 "recovery": 1.7, "weight": 0.7, "finisher_time": 0.9,
                 "style": "Fast combo and recovery, light stagger"},
    "longsword": {"throw": {"charge_time": 1.15, "min_range": 6.0, "max_range": 21.0, "speed": 30.0, "recall_speed": 28.0, "recall_accel": 60.0,
                            "damage": 2.4, "mass": 1.0, "prop_force": 1.0, "spin": 9.0, "swing_speed": 1.0, "catch_time": 0.36,
                            "catch_recover": 0.18, "rip_time": 0.4, "sweep_radius": 0.45, "pitch": 0.88},
                  "style": "Balanced"},
    "greatsword": {"throw": {"charge_time": 1.5, "min_range": 6.5, "max_range": 24.0, "speed": 24.0, "recall_speed": 23.0, "recall_accel": 42.0,
                             "damage": 3.4, "mass": 2.0, "prop_force": 1.7, "spin": 5.5, "swing_speed": 0.75, "catch_time": 0.55,
                             "catch_recover": 0.3, "rip_time": 0.6, "sweep_radius": 0.6, "pitch": 0.7},
                   "two_handed": True,
                   "two_hand_clips": {"atk_slash_r": {"clip": "atk2_slash_r", "start": 0.0, "strike": 0.38, "end": 0.75},
                                      "atk_thrust": {"clip": "atk2_thrust", "start": 0.0, "strike": 0.57, "end": 1.1},
                                      "atk_slash_l": {"clip": "atk2_slash_l", "start": 0.0, "strike": 0.67, "end": 1.15},
                                      "atk_slash": {"clip": "atk2_slash", "start": 0.0, "strike": 0.57, "end": 0.95},
                                      "atk_finisher": {"clip": "atk2_finisher", "start": 0.0, "strike": 0.77, "end": 1.6}}, "recovery": 0.55, "weight": 1.5, "arc": 130.0, "arc_damage": 0.6, "finisher": "slam",
                   "style": "Wide arc, heavy stagger and knockback, slam finisher"},
}


def fmt(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
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
        if ident in PROFILES:
            lines.append("profile = %s" % fmt(PROFILES[ident]))
        (OUT / (ident + ".tres")).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for old in OUT.glob("*.tres"):
        if old.name not in wanted:
            old.unlink()   # an item removed from the table leaves no file behind
    print("wrote", len(ITEMS), "items")


if __name__ == "__main__":
    main()
