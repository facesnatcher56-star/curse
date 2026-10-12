#!/usr/bin/env python3
"""Writes res://data/items/*.tres (ItemDef resources): the base items, Dungeon Siege II style (docs/ds2-combat-and-loot.md 10).

Slots (Items.Slot): 0 weapon, 1 body armour, 2 ring, 3 shield, 4 helm, 5 gloves, 6 boots, 7 amulet. Edit and re-run.
Every base has five item levels (DS2's base and var1-var4): the same sword turns up again, stronger, deeper in the world. Its numbers come
from DS2's curves at that level (ItemDef.stats_at): weapons by type, armour by class and slot. `stats` holds only what is not a curve:
a weapon's swing speed and the share of its type's damage it deals per hit (a faster blade hits for less, as DS2's swing time does), and
no additional body-armour movement modifiers. Models and icons come from tools/blender/make_items.py (assets/models/items/<id>/model.glb,
assets/icons/items/<id>.png).
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "items"

# CURSE CHOICE: DS2 has ~190 bases; Curse starts with two or three a slot, their levels spread so that between them a slot has a base
# within a few levels of any monster level (the Leather Jerkin and the Buckler keep DS2's own levels; the Jerkin's first is 2, not 3,
# so a new hero can wear it). A fighter piece has armour class 1.0, a ranger's 0.8 (DS2's mage 0.6 is not used yet).
ITEMS = [
    # id, display name, slot, item type, armour class, item levels, stats
    ("falchion", "Falchion", 0, "1h", "", [1, 13, 31, 50, 72], {"damage": 0.85, "speed": 1.18}),
    ("longsword", "Longsword", 0, "1h", "", [2, 17, 38, 60, 84], {"damage": 1.0, "speed": 1.0}),
    ("greatsword", "Greatsword", 0, "2h", "", [6, 26, 47, 68, 92], {"damage": 1.0, "speed": 0.82}),
    ("leather_jerkin", "Leather Jerkin", 1, "body", "ranger", [2, 9, 18, 27, 36], {}),
    ("mail_hauberk", "Mail Hauberk", 1, "body", "fighter", [5, 14, 30, 46, 62], {}),
    ("plate_cuirass", "Plate Cuirass", 1, "body", "fighter", [22, 40, 58, 77, 95], {}),
    ("signet", "Signet", 2, "ring", "", [1, 16, 34, 55, 78], {}),
    ("band", "Iron Band", 2, "ring", "", [8, 25, 45, 66, 92], {}),
    ("buckler", "Buckler", 3, "shield", "fighter", [6, 11, 17, 28, 39], {}),
    ("kite_shield", "Kite Shield", 3, "shield", "fighter", [20, 44, 60, 78, 94], {}),
    ("leather_cap", "Leather Cap", 4, "helm", "ranger", [1, 12, 28, 46, 68], {}),
    ("iron_helm", "Iron Helm", 4, "helm", "fighter", [5, 20, 38, 58, 84], {}),
    ("leather_gloves", "Leather Gloves", 5, "gloves", "ranger", [1, 10, 26, 44, 66], {}),
    ("iron_gauntlets", "Iron Gauntlets", 5, "gloves", "fighter", [4, 18, 36, 56, 82], {}),
    ("leather_boots", "Leather Boots", 6, "boots", "ranger", [2, 11, 27, 45, 67], {}),
    ("iron_greaves", "Iron Greaves", 6, "boots", "fighter", [5, 19, 37, 57, 83], {}),
    ("charm", "Charm", 7, "amulet", "", [3, 20, 40, 62, 86], {}),
    ("talisman", "Talisman", 7, "amulet", "", [10, 30, 50, 72, 95], {}),
    ("axe_1h", "War Axe", 0, "1h", "", [3, 15, 33, 52, 75], {"damage": 1.0, "speed": 1.0}),
    ("mace", "Mace", 0, "1h", "", [4, 18, 36, 55, 78], {"damage": 1.0, "speed": 1.0}),
    ("club", "Club", 0, "1h", "", [1, 10, 24, 45, 68], {"damage": 1.0, "speed": 1.0}),
    ("dagger", "Dagger", 0, "1h", "", [1, 11, 28, 48, 70], {"damage": 1.0, "speed": 1.0}),
    ("axe_2h", "Battle Axe", 0, "2h", "", [9, 22, 42, 64, 88], {"damage": 1.0, "speed": 0.82}),
    ("hammer_2h", "Warhammer", 0, "2h", "", [6, 24, 44, 66, 90], {"damage": 1.0, "speed": 0.82}),
    ("short_bow", "Short Bow", 0, "bow", "", [2, 17, 38, 60, 84], {"damage": 1.0, "speed": 1.0}),
]

TWO_HAND_CLIPS = {
    "atk_slash_r": {"clip": "atk2_slash_r", "start": 0.0, "strike": 0.38, "end": 0.75},
    "atk_thrust": {"clip": "atk2_thrust", "start": 0.0, "strike": 0.57, "end": 1.1},
    "atk_slash_l": {"clip": "atk2_slash_l", "start": 0.0, "strike": 0.67, "end": 1.15},
    "atk_slash": {"clip": "atk2_slash", "start": 0.0, "strike": 0.57, "end": 0.95},
    "atk_finisher": {"clip": "atk2_finisher", "start": 0.0, "strike": 0.77, "end": 1.6},
}

# Weapons beyond damage and speed (see ItemDef.profile). The longsword is the baseline: its moveset is what the game always had.
PROFILES = {
    "falchion": {"recovery": 1.7, "weight": 0.7, "finisher_time": 0.9,
                 "style": "Fast combo and recovery, light stagger"},
    "longsword": {"style": "Balanced"},
    "greatsword": {"two_handed": True,
                   "two_hand_clips": TWO_HAND_CLIPS, "recovery": 0.55, "weight": 1.5,
                   "style": "Single target, heavy stagger and knockback"},
    "axe_1h": {"style": "Heavy chopping blade"},
    "mace": {"style": "Crushing mace"},
    "club": {"style": "Bludgeon"},
    "dagger": {"style": "Quick piercing blade"},
    "axe_2h": {"two_handed": True,
               "two_hand_clips": TWO_HAND_CLIPS, "recovery": 0.55, "weight": 1.5,
               "style": "Heavy two-handed axe, heavy stagger"},
    "hammer_2h": {"two_handed": True,
                 "two_hand_clips": TWO_HAND_CLIPS, "recovery": 0.55, "weight": 1.5,
                 "style": "Heavy two-handed hammer, heavy stagger"},
    "short_bow": {"style": "Bow", "ranged": True, "two_handed": True},
}

# Inventory size overrides (width, height). If omitted, ItemDef inherits DS2 defaults from item_type.
INVENTORY_SIZES = {
    "club": (1, 2),
    "dagger": (1, 2),
    "axe_2h": (2, 3),
    "hammer_2h": (2, 3),
}

# Explicit model and icon path overrides. If omitted, default res://assets/... paths are used.
CUSTOM_PATHS = {
    "short_bow": ("res://assets/models/archer/bow/model.glb", "res://assets/icons/take_aim.png"),
}

CUSTOM_ORDERS = {
    "short_bow": 20,
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
    for order, (ident, name, slot, kind, armor_class, levels, stats) in enumerate(ITEMS):
        wanted.add(ident + ".tres")
        item_order = CUSTOM_ORDERS.get(ident, order)
        model_path, icon_path = CUSTOM_PATHS.get(ident, (
            "res://assets/models/items/%s/model.glb" % ident,
            "res://assets/icons/items/%s.png" % ident,
        ))
        lines = [
            '[gd_resource type="Resource" script_class="ItemDef" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://game/data/item_def.gd" id="1"]', "", "[resource]",
            'script = ExtResource("1")', 'id = "%s"' % ident, 'display_name = "%s"' % name, "slot = %d" % slot, "order = %d" % item_order,
            'model_path = "%s"' % model_path, 'icon_path = "%s"' % icon_path,
            'item_type = "%s"' % kind, 'armor_class = "%s"' % armor_class,
            "levels = Array[int]([%s])" % ", ".join(str(level) for level in levels), "stats = %s" % fmt(stats),
        ]
        if ident in INVENTORY_SIZES:
            w, h = INVENTORY_SIZES[ident]
            lines.append("inventory_size = Vector2i(%d, %d)" % (w, h))
        if ident in PROFILES:
            lines.append("profile = %s" % fmt(PROFILES[ident]))
        (OUT / (ident + ".tres")).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for old in OUT.glob("*.tres"):
        if old.name not in wanted:
            old.unlink()   # an item removed from the table leaves no file behind
    print("wrote", len(ITEMS), "items")


if __name__ == "__main__":
    main()
