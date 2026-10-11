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


# DS2's per-rank tables (passive_skills.gas, docs/ds2_passives_reference.md): the curve flattens toward rank 20.
TABLES = {
    "fortitude": [6, 10, 14, 18, 21, 24, 26, 28, 30, 32, 34, 36, 38, 39, 40, 41, 42, 43, 44, 45],
    "critical_strike": [8, 14, 18, 22, 25.5, 28.5, 31, 33.5, 36, 38, 40, 41.5, 43, 44.5, 46, 47, 48, 49, 49.5, 50],
    "barricade": [2, 4, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 16.5, 17, 17.5, 18, 18.5, 19, 19.5, 20],   # block, melee and ranged
    "overbear": [8, 14, 18, 22, 25.5, 28.5, 31, 33.5, 36, 38, 40, 41.5, 43, 44.5, 46, 47, 48, 49, 49.5, 50],
    "toughness": [3, 5, 7, 9, 11, 12.5, 14, 15.5, 17, 18, 19, 20, 21, 22, 23, 24, 24.5, 25, 25.5, 26],
    "alacrity": [3, 5, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25],
    "smite": [5, 10, 14, 18, 22, 25, 28, 31, 34, 36, 38, 40, 42, 44, 45, 46, 47, 48, 49, 50],   # stun chance
    "reinforced_armor": [4, 7, 10, 13, 15, 17, 19, 21, 23, 24.5, 26, 27.5, 29, 30, 31, 32, 33, 34, 34.5, 35],
    "fierce_renewal": [3, 6, 8, 10, 12, 14, 16, 17.5, 19, 20.5, 22, 23, 24, 25, 26, 26, 27, 28, 29, 30],
    "rebuke": [0.4, 0.7, 0.9, 1.1, 1.3, 1.45, 1.6, 1.7, 1.8, 1.9, 1.98, 2.06, 2.14, 2.22, 2.3, 2.34, 2.38, 2.42, 2.46, 2.5],
    "deadly_strike": [224, 242, 256, 268, 279, 288, 296, 303, 310, 316, 322, 327, 332, 336, 340, 343, 346, 348, 349, 350],
    "critical_shot": [8, 14, 18, 22, 25.5, 28.5, 31, 33.5, 36, 38, 40, 41.5, 43, 44.5, 46, 47, 48, 49, 49.5, 50],
    "dodge": [4, 7, 10, 13, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 35, 36, 37, 38, 39, 40],
    "quick_draw": [3, 5, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25],
    "survival": [10, 17, 22, 27, 31, 35, 38, 41, 44, 46.5, 49, 51, 53, 55, 56, 57, 58, 59, 59.5, 60],   # fire (and ice, lightning) resistance
    "bleed": [10, 15, 18, 22, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25],   # chance
    "brilliance": [7, 14, 21, 28, 36, 44, 52, 60, 68, 76, 83, 90, 97, 105, 113, 121, 129, 136, 143, 150],
    "devastation": [10, 17, 22, 27, 31, 35, 38, 41, 44, 46.5, 49, 51, 53, 55, 56, 57, 58, 59, 59.5, 60],
    "searing_flames": [8, 14, 20, 24, 28, 32, 36, 39, 42, 44, 46, 48, 50, 52, 54, 56, 57, 58, 59, 60],
    "quickened_casting": [4, 7, 10, 12, 14, 15.5, 17, 18, 19, 20, 21, 21.75, 22.5, 23, 23.5, 24, 24.25, 24.5, 24.75, 25],
    "ignite": [0.08, 0.14, 0.18, 0.22, 0.25, 0.28, 0.31, 0.33, 0.35, 0.37, 0.39, 0.41, 0.43, 0.44, 0.45, 0.46, 0.47, 0.48, 0.49, 0.5],   # x INT a second
}

# A passive's other values, each DS2's 20-rank table (docs/ds2_passives_reference.md).
STUN_STEPS = [1, 1, 1, 1, 1, 1.25, 1.25, 1.25, 1.25, 1.25, 1.5, 1.5, 1.5, 1.5, 1.5, 2, 2, 2, 2, 2]
EXTRA = {
    "barricade": {"shield_armor": [20, 35, 45, 55, 63, 70, 76, 82, 88, 93, 98, 102, 106, 109, 112, 114, 116, 118, 119, 120]},
    "smite": {"stun": STUN_STEPS},
    "rebuke": {"stun": STUN_STEPS},
    "survival": {"health_harvested": list(range(1, 21))},
    "bleed": {"dps": [0.06, 0.11, 0.15, 0.19, 0.23, 0.26, 0.29, 0.315, 0.34, 0.36, 0.38, 0.4, 0.42, 0.435, 0.45, 0.46, 0.47, 0.48, 0.49, 0.5]},
    "ignite": {"chance": [5, 8, 11, 13, 15, 17, 18.5, 20, 21.5, 22.5, 23.5, 24.5, 25.5, 26.5, 27.25, 28, 28.5, 29, 29.5, 30]},
}

NEEDS = {"critical_shot": "a ranged attack", "quick_draw": "throwing weapons", "bleed": "throwing weapons"}

# Source prerequisite paths needed to reach every rank of the implemented powers.
PASSIVES += [
    ("biting_arrow", "Biting Arrow", "ranged", 5, {"critical_shot": 1}, 8, 50, "Bow and crossbow damage +%s%%"),
    ("far_shot", "Far Shot", "ranged", 12, {"biting_arrow": 1}, 6, 60, "Bow and crossbow range +%s%%"),
    ("penetrate", "Penetrate", "ranged", 24, {}, 12, 75, "Projectile penetration chance %s%%"),
    ("cunning_renewal", "Cunning Renewal", "ranged", 24, {"bleed": 1}, 3, 30, "Ranged power recharge +%s%%"),
    ("mortal_wound", "Mortal Wound", "ranged", 36, {"far_shot": 1, "penetrate": 1}, 224, 350, "Bow and crossbow critical damage %s%%"),
    ("ricochet", "Ricochet", "ranged", 36, {"bleed": 1, "penetrate": 1}, 66, 150, "Thrown critical ricochet damage %s%%"),
    ("arcane_fury", "Arcane Fury", "combat", 36, {"quickened_casting": 1}, 3, 30, "Magic power damage +%s%%"),
]
TABLES.update({
    "biting_arrow": TABLES["critical_shot"], "mortal_wound": TABLES["deadly_strike"],
    "cunning_renewal": TABLES["fierce_renewal"], "arcane_fury": TABLES["fierce_renewal"],
    "far_shot": [6, 10, 14, 18, 22, 25, 28, 31, 34, 37, 40, 43, 46, 48, 50, 52, 54, 56, 58, 60],
    "penetrate": [12, 22, 30, 36, 41, 46, 50, 54, 57, 60, 63, 65, 67, 69, 70.5, 72, 73, 74, 74.5, 75],
    "ricochet": [66, 78, 86, 94, 101, 107, 112, 117, 122, 126, 130, 133, 136, 139, 142, 144, 146, 148, 149, 150],
})
NEEDS.update({"biting_arrow": "a hero bow or crossbow", "far_shot": "a hero bow or crossbow", "penetrate": "a hero ranged attack",
              "mortal_wound": "a hero bow or crossbow", "ricochet": "hero throwing weapons"})


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
            "table = Array[float]([%s])" % ", ".join(str(float(v)) for v in TABLES.get(ident, [])),
            "extra = {%s}" % ", ".join('"%s": [%s]' % (k, ", ".join(str(float(x)) for x in v)) for k, v in EXTRA.get(ident, {}).items()), 'needs = "%s"' % NEEDS.get(ident, ""),
        ]
        (OUT / (ident + ".tres")).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for old in OUT.glob("*.tres"):
        if old.name not in wanted:
            old.unlink()
    print("wrote", len(PASSIVES), "passives")


if __name__ == "__main__":
    main()
