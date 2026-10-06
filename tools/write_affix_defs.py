#!/usr/bin/env python3
"""Writes res://data/affixes/*.tres (AffixDef resources). Slot: 0 weapon, 1 armor, 2 trinket. Edit and re-run."""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "affixes"

AFFIXES = [
    # id, title, slot, description
    # Weapons
    ("cleaving", "Cleaving", 0, "Your combo finisher also strikes everything in an arc in front of you."),
    ("chain", "Stormcalled", 0, "25% of hits arc lightning to another nearby enemy."),
    ("searing", "Searing", 0, "Critical hits set the enemy on fire."),
    ("executioner", "Executioner's", 0, "Deal 60% more damage to enemies below 25% health."),
    ("kindling", "Kindling", 0, "Hits on burning enemies deal 50% more damage and spread the fire to enemies next to them."),
    ("juggler", "Juggler's", 0, "Hits on enemies in mid-air deal 80% more damage and knock them back up."),
    ("breaker", "Breaker's", 0, "Hits on stunned or knocked-down enemies are always critical hits."),
    ("maelstrom", "Maelstrom", 0, "Your combo finisher stuns every enemy it hits for 1 second."),
    ("impaler", "Impaler's", 0, "Enemies kicked off your Skewer burst where they land, hurting everything around them."),
    # Armor
    ("shock_roll", "Thunderstep", 1, "Starting a dodge roll blasts nearby enemies away and hurts them."),
    ("cinder_roll", "Ember-Treaded", 1, "Your dodge roll leaves a trail of embers that sets enemies alight for 3 seconds."),
    ("vaultborn", "Vaultborn", 1, "Landing a Leap makes your next Power Strike within 4 seconds free, with no cooldown."),
    ("charger", "Ramming", 1, "The enemies too big for your Skewer to move are stunned much longer."),
    ("smouldering", "Smouldering", 1, "When you are hit, every enemy close to you catches fire."),
    # Trinkets
    ("twin_flame", "Twin-Flame", 2, "Fireball launches a second fireball at an angle."),
    ("quickening", "Quickened", 2, "12% of kills reset all your skill cooldowns."),
    ("wildfire", "Wildfire", 2, "A Fireball that catches three or more enemies in its blast has 3 seconds taken off its cooldown."),
    ("virtuoso", "Virtuoso's", 2, "Using a different skill than your last adds 20% damage (up to 3 stacks, for 4 seconds). Repeating a skill drops the stacks."),
    ("quaker", "Quakebound", 2, "Every kill charges 4% of Earthshatter."),
    ("pyre", "Pyrebound", 2, "Enemies that die while burning explode, hurting and igniting everything around them."),
    # unique-only (no title)
    ("gravewarden", "", 0, "Power Strike sends a shockwave surging forward through every enemy in a line."),
    ("aegis", "", 1, "Every 4th hit you take is blocked and answered with a shockwave."),
    ("ember", "", 2, "Every kill erupts in a fiery explosion."),
]


def q(s: str) -> str:
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    keep = {"%s.tres" % a[0] for a in AFFIXES}
    for old_file in OUT.glob("*.tres"):
        if old_file.name not in keep:
            old_file.unlink()   # an affix removed from the table leaves no file behind
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
