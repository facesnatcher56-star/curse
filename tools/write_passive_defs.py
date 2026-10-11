#!/usr/bin/env python3
"""Writes res://data/passives/*.tres (PassiveDef): Dungeon Siege II's passive skills that Curse has a mechanic for.

Effects (rank 1 -> rank 20) are DS2's (docs/ds2-combat-and-loot.md 6 and 4). The class-level tiers are DS2's (1, 5, 12, 24, 36, from
passive_skills.gas). Which tier each passive sits in and what it needs first follow DS2 where the reference names it (Smite needs
Fortitude, Reinforced Armor Barricade and Melee 24, Rebuke Barricade, Alacrity sits at 12); the rest are CURSE CHOICES until the full
passive_skills.gas table is read (Alacrity asks for Critical Strike instead of DS2's Dual Wield, which Curse does not have).
Left out until Curse has the mechanic: Dual Wield, the bow and crossbow passives, summons, ice, lightning, death, curses, nature magic.
Edit and re-run; stale files are removed.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "passives"

PASSIVES = [
    # id, name, tree, class level, prereqs, rank 1, rank 20, text
    ("fortitude", "Fortitude", "melee", 1, {}, 6, 45, "Max life +%s%%"),
    ("critical_strike", "Critical Strike", "melee", 1, {}, 8, 50, "Melee critical chance %s%%"),
    ("overbear", "Overbear", "melee", 5, {}, 8, 50, "Two-handed weapons; their damage +%s%%"),
    ("toughness", "Toughness", "melee", 5, {}, 3, 26, "Physical damage taken -%s%%"),
    ("barricade", "Barricade", "melee", 12, {}, 2, 20, "Shields; block +%s%% and shield armor +20 to +120%%"),
    ("alacrity", "Alacrity", "melee", 12, {"critical_strike": 1}, 3, 25, "Melee attack speed +%s%%"),
    ("smite", "Smite", "melee", 12, {"fortitude": 1}, 5, 50, "Two-handed hits stun: %s%% chance"),
    ("reinforced_armor", "Reinforced Armor", "melee", 24, {"barricade": 1}, 4, 35, "Armor +%s%%"),
    ("fierce_renewal", "Fierce Renewal", "melee", 24, {"toughness": 1}, 3, 30, "Melee power recharge +%s%%"),
    ("rebuke", "Rebuke", "melee", 36, {"barricade": 1}, 0.4, 2.5, "On a block: %s x Melee level back, and a stun"),
    ("deadly_strike", "Deadly Strike", "melee", 36, {"critical_strike": 1}, 224, 350, "Critical damage %s%%"),
    ("critical_shot", "Critical Shot", "ranged", 1, {}, 8, 50, "Thrown critical chance %s%%"),
    ("dodge", "Dodge", "ranged", 1, {}, 4, 40, "Dodge melee and ranged blows %s%%"),
    ("quick_draw", "Quick Draw", "ranged", 5, {}, 3, 25, "Weapon Throw wind-up +%s%% faster"),
    ("survival", "Survival", "ranged", 12, {"dodge": 1}, 10, 60, "Fire resistance +%s%%"),
    ("bleed", "Bleed", "ranged", 12, {"critical_shot": 1}, 10, 25, "Thrown hits bleed: %s%% chance"),
    ("brilliance", "Brilliance", "combat", 1, {}, 7, 150, "Max mana +%s%%"),
    ("devastation", "Devastation", "combat", 1, {}, 10, 60, "Combat magic damage +%s%%"),
    ("searing_flames", "Searing Flames", "combat", 5, {}, 8, 60, "Fire damage +%s%%"),
    ("quickened_casting", "Quickened Casting", "combat", 12, {"brilliance": 1}, 4, 25, "Cast speed +%s%%"),
    ("ignite", "Ignite", "combat", 12, {"searing_flames": 1}, 0.08, 0.5, "Fire hits may ignite: %s x INT a second"),
]


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
        ]
        (OUT / (ident + ".tres")).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for old in OUT.glob("*.tres"):
        if old.name not in wanted:
            old.unlink()
    print("wrote", len(PASSIVES), "passives")


if __name__ == "__main__":
    main()
