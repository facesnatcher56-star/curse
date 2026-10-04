#!/usr/bin/env python3
"""Writes res://data/enemies/*.tres (EnemyDef resources). Edit the table below and re-run to change enemy data;
the .tres files are what the game loads."""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "enemies"

ZOMBIE_CLIPS = ["idle", "walk", "run", "attack", "hit", "death"]

ENEMIES = {
    "zombie": dict(display_name="Zombie", model_path="res://assets/models/zombie", height=1.75, radius=0.42, health=60.0,
                   damage_min=6.0, damage_max=10.0, speed=3.6, attack_range=1.6, attack_time=1.1, armor=8.0, defense=12.0,
                   attack_rating=28.0, flinch=0.35, behavior="melee", params={"heavy_chance": 0.25},
                   min_wave=1, spawn_mode="pack", base_count=11.0, per_wave=3.0, max_per_wave=60),
    "brute": dict(display_name="Brute", model_path="res://assets/models/zombie_brute", height=2.4, radius=0.62, health=220.0,
                  damage_min=14.0, damage_max=22.0, speed=2.9, attack_range=2.2, attack_time=1.4, armor=25.0, defense=20.0,
                  attack_rating=45.0, flinch=0.1, knock_resist=0.6, stun_resist=0.5, impalable=False, behavior="melee",
                  params={"heavy_chance": 0.5}, token_weight=2, gib_color=(0.38, 0.42, 0.34),
                  min_wave=2, spawn_mode="solo", base_count=1.0, per_wave=0.5, max_per_wave=8),
    "ghoul": dict(display_name="Ghoul", model_path="res://assets/models/ghoul", height=1.6, radius=0.36, health=38.0,
                  damage_min=5.0, damage_max=8.0, speed=4.8, attack_range=1.5, attack_time=0.8, armor=3.0, defense=20.0,
                  attack_rating=30.0, flinch=0.5, behavior="pouncer", model_scale=(0.95, 0.95, 0.95),
                  clips=["idle", "walk", "run", "attack", "hit", "death", "leap", "charge_run"],
                  gib_color=(0.5, 0.5, 0.47),
                  params={"flank_radius": 5.5, "leap_min": 2.8, "leap_max": 6.5, "windup": 0.55, "leap_time": 0.42,
                          "recover": 1.1, "pounce_mult": 1.5, "cooldown_min": 2.2, "cooldown_max": 3.6},
                  min_wave=2, spawn_mode="pack", base_count=2.0, per_wave=0.7, max_per_wave=8),
    "spitter": dict(display_name="Spitter", model_path="res://assets/models/spitter", height=1.7, radius=0.4, health=34.0,
                    damage_min=6.0, damage_max=9.0, speed=3.2, attack_range=1.5, attack_time=1.0, armor=4.0, defense=14.0,
                    attack_rating=30.0, flinch=0.5, behavior="spitter",
                    clips=["idle", "walk", "run", "hit", "death", "throw", "stagger"], gib_color=(0.55, 0.6, 0.25),
                    params={"preferred": 8.0, "min_dist": 5.0, "fire_range": 13.0, "windup": 0.75, "cooldown_min": 2.4,
                            "cooldown_max": 3.6, "glob_time": 0.85, "splash": 1.3, "puddle_radius": 1.6,
                            "puddle_time": 3.5, "puddle_dps": 5.0, "puddle_slow": 0.3},
                    min_wave=3, spawn_mode="solo", base_count=1.0, per_wave=0.5, max_per_wave=5),
    "bloater": dict(display_name="Bloater", model_path="res://assets/models/bloater", height=2.0, radius=0.7, health=90.0,
                    damage_min=14.0, damage_max=14.0, speed=3.3, attack_range=2.3, attack_time=1.0, armor=4.0, defense=8.0,
                    attack_rating=30.0, flinch=0.1, knock_resist=0.5, impalable=False, behavior="bloater",
                    model_scale=(1.0, 1.0, 1.0), clips=["idle", "walk", "run", "attack", "hit", "death", "scream"],
                    gib_color=(0.62, 0.66, 0.4), token_weight=0,
                    params={"fuse_range": 2.3, "fuse_time": 1.0, "blast_radius": 3.2, "blast_damage": 22.0,
                            "cloud_time": 4.5, "cloud_dps": 5.0, "fire_blast_damage": 32.0},
                    min_wave=4, spawn_mode="solo", base_count=1.0, per_wave=0.35, max_per_wave=3),
    "priest": dict(display_name="Plague Priest", model_path="res://assets/models/priest", height=1.85, radius=0.4, health=55.0,
                   damage_min=6.0, damage_max=9.0, speed=2.2, attack_range=1.8, attack_time=0.9, armor=4.0, defense=14.0,
                   attack_rating=30.0, flinch=0.4, behavior="support",
                   clips=["idle", "walk", "run", "attack", "hit", "death", "cast"], gib_color=(0.3, 0.3, 0.32),
                   attack_clip="attack", attack_start=0.5, attack_strike=1.07, attack_end=1.45, token_weight=1,
                   params={"ward_interval": 7.0, "ward_time": 5.0, "ward_reduction": 0.4, "ward_haste": 1.25,
                           "summon_interval": 15.0, "summon_count": 2, "summon_max": 4, "keep_min": 6.5,
                           "keep_max": 11.0, "flee_dist": 4.5},
                   min_wave=5, spawn_mode="support", base_count=1.0, per_wave=0.3, max_per_wave=2),
}

DEFAULTS = dict(attack_start=0.6, attack_strike=1.43, attack_end=2.0, model_scale=(1.0, 1.0, 1.0), knock_resist=0.0, stun_resist=0.0, impalable=True, token_weight=1,
                gib_color=(0.42, 0.48, 0.37), clips=ZOMBIE_CLIPS, attack_clip="attack", spawn_mode="pack", min_wave=1,
                base_count=0.0, per_wave=0.0, max_per_wave=0, params={})


def fmt(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, tuple) and len(v) == 3:
        return "Vector3(%s, %s, %s)" % tuple(repr(float(x)) for x in v)
    if isinstance(v, list):
        return "Array[String]([%s])" % ", ".join('"%s"' % x for x in v)
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n%s\n}" % ",\n".join('"%s": %s' % (k, fmt(x)) for k, x in v.items())
    raise TypeError(v)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for eid, spec in ENEMIES.items():
        d = {**DEFAULTS, **spec}
        gib = d["gib_color"]
        lines = [
            '[gd_resource type="Resource" script_class="EnemyDef" load_steps=2 format=3]', "",
            '[ext_resource type="Script" path="res://game/data/enemy_def.gd" id="1"]', "", "[resource]",
            'script = ExtResource("1")', 'id = "%s"' % eid,
        ]
        for key in ("display_name", "model_path", "model_scale", "height", "radius", "clips"):
            lines.append("%s = %s" % (key, fmt(d[key])))
        lines.append("gib_color = Color(%s, %s, %s, 1)" % tuple(repr(float(x)) for x in gib))
        for key in ("health", "damage_min", "damage_max", "speed", "attack_range", "attack_time", "armor", "defense",
                    "attack_rating", "flinch", "knock_resist", "stun_resist", "impalable", "attack_clip", "attack_start",
                    "attack_strike", "attack_end", "behavior",
                    "params", "token_weight", "min_wave", "spawn_mode", "base_count", "per_wave", "max_per_wave"):
            lines.append("%s = %s" % (key, fmt(d[key])))
        (OUT / ("%s.tres" % eid)).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        print("wrote", eid)


if __name__ == "__main__":
    main()
