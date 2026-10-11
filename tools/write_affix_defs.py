#!/usr/bin/env python3
"""Writes res://data/affixes/*.tres (AffixDef resources): Dungeon Siege II's numeric item modifiers (docs/ds2-combat-and-loot.md 10.5).

Each family is a chain of tiers keyed to a modifier level. The reference gives each family's tier count and its first and last tier
(name, modifier level, value); the tiers between are filled in evenly (CURSE CHOICE: levels and values interpolated, and the middle
tiers named in the same style). Only families Curse has a mechanic for are here: no ice, lightning or death damage, no class-skill
bonuses yet. `slots` are the item kinds it may roll on; one affix per family per item (the family is its exclusion group).
Edit the table and re-run; stale files are removed.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "affixes"

W, BODY, HELM, GLOVES, BOOTS, SHIELD, RING, AMULET = "weapon", "body", "helm", "gloves", "boots", "shield", "ring", "amulet"
ARMOUR = [BODY, HELM, GLOVES, BOOTS, SHIELD]
JEWELRY = [RING, AMULET]

# family: (stat, prefix or suffix, (first level, last level), (first value, last value), tier names, slots, is_percent)
FAMILIES = {
    "strength": ("str", "suffix", (2, 82), (1, 72),
                 ["of Hardiness", "of Vigor", "of Brawn", "of Might", "of Power", "of Strength", "of the Ox", "of the Titan", "of the Colossus"],
                 [W, BODY, HELM, GLOVES] + JEWELRY, False),
    "dexterity": ("dex", "suffix", (1, 81), (1, 100),
                  ["of the Swift", "of Agility", "of Deftness", "of Nimbleness", "of Grace", "of Finesse", "of Precision", "of Fluidity",
                   "of Effortlessness"], [W, BODY, GLOVES, BOOTS] + JEWELRY, False),
    "intelligence": ("int", "suffix", (3, 83), (1, 60),
                     ["of Awareness", "of Wit", "of Insight", "of Learning", "of Wisdom", "of Lore", "of Sagacity", "of Genius", "of Omniscience"],
                     [W, BODY, HELM] + JEWELRY, False),
    "life": ("life", "suffix", (1, 75), (4, 237),
             ["of the Rat", "of the Hare", "of the Fox", "of the Badger", "of the Wolf", "of the Boar", "of the Stag", "of the Elk",
              "of the Bull", "of the Bear", "of the Mammoth", "of the Lion"], [W] + ARMOUR + JEWELRY, False),
    "mana": ("mana", "suffix", (1, 67), (4, 274),
             ["of the Toad", "of the Newt", "of the Snake", "of the Owl", "of the Raven", "of the Lynx", "of the Serpent", "of the Basilisk",
              "of the Wyvern", "of the Gryphon", "of the Drake", "of the Dragon"], [BODY, HELM] + JEWELRY, False),
    "melee_max": ("melee_max", "suffix", (1, 74), (1, 72),
                  ["of Wounding", "of Maiming", "of Mangling", "of Ravaging", "of Butchery", "of Torture"], [W, GLOVES], False),
    "melee_min": ("melee_min", "suffix", (3, 48), (3, 18),
                  ["of Affliction", "of Suffering", "of Agony", "of Anguish", "of Ruin", "of Desolation"], [W], False),
    "melee_pct": ("melee_pct", "prefix", (2, 53), (10, 56),
                  ["Cruel", "Vicious", "Brutal", "Savage", "Merciless", "Ferocious", "Barbarous", "Excruciating"], [W, GLOVES], True),
    "spell_pct": ("spell_pct", "prefix", (2, 53), (4, 32),
                  ["Destructive", "Ruinous", "Devastating", "Cataclysmic", "Calamitous", "Dire", "Doomed", "Tragic"], JEWELRY, True),
    "fire_added": ("fire_added", "prefix", (15, 80), (2, 36),
                   ["Smouldering", "Scorching", "Burning", "Searing", "Blazing", "Infernal"], [W], False),
    "life_steal": ("life_steal", "suffix", (6, 60), (3, 8),
                   ["of the Parasite", "of the Leech", "of the Tick", "of the Vampire", "of the Ghoul", "of Blood"], [W, RING], True),
    "life_per_hit": ("life_per_hit", "suffix", (12, 78), (2, 23),
                     ["of Consumption", "of Feeding", "of Gorging", "of Hunger", "of Gluttony", "of Devouring"], [W, GLOVES], False),
    "armor": ("armor", "prefix", (1, 86), (2, 85),
              ["Stout", "Sturdy", "Reinforced", "Hardened", "Tempered", "Bolstered", "Fortified", "Bastioned", "Ironclad", "Impervious",
               "Unassailable", "Adamantine"], ARMOUR, False),
    "armor_pct": ("armor_pct", "prefix", (4, 60), (26, 115),
                  ["Steadfast", "Stalwart", "Resolute", "Unyielding", "Unbreakable", "Indomitable", "Everlasting", "Eternal"], ARMOUR, True),
    "fire_resist": ("fire_resist", "prefix", (8, 56), (10, 25),
                    ["Ruddy", "Crimson", "Scarlet", "Vermilion", "Carmine"], ARMOUR + JEWELRY, True),
    "reflect": ("reflect", "suffix", (10, 60), (10, 40),
                ["of Reversal", "of Recoil", "of Vengeance", "of Retribution"], [BODY, SHIELD], True),
    "life_regen": ("life_regen", "suffix", (5, 50), (4, 12),
                   ["of Mending", "of Healing", "of Restoration", "of Regeneration"], [BODY, BOOTS] + JEWELRY, True),
    "mana_regen": ("mana_regen", "suffix", (5, 50), (4, 12),
                   ["of Brightening", "of Lucidity", "of Enlightenment", "of Visions"], [HELM] + JEWELRY, True),
    "block": ("block", "suffix", (8, 60), (4, 15),
              ["of Repulsion", "of Warding", "of the Bulwark", "of Deflection"], [SHIELD], True),
    "recharge": ("recharge", "prefix", (20, 50), (5, 10),
                 ["Rousing", "Stirring", "Invigorating"], [W] + JEWELRY, True),
    "magic_find": ("magic_find", "prefix", (20, 60), (4, 35),
                   ["Fortunate", "Lucky", "Charmed", "Blessed", "Serendipitous"], [HELM] + JEWELRY, True),
    "gold_find": ("gold_find", "prefix", (1, 60), (5, 70),
                  ["Glittering", "Gilded", "Golden", "Opulent", "Affluent"], JEWELRY, True),
}


def tiers(levels, values, count):
    """Evenly spaced levels and values from first to last tier (rounded; values never repeat downward)."""
    out = []
    for i in range(count):
        t = i / (count - 1) if count > 1 else 0.0
        level = round(levels[0] + (levels[1] - levels[0]) * t)
        value = round(values[0] + (values[1] - values[0]) * t)
        if out and value <= out[-1][1]:
            value = out[-1][1] + 1
        out.append((level, value))
    out[-1] = (levels[1], values[1])
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = set()
    count = 0
    for family, (stat, position, levels, values, names, slots, percent) in FAMILIES.items():
        for index, (level, value) in enumerate(tiers(levels, values, len(names))):
            ident = "%s_%d" % (family, index + 1)
            wanted.add(ident + ".tres")
            lines = [
                '[gd_resource type="Resource" script_class="AffixDef" load_steps=2 format=3]', "",
                '[ext_resource type="Script" path="res://game/data/affix_def.gd" id="1"]', "", "[resource]",
                'script = ExtResource("1")', 'id = "%s"' % ident, 'family = "%s"' % family, 'stat = "%s"' % stat,
                'title = "%s"' % names[index], 'position = "%s"' % position, "tier = %d" % (index + 1), "level = %d" % level,
                "value = %s" % float(value), "percent = %s" % ("true" if percent else "false"),
                "slots = Array[String]([%s])" % ", ".join('"%s"' % s for s in slots),
            ]
            (OUT / (ident + ".tres")).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
            count += 1
    for old in OUT.glob("*.tres"):
        if old.name not in wanted:
            old.unlink()
    print("wrote", count, "affixes in", len(FAMILIES), "families")


if __name__ == "__main__":
    main()
