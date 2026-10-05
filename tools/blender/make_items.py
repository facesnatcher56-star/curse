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


BUILDERS = {
    "falchion": build_falchion, "longsword": build_longsword, "greatsword": build_greatsword,
    "leather_jerkin": build_leather_jerkin, "mail_hauberk": build_mail_hauberk, "plate_cuirass": build_plate_cuirass,
    "charm": build_charm, "signet": build_signet, "talisman": build_talisman,
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
        elif material_key.startswith("leather") or material_key == "cloth":
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
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
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
    obj.rotation_euler = (0, 0, math.radians(-38 if long_axis > 0.5 else -15))
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


main()
