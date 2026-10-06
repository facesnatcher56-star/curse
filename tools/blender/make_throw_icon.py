"""Renders the Weapon Throw hotbar icon: assets/icons/throw.png (transparent, 192 px).

    blender --background --python /absolute/path/tools/blender/make_throw_icon.py

A worn longsword in flight, point first and slightly down, with the dirt and chips it kicks up and three dull streaks behind it so it
reads as thrown, not just held. Same rules as the other icons (docs/ART_DIRECTION.md): muted, painted on the vertices, lit from the
upper left with a warm key and a cold fill; make_items' own renderer and sword builder are reused.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
import make_items as mi
import make_crypt_props as cp
from make_items import Parts, box, sphere

ICON_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "icons"))


def build():
    parts = Parts()
    mi.build_longsword(parts)
    streak = parts.bm("dark_steel")
    for i, (y, length) in enumerate(((0.12, 0.7), (-0.05, 0.9), (-0.22, 0.55))):
        box(streak, (-0.55 - length * 0.5, y, -0.03), (length, 0.012, 0.006))   # streaks trailing behind the pommel
    dirt = parts.bm("leather_dark")
    for i, (x, y, r) in enumerate(((0.75, -0.18, 0.03), (0.86, -0.1, 0.022), (0.7, -0.3, 0.02), (0.95, -0.22, 0.016))):
        sphere(dirt, (x, y, -0.04), r, (1.0, 1.0, 0.7), segs=8, rings=5)
    return parts


def main():
    mi.reset_scene()
    parts = build()
    obj = cp.make_object("throw", parts, 77)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    mi.ICONS = ICON_DIR
    mi.render_icon(obj, "throw", 192)


if __name__ == "__main__":
    main()
