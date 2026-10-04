#!/usr/bin/env python3
"""Writes res://data/affixes/*.tres (AffixDef resources). Slot: 0 weapon, 1 armor, 2 trinket. Edit and re-run."""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "affixes"

AFFIXES = [
    # id, title, slot, description
    ("cleaving", "Cleaving", 0, "Your combo finisher also strikes everything in an arc in front of you."),
    ("momentum", "Relentless", 0, "Each kill makes you attack 30% faster for 3 seconds."),
    ("chain", "Stormcalled", 0, "25% of hits arc lightning to another nearby enemy."),
    ("searing", "Searing", 0, "Critical hits set the enemy on fire."),
    ("executioner", "Executioner's", 0, "Deal 60% more damage to enemies below 25% health."),
    ("frostbite", "Frostbitten", 0, "Hits slow enemies by 40% for 2 seconds."),
    ("riposte", "Duelist's", 1, "After a dodge roll, your next attack within 1.5 seconds always crits."),
    ("shock_roll", "Thunderstep", 1, "Starting a dodge roll blasts nearby enemies away and hurts them."),
    ("warding", "Warded", 1, "The first hit you take every 8 seconds is blocked completely."),
    ("last_stand", "Stalwart", 1, "Below 35% health, you take 30% less damage."),
    ("twin_flame", "Twin-Flame", 2, "Fireball launches a second fireball at an angle."),
    ("whirlpool", "Whirling", 2, "Cleave first drags nearby enemies in toward you."),
    ("windfall", "Fortunate", 2, "15% of kills drop a health orb."),
    ("quickening", "Quickened", 2, "12% of kills reset all your skill cooldowns."),
    # unique-only (no title)
    ("gravewarden", "", 0, "Power Strike sends a shockwave surging forward through every enemy in a line."),
    ("aegis", "", 1, "Every 4th hit you take is blocked and answered with a shockwave."),
    ("ember", "", 2, "Every kill erupts in a fiery explosion."),
]


def q(s: str) -> str:
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for aid, title, slot, desc in AFFIXES:
        text = "\n".join([
            '[gd_resource type="Resource" script_class="AffixDef" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://game/data/affix_def.gd" id="1"]', "", "[resource]",
            'script = ExtResource("1")', "id = %s" % q(aid), "title = %s" % q(title), "slot = %d" % slot,
            "description = %s" % q(desc), ""])
        (OUT / ("%s.tres" % aid)).write_text(text, encoding="utf-8", newline="\n")
    print("wrote", len(AFFIXES), "affixes")


if __name__ == "__main__":
    main()
