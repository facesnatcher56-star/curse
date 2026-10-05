"""Builds the town's buildings and clutter in Blender: assets/models/town/<name>/model.glb.

    "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background --python tools/blender/make_town_props.py -- [names...]

Same rules as the items (docs/ART_DIRECTION.md, tools/blender/make_items.py, whose helpers and weathering this reuses): weathered
timber, cracked stone, soiled thatch and cloth, painted on the vertices from noise, muted palette with one warm accent (the
forge's embers). Dimensions are real metres, so a model needs no scale in the game beyond its own height. The front faces
Blender -Y, which is +Z in Godot. Then `godot --headless --import`.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh
import mathutils
import make_items as mi
from make_items import Parts, box, cylinder, sphere

mi.OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "town"))

WOOD = (0.17, 0.12, 0.08)
WOOD_DARK = (0.085, 0.065, 0.048)
STONE = (0.25, 0.245, 0.23)
STONE_DARK = (0.14, 0.138, 0.135)
THATCH = (0.18, 0.15, 0.10)
SLATE = (0.15, 0.155, 0.17)
HIDE = (0.24, 0.18, 0.125)
WATER = (0.07, 0.09, 0.10)
mi.MATERIALS.update({
    "wood": (WOOD, 0.0, 0.9, 0.9),
    "wood_dark": (WOOD_DARK, 0.0, 0.92, 0.9),
    "stone": (STONE, 0.0, 0.95, 1.0),
    "stone_dark": (STONE_DARK, 0.0, 0.95, 1.0),
    "thatch": (THATCH, 0.0, 1.0, 0.8),
    "slate": (SLATE, 0.0, 0.8, 0.8),
    "hide": (HIDE, 0.0, 0.9, 0.8),
    "water": (WATER, 0.0, 0.25, 0.2),
})


def gable(bm, cx, cy, z0, width, depth, rise, overhang=0.3):
    """A closed gable roof solid: ridge along Y, eaves at z0, ridge `rise` above."""
    w = width / 2 + overhang
    d = depth / 2 + overhang
    v = [bm.verts.new(c) for c in (
        (cx - w, cy - d, z0), (cx + w, cy - d, z0), (cx + w, cy + d, z0), (cx - w, cy + d, z0),
        (cx, cy - d, z0 + rise), (cx, cy + d, z0 + rise))]
    bm.faces.new((v[3], v[2], v[1], v[0]))
    bm.faces.new((v[0], v[1], v[4]))
    bm.faces.new((v[2], v[3], v[5]))
    bm.faces.new((v[1], v[2], v[5], v[4]))
    bm.faces.new((v[3], v[0], v[4], v[5]))


def timber_frame(parts, cx, cy, z0, width, depth, height, spacing=1.4):
    """Dark beams across a plaster/wood wall block, front and back."""
    b = parts.bm("wood_dark")
    for side in (-1, 1):
        y = cy + side * (depth / 2 + 0.02)
        for i in range(int(width / spacing) + 1):
            x = cx - width / 2 + i * width / max(int(width / spacing), 1)
            box(b, (x, y, z0 + height / 2), (0.14, 0.1, height))
        box(b, (cx, y, z0 + 0.1), (width, 0.1, 0.16))
        box(b, (cx, y, z0 + height - 0.08), (width, 0.1, 0.16))


def build_crate_stack(parts):
    w = parts.bm("wood")
    d = parts.bm("wood_dark")
    for (x, y, z, s, r) in ((0, 0, 0.0, 0.8, 0.05), (0.85, 0.1, 0.0, 0.7, -0.12), (0.3, 0.05, 0.8, 0.65, 0.2)):
        box(w, (x, y, z + s / 2), (s, s, s), rot=(0, 0, r), cuts=1)
        for sx in (-1, 1):
            box(d, (x + sx * s * 0.42, y, z + s / 2), (0.07, s * 1.02, s * 1.02), rot=(0, 0, r))
        box(d, (x, y, z + s * 0.5), (s * 1.02, 0.06, s * 1.02), rot=(0, 0, r))


def build_wood_pile(parts):
    w = parts.bm("wood")
    end = parts.bm("hide")
    rows = (6, 5, 4, 3)
    for r, count in enumerate(rows):
        for i in range(count):
            x = (i - (count - 1) / 2) * 0.27
            z = 0.14 + r * 0.24
            cylinder(w, (x, 0, z), 0.12 + 0.01 * ((i + r) % 2), 1.5, axis="Y", segs=8)
            cylinder(end, (x, -0.745, z), 0.095, 0.02, axis="Y", segs=8)
            cylinder(end, (x, 0.745, z), 0.095, 0.02, axis="Y", segs=8)
    box(parts.bm("wood_dark"), (-0.95, 0, 0.5), (0.08, 0.1, 1.0))
    box(parts.bm("wood_dark"), (0.95, 0, 0.5), (0.08, 0.1, 1.0))


def build_water_trough(parts):
    w = parts.bm("wood")
    box(w, (0, 0, 0.45), (2.0, 0.65, 0.12))
    for sx in (-1, 1):
        box(w, (sx * 0.95, 0, 0.6), (0.1, 0.65, 0.4))
    for sy in (-1, 1):
        box(w, (0, sy * 0.3, 0.6), (2.0, 0.1, 0.4))
    box(parts.bm("water"), (0, 0, 0.7), (1.8, 0.5, 0.04))
    d = parts.bm("wood_dark")
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(d, (sx * 0.8, sy * 0.25, 0.2), (0.14, 0.14, 0.4))


def build_anvil(parts):
    cylinder(parts.bm("wood"), (0, 0, 0.3), 0.32, 0.6, axis="Z", segs=9)
    i = parts.bm("iron")
    box(i, (0, 0, 0.66), (0.5, 0.26, 0.12))
    box(i, (0, 0, 0.78), (0.22, 0.2, 0.14))
    box(i, (0, 0, 0.92), (0.72, 0.24, 0.14))
    cylinder(i, (0.5, 0, 0.92), 0.07, 0.3, axis="X", radius2=0.015, segs=8)
    box(parts.bm("steel"), (-0.32, 0, 0.95), (0.1, 0.2, 0.05))


def build_drying_rack(parts):
    w = parts.bm("wood")
    for sx in (-1, 1):
        box(w, (sx * 1.2, 0, 0.95), (0.12, 0.12, 1.9), rot=(0, 0.06 * sx, 0))
        box(w, (sx * 1.2, 0.5, 0.3), (0.1, 1.0, 0.1), rot=(0.4, 0, 0))
    box(w, (0, 0, 1.75), (2.5, 0.1, 0.1))
    box(w, (0, 0, 1.05), (2.4, 0.08, 0.08))
    h = parts.bm("hide")
    for x, drop in ((-0.8, 1.0), (-0.2, 0.8), (0.45, 1.1), (0.95, 0.7)):
        box(h, (x, 0, 1.75 - drop / 2), (0.34, 0.04, drop), rot=(0, 0.05, 0))
    box(parts.bm("cloth"), (0.2, 0.02, 0.8), (0.9, 0.04, 0.35))


def build_laundry_line(parts):
    w = parts.bm("wood")
    for sx in (-1, 1):
        box(w, (sx * 1.6, 0, 1.0), (0.1, 0.1, 2.0))
    box(parts.bm("wood_dark"), (0, 0, 1.85), (3.2, 0.025, 0.025))
    c = parts.bm("cloth")
    for x, wd, h, tilt in ((-1.1, 0.5, 0.8, 0.05), (-0.35, 0.7, 0.6, -0.04), (0.45, 0.5, 0.95, 0.06), (1.1, 0.4, 0.5, -0.05)):
        box(c, (x, 0, 1.82 - h / 2), (wd, 0.03, h), rot=(0, tilt, 0))
    box(parts.bm("hide"), (-0.35, 0.01, 1.4), (0.5, 0.03, 0.2))


def open_front(parts, cx, cy, z0, width, depth):
    """Posts and a plank floor for an open-sided shed."""
    w = parts.bm("wood_dark")
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(w, (cx + sx * (width / 2 - 0.15), cy + sy * (depth / 2 - 0.15), z0 + 1.5), (0.28, 0.28, 3.0))


def build_forge(parts):
    """An open-sided smithy: timber posts, a lean-to roof, a stone hearth and chimney at the back, glowing coals, a bellows."""
    width, depth = 5.4, 4.2
    open_front(parts, 0, 0, 0, width, depth)
    box(parts.bm("wood"), (0, 0, 0.05), (width, depth, 0.1))
    # Mono-pitch roof: higher at the back (+Y).
    r = parts.bm("thatch")
    box(r, (0, 0.1, 3.25), (width + 0.7, depth + 0.9, 0.22), rot=(0.18, 0, 0), cuts=1)
    box(parts.bm("wood_dark"), (0, 0.0, 3.05), (width + 0.2, depth, 0.15), rot=(0.18, 0, 0))
    # The hearth against the back wall, and a tall chimney.
    st = parts.bm("stone")
    box(st, (-0.6, depth / 2 - 0.7, 0.55), (2.2, 1.2, 1.1), cuts=2)
    box(st, (-0.6, depth / 2 - 0.55, 2.4), (1.0, 0.8, 3.6), cuts=2)
    box(parts.bm("stone_dark"), (-0.6, depth / 2 - 1.1, 0.8), (1.2, 0.5, 0.5))
    box(parts.bm("ember"), (-0.6, depth / 2 - 1.12, 0.87), (0.9, 0.35, 0.1))
    box(parts.bm("stone_dark"), (-0.6, depth / 2 - 0.55, 4.28), (1.2, 1.0, 0.18))
    # Back wall planks.
    box(parts.bm("wood"), (1.4, depth / 2 - 0.1, 1.5), (2.8, 0.15, 3.0), cuts=2)
    # Bellows, tongs rack, a quench barrel.
    box(parts.bm("leather"), (0.75, depth / 2 - 0.7, 0.9), (0.5, 0.5, 0.35), rot=(0, 0.25, 0))
    cylinder(parts.bm("wood"), (1.8, 0.4, 0.45), 0.4, 0.9, axis="Z", segs=10)
    cylinder(parts.bm("water"), (1.8, 0.4, 0.89), 0.34, 0.02, axis="Z", segs=10)
    box(parts.bm("iron"), (2.45, depth / 2 - 0.3, 1.6), (0.05, 0.05, 1.2), rot=(0, 0.3, 0))


def build_granary(parts):
    """A timber store raised on posts, gabled, with a ladder-stepped door."""
    width, depth, wall = 5.0, 3.8, 2.6
    base = 0.55
    for sx in (-1, 0, 1):
        for sy in (-1, 1):
            box(parts.bm("stone_dark"), (sx * width * 0.42, sy * depth * 0.4, base / 2), (0.4, 0.4, base))
    box(parts.bm("wood_dark"), (0, 0, base + 0.08), (width + 0.1, depth + 0.1, 0.16))
    box(parts.bm("wood"), (0, 0, base + 0.16 + wall / 2), (width, depth, wall), cuts=3)
    timber_frame(parts, 0, 0, base + 0.16, width, depth, wall)
    gable(parts.bm("thatch"), 0, 0, base + 0.16 + wall, width, depth, 1.6, 0.45)
    box(parts.bm("wood_dark"), (0, -depth / 2 - 0.02, base + 1.2), (1.1, 0.12, 1.9))
    box(parts.bm("wood"), (0, -depth / 2 - 0.55, base / 2), (1.0, 1.1, 0.12), rot=(-0.5, 0, 0))
    box(parts.bm("wood_dark"), (width * 0.3, -depth / 2 - 0.02, base + 1.5), (0.55, 0.1, 0.55))


def build_chapel(parts):
    """A small stone chapel: cracked walls, a steep slate roof, a bell frame on the gable and a dark door."""
    width, depth, wall = 5.0, 7.0, 3.4
    box(parts.bm("stone_dark"), (0, 0, 0.2), (width + 0.4, depth + 0.4, 0.4))
    box(parts.bm("stone"), (0, 0, 0.4 + wall / 2), (width, depth, wall), cuts=4)
    for sy in (-1, 1):
        for sx in (-1, 1):
            box(parts.bm("stone_dark"), (sx * width / 2, sy * depth / 2, 0.4 + wall / 2), (0.5, 0.5, wall + 0.1))
    gable(parts.bm("slate"), 0, 0, 0.4 + wall, width, depth, 2.4, 0.4)
    # Door and narrow windows.
    box(parts.bm("wood_dark"), (0, -depth / 2 - 0.04, 0.4 + 1.1), (1.2, 0.14, 2.2))
    box(parts.bm("stone_dark"), (0, -depth / 2 - 0.08, 0.4 + 2.35), (1.5, 0.16, 0.25))
    for sx in (-1, 1):
        for y in (-1.6, 0.4, 2.2):
            box(parts.bm("wood_dark"), (sx * (width / 2 + 0.03), y, 0.4 + 2.2), (0.1, 0.35, 1.0))
    # A bell frame at the front gable peak and a leaning cross at the back.
    w = parts.bm("wood_dark")
    top = 0.4 + wall + 2.4
    for sx in (-1, 1):
        box(w, (sx * 0.45, -depth / 2 - 0.1, top + 0.1), (0.12, 0.12, 1.1))
    box(w, (0, -depth / 2 - 0.1, top + 0.65), (1.1, 0.12, 0.12))
    sphere(parts.bm("brass"), (0, -depth / 2 - 0.1, top + 0.25), 0.22, (1, 1, 1.2))
    box(w, (0, depth / 2 + 0.05, top - 0.2), (0.1, 0.1, 1.2), rot=(0, 0.1, 0))
    box(w, (0, depth / 2 + 0.05, top + 0.15), (0.6, 0.1, 0.1), rot=(0, 0.1, 0))


def build_inn(parts):
    """A two-storey tavern: stone ground floor, jettied timber upper floor, a steep roof, a chimney, a door and a hanging sign."""
    width, depth = 8.4, 6.0
    ground, upper = 2.7, 2.4
    box(parts.bm("stone_dark"), (0, 0, 0.15), (width + 0.3, depth + 0.3, 0.3))
    box(parts.bm("stone"), (0, 0, 0.3 + ground / 2), (width, depth, ground), cuts=4)
    box(parts.bm("wood_dark"), (0, 0, 0.3 + ground + 0.1), (width + 0.7, depth + 0.7, 0.2))
    box(parts.bm("wood"), (0, 0, 0.3 + ground + 0.2 + upper / 2), (width + 0.5, depth + 0.5, upper), cuts=3)
    timber_frame(parts, 0, 0, 0.3 + ground + 0.2, width + 0.5, depth + 0.5, upper, spacing=1.5)
    gable(parts.bm("thatch"), 0, 0, 0.3 + ground + 0.2 + upper, width + 0.5, depth + 0.5, 2.6, 0.5)
    # Door, shuttered windows.
    box(parts.bm("wood_dark"), (-1.2, -depth / 2 - 0.04, 0.3 + 1.1), (1.3, 0.14, 2.2))
    for x in (1.3, 2.9):
        box(parts.bm("wood_dark"), (x, -depth / 2 - 0.04, 0.3 + 1.6), (0.9, 0.12, 0.9))
    for x in (-2.6, 0.2, 2.8):
        box(parts.bm("wood_dark"), (x, -depth / 2 - 0.35, 0.3 + ground + 1.5), (0.9, 0.12, 0.9))
    # A chimney with a dull glow from the hearth below, and a hanging sign on an iron arm.
    box(parts.bm("stone"), (width * 0.3, depth * 0.15, 6.0), (0.9, 0.9, 3.2), cuts=2)
    box(parts.bm("stone_dark"), (width * 0.3, depth * 0.15, 7.65), (1.2, 1.2, 0.2))
    box(parts.bm("iron"), (-width / 2 - 0.55, -depth / 2 + 0.3, 3.2), (1.1, 0.06, 0.06))
    box(parts.bm("wood"), (-width / 2 - 0.9, -depth / 2 + 0.3, 2.75), (0.7, 0.05, 0.6))
    box(parts.bm("ember"), (-width / 2 - 0.9, -depth / 2 + 0.26, 2.8), (0.28, 0.02, 0.28))


def densify(parts, max_edge=0.35, passes=4):
    """The wear is painted on vertices, so a big flat face needs vertices to carry it: split long edges until they are short."""
    for bm in parts.groups.values():
        for _ in range(passes):
            long_edges = [e for e in bm.edges if e.calc_length() > max_edge]
            if not long_edges:
                break
            bmesh.ops.subdivide_edges(bm, edges=long_edges, cuts=1, use_grid_fill=True)
        for v in bm.verts:   # a slight, coherent warp so nothing is dead straight (shared corners move together)
            p = v.co
            v.co = p + mathutils.Vector((mi.noise.noise(p * 2.3) * 0.025, mi.noise.noise(p * 2.3 + mathutils.Vector((5, 1, 3))) * 0.025,
                                         mi.noise.noise(p * 2.3 + mathutils.Vector((2, 7, 1))) * 0.02))


def weather(obj):
    """After the base paint: plank lines on walls, shingle rows on roofs, soil splashed up from the ground, soot under eaves and
    patchy moss in the damp low corners, so the buildings share the cottages' worn, dirty hand-painted look."""
    mesh = obj.data
    attr = mesh.color_attributes.active_color
    low = min(v.co.z for v in mesh.vertices)
    high = max(v.co.z for v in mesh.vertices)
    for v in mesh.vertices:
        c = attr.data[v.index].color
        r, g, b = c[0], c[1], c[2]
        p = v.co
        n = v.normal
        f = 1.0
        if abs(n.z) < 0.35:      # walls: vertical planks
            f *= 0.78 + 0.22 * abs(math.sin((p.x + p.y) * 7.0 + mi.noise.noise(p * 3.0) * 1.5))
        elif 0.3 < n.z < 0.95:   # sloped roofs: rows of shingles or thatch
            f *= 0.7 + 0.3 * abs(math.sin(p.z * 11.0 + mi.noise.noise(p * 4.0)))
        height = (p.z - low) / max(high - low, 0.01)
        f *= 0.55 + 0.45 * min(height * 4.0, 1.0)          # mud and grime climb up from the ground
        f *= 1.0 - 0.25 * max(0.0, mi.noise.noise(p * 5.0 + mathutils.Vector((8, 8, 8))))   # soot / damp blotches
        moss = max(0.0, mi.noise.noise(p * 4.0 + mathutils.Vector((1, 9, 4))) - 0.25) * (1.0 - min(height * 3.0, 1.0)) * 1.6
        r, g, b = r * f, g * f, b * f
        r, g, b = r * (1 - moss) + 0.03 * moss, g * (1 - moss) + 0.07 * moss, b * (1 - moss) + 0.03 * moss
        attr.data[v.index].color = (r, g, b, 1.0)


BUILDERS = {
    "crate_stack": build_crate_stack, "wood_pile": build_wood_pile, "water_trough": build_water_trough, "anvil": build_anvil,
    "drying_rack": build_drying_rack, "laundry_line": build_laundry_line, "forge": build_forge, "granary": build_granary,
    "chapel": build_chapel, "inn": build_inn,
}


def main():
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for i, (name, builder) in enumerate(BUILDERS.items()):
        if wanted and name not in wanted:
            continue
        mi.reset_scene()
        parts = Parts()
        builder(parts)
        densify(parts)
        obj = mi.make_object(name, parts, i + 20)
        weather(obj)
        for poly in obj.data.polygons:   # buildings are flat-shaded: smoothing would melt the boxes
            poly.use_smooth = False
        mi.export(obj, name)


if __name__ == "__main__":
    main()
