"""Renders the hotbar icons of the Dungeon Siege II powers Curse plays: assets/icons/<power id>.png (transparent, 192 px).

    blender --background --python /absolute/path/tools/blender/make_power_icons.py -- [ids...]
    (on a machine with no GPU: CURSE_ICON_ENGINE=CYCLES)

Same rules as the other icons (docs/ART_DIRECTION.md): worn, muted, painted on the vertices, lit from the upper left with a warm key and a
cold fill; make_items' helpers, palette, weathering and renderer are reused. Each is one plain object that reads at hotbar size: a blade in
a ring of steel streaks (Whirling Strike), a greatsword driven into split ground (Staggering Blow), a horned helm with the cry's rings
(War Cry), a shield struck with a blade (Provoke), stones thrown out of a ring (Repulse), a skull bound shut (Silence), a ring of embers
(Flame Nexus), a burst of embers and rock (Detonation).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
import make_items as mi
import make_crypt_props as cp
from make_items import Parts, box, cylinder, sphere, torus

ICON_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "icons"))


def streak_ring(bm, radius, count, z=0.0, thick=0.012, gap=0.35):
    for i in range(count):
        a = math.tau * i / count
        for k in range(3):
            t = a + k * gap / count
            box(bm, (math.cos(t) * radius, math.sin(t) * radius, z), (0.06, thick, 0.006), rot=(0, 0, t + math.pi / 2))


def build_whirling_strike(parts):
    mi.build_longsword(parts)
    streak_ring(parts.bm("dark_steel"), 0.62, 14)


def build_staggering_blow(parts):
    mi.build_greatsword(parts)
    ground = parts.bm("leather_dark")
    box(ground, (1.25, 0.0, -0.06), (0.5, 0.8, 0.05), cuts=2)
    for i in range(7):
        a = math.tau * i / 7
        box(parts.bm("iron"), (1.25 + math.cos(a) * 0.22, math.sin(a) * 0.22, -0.02), (0.18, 0.02, 0.01), rot=(0, 0, a))
        sphere(parts.bm("leather_dark"), (1.25 + math.cos(a) * 0.4, math.sin(a) * 0.4, 0.0), 0.035, (1, 1, 0.7), segs=8, rings=5)


def build_war_cry(parts):
    mi.build_iron_helm(parts)
    for side in (-1, 1):
        cylinder(parts.bm("bone"), (0.0, side * 0.2, 0.15), 0.04, 0.22, axis="Y", segs=10, radius2=0.008, rot=(0.6 * side, 0, 0))
    for r in (0.3, 0.4, 0.5):
        for i in range(5):
            a = -0.7 + 1.4 * i / 4
            box(parts.bm("dark_steel"), (math.cos(a) * r + 0.05, math.sin(a) * r, 0.06), (0.012, 0.07, 0.006), rot=(0, 0, a))


def build_provoke(parts):
    mi.build_buckler(parts)
    blade = parts.bm("steel")
    box(blade, (0.05, -0.05, 0.08), (0.5, 0.035, 0.01), rot=(0, 0, 0.7))
    box(parts.bm("dark_steel"), (-0.13, -0.24, 0.08), (0.03, 0.12, 0.02), rot=(0, 0, 0.7))


def build_repulse(parts):
    sphere(parts.bm("iron"), (0, 0, 0.04), 0.07, (1, 1, 0.7), segs=14, rings=8)
    torus(parts.bm("dark_steel"), (0, 0, 0.02), 0.2, 0.01, axis="Z", major_segs=36, minor_segs=6)
    for i in range(8):
        a = math.tau * i / 8
        box(parts.bm("steel"), (math.cos(a) * 0.32, math.sin(a) * 0.32, 0.02), (0.12, 0.018, 0.01), rot=(0, 0, a))
        sphere(parts.bm("leather_dark"), (math.cos(a) * 0.45, math.sin(a) * 0.45, 0.02), 0.03, (1, 1, 0.7), segs=8, rings=5)


def build_silence(parts):
    bone = parts.bm("bone")
    sphere(bone, (0.0, 0.0, 0.08), 0.12, (1.0, 0.95, 0.9), segs=18, rings=12)
    box(bone, (0.1, 0.0, 0.02), (0.08, 0.13, 0.05), cuts=1)
    for side in (-1, 1):
        sphere(parts.bm("leather_dark"), (0.07, side * 0.045, 0.14), 0.03, (1, 1, 0.6), segs=10, rings=6)
    band = parts.bm("iron")
    box(band, (0.1, 0.0, 0.03), (0.04, 0.3, 0.08), cuts=1)
    for side in (-1, 1):
        sphere(parts.bm("brass"), (0.12, side * 0.12, 0.07), 0.012, segs=6, rings=4)


def build_flame_nexus(parts):
    sphere(parts.bm("leather_dark"), (0, 0, 0.0), 0.12, (1, 1, 0.3), segs=14, rings=6)
    for i in range(10):
        a = math.tau * i / 10
        cylinder(parts.bm("ember"), (math.cos(a) * 0.28, math.sin(a) * 0.28, 0.06), 0.045, 0.14, axis="Z", segs=8, radius2=0.004)
        cylinder(parts.bm("ember"), (math.cos(a + 0.3) * 0.36, math.sin(a + 0.3) * 0.36, 0.04), 0.03, 0.09, axis="Z", segs=8, radius2=0.003)


def build_detonation(parts):
    sphere(parts.bm("ember"), (0, 0, 0.05), 0.1, (1, 1, 0.8), segs=14, rings=8)
    for i in range(12):
        a = math.tau * i / 12
        r = 0.22 + 0.06 * (i % 3)
        box(parts.bm("ember"), (math.cos(a) * r, math.sin(a) * r, 0.04), (0.12, 0.025, 0.01), rot=(0, 0, a))
        sphere(parts.bm("leather_dark"), (math.cos(a + 0.2) * (r + 0.13), math.sin(a + 0.2) * (r + 0.13), 0.03), 0.028, (1, 1, 0.7), segs=8, rings=5)


# Placeholders until the painted icons are made with tools/meshy_icons.py (Whirling Strike already uses the painted cleave icon, so it is
# not rendered by default: pass its id to render it).
BUILDERS = {
    "staggering_blow": build_staggering_blow, "war_cry": build_war_cry,
    "provoke": build_provoke, "repulse": build_repulse, "silence": build_silence, "flame_nexus": build_flame_nexus,
    "detonation": build_detonation,
}


def main():
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    mi.ICONS = ICON_DIR
    builders = dict(BUILDERS, whirling_strike=build_whirling_strike) if "whirling_strike" in wanted else BUILDERS
    for i, (name, builder) in enumerate(builders.items()):
        if wanted and name not in wanted:
            continue
        mi.reset_scene()
        parts = Parts()
        builder(parts)
        obj = cp.make_object(name, parts, 90 + i)
        mi.render_icon(obj, name, 192)


if __name__ == "__main__":
    main()
