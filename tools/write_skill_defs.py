#!/usr/bin/env python3
"""Writes res://data/skills/*.tres (SkillDef resources). Edit the table and re-run to change skill data."""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "skills"

COMBO = [
    [
        {"clip": "atk_slash_r", "start": 0.0, "strike": 0.38, "end": 0.75, "time": 0.9, "weight": 1.0, "lunge": 0.4},
        {"clip": "atk_thrust", "start": 0.0, "strike": 0.57, "end": 1.1, "time": 1.0, "weight": 0.9, "lunge": 0.7, "range": 2.8},
    ],
    [
        {"clip": "atk_slash_l", "start": 0.0, "strike": 0.67, "end": 1.15, "time": 1.0, "weight": 1.0, "lunge": 0.4},
        {"clip": "atk_slash", "start": 0.0, "strike": 0.57, "end": 0.95, "time": 0.95, "weight": 1.0, "lunge": 0.5},
    ],
    [
        {"clip": "atk_finisher", "start": 0.0, "strike": 0.77, "end": 1.6, "time": 1.45, "weight": 1.7, "lunge": 0.9,
         "mult": 1.35, "finisher": True},
    ],
]

SKILLS = {
    "basic": dict(display_name="Attack", mana=0.0, cooldown=0.0, time=0.85, clip="atk_slash", clip_start=0.0, clip_strike=0.57,
                  clip_end=0.95, kind="melee", range=2.4, mult=1.0, weight=1.0, lunge=0.5,
                  description="A three-hit sword combo. The first two hits vary between slashes and thrusts; the third is a heavy finisher. Pause for a moment and the combo resets.",
                  extra={"combo": COMBO}),
    "fireball": dict(display_name="Fireball", mana=16.0, cooldown=5.5, time=1.4, clip="charge", clip_start=0.8, clip_strike=2.05,
                     clip_end=2.3, kind="projectile", range=14.0, mult=1.0, weight=1.6, lunge=0.4, aimed=True,
                     description="Hold the key to aim a ground target, release to cast. The fireball flies to that exact point and explodes, burning everything inside the highlighted sphere. Fire damage ignores armor and cannot miss.",
                     extra={"charged": True, "gather": 0.72, "release_clip": "throw", "release_start": 0.55,
                            "release_speed": 1.5, "release_after": 0.3}),
    "brutal_attack": dict(display_name="Brutal Attack", mana=0.0, cooldown=0.0, time=0.0, kind="buff", range=0.0, mult=15.0,
                         description="Gather a faint orange heat haze along your silhouette. The next basic melee hit deals 1500% weapon damage and gibs its victim if lethal. Missing, being dodged or being blocked does not spend it. Recharges from damage dealt by your active party, using Dungeon Siege II's 21-seconds-of-combat formula.", extra={"attack_animation": {"clip": "power", "start": 0.78, "strike": 1.23, "end": 1.72, "time": 1.56, "swing_from": 0.65, "swing_slow": 1.25, "weight": 2.15, "lunge": 0.85, "range": 2.5, "brutal_animation": True}}),
    "take_aim": dict(display_name="Take Aim", mana=0.0, cooldown=0.0, time=0.0, kind="buff", range=0.0, mult=15.0,
                     description="Order Cutter to gather his focus. His next arrow deals 1500% weapon damage and gibs its victim if lethal. Recharges from damage dealt by your active party, using Dungeon Siege II's 21-seconds-of-combat formula.", extra={}),
    # Dungeon Siege II powers (PowerController; their numbers are PowerDef's, by rank): no mana, no cooldown, recharged by damage dealt.
    "whirling_strike": dict(display_name="Whirling Strike", kind="power", range=0.0,
                            description="Whirl your weapon in a full circle: every enemy within reach takes a heavy share of your weapon damage and is stunned for a moment. A DS2 Melee power: it opens with Critical Strike and Fortitude and recharges from damage dealt."),
    "staggering_blow": dict(display_name="Staggering Blow", kind="power", range=0.0,
                            description="Your next blow with a two-handed weapon sends out a shockwave that stuns every enemy around the one you hit for several seconds. A miss does not spend it. A DS2 Melee power (Overbear)."),
    "war_cry": dict(display_name="War Cry", kind="power", range=0.0,
                    description="A deafening cry in a cone in front of you: the enemies in it run in fear with their armour stripped for 20 seconds, and your next blows are all critical. A DS2 Melee power (Critical Strike, Smite)."),
    "provoke": dict(display_name="Provoke", kind="power", range=0.0,
                    description="Bang your shield: every enemy around turns on you, and your armour rises while you hold them. Needs a shield. A DS2 Melee power (Barricade)."),
    "repulse": dict(display_name="Repulse", kind="power", range=0.0,
                    description="For a while, anything that comes within reach of you is thrown back and stunned. A DS2 Ranged power (Dodge, Survival)."),
    "silence": dict(display_name="Silence", kind="power", range=0.0,
                    description="Monsters in the area under the cursor cannot cast spells for a long while: no wards, no raising the dead. A DS2 Ranged power (Dodge, Survival)."),
    "flame_nexus": dict(display_name="Flame Nexus", kind="power", range=0.0,
                        description="Fire erupts around you, burning every enemy near and setting them alight. Grows with Combat Magic and Searing Flames. A DS2 Combat Magic power."),
    "detonation": dict(display_name="Detonation", kind="power", range=0.0,
                       description="A great blast of fire at the cursor throws enemies back and sets them alight. Grows with Combat Magic and Searing Flames. A DS2 Combat Magic power (Ignite)."),
    "thunderous_shot": dict(display_name="Thunderous Shot", kind="power", range=0.0, aimed=True,
                            description="Hold the key to aim: a lit line shows where the bolt will go and outlines every enemy it will go through. Let go to draw back and loose a thunderous bolt that flies faster than the eye can follow, punching through all of them and stunning them for several seconds. Needs a bow. A DS2 Ranged power (Biting Arrow)."),
    "potion": dict(display_name="Potion", mana=0.0, cooldown=1.0, time=0.0, kind="potion", range=0.0, mult=0.0,
                   description="Drink a health potion to restore 60 health. Does nothing at full health."),
    "dodge": dict(display_name="Dodge", mana=0.0, cooldown=0.7, time=0.55, kind="dodge", range=0.0, mult=0.0,
                  description="Roll in the direction you are moving (or toward the cursor). You take no damage for the whole roll, and every non-boss enemy near you is shoved aside and has its current attack interrupted."),
}

DEFAULTS = dict(mana=0.0, cooldown=0.0, time=1.0, clip="", clip_start=0.0, clip_strike=0.0, clip_end=0.0, kind="melee",
                range=2.4, mult=1.0, weight=1.0, lunge=0.0, directional=False, aimed=False, description="", extra={})


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
        lines.append("extra = %s" % fmt(d["extra"]))
        (OUT / ("%s.tres" % sid)).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        print("wrote", sid)


if __name__ == "__main__":
    main()
