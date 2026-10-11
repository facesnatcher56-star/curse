#!/usr/bin/env python3
"""Writes res://data/passives/*.tres (PassiveDef): Dungeon Siege II's passive skills that Curse has a mechanic for.

Effects (rank 1 -> rank 20) are DS2's (docs/ds2-combat-and-loot.md 6 and 4). The tiers (class level 1, 5, 12, 24, 36) and the
prerequisites are DS2's own, read from passive_skills.gas (docs/ds2-combat-and-loot.md 6.1; a prerequisite is one rank). One CURSE CHOICE:
Alacrity asks for Critical Strike instead of DS2's Dual Wield, which Curse does not have.
NEEDS: what Curse lacks for a passive's effect (since Weapon Throw retired, the hero has no ranged attack of his own); it can still be
bought, as DS2's path to what follows. Left out until Curse has the mechanic: Dual Wield, the bow and crossbow passives, summons, ice, lightning, death, curses, nature magic.
Edit and re-run; stale files are removed.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "passives"

PASSIVES = [
    # id, name, tree, class level, prereqs, rank 1, rank 20, text
    ("fortitude", "Fortitude", "melee", 1, {}, 6, 45, "Max life +%s%%"),
    ("critical_strike", "Critical Strike", "melee", 1, {}, 8, 50, "Melee critical chance %s%%"),
    ("barricade", "Barricade", "melee", 5, {"fortitude": 1}, 2, 20, "Shields; block +%s%% and shield armor +20 to +120%%"),
    ("overbear", "Overbear", "melee", 5, {"critical_strike": 1}, 8, 50, "Two-handed weapons; their damage +%s%%"),
    ("toughness", "Toughness", "melee", 12, {"fortitude": 1}, 3, 26, "Physical damage taken -%s%%"),
    ("alacrity", "Alacrity", "melee", 12, {"critical_strike": 1}, 3, 25, "Melee attack speed +%s%%"),
    ("reinforced_armor", "Reinforced Armor", "melee", 24, {"barricade": 1}, 4, 35, "Armor +%s%%"),
    ("smite", "Smite", "melee", 24, {"overbear": 1, "toughness": 1}, 5, 50, "Two-handed hits stun: %s%% chance"),
    ("fierce_renewal", "Fierce Renewal", "melee", 24, {"alacrity": 1}, 3, 30, "Melee power recharge +%s%%"),
    ("rebuke", "Rebuke", "melee", 36, {"reinforced_armor": 1}, 0.4, 2.5, "On a block: %s x Melee level back, and a stun"),
    ("deadly_strike", "Deadly Strike", "melee", 36, {"critical_strike": 1}, 224, 350, "Critical damage %s%%"),
    ("critical_shot", "Critical Shot", "ranged", 1, {}, 8, 50, "Ranged critical chance %s%%"),
    ("dodge", "Dodge", "ranged", 1, {}, 4, 40, "Dodge melee and ranged blows %s%%"),
    ("quick_draw", "Quick Draw", "ranged", 5, {"critical_shot": 1}, 3, 25, "Thrown weapons; their attack rate +%s%%"),
    ("survival", "Survival", "ranged", 5, {}, 10, 60, "Fire resistance +%s%%"),
    ("bleed", "Bleed", "ranged", 12, {"quick_draw": 1}, 10, 25, "Thrown hits bleed: %s%% chance"),
    ("brilliance", "Brilliance", "combat", 1, {}, 7, 150, "Max mana +%s%%"),
    ("devastation", "Devastation", "combat", 1, {}, 10, 60, "Combat magic damage +%s%%"),
    ("searing_flames", "Searing Flames", "combat", 5, {"devastation": 1}, 8, 60, "Fire damage +%s%%"),
    ("quickened_casting", "Quickened Casting", "combat", 24, {"brilliance": 1}, 4, 25, "Cast speed +%s%%"),
    ("ignite", "Ignite", "combat", 24, {"searing_flames": 1}, 0.08, 0.5, "Fire hits may ignite: %s x INT a second"),
]


# DS2's per-rank tables (passive_skills.gas), where read: the curve flattens toward rank 20. The rest go straight from rank 1 to 20
# until their tables are read.
TABLES = {
    "deadly_strike": [224, 242, 256, 268, 279, 288, 296, 303, 310, 316, 322, 327, 332, 336, 340, 343, 346, 348, 349, 350],
}

NEEDS = {"critical_shot": "a ranged attack", "quick_draw": "throwing weapons", "bleed": "throwing weapons"}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for order, (ident, name, tree, level, prereqs, first, last, text) in enumerate(PASSIVES):
        wanted.add(ident + ".tres")
        pre = "{}" if not prereqs else "{\n%s\n}" % ",\n".join('"%s": %d' % (k, v) for k, v in prereqs.items())
        lines = [
            '[gd_resource type="Resource" script_class="PassiveDef" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://game/data/passive_def.gd" id="1"]', "", "[resource]",
            'script = ExtResource("1")', 'id = "%s"' % ident, 'display_name = "%s"' % name, 'tree = "%s"' % tree,
            "class_level = %d" % level, "prereqs = %s" % pre, "first = %s" % float(first), "last = %s" % float(last),
            'text = "%s"' % text, "order = %d" % order,
            "table = Array[float]([%s])" % ", ".join(str(float(v)) for v in TABLES.get(ident, [])), 'needs = "%s"' % NEEDS.get(ident, ""),
        ]
        (OUT / (ident + ".tres")).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for old in OUT.glob("*.tres"):
        if old.name not in wanted:
            old.unlink()
    print("wrote", len(PASSIVES), "passives")


if __name__ == "__main__":
    main()
