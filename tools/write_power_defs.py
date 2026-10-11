#!/usr/bin/env python3
"""Writes res://data/powers/*.tres (PowerDef): Dungeon Siege II's hero powers, all of them, from docs/ds2_powers_reference.md (read from
the installed game's active_skills.gas) and docs/ds2-combat-and-loot.md 7.

A power has three ranks, each opened by passive ranks (no points are spent on it), costs no mana and recharges from damage dealt.
Values are expressions in the class levels melee, ranged, combat, nature. Where the extract did not carry rank 2 or 3 of a value the
key is listed in `estimated`: rank 3 from ds2-combat-and-loot.md 7.2 when it has it, rank 2 halfway, otherwise rank 1 repeated.
`needs` names what Curse lacks for the power; a power with needs is data only (shown, not usable) until that system exists.
Passive ids follow Curse's (DS2's aegis is Barricade). ASSUMPTION: DS2's `desperate_frenzy` is Deadly Strike (to confirm against
passive_skills.gas). Edit and re-run; stale files are removed.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "powers"

ALIASES = {"aegis": "barricade", "desperate_frenzy": "deadly_strike"}

def r3(a, b, c):
    return [str(a), str(b), str(c)]

def same(v):
    return [str(v)] * 3

POWERS = [
    # id, name, tree, recharge, stance, three requirement dicts, values, estimated keys, needs, summary
    ("brutal_attack", "Brutal Attack", "melee", 21, "melee",
     [{"critical_strike": 1}, {"critical_strike": 5}, {"critical_strike": 8}],
     {"damage_pct": r3("1500 + 25 * melee", "1750 + 42.5 * melee", "2000 + 60 * melee")}, ["damage_pct"], "",
     "Your next melee hit deals massive damage."),
    ("provoke", "Provoke", "melee", 12, "shield",
     [{"aegis": 1}, {"aegis": 6, "toughness": 4}, {"aegis": 10, "toughness": 10, "rebuke": 5}],
     {"radius": r3(6, 7, 8), "armor_pct": r3(25, 30, 50), "duration": r3(5, 8, 10)}, [], "not built yet",
     "Enemies around you turn on you, and your armour rises while you hold them."),
    ("whirling_strike", "Whirling Strike", "melee", 35, "melee",
     [{"critical_strike": 6, "fortitude": 8}, {"critical_strike": 8, "fortitude": 10, "reinforced_armor": 6},
      {"critical_strike": 12, "fortitude": 12, "reinforced_armor": 12}],
     {"radius": r3(3, 3.5, 4), "damage_pct": same("920 + 9 * melee"), "stun": same(1.5)}, ["damage_pct"], "not built yet",
     "Whirl your weapon in a circle, damaging and briefly stunning everything near you."),
    ("staggering_blow", "Staggering Blow", "melee", 35, "two_handed",
     [{"overbear": 1}, {"overbear": 5, "toughness": 4}, {"overbear": 12, "toughness": 10, "smite": 8}],
     {"damage_pct": r3("400 + 7 * melee", "600 + 9.5 * melee", "800 + 12 * melee"), "stun": r3(6, 8, 10), "radius": r3(2.75, 3.25, 4)},
     ["damage_pct"], "not built yet",
     "Your next two-handed blow sends out a shockwave that stuns everything caught in it."),
    ("war_cry", "War Cry", "melee", 35, "melee",
     [{"critical_strike": 8, "smite": 1}, {"critical_strike": 12, "smite": 8, "desperate_frenzy": 2},
      {"critical_strike": 12, "smite": 12, "desperate_frenzy": 8}],
     {"armor_reduction_pct": r3(35, 47.5, 60), "duration": same(20), "critical_hits": r3(8, 12, 15)}, ["armor_reduction_pct", "critical_hits"],
     "not built yet", "A deafening cry in a cone: enemies flee with their armour stripped, and your next hits are critical."),
    ("waves_of_force", "Waves of Force", "melee", 35, "dual_wield",
     [{"dual_wield": 1}, {"dual_wield": 5, "alacrity": 4}, {"dual_wield": 10, "alacrity": 10, "desperate_frenzy": 8}],
     {"damage_pct": r3("200 + 3.6 * melee", "345 + 6.3 * melee", "490 + 9 * melee"), "waves": same(5), "period": same(0.24),
      "distance": same(12), "speed": same(10)}, ["damage_pct"], "dual wielding",
     "A sequence of swings, each sending a wave of force tearing out in front of you."),
    ("elemental_rage", "Elemental Rage", "melee", 60, "dual_wield",
     [{"critical_strike": 8, "fierce_renewal": 2}, {"critical_strike": 10, "fierce_renewal": 6, "desperate_frenzy": 1},
      {"critical_strike": 14, "fierce_renewal": 12, "desperate_frenzy": 12}],
     {"duration": same(15), "attack_rate_pct": r3(10, 15, 20), "elements": same(3),
      "element_damage_min": same("(3.7 + 0.9 * melee) * (2.0 + 0.015 * melee)"), "element_damage_max": same("(6.2 + 1.54 * melee) * (2.0 + 0.015 * melee)"),
      "vulnerability_pct": r3(12, 16, 20)}, ["element_damage_min", "element_damage_max", "vulnerability_pct"], "dual wielding, ice and lightning",
     "A frenzy: faster attacks carrying fire, ice and lightning, but you take more damage."),
    ("take_aim", "Take Aim", "ranged", 21, "any",
     [{"critical_shot": 1}, {"critical_shot": 5}, {"critical_shot": 8, "penetrate": 1}],
     {"damage_pct": r3("1500 + 25 * ranged", "2000 + 42.5 * ranged", "2500 + 60 * ranged")}, ["damage_pct"], "",
     "The next shot deals massive damage (Cutter's)."),
    ("thunderous_shot", "Thunderous Shot", "ranged", 35, "bow",
     [{"biting_arrow": 1}, {"biting_arrow": 8, "far_shot": 1}, {"biting_arrow": 12, "far_shot": 8, "mortal_wound": 5}],
     {"damage_pct": r3("530 + 9 * ranged", "877.5 + 15 * ranged", "1225 + 21 * ranged"), "stun": r3(6, 8, 10)}, ["damage_pct"], "bows",
     "A piercing shot that stuns everything it passes through."),
    ("silence", "Silence", "ranged", 21, "any",
     [{"dodge": 5, "survival": 3}, {"dodge": 10, "survival": 6, "mortal_wound": 1}, {"dodge": 14, "survival": 10, "mortal_wound": 12}],
     {"radius": r3(4, 5, 6), "duration": r3(15, 20, 25)}, [], "not built yet",
     "Monsters in an area cannot cast spells for a while."),
    ("shrapnel_blast", "Shrapnel Blast", "ranged", 35, "thrown",
     [{"quick_draw": 1}, {"quick_draw": 5, "bleed": 5}, {"quick_draw": 10, "bleed": 8, "penetrate": 6}],
     {"missiles": r3(5, 7, 9), "damage_pct": same("950 + 17 * ranged"), "radial_damage_pct": same("80 + 1.5 * ranged"), "radius": same(1)},
     ["damage_pct", "radial_damage_pct"], "throwing weapons", "A thrown weapon bursts into a spray of missiles."),
    ("repulse", "Repulse", "ranged", 60, "any",
     [{"dodge": 4, "survival": 3}, {"dodge": 10, "survival": 6, "ricochet": 1}, {"dodge": 14, "survival": 10, "ricochet": 12}],
     {"radius": r3(3, 3.5, 4), "knockback": r3(3, 5, 7), "stun": same(1.5), "duration": r3(12, 16, 20)}, [], "not built yet",
     "A field around you that throws back and stuns enemies who come close."),
    ("flurry", "Flurry", "ranged", 60, "thrown",
     [{"critical_shot": 8, "cunning_renewal": 4}, {"critical_shot": 10, "cunning_renewal": 8, "ricochet": 8},
      {"critical_shot": 14, "cunning_renewal": 12, "ricochet": 12}],
     {"attack_rate": r3(1.2, 1.4, 1.5), "damage_pct": r3("180 + 1.4 * ranged", "205 + 2.2 * ranged", "210 + 2.6 * ranged"),
      "projectiles": same(2), "duration": same(15)}, [], "throwing weapons", "Throw faster, several weapons at once, for a while."),
    ("energy_orb", "Energy Orb", "combat", 21, "any",
     [{"brilliance": 1}, {"brilliance": 4, "devastation": 2}, {"brilliance": 8, "devastation": 4}],
     {"damage_min": r3("(20 + 5 * combat) * (0.82 + 0.015 * combat)", "(20 + 5 * combat) * (1.0 + 0.029 * combat)", "(20 + 5 * combat) * (1.2 + 0.036 * combat)"),
      "damage_max": r3("(30 + 7.5 * combat) * (0.82 + 0.015 * combat)", "(30 + 7.5 * combat) * (1.0 + 0.029 * combat)", "(30 + 7.5 * combat) * (1.2 + 0.036 * combat)"),
      "duration": same(20)}, [], "magic damage", "An orb of energy that circles you and strikes nearby enemies."),
    ("flame_nexus", "Flame Nexus", "combat", 35, "any",
     [{"devastation": 2, "searing_flames": 1}, {"devastation": 5, "searing_flames": 4}, {"devastation": 12, "searing_flames": 8, "ignite": 5}],
     {"damage": same("(40 + 10 * combat) * (0.82 + 0.015 * combat)")}, ["damage"], "not built yet",
     "Fire erupts around you, burning everything near."),
    ("detonation", "Detonation", "combat", 60, "any",
     [{"searing_flames": 8, "ignite": 1}, {"searing_flames": 12, "ignite": 6}, {"searing_flames": 16, "ignite": 10, "arcane_fury": 8}],
     {"damage": same("(67.5 + 16.9 * combat) * (2.0 + 0.015 * combat)"), "radius": r3(3, 3.5, 4)}, ["damage"], "not built yet",
     "A great blast of fire at the target."),
    ("corrosive_eruption", "Corrosive Eruption", "combat", 35, "any",
     [{"debilitation": 1}, {"debilitation": 5, "grim_necromancy": 4}, {"debilitation": 12, "grim_necromancy": 10, "arcane_fury": 4}],
     {"curse_duration": r3(30, 60, 300), "curse_radius": r3(4, 5, 6), "damage_pct": same(45), "eruption_radius": same(2.5)}, ["damage_pct"],
     "death damage and curses", "Curse an area: a cursed monster that dies erupts, damaging its neighbours."),
    ("harvest_soul", "Harvest Soul", "combat", 35, "any",
     [{"devastation": 6, "grim_necromancy": 5}, {"devastation": 8, "grim_necromancy": 8, "vampirism": 4},
      {"devastation": 10, "grim_necromancy": 12, "vampirism": 10}],
     {"damage": same("(40 + 10 * combat) * (1.5 + 0.015 * combat)"), "radius": same(3), "healed_pct": same(6)}, ["damage", "healed_pct"],
     "death damage", "Rip the life from enemies around a target and take some of it."),
    ("chain_lightning", "Chain Lightning", "combat", 21, "any",
     [{"devastation": 2, "amplified_lightning": 1}, {"devastation": 5, "amplified_lightning": 4},
      {"devastation": 12, "amplified_lightning": 8, "arcing": 5}],
     {"damage": same("(66.4 + 16.6 * combat) * (0.82 + 0.015 * combat)"), "jumps": r3(2, 4, 6), "damage_ratio": r3(0.3, 0.22, 0.15)},
     ["damage", "damage_ratio"], "lightning", "Lightning leaps from enemy to enemy."),
    ("gathered_bolt", "Gathered Bolt", "combat", 60, "any",
     [{"amplified_lightning": 8, "quickened_casting": 1}, {"amplified_lightning": 10, "quickened_casting": 6, "arcane_fury": 1},
      {"amplified_lightning": 14, "quickened_casting": 12, "arcane_fury": 6}],
     {"damage": same("(70 + 17.5 * combat) * (1.85 + 0.015 * combat)"), "radius": r3(3.5, 4, 5)}, ["damage"], "lightning",
     "A gathered bolt of lightning strikes an area."),
    ("gravity_stone", "Gravity Stone", "nature", 35, "any",
     [{"natural_bond": 1}, {"natural_bond": 5}, {"natural_bond": 8, "arcane_renewal": 6}],
     {"radius": r3(4, 5, 6), "pull": same(2), "duration": r3(4, 5, 6)}, [], "the Nature Magic tree", "Pull enemies together."),
    ("icicle_blast", "Icicle Blast", "nature", 35, "any",
     [{"aquatic_affinity": 2}, {"aquatic_affinity": 5, "arctic_mastery": 5}, {"aquatic_affinity": 10, "arctic_mastery": 10, "freezing": 8}],
     {"damage": same("(56 + 14 * nature) * (0.82 + 0.015 * nature)")}, ["damage"], "ice", "A cone of icicles."),
    ("circle_of_frost", "Circle of Frost", "nature", 60, "any",
     [{"natural_bond": 5, "arctic_mastery": 8, "freezing": 1}, {"natural_bond": 6, "arctic_mastery": 10, "freezing": 6},
      {"natural_bond": 8, "arctic_mastery": 12, "freezing": 12}],
     {"freeze": r3(12, 15, 18), "radius": r3(3.5, 4, 4.5), "damage": same("(13.3 + 3.3 * nature) * (2.0 + 0.015 * nature)")}, ["damage"], "ice",
     "Freeze everything around you."),
    ("summon_provoke", "Summon Provoke", "nature", 12, "any",
     [{"summon_fortitude": 3, "summon_might": 1}, {"summon_fortitude": 7, "summon_might": 4}, {"summon_fortitude": 12, "summon_might": 6, "summon_bond": 6}],
     {"radius": r3(6, 7, 8)}, [], "summons", "Your summon draws the enemies around it."),
    ("aether_blast", "Aether Blast", "nature", 35, "any",
     [{"summon_might": 8, "arcane_renewal": 1}, {"summon_might": 10, "arcane_renewal": 6, "summon_bond": 2},
      {"summon_might": 14, "arcane_renewal": 8, "summon_bond": 12}],
     {"radius": r3(3.5, 4, 5), "stun": same(5), "damage_pct": same("240 + 1.8 * nature")}, ["damage_pct"], "summons",
     "Your summon bursts with aether, stunning those around it."),
    ("invulnerability", "Invulnerability", "nature", 60, "any",
     [{"enveloping_embrace": 1}, {"enveloping_embrace": 6, "nurturing_gift": 4}, {"enveloping_embrace": 12, "nurturing_gift": 8, "arcane_renewal": 6}],
     {"duration": r3(6, 8, 12)}, [], "the Nature Magic tree", "Nothing can hurt the target for a few seconds."),
    ("glacial_aura", "Glacial Aura", "nature", 60, "any",
     [{"feral_wrath": 8, "freezing": 4}, {"feral_wrath": 12, "freezing": 12, "absorption": 6}, {"feral_wrath": 14, "freezing": 15, "absorption": 12}],
     {"duration": r3(10, 12, 15), "freeze": r3(4, 5, 6), "wave_damage": same("(2.6 + 0.65 * nature) * (2.0 + 0.015 * nature)"), "period": same(0.8)},
     ["wave_damage"], "ice", "Waves of frost pulse from you, freezing what they touch."),
]


def gd_str(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for order, (ident, name, tree, recharge, stance, ranks, values, estimated, needs, summary) in enumerate(POWERS):
        wanted.add(ident + ".tres")
        rank_dicts = []
        for req in ranks:
            pairs = ", ".join('"%s": %d' % (ALIASES.get(k, k), v) for k, v in req.items())
            rank_dicts.append("{%s}" % pairs)
        vals = "{\n%s\n}" % ",\n".join('"%s": [%s]' % (k, ", ".join(gd_str(x) for x in v)) for k, v in values.items())
        lines = [
            '[gd_resource type="Resource" script_class="PowerDef" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://game/data/power_def.gd" id="1"]', "", "[resource]",
            'script = ExtResource("1")', 'id = "%s"' % ident, 'display_name = %s' % gd_str(name), 'tree = "%s"' % tree,
            "recharge = %s" % float(recharge), 'stance = "%s"' % stance, "ranks = Array[Dictionary]([%s])" % ", ".join(rank_dicts),
            "values = %s" % vals, "estimated = Array[String]([%s])" % ", ".join(gd_str(k) for k in estimated),
            "summary = %s" % gd_str(summary), "order = %d" % order, "needs = %s" % gd_str(needs),
        ]
        (OUT / (ident + ".tres")).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for old in OUT.glob("*.tres"):
        if old.name not in wanted:
            old.unlink()
    print("wrote", len(POWERS), "powers")


if __name__ == "__main__":
    main()
