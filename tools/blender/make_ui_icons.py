"""Renders the HUD's small status icons in Blender: assets/icons/ui/<name>.png (transparent, 128 px).

    blender --background --python /absolute/path/tools/blender/make_ui_icons.py -- [names...]

Same rules as every other asset (docs/ART_DIRECTION.md, make_items.py and make_crypt_props.py, whose helpers, palette and
weathering this reuses): worn, muted, hand-painted on the vertices, lit from the upper left with a warm key and a cold fill, like
the item icons. Seen from the front, a little from above, so a coin stack, a loaf, a skull and a clawed hand all read at 28 px.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
import mathutils
import make_items as mi
import make_crypt_props as cp
from make_items import Parts, box, cylinder, sphere

V = mathutils.Vector
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "icons", "ui"))
mi.MATERIALS.update({
    "gold": ((0.50, 0.37, 0.12), 0.75, 0.45, 0.9),
    "bread": ((0.44, 0.29, 0.13), 0.0, 0.9, 0.5),
    "crust": ((0.28, 0.17, 0.07), 0.0, 0.95, 0.6),
    "rot": ((0.30, 0.34, 0.22), 0.0, 0.8, 0.8),
    "dark": ((0.05, 0.045, 0.04), 0.0, 1.0, 0.0),
})


def build_gold(parts):
    """A little stack of worn coins with one leaning on it."""
    g = parts.bm("gold")
    for i, (x, y, r) in enumerate(((0.0, 0.0, 0.5), (0.04, -0.02, 0.5), (-0.03, 0.03, 0.5), (0.02, 0.0, 0.49), (-0.02, -0.03, 0.5))):
        cylinder(g, (x, y, 0.05 + i * 0.1), r, 0.09, axis="Z", segs=24)
    cylinder(g, (0.0, 0.0, 0.58), 0.41, 0.03, axis="Z", segs=24)   # the raised rim face of the top coin
    cylinder(parts.bm("dark"), (0.0, 0.0, 0.595), 0.28, 0.02, axis="Z", segs=24)   # worn-in centre
    cylinder(g, (0.0, 0.0, 0.6), 0.2, 0.02, axis="Z", segs=24)
    # a coin leaning on the front of the stack
    cylinder(g, (0.0, -0.62, 0.38), 0.44, 0.08, axis="Y", segs=24, rot=(0.35, 0.0, 0.0))
    cylinder(parts.bm("dark"), (0.0, -0.67, 0.4), 0.27, 0.02, axis="Y", segs=24, rot=(0.35, 0.0, 0.0))


def build_food(parts):
    """A crusty loaf, slashed across the top, with a heel torn off."""
    b = parts.bm("bread")
    sphere(b, (0.0, 0.0, 0.32), 0.62, scale=(1.35, 0.8, 0.62), segs=24, rings=14)
    cp.lump(b, 0.04, 3.0, 5.0)
    c = parts.bm("crust")
    for i in range(4):
        x = -0.52 + i * 0.36
        box(c, (x, 0.0, 0.66), (0.09, 0.62, 0.05), rot=(0.0, 0.0, 0.5))   # the slashes
    sphere(c, (0.0, 0.0, 0.06), 0.8, scale=(1.35, 0.8, 0.12), segs=20, rings=6)   # the dark base crust
    sphere(b, (0.95, -0.45, 0.13), 0.17, scale=(1.2, 1, 0.8), segs=10, rings=6)   # crumbs
    sphere(b, (-0.9, -0.5, 0.1), 0.12, scale=(1.2, 1, 0.8), segs=10, rings=6)


def build_kills(parts):
    """A skull over two crossed bones."""
    bone = parts.bm("bone")
    sphere(bone, (0.0, 0.0, 0.55), 0.46, scale=(1.0, 0.95, 1.0), segs=20, rings=14)
    box(bone, (0.0, -0.18, 0.2), (0.5, 0.36, 0.22), cuts=1)   # the jaw
    cp.lump(bone, 0.025, 6.0, 2.0)
    d = parts.bm("dark")
    for sx in (-1, 1):
        sphere(d, (sx * 0.17, -0.36, 0.58), 0.12, scale=(1.0, 0.5, 1.2), segs=10, rings=8)
    box(d, (0.0, -0.44, 0.42), (0.07, 0.06, 0.12))
    for x in (-0.15, -0.05, 0.05, 0.15):   # teeth
        box(bone, (x, -0.36, 0.1), (0.07, 0.05, 0.13))
    for sgn in (-1, 1):   # crossed long bones behind
        cylinder(bone, (0.0, 0.3, 0.12), 0.07, 1.7, axis="X", segs=8, rot=(0.0, 0.0, sgn * 0.5))
        for end in (-1, 1):
            sphere(bone, (end * 0.8 * math.cos(0.5), 0.3 + sgn * end * 0.8 * math.sin(0.5), 0.12), 0.12, segs=8, rings=6)


def build_enemies(parts):
    """A rotted hand clawing up out of the ground: the thing that is still out there."""
    r = parts.bm("rot")
    box(r, (0.0, 0.0, 0.45), (0.7, 0.3, 0.6), cuts=1)   # palm and wrist
    cylinder(r, (0.0, 0.1, 0.1), 0.2, 0.5, axis="Z", segs=10)   # forearm
    cp.lump(r, 0.03, 5.0, 3.0)
    for i, (x, h, lean) in enumerate(((-0.27, 0.78, -0.25), (-0.09, 0.9, -0.08), (0.1, 0.88, 0.08), (0.27, 0.74, 0.25))):
        for seg in range(3):   # three joints, each leaning a little more
            z = 0.65 + seg * h * 0.28
            cylinder(r, (x + lean * seg * 0.2, 0.0 - seg * 0.04, z + 0.12), 0.065 - seg * 0.01, h * 0.3, axis="Z", radius2=0.055 - seg * 0.01,
                     segs=7, rot=(0.12 * seg, lean * (1 + seg * 0.4), 0.0))
        cylinder(parts.bm("bone"), (x + lean * 0.7, -0.16, 0.65 + 3 * h * 0.28), 0.02, 0.14, axis="Z", radius2=0.002, segs=5)   # a nail
    cylinder(r, (0.46, -0.05, 0.6), 0.075, 0.5, axis="Z", radius2=0.05, segs=7, rot=(0.0, 0.9, 0.0))   # the thumb


BUILDERS = {"gold": build_gold, "food": build_food, "kills": build_kills, "enemies": build_enemies}


def render(obj, name, size=128):
    os.makedirs(OUT, exist_ok=True)
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = 32
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.33, 0.38, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    scene.world = world
    corners = [obj.matrix_world @ V(c) for c in obj.bound_box]
    centre = sum(corners, V()) / 8.0
    span = max(max(c[i] for c in corners) - min(c[i] for c in corners) for i in range(3))
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span * 1.15
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    tilt = math.radians(58)   # looking down 32 degrees: a coin stack and a loaf show their tops, a skull still faces us
    cam.location = centre + V((0.0, -math.sin(tilt) * 6.0, math.cos(tilt) * 6.0 + 0.0)) * 1.0
    cam.rotation_euler = (tilt, 0.0, 0.0)
    scene.camera = cam
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN"))
    key.data.energy = 4.0
    key.data.color = (1.0, 0.86, 0.68)
    key.rotation_euler = (math.radians(55), math.radians(-25), math.radians(-35))
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    fill.data.energy = 1.4
    fill.data.color = (0.62, 0.72, 1.0)
    fill.rotation_euler = (math.radians(60), math.radians(30), math.radians(140))
    bpy.context.collection.objects.link(key)
    bpy.context.collection.objects.link(fill)
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("icon", scene.render.filepath)


def main():
    wanted = [a for a in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []) if not a.startswith("--")]
    for i, (name, builder) in enumerate(BUILDERS.items()):
        if wanted and name not in wanted:
            continue
        mi.reset_scene()
        parts = Parts()
        builder(parts)
        obj = cp.make_object(name, parts, i + 70)
        for poly in obj.data.polygons:
            poly.use_smooth = name != "gold"
        render(obj, name)


if __name__ == "__main__":
    main()
