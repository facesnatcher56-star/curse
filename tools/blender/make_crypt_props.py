"""Builds the Crypt Road's own props in Blender: assets/models/crypt/<name>/model.glb.

    blender --background --python tools/blender/make_crypt_props.py -- [names...] [--preview]

Same rules as the town props and the items (docs/ART_DIRECTION.md, tools/blender/make_items.py and make_town_props.py, whose
helpers, palette and weathering this reuses): weathered stone, rotten timber, rusted iron, bone and dried blood, painted on the
vertices from noise, muted palette. The one warm accent is ember (candles, lanterns); the nest adds the one sickly green the
spitters already use. Dimensions are real metres, the front faces Blender -Y (+Z in Godot). Then `godot --headless --import`.
`--preview` also renders a quick PNG per model into the ~/.cache/curse_preview, for judging the look before the game does.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
import mathutils
import make_items as mi
import make_town_props as tp
from make_items import Parts, box, cylinder, sphere

mi.OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "crypt"))

FLESH = (0.23, 0.10, 0.09)
FLESH_DARK = (0.11, 0.055, 0.055)
SICK = (0.40, 0.46, 0.17)
mi.MATERIALS.update({
    "flesh": (FLESH, 0.0, 0.55, 0.4),
    "flesh_dark": (FLESH_DARK, 0.0, 0.6, 0.4),
    "sick": (SICK, 0.0, 0.35, 0.1),
})
mi.MATERIALS.setdefault("rust_iron", ((0.2, 0.15, 0.12), 0.7, 0.7, 1.4))

_material_for = mi.material_for


def material_for(key):
    mat = _material_for(key)
    if key == "sick":   # the nest's sacs glow a dull acid green, the same green as the spitters' glands
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Emission Color"].default_value = (0.45, 0.62, 0.12, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.8
    return mat


mi.material_for = material_for
V = mathutils.Vector


def lump(bm, amount, freq, seed=0.0):
    """Pushes every vertex along its normal by noise: smooth organic bulges instead of a perfect sphere."""
    off = V((seed * 3.7, seed * 1.3, seed * 2.9))
    for v in bm.verts:
        v.co += v.normal * mi.noise.noise(v.co * freq + off) * amount


def make_object(name, parts, seed):
    """mi.make_object, but the vertices are painted after the objects are joined. Blender 5.2's join drops the colours of every
    object but the first (the later materials come out white), so each vertex takes its material from its polygon instead."""
    original = mi.paint
    mi.paint = lambda obj, key, s: None
    try:
        obj = mi.make_object(name, parts, seed)
    finally:
        mi.paint = original
    mesh = obj.data
    keys = [m.name.split(".")[0][len("item_"):] for m in mesh.materials]
    owner = {}
    for poly in mesh.polygons:
        for vi in poly.vertices:
            owner[vi] = keys[poly.material_index]
    attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    mesh.color_attributes.active_color = attr
    offset = V((seed * 7.3, seed * 3.1, seed * 5.9))
    for v in mesh.vertices:
        key = owner.get(v.index, keys[0])
        base, _metal, _rough, wear = mi.MATERIALS[key]
        p = v.co + offset
        large = mi.noise.noise(p * 7.0)
        fine = mi.noise.noise(p * 38.0)
        rust_mask = mi.noise.noise(p * 11.0 + V((3.0, 1.0, 2.0)))
        col = tuple(c * (0.78 + 0.32 * (large * 0.5 + 0.5) + 0.12 * fine) for c in base)
        if key in ("steel", "dark_steel", "iron", "brass", "rust_iron"):
            if rust_mask > 0.12:
                col = mi.mix(col, mi.RUST, min((rust_mask - 0.12) * 2.2 * wear, 0.75))
            edge = 1.0 - abs(v.normal.z)
            col = mi.mix(col, tuple(min(c * 1.9, 0.7) for c in base), edge * 0.28)
        elif key.startswith("leather") or key == "cloth":
            col = mi.mix(col, (0.06, 0.045, 0.03), max(0.0, mi.noise.noise(p * 15.0) - 0.1) * 0.8 * wear)
        grime = max(0.0, -mi.noise.noise(p * 22.0 + V((9.0, 9.0, 9.0)))) * 0.5 * wear
        col = tuple(c * (1.0 - grime) for c in col)
        col = tuple(max(c, 0.0) ** 1.6 for c in col)   # written the way it should look; vertex colours are stored linear
        attr.data[v.index].color = (col[0], col[1], col[2], 1.0)
    return obj


def export(obj, name):
    """Writes the model with one mesh object per material. Blender 5.2's glTF exporter writes white vertex colours for every
    primitive after the first of a joined mesh, so the joined object is split by material and each piece exported alone."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    pieces = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    corners = [o.matrix_world @ V(c) for o in pieces for c in o.bound_box]
    mn = V((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    mx = V((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    shift = V(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))   # origin at the middle of the footprint, resting on the ground
    bpy.ops.object.select_all(action="DESELECT")
    for o in pieces:
        for v in o.data.vertices:
            v.co -= shift
        o.select_set(True)
    folder = os.path.normpath(os.path.join(mi.OUT, name))
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "model.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_vertex_color="ACTIVE", export_materials="EXPORT")
    print("wrote", path, "size", tuple(round(c, 3) for c in (mx - mn)), "pieces", len(pieces))
    bpy.ops.object.select_all(action="DESELECT")
    return pieces


def rand_in(rng, a, b):
    return a + (b - a) * rng.random()


def tendril(bm, start, end, radius, sag=0.25, segs=7, sides=6):
    """A thin curved cylinder from start to end that sags in the middle, thicker at the root."""
    a, b = V(start), V(end)
    rings = []
    for i in range(segs + 1):
        t = i / segs
        p = a.lerp(b, t)
        p.z -= math.sin(t * math.pi) * sag
        rings.append((p, radius * (1.0 - 0.75 * t)))
    prev = None
    for i, (p, r) in enumerate(rings):
        d = (rings[min(i + 1, segs)][0] - rings[max(i - 1, 0)][0]).normalized()
        side = d.cross(V((0, 0, 1)))
        if side.length < 0.01:
            side = V((1, 0, 0))
        side.normalize()
        up = side.cross(d).normalized()
        ring = [bm.verts.new(p + (side * math.cos(k * math.tau / sides) + up * math.sin(k * math.tau / sides)) * r) for k in range(sides)]
        if prev:
            mi.ring_grid(bm, [prev, ring])
        prev = ring


def skull(parts, c, scale=1.0, yaw=0.0):
    b = parts.bm("bone")
    sphere(b, c, 0.11 * scale, scale=(1.0, 1.05, 0.95), segs=10, rings=6)
    box(b, (c[0], c[1] - 0.09 * scale, c[2] - 0.08 * scale), (0.12 * scale, 0.08 * scale, 0.07 * scale), rot=(0, 0, yaw))
    for sx in (-1, 1):
        sphere(parts.bm("flesh_dark"), (c[0] + sx * 0.04 * scale, c[1] - 0.09 * scale, c[2] + 0.02 * scale), 0.028 * scale, segs=6, rings=4)


# --- The props -------------------------------------------------------------------------------------------------------------

def build_nest(parts):
    """A corrupted nest: a heaving mound of dried gore and root, ribs and skulls jutting out, glowing sacs bunched on top, and
    tendrils creeping across the ground. About 3 m across and 1.7 m tall, readable as a lump from far above."""
    rng = random.Random(11)
    f = parts.bm("flesh")
    sphere(f, (0, 0, 0.55), 1.15, scale=(1.0, 1.0, 0.62), segs=18, rings=10)
    for i in range(7):
        a = i * math.tau / 7 + rng.random() * 0.4
        r = rand_in(rng, 0.55, 0.95)
        sphere(f, (math.cos(a) * r, math.sin(a) * r, rand_in(rng, 0.35, 0.8)), rand_in(rng, 0.3, 0.5), scale=(1, 1, 0.8), segs=10, rings=6)
    sphere(f, (0.0, 0.0, 1.0), 0.55, scale=(1.0, 1.0, 0.85), segs=12, rings=8)
    lump(f, 0.16, 2.2, 1.0)
    d = parts.bm("flesh_dark")
    for i in range(9):   # roots and tendrils spreading over the ground
        a = i * math.tau / 9 + rng.random() * 0.5
        r0 = 0.8
        r1 = rand_in(rng, 1.7, 2.5)
        tendril(d, (math.cos(a) * r0, math.sin(a) * r0, 0.28), (math.cos(a + 0.35) * r1, math.sin(a + 0.35) * r1, 0.03), 0.11, sag=-0.12)
    sphere(d, (0.0, 0.0, 0.08), 1.7, scale=(1.0, 1.0, 0.04), segs=18, rings=6)   # a stained skirt of dead ground
    s = parts.bm("sick")
    for i in range(6):   # glowing sacs bunched near the top
        a = i * math.tau / 6 + 0.3
        r = rand_in(rng, 0.2, 0.5)
        sphere(s, (math.cos(a) * r, math.sin(a) * r, rand_in(rng, 1.2, 1.55)), rand_in(rng, 0.14, 0.26), segs=10, rings=7)
    sphere(s, (0.0, -0.1, 1.5), 0.3, segs=12, rings=8)
    for i in range(4):
        a = i * math.tau / 4 + 0.7
        sphere(s, (math.cos(a) * 0.95, math.sin(a) * 0.95, 0.6), rand_in(rng, 0.1, 0.17), segs=8, rings=6)
    b = parts.bm("bone")
    for i in range(7):   # ribs and long bones bristling out of it
        a = i * math.tau / 7 + 0.2
        r = rand_in(rng, 0.7, 1.0)
        tip_h = rand_in(rng, 0.5, 1.1)
        cylinder(b, (math.cos(a) * r * 1.15, math.sin(a) * r * 1.15, 0.7 + tip_h * 0.3), 0.045, rand_in(rng, 0.7, 1.3), axis="Z",
                 radius2=0.012, segs=6, rot=(math.sin(a) * 0.9, -math.cos(a) * 0.9, 0))
    skull(parts, (0.95, -0.55, 0.38), 1.0, 0.5)
    skull(parts, (-0.9, 0.5, 0.3), 1.1, -0.8)
    skull(parts, (0.1, 1.0, 0.45), 0.9, 2.0)


def build_shrine(parts):
    """An old roadside shrine: stepped stone base, a niche with a weathered headless figure, a cracked column leaning on it,
    candle stubs burning low (the ember accent) and an iron offering bowl. About 3.6 m tall."""
    s = parts.bm("stone")
    sd = parts.bm("stone_dark")
    box(sd, (0, 0, 0.12), (3.2, 3.0, 0.24), cuts=2)
    box(s, (0, 0, 0.38), (2.6, 2.4, 0.28), cuts=2)
    box(sd, (0, 0, 0.64), (2.1, 1.9, 0.24), cuts=2)
    box(s, (0, 0.2, 1.05), (1.5, 1.0, 0.6), cuts=2)   # plinth
    box(sd, (0, 0.55, 2.0), (1.7, 0.35, 2.3), cuts=3)   # the back wall of the niche
    for sx in (-1, 1):
        box(s, (sx * 0.78, 0.45, 1.95), (0.3, 0.6, 2.1), cuts=2)
    box(s, (0, 0.45, 3.1), (2.0, 0.7, 0.3), rot=(0, 0.03, 0), cuts=2)
    box(sd, (0.35, 0.45, 3.4), (1.0, 0.6, 0.35), rot=(0, 0.28, 0), cuts=1)   # a broken gable, one half fallen
    # The figure: robed body, no head (it lies at its feet), hands clasped.
    cylinder(s, (0, 0.25, 1.9), 0.3, 1.3, axis="Z", radius2=0.2, segs=10)
    sphere(s, (0, 0.25, 2.62), 0.15, scale=(1, 1, 0.5), segs=8, rings=5)
    box(s, (0, 0.05, 2.2), (0.3, 0.12, 0.18))
    sphere(sd, (0.45, -0.25, 0.8), 0.16, segs=8, rings=6)
    # A cracked column that has slumped against the base.
    cylinder(s, (-1.55, -0.6, 0.65), 0.22, 1.5, axis="Z", segs=8, rot=(0.0, 0.5, 0.3))
    cylinder(sd, (-1.9, -1.1, 0.2), 0.22, 0.5, axis="Z", segs=8, rot=(1.4, 0.2, 0.9))
    # Candle stubs and the bowl.
    for x, y, h in ((-0.5, -0.35, 0.18), (-0.25, -0.5, 0.12), (0.6, -0.4, 0.22)):
        cylinder(parts.bm("bone"), (x, y, 0.76 + h / 2), 0.035, h, axis="Z", segs=6)
        sphere(parts.bm("ember"), (x, y, 0.78 + h), 0.03, scale=(0.8, 0.8, 1.5), segs=6, rings=4)
    cylinder(parts.bm("iron"), (0.1, -0.45, 0.88), 0.28, 0.12, axis="Z", radius2=0.16, segs=10)
    # Offerings long since rotted: ribbon scraps and a few small bones.
    box(parts.bm("cloth"), (-0.8, -0.2, 0.74), (0.5, 0.06, 0.02), rot=(0, 0, 0.5))
    box(parts.bm("bone"), (0.9, -0.2, 0.74), (0.2, 0.03, 0.03), rot=(0, 0, 1.0))


def build_crypt_gate(parts):
    """The crypt's front: a heavy stone facade with a pedimented lintel, pillars, a sealed pair of iron-banded doors, a skull
    frieze, braziers' stone sockets either side and a flight of worn steps. About 10 m wide and 7.5 m tall."""
    s = parts.bm("stone")
    sd = parts.bm("stone_dark")
    w = 10.0
    for i, (z, d) in enumerate(((0.15, 3.4), (0.45, 2.9), (0.75, 2.5))):   # three steps, the lowest widest
        box(sd, (0, -0.6 - (2 - i) * 0.5, z), (w * 0.62 + (2 - i) * 0.6, d * 0.5, 0.3), cuts=2)
    box(sd, (0, 0.6, 0.55), (w, 3.0, 1.1), cuts=3)   # the plinth the whole facade stands on
    box(s, (0, 0.8, 3.6), (w - 1.0, 1.8, 5.0), cuts=4)   # the wall
    for sx in (-1, 1):   # engaged pillars
        box(sd, (sx * (w / 2 - 0.2), -0.25, 3.6), (0.9, 0.9, 5.2), cuts=3)
        box(s, (sx * (w / 2 - 0.2), -0.25, 6.3), (1.15, 1.15, 0.35), cuts=1)
        box(s, (sx * (w / 2 - 0.2), -0.25, 1.2), (1.15, 1.15, 0.3), cuts=1)
    box(sd, (0, -0.1, 6.25), (w + 0.4, 1.4, 0.45), cuts=3)   # entablature
    # Pediment: a shallow triangle above.
    bm = sd
    verts = [bm.verts.new(c) for c in ((-w / 2 - 0.3, -0.7, 6.45), (w / 2 + 0.3, -0.7, 6.45), (0.0, -0.7, 7.6),
                                       (-w / 2 - 0.3, 0.7, 6.45), (w / 2 + 0.3, 0.7, 6.45), (0.0, 0.7, 7.6))]
    import bmesh
    bmesh.ops.contextual_create(bm, geom=[verts[0], verts[1], verts[2]])
    bmesh.ops.contextual_create(bm, geom=[verts[5], verts[4], verts[3]])
    bmesh.ops.contextual_create(bm, geom=[verts[0], verts[3], verts[4], verts[1]])
    bmesh.ops.contextual_create(bm, geom=[verts[1], verts[4], verts[5], verts[2]])
    bmesh.ops.contextual_create(bm, geom=[verts[2], verts[5], verts[3], verts[0]])
    # The doorway: a deep recess with a rounded head, and two doors shut in it.
    box(parts.bm("stone_dark"), (0, -0.2, 2.3), (4.4, 1.2, 3.8), cuts=2)
    cylinder(parts.bm("stone_dark"), (0, -0.2, 4.2), 2.2, 1.2, axis="Y", segs=14)
    for sx in (-1, 1):
        box(parts.bm("wood_dark"), (sx * 0.98, -0.75, 2.4), (1.95, 0.22, 4.1), cuts=3)
        for z in (0.9, 2.0, 3.1):   # iron bands
            box(parts.bm("iron"), (sx * 0.98, -0.88, z), (1.95, 0.06, 0.2))
        for z in (0.9, 2.0, 3.1):
            sphere(parts.bm("rust_iron"), (sx * 0.98, -0.93, z), 0.07, segs=6, rings=4)
    cylinder(parts.bm("wood_dark"), (0, -0.7, 4.38), 2.0, 0.22, axis="Y", segs=14)
    box(parts.bm("iron"), (0, -0.9, 2.0), (0.12, 0.1, 3.9))   # the seam, and a great ring each side
    for sx in (-1, 1):
        cylinder(parts.bm("rust_iron"), (sx * 0.5, -0.98, 2.0), 0.2, 0.05, axis="Y", segs=12)
    # A frieze of skulls over the door.
    for i in range(9):
        skull(parts, (-2.8 + i * 0.7, -0.85, 5.75), 0.8, 0.0)
    # Braziers' sockets either side of the steps.
    for sx in (-1, 1):
        cylinder(sd, (sx * 3.7, -2.0, 0.9), 0.5, 1.2, axis="Z", radius2=0.4, segs=8)
        cylinder(parts.bm("iron"), (sx * 3.7, -2.0, 1.55), 0.55, 0.18, axis="Z", radius2=0.7, segs=10)
        sphere(parts.bm("ember"), (sx * 3.7, -2.0, 1.62), 0.32, scale=(1, 1, 0.5), segs=8, rings=5)
    # Cracks and fallen blocks.
    box(sd, (-3.6, -1.7, 0.2), (0.7, 0.5, 0.4), rot=(0, 0, 0.5))
    box(sd, (3.9, -2.6, 0.15), (0.5, 0.4, 0.3), rot=(0, 0, -0.4))


def build_cottage_ruin(parts):
    """A collapsed cottage: the stone walls stand to different heights with broken tops, the chimney stack still stands, and the
    roof has fallen in, its beams propped at angles on the walls, thatch and rubble heaped inside. About 6 m by 5 m."""
    rng = random.Random(4)
    s = parts.bm("stone")
    sd = parts.bm("stone_dark")
    w, d = 6.0, 5.0
    t = 0.45
    # Walls: each built from blocks of varying height so the top edge is broken.
    def wall(x0, y0, x1, y1, max_h, name):
        length = math.hypot(x1 - x0, y1 - y0)
        n = max(int(length / 0.6), 2)
        ang = math.atan2(y1 - y0, x1 - x0)
        for i in range(n):
            u = (i + 0.5) / n
            cx, cy = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
            h = max_h * (0.35 + 0.65 * abs(mi.noise.noise(V((cx * 0.8, cy * 0.8, 1.0 + name)))) * 1.7)
            h = min(h, max_h)
            box(s if i % 3 else sd, (cx, cy, h / 2), (length / n + 0.02, t, h), rot=(0, 0, ang), cuts=1)
    wall(-w / 2, -d / 2, w / 2, -d / 2, 2.6, 1)
    wall(-w / 2, d / 2, w / 2, d / 2, 3.0, 2)
    wall(-w / 2, -d / 2, -w / 2, d / 2, 2.2, 3)
    wall(w / 2, -d / 2, w / 2, d / 2, 1.2, 4)
    # A door gap in the front is left by dropping those blocks to the ground.
    box(sd, (0.2, -d / 2, 0.22), (1.1, t + 0.1, 0.44))
    # The chimney stack, still standing.
    box(s, (-w / 2 + 0.6, d / 2 - 0.5, 2.0), (1.1, 1.0, 4.0), cuts=3)
    box(sd, (-w / 2 + 0.6, d / 2 - 0.5, 4.1), (1.3, 1.2, 0.2))
    box(parts.bm("stone_dark"), (-w / 2 + 0.8, d / 2 - 1.0, 0.6), (0.9, 0.3, 1.1))   # the hearth mouth
    # The fallen roof: beams at angles, thatch, and a heap of rubble.
    wd = parts.bm("wood_dark")
    for i in range(7):
        x = rand_in(rng, -2.2, 2.0)
        y = rand_in(rng, -1.6, 1.6)
        box(wd, (x, y, rand_in(rng, 0.5, 1.7)), (0.16, rand_in(rng, 2.6, 4.2), 0.2), rot=(rand_in(rng, -0.7, 0.7), rand_in(rng, -0.5, 0.5), rand_in(rng, -0.4, 0.4)), cuts=1)
    th = parts.bm("thatch")
    for i in range(5):
        sphere(th, (rand_in(rng, -2.0, 2.0), rand_in(rng, -1.5, 1.5), 0.3), rand_in(rng, 0.6, 1.0), scale=(1.4, 1.0, 0.45), segs=10, rings=6)
    for i in range(14):
        box(sd, (rand_in(rng, -2.6, 2.6), rand_in(rng, -2.2, 2.2), 0.12), (rand_in(rng, 0.2, 0.5), rand_in(rng, 0.2, 0.5), rand_in(rng, 0.15, 0.3)),
            rot=(0, 0, rng.random() * 3), cuts=0)
    box(parts.bm("wood"), (1.2, 1.2, 0.5), (1.4, 0.7, 0.9), rot=(0, 0, 0.5), cuts=1)   # a table, crushed
    box(parts.bm("cloth"), (-0.8, 0.5, 0.18), (1.0, 0.7, 0.05), rot=(0, 0, 0.3))


def build_iron_fence(parts):
    """A graveyard fence segment, 3 m long: two stone posts and rusted spiked bars, some bent, one missing."""
    rng = random.Random(9)
    sd = parts.bm("stone_dark")
    for sx in (-1, 1):
        box(sd, (sx * 1.5, 0, 0.7), (0.3, 0.3, 1.4), cuts=2)
        box(parts.bm("stone"), (sx * 1.5, 0, 1.45), (0.4, 0.4, 0.12))
        sphere(sd, (sx * 1.5, 0, 1.6), 0.14, segs=8, rings=5)
    i = parts.bm("rust_iron")
    box(i, (0, 0, 0.35), (3.0, 0.05, 0.07))
    box(i, (0, 0, 1.15), (3.0, 0.05, 0.07))
    n = 15
    for k in range(n):
        if k == 6:
            continue   # a missing bar
        x = -1.3 + k * 2.6 / (n - 1)
        lean = rand_in(rng, -0.08, 0.08) + (0.35 if k == 9 else 0.0)
        box(i, (x, 0, 0.78), (0.035, 0.035, 1.45 + (0.12 if k % 2 else 0.0)), rot=(0, lean, 0))
        cylinder(i, (x + lean * 0.8, 0, 1.58 + (0.12 if k % 2 else 0.0)), 0.035, 0.14, axis="Z", radius2=0.002, segs=4)


def build_corpse(parts):
    """A torn body for the feeders to hunch over: a ragged torso and limbs, a dark pool of blood and scattered bones. 2 m long,
    barely knee high, so it reads on the ground from far above."""
    rng = random.Random(21)
    pool = parts.bm("flesh_dark")
    sphere(pool, (0, 0, 0.012), 1.0, scale=(1.15, 0.8, 0.012), segs=14, rings=4)
    c = parts.bm("cloth")
    box(c, (0, 0, 0.18), (0.75, 0.42, 0.26), rot=(0, 0, 0.15), cuts=1)   # torso
    box(c, (-0.55, 0.18, 0.1), (0.62, 0.17, 0.14), rot=(0, 0, -0.5))   # an arm, flung out
    box(c, (0.85, -0.12, 0.1), (0.7, 0.2, 0.15), rot=(0, 0, 0.2))     # legs
    box(c, (0.95, 0.12, 0.09), (0.6, 0.2, 0.14), rot=(0, 0, -0.25))
    sphere(parts.bm("hide"), (-0.62, -0.15, 0.13), 0.13, segs=8, rings=6)   # a head
    f = parts.bm("flesh")
    sphere(f, (0.0, 0.02, 0.27), 0.28, scale=(1.3, 0.9, 0.5), segs=10, rings=6)   # the opened chest
    lump(f, 0.05, 6.0, 3.0)
    b = parts.bm("bone")
    for i in range(6):
        box(b, (rand_in(rng, -0.9, 0.9), rand_in(rng, -0.6, 0.6), 0.03), (rand_in(rng, 0.15, 0.4), 0.035, 0.035), rot=(0, 0, rng.random() * 3))
    for sx in (-1, 1):   # ribs
        box(b, (0.15 * sx, 0.0, 0.34), (0.03, 0.35, 0.03), rot=(0.4 * sx, 0, 0.3))


def build_road_gate(parts):
    """Where the road leaves town: two stout timber-and-stone posts, a crossbeam hung with an iron lantern (ember) and a
    weather-beaten signboard, a bar of spiked stakes either side. About 8 m wide, 5 m tall, open in the middle."""
    s = parts.bm("stone_dark")
    w = parts.bm("wood")
    wd = parts.bm("wood_dark")
    span = 8.0
    for sx in (-1, 1):
        box(s, (sx * span / 2, 0, 0.5), (1.1, 1.1, 1.0), cuts=2)
        box(w, (sx * span / 2, 0, 3.0), (0.6, 0.6, 4.4), cuts=3)
        box(wd, (sx * (span / 2 - 0.55), 0, 4.2), (0.2, 0.2, 1.1), rot=(0, sx * 0.7, 0))   # braces
    box(w, (0, 0, 5.1), (span + 1.0, 0.55, 0.55), cuts=4)
    box(wd, (0, -0.35, 4.55), (4.0, 0.12, 0.9), rot=(0, 0.02, 0), cuts=2)   # the signboard
    box(parts.bm("bone"), (0, -0.43, 4.55), (3.2, 0.03, 0.08))
    box(parts.bm("bone"), (0.3, -0.43, 4.3), (2.0, 0.03, 0.08))
    cylinder(parts.bm("iron"), (-1.9, 0, 4.9), 0.012, 0.5, axis="Z", segs=4)   # lantern chain and cage
    box(parts.bm("iron"), (-1.9, 0, 4.4), (0.34, 0.34, 0.5))
    box(parts.bm("ember"), (-1.9, 0, 4.4), (0.22, 0.22, 0.3))
    for sx in (-1, 1):   # stakes either side, leaning out
        for k in range(5):
            x = sx * (span / 2 + 0.9 + k * 0.5)
            cylinder(wd, (x, 0, 0.8), 0.07, 1.7, axis="Z", radius2=0.015, segs=5, rot=(0.12 * ((k % 2) * 2 - 1), 0.1 * sx, 0))
    box(s, (0, 0, 0.04), (span - 0.6, 3.0, 0.08), cuts=3)   # worn cobbles through the opening


BUILDERS = {
    "nest": build_nest, "shrine": build_shrine, "crypt_gate": build_crypt_gate, "cottage_ruin": build_cottage_ruin,
    "iron_fence": build_iron_fence, "corpse": build_corpse, "road_gate": build_road_gate,
}
FLAT = ("shrine", "crypt_gate", "cottage_ruin", "iron_fence", "road_gate")   # hard-edged: smoothing would melt the masonry


def preview(obj, name):
    """A quick three-quarter render so the look can be judged without the game."""
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = scene.render.resolution_y = 640
    bbox = [V(c) for o in bpy.context.scene.objects if o.type == "MESH" for c in o.bound_box]
    size = max((max(v[i] for v in bbox) - min(v[i] for v in bbox)) for i in range(3))
    mid = V((0, 0, (max(v.z for v in bbox) + min(v.z for v in bbox)) / 2))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    bpy.context.collection.objects.link(cam)
    cam.location = mid + V((0.9, -1.6, 0.8)) * size * 1.15
    cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 45
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (0.9, 0.2, 0.6)
    bpy.context.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.07, 1.0)
    scene.world = world
    folder = os.path.join(os.path.expanduser("~"), ".cache", "curse_preview")   # a flatpak Blender cannot see /tmp
    os.makedirs(folder, exist_ok=True)
    scene.render.filepath = os.path.join(folder, "crypt_" + name + ".png")
    bpy.ops.render.render(write_still=True)
    print("preview", scene.render.filepath)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    want_preview = "--preview" in args
    wanted = [a for a in args if not a.startswith("--")]
    for i, (name, builder) in enumerate(BUILDERS.items()):
        if wanted and name not in wanted:
            continue
        mi.reset_scene()
        parts = Parts()
        builder(parts)
        tp.densify(parts, max_edge=0.4 if name != "crypt_gate" else 0.5)
        obj = make_object(name, parts, i + 40)
        tp.weather(obj)
        for poly in obj.data.polygons:
            poly.use_smooth = name not in FLAT
        pieces = export(obj, name)
        if want_preview:
            preview(pieces[0], name)


if __name__ == "__main__":
    main()
