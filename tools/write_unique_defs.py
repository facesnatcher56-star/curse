#!/usr/bin/env python3
"""Writes res://data/uniques/*.tres (UniqueDef) and res://data/sets/*.tres (SetDef): Curse's hand-authored items.

Dungeon Siege II has 198 uniques and 22 sets (docs/ds2-combat-and-loot.md 10.4, 10.6). Curse starts with a few of each, built the same way:
a base at a fixed item level with fixed modifiers (the stats of AffixDb.STAT_NAMES), and a set whose bonuses grow with the pieces worn.
Gravecutter is modelled on DS2's Claw of Kajj. Edit and re-run; stale files are removed.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "data"

UNIQUES = [
    # id, name, base, item level, mods, set
    # Two DS2 catalogue items (data/reference/ds2_equipment_catalog.json) whose bases and every alteration Curse already has: DS2 values, exact.
    ("dusk", "Dusk", "leather_jerkin", 16, {"armor": 8, "lightning_resist": 13, "death_resist": 13, "dodge_melee": 6, "magic_find": 18}, ""),
    ("grace_of_night", "Grace of Night", "leather_boots", 8, {"life": 12, "armor": 4, "ice_resist": 12, "dodge_ranged": 8}, ""),
    # DS2 crafted item `mgc_a3_vet_crafted_4`: every alteration is implemented; its source requirement is melee or ranged item level - 8.
    ("assailing_talisman", "Assailing Talisman", "talisman", 75, {"melee_max": 18, "ranged_max": 18, "recharge": 7, "power_damage": 3, "reflect": 30}, ""),
    ("gravecutter", "Gravecutter", "falchion", 12, {"melee_min": 7, "melee_pct": 20, "life_steal": 5, "magic_find": 10}, ""),
    ("wardens_oath", "The Warden's Oath", "kite_shield", 44, {"armor_pct": 60, "block": 12, "life": 120, "reflect": 20}, ""),
    ("emberheart", "Emberheart", "talisman", 30, {"int": 25, "spell_pct": 25, "fire_resist": 20, "mana": 120}, ""),
    ("ashen_crown", "The Ashen Crown", "iron_helm", 58, {"str": 30, "life": 180, "armor_pct": 80, "magic_find": 20}, ""),
    ("roadwarden_helm", "Roadwarden's Visor", "iron_helm", 20, {"life": 40, "armor": 10}, "roadwarden"),
    ("roadwarden_gauntlets", "Roadwarden's Grip", "iron_gauntlets", 18, {"str": 6, "melee_max": 8}, "roadwarden"),
    ("roadwarden_greaves", "Roadwarden's March", "iron_greaves", 19, {"dex": 6, "life_regen": 6}, "roadwarden"),
    ("roadwarden_hauberk", "Roadwarden's Coat", "mail_hauberk", 14, {"life": 60, "fire_resist": 12}, "roadwarden"),
    # Representative resistance-bearing source templates from ds2_equipment_catalog.json. Existing Curse meshes/bases are reused;
    # the source names, levels, supported effects and exact requirements are retained for playable testing.
    ("traveler_robe", "Traveler's Robe", "apprentice_robe", 16,
     {"life": 25, "mana": 35, "ice_resist": 14, "physical_resist": 3}, "", "combat magic:#item_level-2.0"),
    ("oakcase_carved_tunic", "Oakcase Carved Tunic", "carved_tunic", 26,
     {"life": 50, "armor": 13, "death_resist": 16, "melee_resist": 6}, "", "ranged:#item_level-2.0"),
    ("forest_shroud", "Forest Shroud", "woven_hood", 13,
     {"int": 3, "lightning_resist": 12, "ranged_resist": 10, "dodge_ranged": 12}, "", "nature magic:#item_level - 2.0"),
    ("heros_amulet", "Hero's Amulet", "charm", 5,
     {"magical_resist": 4}, "", ""),
]

SETS = [
    # id, name, {pieces worn: bonus}
    ("roadwarden", "The Roadwarden's Harness", {2: {"armor": 20}, 3: {"str": 12, "life": 60},
                                                 4: {"armor_pct": 40, "melee_pct": 15, "magic_find": 20}}),
]


# Source requirement expressions that differ from the base item's.
REQUIREMENTS = {"assailing_talisman": "melee:#item_level-8|ranged:#item_level-8"}


def mods(d) -> str:
    if not d:
        return "{}"
    return "{\n%s\n}" % ",\n".join('"%s": %s' % (k, float(v)) for k, v in d.items())


def write(folder: str, files: dict) -> None:
    out = ROOT / folder
    out.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (out / name).write_text(text, encoding="utf-8", newline="\n")
    for old in out.glob("*.tres"):
        if old.name not in files:
            old.unlink()


def main() -> None:
    uniques = {}
    for row in UNIQUES:
        ident, name, base, level, m, set_id = row[:6]
        requirements = row[6] if len(row) > 6 else REQUIREMENTS.get(ident, "")
        lines = [
            '[gd_resource type="Resource" script_class="UniqueDef" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://game/data/unique_def.gd" id="1"]', "", "[resource]",
            'script = ExtResource("1")', 'id = "%s"' % ident, 'display_name = "%s"' % name.replace('"', '\\"'), 'base = "%s"' % base,
            "level = %d" % level, "mods = %s" % mods(m), 'set_id = "%s"' % set_id,
            'requirements = "%s"' % requirements.replace('"', '\\"')]
        uniques[ident + ".tres"] = "\n".join(lines) + "\n"
    sets = {}
    for ident, name, bonuses in SETS:
        body = "{\n%s\n}" % ",\n".join('"%d": %s' % (count, mods(b)) for count, b in bonuses.items())
        sets[ident + ".tres"] = "\n".join([
            '[gd_resource type="Resource" script_class="SetDef" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://game/data/set_def.gd" id="1"]', "", "[resource]",
            'script = ExtResource("1")', 'id = "%s"' % ident, 'display_name = "%s"' % name.replace('"', '\\"'), "bonuses = %s" % body]) + "\n"
    write("uniques", uniques)
    write("sets", sets)
    print("wrote", len(uniques), "uniques and", len(sets), "sets")


if __name__ == "__main__":
    main()
