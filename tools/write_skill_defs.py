#!/usr/bin/env python3
"""Writes res://data/skills/*.tres (SkillDef resources). Edit the table and re-run to change skill data."""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "skills"

COMBO = [
    [
        {"clip": "slash_r", "start": 0.35, "strike": 0.73, "end": 1.1, "time": 0.78, "weight": 1.0, "lunge": 0.4},
        {"clip": "thrust", "start": 1.0, "strike": 1.57, "end": 2.1, "time": 0.9, "weight": 0.9, "lunge": 0.7, "range": 2.8},
    ],
    [
        {"clip": "slash_l", "start": 0.7, "strike": 1.37, "end": 1.85, "time": 0.85, "weight": 1.0, "lunge": 0.4},
        {"clip": "slash", "start": 0.5, "strike": 1.07, "end": 1.45, "time": 0.85, "weight": 1.0, "lunge": 0.5},
    ],
    [
        {"clip": "combo_end", "start": 0.6, "strike": 1.37, "end": 2.2, "time": 1.3, "weight": 1.7, "lunge": 0.9,
         "mult": 1.35, "finisher": True},
    ],
]

SKILLS = {
    "basic": dict(display_name="Attack", mana=0.0, cooldown=0.0, time=0.85, clip="slash", clip_start=0.5, clip_strike=1.07,
                  clip_end=1.45, kind="melee", range=2.4, mult=1.0, weight=1.0, lunge=0.5,
                  description="A three-hit sword combo. The first two hits vary between slashes and thrusts; the third is a heavy finisher. Pause for a moment and the combo resets.",
                  modifier_affixes=["cleaving", "momentum", "chain", "searing", "executioner", "frostbite", "riposte"],
                  extra={"combo": COMBO}),
    "power": dict(display_name="Power Strike", mana=8.0, cooldown=2.0, time=1.3, clip="power", clip_start=0.55, clip_strike=1.23,
                  clip_end=1.75, kind="melee", range=2.4, mult=2.3, weight=1.9, lunge=1.0,
                  description="Heave the blade overhead for a crushing blow. Hits much harder than a normal swing, and heavily staggers and knocks back what it hits.",
                  modifier_affixes=["gravewarden", "executioner", "frostbite", "searing", "chain"]),
    "cleave": dict(display_name="Cleave", mana=12.0, cooldown=3.5, time=1.35, clip="cleave", clip_start=1.0, clip_strike=1.73,
                   clip_end=3.0, kind="cleave", range=3.0, mult=1.1, weight=1.3, lunge=0.3,
                   description="Whirl your blade around you, striking every enemy within reach.",
                   modifier_affixes=["whirlpool", "executioner", "frostbite", "searing", "chain"]),
    "fireball": dict(display_name="Fireball", mana=16.0, cooldown=3.0, time=1.4, clip="charge", clip_start=0.8, clip_strike=2.05,
                     clip_end=2.3, kind="projectile", range=14.0, mult=1.0, weight=1.6, lunge=0.4, aimed=True,
                     description="Hold the key to aim a ground target, release to cast. The fireball flies to that exact point and explodes, burning everything inside the highlighted sphere. Fire damage ignores armor and cannot miss.",
                     modifier_affixes=["twin_flame"],
                     extra={"charged": True, "gather": 0.72, "release_clip": "throw", "release_start": 0.55,
                            "release_speed": 1.5, "release_after": 0.3}),
    "skewer": dict(display_name="Skewer", mana=18.0, cooldown=9.0, time=1.8, clip="charge_run", clip_start=0.0, clip_strike=0.3,
                   clip_end=0.5, kind="charge", range=9.0, mult=1.5, weight=2.2, lunge=0.0, directional=True,
                   description="Lower the blade and charge toward the cursor. The first enemy in your path is run through to the hilt and carried along; up to two more are skewered on the same blade. Then you plant yourself and drive a boot into the pile, kicking all of them off the sword and far away from you. Enemies in the way that do not fit on the blade are shoved aside. Bosses cannot be impaled and stop the charge.",
                   modifier_affixes=["frostbite", "searing"], extra={"skewer": True}),
    "leap": dict(display_name="Leap", mana=12.0, cooldown=7.0, time=1.8, clip="leap", clip_start=1.4, clip_strike=2.5,
                 clip_end=3.9, kind="leap", range=10.0, mult=1.3, weight=2.0, lunge=0.0, directional=True,
                 description="Spring through the air to the cursor. Land on a knocked-down enemy and drive the sword straight down through it into the earth for a guaranteed critical blow, then plant a boot on it, pinning it and stunning it while you wrench the blade free. Land anywhere else and the same plunging chop hits everything around the landing spot for lighter damage. You sail over enemies in the way.",
                 modifier_affixes=[], extra={"leap": True}),
    "earthshatter": dict(display_name="Earthshatter", mana=0.0, cooldown=0.0, time=1.9, clip="earthshatter", clip_start=0.0, clip_strike=1.93,
                         clip_end=3.03, kind="earthshatter", range=7.5, mult=3.2, weight=3.0, lunge=0.0, directional=True,
                         description="The ultimate. It charges as you deal damage (taking damage does not charge it); when the bar is full, raise your blade overhead and drive it into the earth. The shockwave hurls every enemy around you high into the air, hardest near the centre, and leaves them stunned. Anything thrown into a wall or pillar is slammed for extra damage. Burning, bleeding and chilled enemies pass those effects to everyone else caught in it. Bosses are staggered, not thrown.",
                         modifier_affixes=[], extra={"earthshatter": True, "charge": 650.0}),
    "potion": dict(display_name="Potion", mana=0.0, cooldown=1.0, time=0.0, kind="potion", range=0.0, mult=0.0,
                   description="Drink a health potion to restore 60 health. Does nothing at full health.", modifier_affixes=[]),
    "dodge": dict(display_name="Dodge", mana=0.0, cooldown=0.7, time=0.55, kind="dodge", range=0.0, mult=0.0,
                  description="Roll in the direction you are moving (or toward the cursor). You take no damage for the whole roll, and every non-boss enemy near you is shoved aside and has its current attack interrupted.",
                  modifier_affixes=["shock_roll", "riposte"]),
}

DEFAULTS = dict(mana=0.0, cooldown=0.0, time=1.0, clip="", clip_start=0.0, clip_strike=0.0, clip_end=0.0, kind="melee",
                range=2.4, mult=1.0, weight=1.0, lunge=0.0, directional=False, aimed=False, description="",
                modifier_affixes=[], extra={})


def fmt(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, list):
        return "[%s]" % ", ".join(fmt(x) for x in v)
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{%s}" % ", ".join("%s: %s" % (fmt(k), fmt(x)) for k, x in v.items())
    raise TypeError(v)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for sid, spec in SKILLS.items():
        d = {**DEFAULTS, **spec}
        lines = ['[gd_resource type="Resource" script_class="SkillDef" load_steps=2 format=3]', "",
                 '[ext_resource type="Script" path="res://game/data/skill_def.gd" id="1"]', "", "[resource]",
                 'script = ExtResource("1")', 'id = "%s"' % sid]
        for key in ("display_name", "description", "mana", "cooldown", "time", "clip", "clip_start", "clip_strike", "clip_end",
                    "kind", "range", "mult", "weight", "lunge", "directional", "aimed"):
            lines.append("%s = %s" % (key, fmt(d[key])))
        affixes = d["modifier_affixes"]
        lines.append("modifier_affixes = Array[String]([%s])" % ", ".join('"%s"' % a for a in affixes))
        lines.append("extra = %s" % fmt(d["extra"]))
        (OUT / ("%s.tres" % sid)).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        print("wrote", sid)


if __name__ == "__main__":
    main()
