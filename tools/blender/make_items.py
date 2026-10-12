"""Builds the dropped-item models for Curse in Blender: assets/models/items/<name>/model.glb.

    "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background --python tools/blender/make_items.py -- [names...]

Art direction (docs/ART_DIRECTION.md): gritty and versatile. Every piece is weathered, never clean: dark scuffed steel with rust,
stained leather, dented plate, tarnished brass. Colour is painted on the vertices from position noise (grime, rust, bright worn
edges) so no texture files are needed, and every item shares the same palette and wear rules. Each model lies on the ground,
flat side up, with its long axis along X, and sits on y = 0 once imported into Godot (glTF is Y-up).

Add an item: write a `build_<name>(parts)` function, register it in BUILDERS, run this script, then `godot --headless --import`.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "items")
ICONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "icons", "items")

# --- Palette: muted, with one warm accent (docs/ART_DIRECTION.md) ---------------------------------------------------------
STEEL = (0.38, 0.39, 0.42)
STEEL_DARK = (0.18, 0.19, 0.21)
IRON = (0.22, 0.21, 0.21)
RUST = (0.30, 0.14, 0.07)
BRASS = (0.40, 0.31, 0.14)
LEATHER = (0.26, 0.16, 0.09)
LEATHER_DARK = (0.12, 0.08, 0.05)
BONE = (0.55, 0.50, 0.40)
CLOTH = (0.18, 0.15, 0.12)
EMBER = (0.75, 0.30, 0.08)
WOOD = (0.24, 0.17, 0.11)

# material key -> (base colour, metallic, roughness, wear: how much rust and grime it takes)
MATERIALS = {
    "steel": (STEEL, 0.85, 0.5, 1.0),
    "dark_steel": (STEEL_DARK, 0.8, 0.55, 1.0),
    "iron": (IRON, 0.8, 0.6, 1.2),
    "brass": (BRASS, 0.7, 0.55, 0.8),
    "leather": (LEATHER, 0.0, 0.85, 0.7),
    "leather_dark": (LEATHER_DARK, 0.0, 0.9, 0.7),
    "cloth": (CLOTH, 0.0, 0.95, 0.5),
    "bone": (BONE, 0.0, 0.8, 0.5),
    "ember": (EMBER, 0.2, 0.45, 0.2),
    "wood": (WOOD, 0.0, 0.9, 0.9),
}


class Parts:
    """Geometry grouped by material; each group is one bmesh."""

    def __init__(self):
        self.groups = {}

    def bm(self, material):
        if material not in self.groups:
            self.groups[material] = bmesh.new()
        return self.groups[material]


# --- Geometry helpers ------------------------------------------------------------------------------------------------------

def _xf(center, scale=(1, 1, 1), rot=(0, 0, 0)):
    m = Matrix.Translation(Vector(center))
    m = m @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X")
    return m @ Matrix.Diagonal(Vector((scale[0], scale[1], scale[2], 1.0)))


def box(bm, center, size, rot=(0, 0, 0), cuts=0):
    geom = bmesh.ops.create_cube(bm, size=1.0, matrix=_xf(center, size, rot))
    if cuts:
        edges = list({e for v in geom["verts"] for e in v.link_edges})
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=cuts, use_grid_fill=True)


def cylinder(bm, center, radius, depth, axis="X", segs=16, radius2=None, rot=(0, 0, 0)):
    """A cylinder or cone frustum along `axis`."""
    base = {"X": (0, math.pi / 2, 0), "Y": (-math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    m = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") \
        @ Matrix.Rotation(rot[0], 4, "X") @ Matrix.Rotation(base[2], 4, "Z") @ Matrix.Rotation(base[1], 4, "Y") \
        @ Matrix.Rotation(base[0], 4, "X")
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=radius if radius2 is None else radius2,
                          depth=depth, matrix=m)


def sphere(bm, center, radius, scale=(1, 1, 1), segs=14, rings=8):
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius, matrix=_xf(center, scale))


def torus(bm, center, major, minor, axis="Z", major_segs=28, minor_segs=8, scale=(1, 1, 1)):
    ring = bmesh.new()
    verts = []
    for i in range(major_segs):
        a = math.tau * i / major_segs
        row = []
        for j in range(minor_segs):
            b = math.tau * j / minor_segs
            r = major + minor * math.cos(b)
            row.append(ring.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        verts.append(row)
    for i in range(major_segs):
        for j in range(minor_segs):
            ring.faces.new((verts[i][j], verts[(i + 1) % major_segs][j], verts[(i + 1) % major_segs][(j + 1) % minor_segs],
                            verts[i][(j + 1) % minor_segs]))
    rot = {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
    mesh = bpy.data.meshes.new("t")
    ring.to_mesh(mesh)
    ring.free()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    # from_mesh appended in place; move the appended verts (the last major*minor ones)
    appended = bm.verts[-(major_segs * minor_segs):]
    mat = _xf(center, scale, rot)
    for v in appended:
        v.co = mat @ v.co


def ring_grid(bm, rings, close=True):
    """Joins consecutive rings (lists of vertices of equal length) with quads."""
    for a, b in zip(rings[:-1], rings[1:]):
        n = len(a)
        for i in range(n):
            j = (i + 1) % n if close else i + 1
            if not close and j >= n:
                continue
            bm.faces.new((a[i], a[j], b[j], b[i]))


# --- Weapons ---------------------------------------------------------------------------------------------------------------

def blade(bm, length, width, thickness, tip_len, curve=0.0, belly=0.0, fuller=0.35, steps=60):
    """A double-edged (or, with `curve`, a swept single-edged) blade lying along +X, flat face up (+Z), starting at x = 0."""
    prev = None
    rings = []
    for i in range(steps + 1):
        t = i / steps
        x = t * length
        # Width: constant, widening a little with `belly`, then tapering to the tip over the last `tip_len` metres.
        w = width * (1.0 + belly * math.sin(math.pi * min(t * 1.25, 1.0)))
        dist_tip = length - x
        if dist_tip < tip_len:
            u = dist_tip / tip_len
            w *= math.sqrt(max(u, 0.0)) if curve else u ** 0.8
        th = thickness * (1.0 if dist_tip > tip_len else max(dist_tip / tip_len, 0.05))
        sweep = curve * (t ** 2) * length          # the edge curves away to one side
        y0 = sweep
        f = fuller * th
        ring = [
            bm.verts.new((x, y0 - w, 0.0)),                 # edge (left)
            bm.verts.new((x, y0 - w * 0.40, th * 0.9)),
            bm.verts.new((x, y0 - w * 0.12, th * 0.9 - f)),  # fuller groove
            bm.verts.new((x, y0 + w * 0.12, th * 0.9 - f)),
            bm.verts.new((x, y0 + w * 0.40, th * 0.9)),
            bm.verts.new((x, y0 + w, 0.0)),                 # edge (right)
            bm.verts.new((x, y0 + w * 0.40, -th * 0.9)),
            bm.verts.new((x, y0 - w * 0.40, -th * 0.9)),
        ]
        rings.append(ring)
    ring_grid(bm, rings)
    # Close the ends: butt and a pointed tip.
    bm.faces.new(rings[0][::-1])
    tip = bm.verts.new((length + 0.012, rings[-1][0].co.y * 0.0 + (curve * length) + 0.0, 0.0))
    last = rings[-1]
    for i in range(len(last)):
        bm.faces.new((last[i], last[(i + 1) % len(last)], tip))


def sword(parts, blade_len, blade_w, blade_t, guard_w, grip_len, pommel_r, curve=0.0, belly=0.0, tip=0.16,
          guard_style="bar", fuller=0.35):
    b = parts.bm("steel")
    blade(b, blade_len, blade_w, blade_t, tip, curve, belly, fuller)
    # Ricasso: the plain steel just above the guard.
    box(parts.bm("steel"), (-0.02, 0, 0), (0.05, blade_w * 1.9, blade_t * 1.8), cuts=2)
    g = parts.bm("dark_steel")
    if guard_style == "bar":
        box(g, (-0.045, 0, 0), (0.035, guard_w, 0.03), cuts=4)
        sphere(g, (-0.045, guard_w / 2, 0), 0.026, (1, 1, 1))
        sphere(g, (-0.045, -guard_w / 2, 0), 0.026, (1, 1, 1))
    elif guard_style == "down":   # quillons that droop toward the blade
        box(g, (-0.045, 0, 0), (0.04, guard_w, 0.035), cuts=4)
        box(g, (-0.025, guard_w / 2 - 0.02, 0), (0.05, 0.04, 0.03), rot=(0, 0, 0.5))
        box(g, (-0.025, -guard_w / 2 + 0.02, 0), (0.05, 0.04, 0.03), rot=(0, 0, -0.5))
    else:   # a plain oval disc guard, for the falchion
        sphere(g, (-0.04, 0, 0), guard_w / 2, (0.12, 1.0, 0.65), segs=18, rings=10)
    grip = parts.bm("leather")
    cylinder(grip, (-0.06 - grip_len / 2, 0, 0), 0.0185, grip_len, axis="X", segs=10)
    wraps = parts.bm("leather_dark")
    for i in range(5):
        cylinder(wraps, (-0.075 - i * grip_len / 5.2, 0, 0), 0.021, 0.007, axis="X", segs=10)
    pom = parts.bm("brass")
    sphere(pom, (-0.065 - grip_len - pommel_r * 0.6, 0, 0), pommel_r, (0.8, 1.0, 1.0), segs=12, rings=8)


def build_falchion(parts):
    sword(parts, 0.72, 0.040, 0.011, 0.15, 0.16, 0.030, curve=0.05, belly=0.28, tip=0.14, guard_style="disc", fuller=0.25)


def build_longsword(parts):
    sword(parts, 0.95, 0.032, 0.010, 0.24, 0.20, 0.030, guard_style="bar", fuller=0.4)


def build_greatsword(parts):
    sword(parts, 1.28, 0.046, 0.013, 0.34, 0.30, 0.040, guard_style="down", fuller=0.45)


def build_axe_1h(parts):
    wood = parts.bm("wood")
    iron = parts.bm("iron")
    dark = parts.bm("dark_steel")
    steel = parts.bm("steel")
    leather = parts.bm("leather_dark")
    leather_wrap = parts.bm("leather")

    # Hardwood haft: 0.66m long, slightly tapering toward grip, thicker near the head socket
    cylinder(wood, (0.13, 0, 0), radius=0.016, radius2=0.020, depth=0.66, axis="X", segs=12)
    # Exposed shaft top above socket with an iron wedge
    cylinder(wood, (0.47, 0, 0), radius=0.019, depth=0.02, axis="X", segs=10)
    box(iron, (0.481, 0, 0), (0.008, 0.016, 0.006))

    # Grip: worn dark leather wrapping
    grip_len = 0.15
    cylinder(leather, (-0.10, 0, 0), 0.0195, grip_len, axis="X", segs=12)
    for i in range(5):
        cylinder(leather_wrap, (-0.155 + i * 0.028, 0, 0), 0.0215, 0.007, axis="X", segs=12)

    # Butt cap and pommel knob at base
    cylinder(iron, (-0.205, 0, 0), 0.022, 0.018, axis="X", segs=12)
    sphere(iron, (-0.216, 0, 0), 0.015, (0.7, 1.0, 1.0), segs=10, rings=6)

    # Langets: iron reinforcement straps along the haft
    cylinder(iron, (0.375, 0, 0), 0.023, 0.09, axis="X", segs=12)
    box(iron, (0.28, 0, 0.021), (0.12, 0.009, 0.004))
    box(iron, (0.28, 0, -0.021), (0.12, 0.009, 0.004))
    for x in (0.24, 0.30):
        sphere(dark, (x, 0, 0.022), 0.004, segs=6, rings=4)
        sphere(dark, (x, 0, -0.022), 0.004, segs=6, rings=4)

    # Axe head eye / socket
    box(dark, (0.38, 0.005, 0), (0.075, 0.046, 0.044), cuts=1)

    # Rear hammer poll on -Y (sturdy square poll with beveled cap)
    box(iron, (0.38, -0.045, 0), (0.048, 0.046, 0.038), cuts=1)
    box(dark, (0.38, -0.072, 0), (0.040, 0.012, 0.032))

    # Bearded blade cheek (dark steel) and cutting edge bit (steel)
    rings_cheek = []
    rings_bit = []
    steps_cheek = 6
    steps_bit = 3
    total_steps = steps_cheek + steps_bit

    for i in range(total_steps + 1):
        v = i / total_steps
        y = 0.025 + v * 0.125
        # Bearded hook: curves significantly down toward grip in -X, top horn flares in +X
        x_min = 0.345 - 0.095 * math.sin(v * math.pi * 0.90) - 0.025 * (v ** 2)
        x_max = 0.415 + 0.065 * (v ** 1.1)
        th = 0.018 * (1.0 - 0.85 * (v ** 0.6))
        if i == total_steps:
            th = 0.0012

        bm_target = dark if i <= steps_cheek else steel
        w_x = x_max - x_min
        ring = [
            bm_target.verts.new((x_max, y, 0.0)),
            bm_target.verts.new((x_max - w_x * 0.25, y, th * 0.9)),
            bm_target.verts.new((x_min + w_x * 0.50, y, th)),
            bm_target.verts.new((x_min + w_x * 0.20, y, th * 0.9)),
            bm_target.verts.new((x_min, y, 0.0)),
            bm_target.verts.new((x_min + w_x * 0.20, y, -th * 0.9)),
            bm_target.verts.new((x_min + w_x * 0.50, y, -th)),
            bm_target.verts.new((x_max - w_x * 0.25, y, -th * 0.9)),
        ]
        if i <= steps_cheek:
            rings_cheek.append(ring)
        if i >= steps_cheek:
            if i == steps_cheek:
                ring_steel = [
                    steel.verts.new((vert.co.x, vert.co.y, vert.co.z)) for vert in ring
                ]
                rings_bit.append(ring_steel)
            else:
                rings_bit.append(ring)

    ring_grid(dark, rings_cheek)
    ring_grid(steel, rings_bit)
    dark.faces.new(rings_cheek[0])
    steel.faces.new(rings_bit[-1][::-1])


def build_mace(parts):
    dark = parts.bm("dark_steel")
    steel = parts.bm("steel")
    brass = parts.bm("brass")
    leather = parts.bm("leather")

    # Octagonal/cylindrical steel shaft
    cylinder(dark, (0.13, 0, 0), radius=0.014, depth=0.64, axis="X", segs=10)

    # Leather wrapped grip
    grip_len = 0.14
    cylinder(leather, (-0.10, 0, 0), 0.0175, grip_len, axis="X", segs=12)
    # Brass wire wraps
    for i in range(6):
        cylinder(brass, (-0.155 + i * 0.024, 0, 0), 0.0195, 0.005, axis="X", segs=12)

    # Grip collar (small guard)
    cylinder(brass, (-0.028, 0, 0), radius=0.022, depth=0.010, axis="X", segs=12)

    # Pommel: faceted brass bulb with dark steel butt stud
    sphere(brass, (-0.185, 0, 0), 0.026, scale=(1.2, 1.0, 1.0), segs=10, rings=6)
    cylinder(dark, (-0.212, 0, 0), 0.011, 0.018, axis="X", segs=8)

    # Upper shaft collar & flanged head core
    cylinder(brass, (0.275, 0, 0), radius=0.022, depth=0.010, axis="X", segs=12)
    cylinder(dark, (0.365, 0, 0), radius=0.023, depth=0.17, axis="X", segs=12)

    # 6 Flanged wings radiating at 60 degree intervals
    num_flanges = 6
    flange_len = 0.16
    for f in range(num_flanges):
        angle = f * (math.tau / num_flanges)
        ca = math.cos(angle)
        sa = math.sin(angle)
        flange_rings = []
        steps_x = 6
        for sx in range(steps_x + 1):
            u = sx / steps_x
            x = 0.285 + u * flange_len
            if u < 0.70:
                r_outer = 0.024 + 0.044 * (u / 0.70) ** 0.85
            else:
                r_outer = 0.068 - 0.038 * ((u - 0.70) / 0.30) ** 1.2
            r_inner = 0.022
            th_base = 0.007
            th_tip = 0.002
            p_inner = Vector((x, r_inner * ca, r_inner * sa))
            p_outer = Vector((x, r_outer * ca, r_outer * sa))
            perp = Vector((0, -sa, ca))
            ring = [
                steel.verts.new(p_inner + perp * (th_base * 0.5)),
                steel.verts.new(p_outer + perp * (th_tip * 0.5)),
                steel.verts.new(p_outer - perp * (th_tip * 0.5)),
                steel.verts.new(p_inner - perp * (th_base * 0.5)),
            ]
            flange_rings.append(ring)
        ring_grid(steel, flange_rings, close=True)
        steel.faces.new(flange_rings[0])
        steel.faces.new(flange_rings[-1][::-1])

    # Crown collar & top pyramid spike
    cylinder(brass, (0.452, 0, 0), radius=0.024, depth=0.012, axis="X", segs=12)
    cylinder(steel, (0.485, 0, 0), radius=0.018, radius2=0.002, depth=0.065, axis="X", segs=4, rot=(math.pi / 4, 0, 0))


def build_club(parts):
    wood = parts.bm("wood")
    iron = parts.bm("iron")
    leather = parts.bm("leather_dark")
    leather_cord = parts.bm("leather")

    # Gnarled wooden cudgel body
    club_rings = []
    rows = 20
    segs = 12
    for r in range(rows + 1):
        t = r / rows
        x = -0.19 + t * 0.62
        if t < 0.25:
            rad = 0.018 + t * 0.010
        elif t < 0.85:
            u = (t - 0.25) / 0.60
            rad = 0.0205 + 0.0315 * math.sin(u * math.pi * 0.5)
        else:
            u = (t - 0.85) / 0.15
            rad = 0.052 * math.cos(u * math.pi * 0.45)

        ring = []
        for s in range(segs):
            a = math.tau * s / segs
            bump = 0.0
            if t > 0.25:
                bump = 0.0035 * math.sin(a * 3.0 + t * 14.0) + 0.0025 * math.cos(a * 2.0 - t * 8.0)
            r_eff = max(rad + bump, 0.004)
            ring.append(wood.verts.new((x, r_eff * math.cos(a), r_eff * math.sin(a))))
        club_rings.append(ring)
    ring_grid(wood, club_rings, close=True)
    wood.faces.new(club_rings[0])
    wood.faces.new(club_rings[-1][::-1])

    # Worn leather grip wrap
    cylinder(leather, (-0.10, 0, 0), radius=0.0225, depth=0.13, axis="X", segs=12)
    for i in range(5):
        cylinder(leather_cord, (-0.150 + i * 0.026, 0, 0), radius=0.024, depth=0.007, axis="X", segs=12)

    # Butt knob & lanyard ring
    sphere(wood, (-0.198, 0, 0), 0.027, scale=(1.0, 1.1, 0.95), segs=10, rings=6)
    cylinder(leather_cord, (-0.218, 0, 0), radius=0.016, depth=0.012, axis="X", segs=10)

    # 3 Heavy forged iron reinforcement bands with spikes
    band_configs = [
        (0.23, 0.046, 0.020, 4, 0.0),
        (0.31, 0.054, 0.022, 6, math.pi / 6),
        (0.38, 0.049, 0.020, 4, math.pi / 4),
    ]
    for bx, brad, bdepth, scount, aoffset in band_configs:
        cylinder(iron, (bx, 0, 0), radius=brad, depth=bdepth, axis="X", segs=14)
        for s in range(scount):
            sa = aoffset + s * (math.tau / scount)
            sca = math.cos(sa)
            ssa = math.sin(sa)
            sp_center = Vector((bx, (brad + 0.014) * sca, (brad + 0.014) * ssa))
            cylinder(iron, sp_center, radius=0.009, radius2=0.0018, depth=0.030, axis="Y", segs=4,
                     rot=(sa + math.pi, 0, 0))

    # Frontal iron center stud
    cylinder(iron, (0.435, 0, 0), radius=0.016, radius2=0.003, depth=0.032, axis="X", segs=6)


def build_dagger(parts):
    steel = parts.bm("steel")
    dark = parts.bm("dark_steel")
    brass = parts.bm("brass")
    leather = parts.bm("leather_dark")

    # Stiletto / combat dagger blade: 0.28m blade with needle tip and fuller
    blade(steel, 0.28, 0.025, 0.008, tip_len=0.09, curve=0.0, belly=0.06, fuller=0.28, steps=26)

    # Ricasso
    box(steel, (-0.012, 0, 0), (0.024, 0.024, 0.011), cuts=1)

    # Crossguard: down-curved quillons in dark steel
    guard_w = 0.092
    box(dark, (-0.026, 0, 0), (0.020, guard_w, 0.016), cuts=2)
    box(dark, (-0.016, guard_w / 2 - 0.005, 0), (0.022, 0.014, 0.014), rot=(0, 0, 0.45))
    box(dark, (-0.016, -guard_w / 2 + 0.005, 0), (0.022, 0.014, 0.014), rot=(0, 0, -0.45))
    sphere(dark, (-0.010, guard_w / 2 + 0.004, 0), 0.010, segs=8, rings=6)
    sphere(dark, (-0.010, -guard_w / 2 - 0.004, 0), 0.010, segs=8, rings=6)

    # Grip: contoured leather wrap
    grip_len = 0.11
    cylinder(leather, (-0.090, 0, 0), 0.0145, grip_len, axis="X", segs=10)
    for i in range(6):
        cylinder(brass, (-0.046 - i * 0.016, 0, 0), 0.0160, 0.0035, axis="X", segs=10)

    # Faceted pear pommel in brass, with peen block
    sphere(brass, (-0.158, 0, 0), 0.022, scale=(1.25, 0.95, 0.95), segs=10, rings=6)
    cylinder(dark, (-0.180, 0, 0), 0.007, 0.012, axis="X", segs=8)


def build_axe_2h(parts):
    wood = parts.bm("wood")
    iron = parts.bm("iron")
    dark = parts.bm("dark_steel")
    steel = parts.bm("steel")
    brass = parts.bm("brass")
    leather = parts.bm("leather_dark")
    leather_wrap = parts.bm("leather")

    # --- 1. Long Reinforced Hardwood Haft ---
    cylinder(wood, (0.19, 0, 0), radius=0.019, radius2=0.024, depth=1.30, axis="X", segs=12)

    # Exposed shaft top inside/above socket with iron wedge
    cylinder(wood, (0.845, 0, 0), radius=0.022, depth=0.02, axis="X", segs=10)
    box(iron, (0.855, 0, 0), (0.010, 0.018, 0.008))

    # --- 2. Lower Grip (Trailing Hand) ---
    cylinder(leather, (-0.32, 0, 0), radius=0.0225, depth=0.22, axis="X", segs=12)
    for i in range(7):
        cylinder(leather_wrap, (-0.41 + i * 0.030, 0, 0), radius=0.0245, depth=0.008, axis="X", segs=12)

    # Heavy iron butt cap and spiked pommel knob
    cylinder(iron, (-0.445, 0, 0), radius=0.025, depth=0.024, axis="X", segs=12)
    sphere(iron, (-0.460, 0, 0), radius=0.018, scale=(0.8, 1.0, 1.0), segs=10, rings=6)
    cylinder(iron, (-0.478, 0, 0), radius=0.009, radius2=0.002, depth=0.020, axis="X", segs=6)

    # Mid-shaft dividing ring between lower and upper grips
    cylinder(iron, (-0.195, 0, 0), radius=0.025, depth=0.016, axis="X", segs=12)
    cylinder(brass, (-0.195, 0, 0), radius=0.0265, depth=0.006, axis="X", segs=12)

    # --- 3. Upper Grip (Primary / Lead Hand) ---
    cylinder(leather, (-0.05, 0, 0), radius=0.023, depth=0.24, axis="X", segs=12)
    for i in range(8):
        cylinder(leather_wrap, (-0.155 + i * 0.030, 0, 0), radius=0.025, depth=0.008, axis="X", segs=12)
    cylinder(iron, (0.08, 0, 0), radius=0.025, depth=0.016, axis="X", segs=12)

    # --- 4. Long Steel Langets & Shaft Reinforcement ---
    cylinder(iron, (0.71, 0, 0), radius=0.027, depth=0.12, axis="X", segs=12)
    box(iron, (0.54, 0, 0.024), (0.24, 0.010, 0.004))
    box(iron, (0.54, 0, -0.024), (0.24, 0.010, 0.004))
    box(iron, (0.54, 0.024, 0), (0.24, 0.004, 0.010))
    box(iron, (0.54, -0.024, 0), (0.24, 0.004, 0.010))
    for x_rivet in (0.45, 0.53, 0.61):
        sphere(dark, (x_rivet, 0, 0.025), 0.0045, segs=6, rings=4)
        sphere(dark, (x_rivet, 0, -0.025), 0.0045, segs=6, rings=4)

    # --- 5. Massive Axe Head Socket Eye ---
    box(dark, (0.76, 0.01, 0), (0.10, 0.062, 0.056), cuts=1)

    # --- 6. Rear Armor-Piercing Beak / Spike on -Y ---
    beak_rings_dark = []
    beak_rings_steel = []
    beak_steps = 6
    split_step = 4
    for i in range(beak_steps + 1):
        u = i / beak_steps
        by = -0.03 - u * 0.12
        bx = 0.76 - 0.035 * (u ** 1.6)
        brad_z = 0.020 * (1.0 - 0.85 * u)
        brad_x = 0.024 * (1.0 - 0.85 * u)
        bm_beak = dark if i <= split_step else steel
        r = [
            bm_beak.verts.new((bx + brad_x, by, 0.0)),
            bm_beak.verts.new((bx, by, brad_z)),
            bm_beak.verts.new((bx - brad_x, by, 0.0)),
            bm_beak.verts.new((bx, by, -brad_z)),
        ]
        if i <= split_step:
            beak_rings_dark.append(r)
        if i >= split_step:
            if i == split_step:
                r_steel = [steel.verts.new((v.co.x, v.co.y, v.co.z)) for v in r]
                beak_rings_steel.append(r_steel)
            else:
                beak_rings_steel.append(r)

    ring_grid(dark, beak_rings_dark)
    ring_grid(steel, beak_rings_steel)
    steel.faces.new(beak_rings_steel[-1][::-1])

    # --- 7. Top Thrusting Spike on +X ---
    cylinder(brass, (0.835, 0, 0), radius=0.028, depth=0.016, axis="X", segs=12)
    cylinder(steel, (0.895, 0, 0), radius=0.020, radius2=0.002, depth=0.105, axis="X", segs=4, rot=(math.pi / 4, 0, 0))

    # --- 8. Broad Sweeping Two-Handed Axe Blade on +Y ---
    rings_cheek = []
    rings_bit = []
    steps_cheek = 8
    steps_bit = 4
    total_steps = steps_cheek + steps_bit

    for i in range(total_steps + 1):
        v = i / total_steps
        y = 0.035 + v * 0.200
        x_min = 0.710 - 0.125 * math.sin(v * math.pi * 0.88) - 0.035 * (v ** 2)
        x_max = 0.810 + 0.125 * (v ** 1.15)
        th = 0.024 * (1.0 - 0.88 * (v ** 0.55))
        if i == total_steps:
            th = 0.0015

        bm_target = dark if i <= steps_cheek else steel
        w_x = x_max - x_min
        ring = [
            bm_target.verts.new((x_max, y, 0.0)),
            bm_target.verts.new((x_max - w_x * 0.22, y, th * 0.85)),
            bm_target.verts.new((x_min + w_x * 0.55, y, th)),
            bm_target.verts.new((x_min + w_x * 0.18, y, th * 0.85)),
            bm_target.verts.new((x_min, y, 0.0)),
            bm_target.verts.new((x_min + w_x * 0.18, y, -th * 0.85)),
            bm_target.verts.new((x_min + w_x * 0.55, y, -th)),
            bm_target.verts.new((x_max - w_x * 0.22, y, -th * 0.85)),
        ]
        if i <= steps_cheek:
            rings_cheek.append(ring)
        if i >= steps_cheek:
            if i == steps_cheek:
                ring_steel = [
                    steel.verts.new((vert.co.x, vert.co.y, vert.co.z)) for vert in ring
                ]
                rings_bit.append(ring_steel)
            else:
                rings_bit.append(ring)

    ring_grid(dark, rings_cheek)
    ring_grid(steel, rings_bit)
    dark.faces.new(rings_cheek[0])
    steel.faces.new(rings_bit[-1][::-1])


def build_hammer_2h(parts):
    wood = parts.bm("wood")
    iron = parts.bm("iron")
    dark = parts.bm("dark_steel")
    steel = parts.bm("steel")
    brass = parts.bm("brass")
    leather = parts.bm("leather_dark")
    leather_wrap = parts.bm("leather")

    # --- 1. Long Reinforced Hardwood Shaft ---
    cylinder(wood, (0.18, 0, 0), radius=0.020, radius2=0.024, depth=1.28, axis="X", segs=12)

    # Exposed shaft top inside socket with iron retention wedge
    cylinder(wood, (0.825, 0, 0), radius=0.022, depth=0.02, axis="X", segs=10)
    box(iron, (0.835, 0, 0), (0.010, 0.018, 0.008))

    # --- 2. Lower Grip (Trailing Hand) ---
    cylinder(leather, (-0.32, 0, 0), radius=0.023, depth=0.22, axis="X", segs=12)
    for i in range(7):
        cylinder(leather_wrap, (-0.41 + i * 0.030, 0, 0), radius=0.025, depth=0.008, axis="X", segs=12)

    # Heavy iron butt cap with lanyard ring
    cylinder(iron, (-0.445, 0, 0), radius=0.026, depth=0.024, axis="X", segs=12)
    sphere(iron, (-0.460, 0, 0), radius=0.018, scale=(0.8, 1.0, 1.0), segs=10, rings=6)
    cylinder(iron, (-0.480, 0, 0), radius=0.012, depth=0.018, axis="X", segs=8)

    # Mid-shaft dividing ring
    cylinder(iron, (-0.195, 0, 0), radius=0.025, depth=0.016, axis="X", segs=12)
    cylinder(brass, (-0.195, 0, 0), radius=0.0265, depth=0.006, axis="X", segs=12)

    # --- 3. Upper Grip (Lead Hand / Leverage) ---
    cylinder(leather, (-0.05, 0, 0), radius=0.0235, depth=0.24, axis="X", segs=12)
    for i in range(8):
        cylinder(leather_wrap, (-0.155 + i * 0.030, 0, 0), radius=0.0255, depth=0.008, axis="X", segs=12)
    cylinder(iron, (0.08, 0, 0), radius=0.026, depth=0.016, axis="X", segs=12)

    # --- 4. Long Steel Langets & Throat Collar ---
    cylinder(iron, (0.69, 0, 0), radius=0.028, depth=0.12, axis="X", segs=12)
    box(dark, (0.52, 0, 0.025), (0.24, 0.012, 0.004))
    box(dark, (0.52, 0, -0.025), (0.24, 0.012, 0.004))
    box(dark, (0.52, 0.025, 0), (0.24, 0.004, 0.012))
    box(dark, (0.52, -0.025, 0), (0.24, 0.004, 0.012))
    for x_rivet in (0.43, 0.51, 0.59):
        sphere(iron, (x_rivet, 0, 0.026), 0.0045, segs=6, rings=4)
        sphere(iron, (x_rivet, 0, -0.026), 0.0045, segs=6, rings=4)

    # --- 5. Massive Transverse Hammer Head Center Block ---
    box(dark, (0.74, 0, 0), (0.11, 0.075, 0.075), cuts=1)

    # Reinforcing side plates with large iron bolt nuts
    cylinder(dark, (0.74, 0, 0.040), radius=0.032, depth=0.008, axis="Z", segs=8)
    cylinder(dark, (0.74, 0, -0.040), radius=0.032, depth=0.008, axis="Z", segs=8)
    sphere(iron, (0.74, 0, 0.045), 0.007, segs=6, rings=4)
    sphere(iron, (0.74, 0, -0.045), 0.007, segs=6, rings=4)

    # --- 6. Front Striking Head (Faceted Impact Block) on +Y ---
    box(dark, (0.74, 0.065, 0), (0.085, 0.055, 0.070), cuts=1)
    box(brass, (0.74, 0.095, 0), (0.090, 0.010, 0.075), cuts=0)
    box(steel, (0.74, 0.125, 0), (0.088, 0.050, 0.072), cuts=1)
    # Corrugated / 4-pronged diamond waffle striking face (y = 0.150 to 0.165)
    for dx in (-0.022, 0.022):
        for dz in (-0.018, 0.018):
            cylinder(steel, (0.74 + dx, 0.156, dz), radius=0.014, radius2=0.003, depth=0.018, axis="Y",
                     segs=4, rot=(math.pi / 2, 0, math.pi / 4))

    # --- 7. Rear Armor-Piercing Crowbill Pick on -Y ---
    pick_rings_dark = []
    pick_rings_steel = []
    pick_steps = 7
    split_pick = 5
    for i in range(pick_steps + 1):
        u = i / pick_steps
        py = -0.035 - u * 0.130
        px = 0.74 - 0.045 * (u ** 1.7)
        rad_z = 0.026 * (1.0 - 0.88 * u)
        rad_x = 0.030 * (1.0 - 0.88 * u)
        bm_pick = dark if i <= split_pick else steel
        r = [
            bm_pick.verts.new((px + rad_x, py, 0.0)),
            bm_pick.verts.new((px, py, rad_z)),
            bm_pick.verts.new((px - rad_x, py, 0.0)),
            bm_pick.verts.new((px, py, -rad_z)),
        ]
        if i <= split_pick:
            pick_rings_dark.append(r)
        if i >= split_pick:
            if i == split_pick:
                r_steel = [steel.verts.new((v.co.x, v.co.y, v.co.z)) for v in r]
                pick_rings_steel.append(r_steel)
            else:
                pick_rings_steel.append(r)

    ring_grid(dark, pick_rings_dark)
    ring_grid(steel, pick_rings_steel)
    steel.faces.new(pick_rings_steel[-1][::-1])

    # --- 8. Top Thrusting Armor-Piercing Spike on +X ---
    cylinder(brass, (0.80, 0, 0), radius=0.030, depth=0.016, axis="X", segs=12)
    cylinder(steel, (0.865, 0, 0), radius=0.022, radius2=0.003, depth=0.115, axis="X", segs=4, rot=(math.pi / 4, 0, 0))


# --- Armour ----------------------------------------------------------------------------------------------------------------

def torso(bm, height, profile, segs=36, rows=28, open_top=True, bump=None):
    """A tube shaped like a torso: `profile(t)` gives (half-width, half-depth) at t in 0..1 from hem to collar. Lies on its back:
    the long axis is X, the chest faces +Z. Returns the rings so a caller can add straps. `bump(a, t)` pushes the surface out."""
    rings = []
    for r in range(rows + 1):
        t = r / rows
        hw, hd = profile(t)
        row = []
        for s in range(segs):
            a = math.tau * s / segs
            push = bump(a, t) if bump else 0.0
            x = t * height
            y = math.cos(a) * (hw + push)
            z = math.sin(a) * (hd + push)
            row.append(bm.verts.new((x, y, z)))
        rings.append(row)
    ring_grid(bm, rings)
    return rings


def build_leather_jerkin(parts):
    h = 0.62
    def prof(t):
        flare = 0.04 * (1.0 - t) ** 2
        return (0.20 + 0.03 * math.sin(t * math.pi) + flare, 0.11 + 0.025 * math.sin(t * math.pi))
    body = torso(parts.bm("leather"), h, prof, bump=lambda a, t: 0.004 * math.sin(a * 6 + t * 20))
    # A seam and lacing down the chest, a belt, and shoulder straps.
    lace = parts.bm("leather_dark")
    for i in range(9):
        box(lace, (0.12 + i * 0.05, 0.0, 0.118), (0.012, 0.075, 0.006), rot=(0, 0, 0.0))
        box(lace, (0.12 + i * 0.05, 0.0, 0.118), (0.006, 0.07, 0.007), rot=(0, 0, 0.8))
    box(lace, (0.19, 0.0, 0.0), (0.06, 0.44, 0.26), cuts=0)
    belt = parts.bm("leather_dark")
    cylinder(belt, (0.18, 0, 0), 0.215, 0.05, axis="X", segs=36, rot=(0, 0, 0))
    box(parts.bm("brass"), (0.18, 0.0, 0.125), (0.04, 0.05, 0.015), cuts=1)
    for side in (-1, 1):
        box(parts.bm("leather_dark"), (h + 0.01, side * 0.14, 0.0), (0.06, 0.045, 0.26), rot=(0, 0, 0))


def build_mail_hauberk(parts):
    h = 0.72
    def prof(t):
        flare = 0.05 * (1.0 - t) ** 2
        return (0.21 + 0.03 * math.sin(t * math.pi) + flare, 0.115 + 0.025 * math.sin(t * math.pi))
    # Rings: a fine diamond relief across the whole surface.
    torso(parts.bm("dark_steel"), h, prof, segs=96, rows=70,
          bump=lambda a, t: 0.0045 * math.sin(a * 36.0) * math.sin(t * 150.0))
    # Short sleeves hang out to each side at the shoulder.
    for side in (-1, 1):
        sl = parts.bm("dark_steel")
        cylinder(sl, (h - 0.1, side * 0.27, 0.0), 0.075, 0.2, axis="Y", segs=20, rot=(0, 0, 0))
    # A leather belt and a stained cloth hem.
    cylinder(parts.bm("leather_dark"), (0.30, 0, 0), 0.232, 0.045, axis="X", segs=36)
    box(parts.bm("brass"), (0.30, 0.0, 0.132), (0.035, 0.045, 0.014), cuts=1)
    cylinder(parts.bm("cloth"), (0.012, 0, 0), 0.255, 0.03, axis="X", segs=36, radius2=0.25)


def build_plate_cuirass(parts):
    h = 0.66
    def prof(t):
        # Broad shoulders, a tucked waist and a flared tasset skirt.
        return (0.205 + 0.045 * math.sin(min(t * 1.4, 1.0) * math.pi * 0.5) - 0.03 * math.exp(-((t - 0.3) ** 2) / 0.02),
                0.125 + 0.03 * math.sin(t * math.pi))
    torso(parts.bm("iron"), h, prof, segs=64, rows=44,
          bump=lambda a, t: 0.006 * noise.noise(Vector((math.cos(a) * 4.0, math.sin(a) * 4.0, t * 6.0))))
    # A raised ridge down the breastplate, rivets round the edges, a gorget at the neck and heavy pauldrons.
    ridge = parts.bm("steel")
    box(ridge, (0.36, 0.0, 0.158), (0.46, 0.022, 0.02), cuts=6)
    for i in range(14):
        a = math.tau * i / 14
        sphere(parts.bm("brass"), (0.012, math.cos(a) * 0.222, math.sin(a) * 0.14), 0.011, (1, 1, 1), segs=8, rings=5)
    for i in range(14):
        a = math.tau * i / 14
        sphere(parts.bm("brass"), (h - 0.02, math.cos(a) * 0.19, math.sin(a) * 0.105), 0.010, (1, 1, 1), segs=8, rings=5)
    cylinder(parts.bm("steel"), (h + 0.015, 0, 0), 0.115, 0.07, axis="X", segs=28, radius2=0.1)
    for side in (-1, 1):
        sphere(parts.bm("iron"), (h - 0.05, side * 0.27, 0.01), 0.115, (0.7, 1.0, 1.0), segs=16, rings=10)
        sphere(parts.bm("steel"), (h - 0.1, side * 0.3, 0.012), 0.08, (0.6, 1.0, 1.0), segs=14, rings=8)
    for k in range(4):   # tasset plates over the hips
        box(parts.bm("iron"), (-0.045 - k * 0.0, (k - 1.5) * 0.095, 0.0), (0.09, 0.09, 0.012), rot=(0, 0, 0))
    cylinder(parts.bm("leather_dark"), (0.24, 0, 0), 0.245, 0.04, axis="X", segs=48)


# --- Trinkets --------------------------------------------------------------------------------------------------------------

def cord(bm, radius, loops_to, steps=30, thick=0.004, scale=(1.0, 1.0)):
    """A flat loop of cord (a ring in the XY plane) with a hanging point at +X."""
    for i in range(steps):
        a = math.tau * i / steps
        x = math.cos(a) * radius * scale[0] + radius
        y = math.sin(a) * radius * scale[1]
        sphere(bm, (x, y, 0.0), thick, (1, 1, 1), segs=6, rings=4)


def build_charm(parts):
    # A knucklebone and a tooth on a knotted cord, with a stained iron ring: a hedge-witch's ward.
    cord(parts.bm("leather_dark"), 0.085, 0, steps=36, thick=0.0045, scale=(1.0, 0.8))
    torus(parts.bm("iron"), (0.215, 0, 0.012), 0.032, 0.0085, axis="Z", scale=(1, 1, 1))
    bone = parts.bm("bone")
    sphere(bone, (0.255, 0.0, 0.026), 0.034, (1.2, 0.75, 0.55), segs=12, rings=8)
    sphere(bone, (0.292, 0.012, 0.026), 0.018, (1, 1, 0.7), segs=10, rings=6)
    sphere(bone, (0.292, -0.012, 0.026), 0.018, (1, 1, 0.7), segs=10, rings=6)
    cylinder(parts.bm("iron"), (0.2, 0.0, 0.016), 0.006, 0.07, axis="Y", segs=8)


def build_signet(parts):
    # A heavy tarnished brass band with a flat bezel and a cracked ember stone.
    torus(parts.bm("brass"), (0.0, 0.0, 0.032), 0.032, 0.0085, axis="X", scale=(1, 1, 1), major_segs=32, minor_segs=10)
    bezel = parts.bm("brass")
    box(bezel, (0.0, 0.0, 0.074), (0.032, 0.032, 0.014), cuts=2)
    box(bezel, (0.0, 0.0, 0.067), (0.04, 0.04, 0.01), cuts=1)
    sphere(parts.bm("ember"), (0.0, 0.0, 0.087), 0.0145, (1.0, 1.0, 0.6), segs=12, rings=6)
    # lying on its side so the stone faces the camera
    # (rotated below by the generic orientation step)


def build_talisman(parts):
    # A dull bronze disc hung on a chain, cut with a cross and ringed with rivets.
    chain = parts.bm("iron")
    for i in range(24):
        a = math.tau * i / 24
        torus(chain, (0.07 + math.cos(a) * 0.075, math.sin(a) * 0.1, 0.01), 0.008, 0.0028, axis="Z" if i % 2 else "X",
              major_segs=10, minor_segs=5)
    disc = parts.bm("brass")
    cylinder(disc, (0.235, 0.0, 0.012), 0.062, 0.014, axis="Z", segs=28)
    cylinder(disc, (0.235, 0.0, 0.021), 0.048, 0.006, axis="Z", segs=28)
    cross = parts.bm("dark_steel")
    box(cross, (0.235, 0.0, 0.026), (0.07, 0.014, 0.008), cuts=1)
    box(cross, (0.235, 0.0, 0.026), (0.014, 0.07, 0.008), cuts=1)
    for i in range(10):
        a = math.tau * i / 10
        sphere(parts.bm("iron"), (0.235 + math.cos(a) * 0.056, math.sin(a) * 0.056, 0.022), 0.0065, (1, 1, 1), segs=6, rings=4)


# --- Helms, gloves, boots, shields and the band (Dungeon Siege II's full gear) --------------------------------------------------

def prism(bm, outline, z0, z1):
    """A flat plate: the polygon `outline` (XY points, in order) from z0 to z1."""
    bottom = [bm.verts.new((x, y, z0)) for x, y in outline]
    top = [bm.verts.new((x, y, z1)) for x, y in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.faces.new(top)
    bm.faces.new(bottom[::-1])


def dome(bm, radius, height, center=(0, 0, 0), segs=28, rows=12, bump=None):
    """An open-bottomed dome (a cap or a helm bowl) standing on z = center.z."""
    rings = []
    for r in range(rows + 1):
        t = r / rows                      # 0 at the rim, 1 at the crown
        a = t * math.pi * 0.5
        rr = radius * math.cos(a)
        z = height * math.sin(a)
        row = []
        for s_i in range(segs):
            b = math.tau * s_i / segs
            push = bump(b, t) if bump else 0.0
            row.append(bm.verts.new((center[0] + math.cos(b) * (rr + push) * 1.08, center[1] + math.sin(b) * (rr + push), center[2] + z + push)))
        rings.append(row)
    ring_grid(bm, rings)
    return rings


def build_leather_cap(parts):
    # A boiled-leather skullcap: four panels stitched over the crown, a thick rolled band, ear flaps.
    dome(parts.bm("leather"), 0.11, 0.1, bump=lambda b, t: 0.003 * math.sin(b * 4.0) * (1.0 - t))
    seams = parts.bm("leather_dark")
    for k in range(4):
        a = k * math.pi / 2
        for i in range(7):
            t = i / 7
            r = 0.112 * math.cos(t * math.pi * 0.5)
            box(seams, (math.cos(a) * r * 1.08, math.sin(a) * r, 0.101 * math.sin(t * math.pi * 0.5) + 0.002), (0.012, 0.012, 0.006),
                rot=(0, 0, a))
    cylinder(parts.bm("leather_dark"), (0, 0, 0.012), 0.118, 0.026, axis="Z", segs=32)
    for side in (-1, 1):
        box(parts.bm("leather"), (0.0, side * 0.115, -0.03), (0.07, 0.012, 0.08), cuts=1)


def build_iron_helm(parts):
    # A dented iron bowl with a riveted brow band, a nasal guard and a low comb.
    dome(parts.bm("iron"), 0.12, 0.13, bump=lambda b, t: 0.004 * noise.noise(Vector((math.cos(b) * 3.0, math.sin(b) * 3.0, t * 4.0))))
    cylinder(parts.bm("steel"), (0, 0, 0.018), 0.132, 0.034, axis="Z", segs=36)
    for i in range(16):
        a = math.tau * i / 16
        sphere(parts.bm("brass"), (math.cos(a) * 0.142, math.sin(a) * 0.132, 0.018), 0.007, segs=6, rings=4)
    box(parts.bm("steel"), (0.138, 0.0, -0.025), (0.016, 0.03, 0.09), cuts=1)
    box(parts.bm("dark_steel"), (0.0, 0.0, 0.128), (0.24, 0.012, 0.022), cuts=4)


def glove(parts, x, y, mirror, plated):
    m = mirror
    body = parts.bm("iron" if plated else "leather")
    box(body, (x, y, 0.016), (0.095, 0.085, 0.03), cuts=1)
    for i in range(4):
        fy = y + (i - 1.5) * 0.021 * m
        length = (0.075, 0.085, 0.08, 0.065)[i]
        if plated:
            for k in range(3):
                box(parts.bm("dark_steel"), (x + 0.06 + k * length / 3.0, fy, 0.016), (length / 3.2, 0.019, 0.022))
        else:
            cylinder(body, (x + 0.047 + length / 2, fy, 0.012), 0.0095, length, axis="X", segs=10)
    thumb = parts.bm("dark_steel" if plated else "leather")
    cylinder(thumb, (x + 0.02, y + 0.06 * m, 0.012), 0.011, 0.06, axis="X", segs=10, rot=(0, 0, 0.7 * m))
    cuff = parts.bm("steel" if plated else "leather_dark")
    cylinder(cuff, (x - 0.075, y, 0.02), 0.05 if plated else 0.044, 0.07, axis="X", segs=20, radius2=0.062 if plated else 0.05)
    if plated:
        for i in range(5):
            sphere(parts.bm("brass"), (x - 0.06, y + (i - 2) * 0.02, 0.07), 0.005, segs=6, rings=4)


def build_leather_gloves(parts):
    glove(parts, 0.0, 0.07, 1, False)
    glove(parts, 0.03, -0.07, -1, False)


def build_iron_gauntlets(parts):
    glove(parts, 0.0, 0.075, 1, True)
    glove(parts, 0.03, -0.075, -1, True)


def boot(parts, x, y, plated):
    """A boot lying on its side, its L outline flat on the ground: the shaft along X, the foot turned along +Y at the low end."""
    leather = parts.bm("leather")
    cylinder(leather, (x + 0.03, y, 0.045), 0.044, 0.2, axis="X", segs=18, radius2=0.05)
    sphere(leather, (x - 0.08, y + 0.055, 0.042), 0.05, (0.95, 1.9, 0.82), segs=16, rings=10)   # the foot
    sphere(leather, (x - 0.085, y - 0.005, 0.042), 0.048, (1.0, 1.0, 0.85), segs=14, rings=8)  # the heel
    sole = parts.bm("leather_dark")
    box(sole, (x - 0.125, y + 0.05, 0.04), (0.012, 0.19, 0.07), cuts=1)
    torus(parts.bm("leather_dark"), (x + 0.13, y, 0.045), 0.048, 0.01, axis="X", major_segs=24, minor_segs=6)   # the turned-down top
    if plated:   # greaves: a shin plate, a knee cop and a plated toe
        cylinder(parts.bm("iron"), (x + 0.035, y, 0.052), 0.05, 0.17, axis="X", segs=18, radius2=0.055)
        sphere(parts.bm("steel"), (x + 0.135, y, 0.06), 0.042, (0.6, 1.0, 1.0), segs=14, rings=8)
        sphere(parts.bm("dark_steel"), (x - 0.08, y + 0.09, 0.05), 0.04, (0.9, 1.1, 0.7), segs=14, rings=8)
        for i in range(4):
            sphere(parts.bm("brass"), (x - 0.03 + i * 0.045, y, 0.104), 0.006, segs=6, rings=4)
    else:   # laces up the front of the shaft
        for i in range(5):
            sphere(parts.bm("leather_dark"), (x - 0.04 + i * 0.035, y + 0.0, 0.088), 0.008, (1.0, 2.2, 0.6), segs=8, rings=5)


def build_leather_boots(parts):
    boot(parts, 0.0, 0.07, False)
    boot(parts, 0.04, -0.12, False)


def build_iron_greaves(parts):
    boot(parts, 0.0, 0.08, True)
    boot(parts, 0.04, -0.13, True)


def build_buckler(parts):
    # A small round shield: weathered planks behind an iron rim and a heavy boss.
    wood = parts.bm("wood")
    cylinder(wood, (0, 0, 0.012), 0.18, 0.024, axis="Z", segs=36)
    for i in range(5):
        box(parts.bm("leather_dark"), (0.0, (i - 2) * 0.07, 0.025), (0.34, 0.004, 0.003))
    torus(parts.bm("iron"), (0, 0, 0.022), 0.18, 0.011, axis="Z", major_segs=40, minor_segs=8)
    sphere(parts.bm("steel"), (0, 0, 0.03), 0.06, (1, 1, 0.65), segs=18, rings=10)
    for i in range(8):
        a = math.tau * i / 8
        sphere(parts.bm("brass"), (math.cos(a) * 0.075, math.sin(a) * 0.075, 0.027), 0.007, segs=6, rings=4)


def build_kite_shield(parts):
    # A tall kite: planks under a faded, scuffed cloth facing, an iron edge and a boss.
    outline = []
    for i in range(13):   # the rounded top
        a = math.pi * i / 12
        outline.append((0.18 + math.sin(a) * 0.12, math.cos(a) * 0.17))
    outline += [(-0.08, -0.13), (-0.3, -0.02), (-0.31, 0.0), (-0.3, 0.02), (-0.08, 0.13)]
    prism(parts.bm("wood"), outline, 0.0, 0.026)
    face = parts.bm("cloth")
    prism(face, [(x * 0.92, y * 0.88) for x, y in outline], 0.026, 0.03)
    edge = parts.bm("iron")
    for i in range(len(outline)):
        ax, ay = outline[i]
        bx, by = outline[(i + 1) % len(outline)]
        for k in range(4):
            t = k / 4
            sphere(edge, (ax + (bx - ax) * t, ay + (by - ay) * t, 0.02), 0.011, segs=8, rings=5)
    sphere(parts.bm("steel"), (0.13, 0, 0.034), 0.045, (1, 1, 0.6), segs=16, rings=8)


def build_band(parts):
    # A plain, heavy iron band, notched and worn smooth on one side.
    torus(parts.bm("iron"), (0.0, 0.0, 0.012), 0.034, 0.011, axis="Z", major_segs=32, minor_segs=10)
    for i in range(8):
        a = math.tau * i / 8
        box(parts.bm("dark_steel"), (math.cos(a) * 0.034, math.sin(a) * 0.034, 0.023), (0.006, 0.006, 0.004), rot=(0, 0, a))


BUILDERS = {
    "falchion": build_falchion, "longsword": build_longsword, "greatsword": build_greatsword,
    "axe_1h": build_axe_1h, "mace": build_mace, "club": build_club, "dagger": build_dagger,
    "axe_2h": build_axe_2h, "hammer_2h": build_hammer_2h,
    "leather_jerkin": build_leather_jerkin, "mail_hauberk": build_mail_hauberk, "plate_cuirass": build_plate_cuirass,
    "charm": build_charm, "signet": build_signet, "talisman": build_talisman,
    "leather_cap": build_leather_cap, "iron_helm": build_iron_helm, "leather_gloves": build_leather_gloves,
    "iron_gauntlets": build_iron_gauntlets, "leather_boots": build_leather_boots, "iron_greaves": build_iron_greaves,
    "buckler": build_buckler, "kite_shield": build_kite_shield, "band": build_band,
}

# --- Weathering ------------------------------------------------------------------------------------------------------------

def mix(a, b, t):
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


def paint(obj, material_key, seed):
    """Vertex colours: the base colour broken up by grime and rust patches, darkened in low spots and brightened where the
    surface turns away (worn edges)."""
    base, _metal, _rough, wear = MATERIALS[material_key]
    mesh = obj.data
    attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    offset = Vector((seed * 7.3, seed * 3.1, seed * 5.9))
    for v in mesh.vertices:
        p = v.co + offset
        large = noise.noise(p * 7.0)
        fine = noise.noise(p * 38.0)
        rust_mask = noise.noise(p * 11.0 + Vector((3.0, 1.0, 2.0)))
        col = tuple(c * (0.78 + 0.32 * (large * 0.5 + 0.5) + 0.12 * fine) for c in base)
        if material_key in ("steel", "dark_steel", "iron", "brass"):
            if rust_mask > 0.12:
                col = mix(col, RUST, min((rust_mask - 0.12) * 2.2 * wear, 0.75))
            edge = 1.0 - abs(v.normal.z)                      # surfaces turned sideways: scuffed bright edges
            col = mix(col, tuple(min(c * 1.9, 0.7) for c in base), edge * 0.28)
        elif material_key.startswith("leather") or material_key in ("cloth", "wood"):
            col = mix(col, (0.06, 0.045, 0.03), max(0.0, noise.noise(p * 15.0) - 0.1) * 0.8 * wear)
        grime = max(0.0, -noise.noise(p * 22.0 + Vector((9.0, 9.0, 9.0)))) * 0.5 * wear
        col = tuple(c * (1.0 - grime) for c in col)
        # The palette above is written the way it should look; vertex colours are stored linear, so convert.
        col = tuple(max(c, 0.0) ** 1.6 for c in col)
        attr.data[v.index].color = (col[0], col[1], col[2], 1.0)


def material_for(key):
    base, metallic, rough, _ = MATERIALS[key]
    mat = bpy.data.materials.new("item_" + key)
    mat.use_nodes = True
    tree = mat.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    color = tree.nodes.new("ShaderNodeVertexColor")
    color.layer_name = "Col"
    tree.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if key == "ember":
        bsdf.inputs["Emission Color"].default_value = (1.0, 0.35, 0.08, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.2
    return mat


def make_object(name, parts, seed):
    objs = []
    for key, bm in parts.groups.items():
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(name + "_" + key)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name + "_" + key, mesh)
        bpy.context.collection.objects.link(obj)
        for poly in mesh.polygons:
            poly.use_smooth = key not in ("steel",) or name.endswith("hauberk")
        paint(obj, key, seed)
        obj.data.materials.append(material_for(key))
        objs.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    return joined


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            block.remove(item)


def export(obj, name):
    folder = os.path.normpath(os.path.join(OUT, name))
    os.makedirs(folder, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # Origin at the centre of the footprint, resting on the ground (Blender Z = glTF Y).
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    mx = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    shift = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for v in obj.data.vertices:
        v.co -= shift
    path = os.path.join(folder, "model.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_vertex_color="ACTIVE", export_materials="EXPORT")
    print("wrote", path, "size", tuple(round(c, 3) for c in (mx - mn)))


def render_icon(obj, name, size=192):
    """The inventory icon: the item seen from above, lit from the upper left with a warm key and a cold fill, on a transparent
    background (the game frames it in the rarity colour). Weapons are turned diagonal so a long blade fits a square."""
    os.makedirs(ICONS, exist_ok=True)
    scene = bpy.context.scene
    # CURSE_ICON_ENGINE=CYCLES renders on the CPU (a headless machine with no GPU cannot run EEVEE).
    engines = (os.environ["CURSE_ICON_ENGINE"],) if os.environ.get("CURSE_ICON_ENGINE") else ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES")
    for engine in engines:
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.film_transparent = True
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = 24
    elif hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = 24
    world = bpy.data.worlds.new("icon_world") if not scene.world else scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.33, 0.38, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    scene.world = world
    long_axis = max(obj.dimensions.x, obj.dimensions.y)
    obj.rotation_euler = (0, 0, math.radians(-38 if long_axis > 0.5 or "dagger" in name else -15))
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    centre = sum(corners, Vector()) / 8.0
    span = max(max(c.x for c in corners) - min(c.x for c in corners), max(c.y for c in corners) - min(c.y for c in corners))
    cam_data = bpy.data.cameras.new("icon_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span * 1.12
    cam = bpy.data.objects.new("icon_cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = centre + Vector((0.0, -3.0 * math.tan(math.radians(8)), 3.0))   # looking 8 degrees off straight down, centred on the item
    cam.rotation_euler = (math.radians(8), 0, 0)
    scene.camera = cam
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN"))
    key.data.energy = 4.0
    key.data.color = (1.0, 0.86, 0.68)
    key.rotation_euler = (math.radians(40), math.radians(-25), math.radians(-35))
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    fill.data.energy = 1.2
    fill.data.color = (0.62, 0.72, 1.0)
    fill.rotation_euler = (math.radians(50), math.radians(30), math.radians(140))
    bpy.context.collection.objects.link(key)
    bpy.context.collection.objects.link(fill)
    scene.render.filepath = os.path.normpath(os.path.join(ICONS, name + ".png"))
    bpy.ops.render.render(write_still=True)
    print("icon", scene.render.filepath)
    for o in (cam, key, fill):
        bpy.data.objects.remove(o)
    obj.rotation_euler = (0, 0, 0)


def main():
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for i, (name, builder) in enumerate(BUILDERS.items()):
        if wanted and name not in wanted:
            continue
        reset_scene()
        parts = Parts()
        builder(parts)
        obj = make_object(name, parts, i + 1)
        export(obj, name)
        render_icon(obj, name)


if __name__ == "__main__":
    main()
