"""Build low-poly staging enemy meshes and export them as GLB (plus optional Blender preview renders).

Run headless from the repo root:

    blender.exe -b -P tools/art/export_enemy.py -- --enemy all --preview
    blender.exe -b -P tools/art/export_enemy.py -- --enemy zombie --preview

Options (after the "--"):
    --enemy NAME|all   zombie, warden, ghoul, brute or all (default: all)
    --out DIR          output folder (default: assets/art_staging/enemies)
    --preview          also write Workbench preview PNGs into <out>/previews

Conventions:
    - Units are metres, origin at the feet, Z up. Character faces -Y, +X is its left.
    - Zombie and warden are rigged on the Lane A knight skeleton (24 bones, see enemy_rig.py) and
      export idle, walk, attack, hit and death clips. Ghoul and brute stay unrigged staging meshes.
    - Flat-shaded faceted geometry, one Principled material per palette entry.
    - Output is triangulated, so the printed triangle count is the real GLB count.
"""

import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import enemy_rig as er  # noqa: E402
from mathutils import Vector  # noqa: E402

PALETTE = {
    "bone": (0.60, 0.56, 0.46),
    "bone_dark": (0.36, 0.33, 0.27),
    "flesh": (0.40, 0.42, 0.37),
    "rot": (0.30, 0.36, 0.22),
    "charcoal": (0.15, 0.15, 0.16),
    "iron": (0.30, 0.31, 0.33),
    "moss": (0.26, 0.34, 0.20),
    "burgundy": (0.34, 0.09, 0.11),
    "blood": (0.20, 0.05, 0.05),
    "leather": (0.28, 0.19, 0.12),
    "rust": (0.42, 0.21, 0.11),
    "eye_milk": (0.70, 0.70, 0.64),
    "void": (0.04, 0.04, 0.05),
}


class Builder:
    def __init__(self):
        self.objs = []
        self.mats = {}
        self.rigid = {}  # object name -> bone name for hand-held props

    def mat(self, key):
        if key not in self.mats:
            m = bpy.data.materials.new(name="enemy_" + key)
            m.use_nodes = True
            rgb = PALETTE[key]
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.88
            bsdf.inputs["Metallic"].default_value = 0.0
            m.diffuse_color = (*rgb, 1.0)
            self.mats[key] = m
        return self.mats[key]

    def _place(self, obj, key, bone=None):
        obj.data.materials.append(self.mat(key))
        self.objs.append(obj)
        if bone:
            self.rigid[obj.name] = bone
        return obj

    def box(self, center, size, key, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=rot)
        o = bpy.context.active_object
        o.scale = size
        return self._place(o, key)

    def blob(self, center, radii, key, sub=1, rot=(0, 0, 0), bone=None):
        # Detail tiers: body masses (radius >= 0.15) get subdivision 3 (320 tris), small parts 2 (80 tris).
        sub = max(sub, 3) if max(radii) >= 0.15 else max(sub, 2)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=1, location=center, rotation=rot)
        o = bpy.context.active_object
        o.scale = radii
        return self._place(o, key, bone)

    def limb(self, p0, p1, r0, r1=None, key="bone", sides=8):
        """Cylinder (r1 None or equal) or tapered cone from p0 to p1 (used by ghoul and brute)."""
        p0, p1 = Vector(p0), Vector(p1)
        length = (p1 - p0).length
        mid = (p0 + p1) * 0.5
        direction = (p1 - p0).normalized()
        rot = Vector((0, 0, 1)).rotation_difference(direction).to_euler()
        r1 = r0 if r1 is None else r1
        if abs(r1 - r0) < 1e-6:
            bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=r0, depth=length, location=mid, rotation=rot)
        else:
            bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r0, radius2=r1, depth=length, location=mid, rotation=rot)
        return self._place(bpy.context.active_object, key)

    def tube(self, key, pts, rx, ry=None, mat="flesh", sides=8, cap0=True, cap1=True, jitter=0.0, seed=1, bone=None):
        o = er.tube(self, key, [Vector(p) for p in pts], rx, ry, sides=sides, cap0=cap0, cap1=cap1,
                    jitter=jitter, seed=seed)
        return self._place(o, mat, bone)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# --------------------------------------------------------------------------- zombie
def build_zombie(b, J):
    """Hunched, shambling, medium. Rot-bloated torso with a torn tunic, a broken bone splinter on the
    left forearm, a sunken dark right eye and a milky left eye, and a cheek bone showing through."""
    for side, f in (("L", lambda p: p), ("R", er.mir)):
        hip, knee, ank, ball, toe = (f(J[k]) for k in ("hip", "knee", "ank", "ball", "toe"))
        thigh_mid = (hip + knee) * 0.5
        shin_mid = (knee + ank) * 0.5 + Vector((0, 0.02, 0))
        b.tube(f"Z_{side}Thigh", [hip, thigh_mid, knee], [0.10, 0.085, 0.065], mat="flesh", jitter=0.05, seed=40)
        b.tube(f"Z_{side}Shin", [knee, shin_mid, ank], [0.065, 0.075, 0.04], mat="flesh", jitter=0.05, seed=41)
        b.tube(f"Z_{side}Foot", [ank, ball], [0.045, 0.05], mat="flesh", sides=8)
        b.tube(f"Z_{side}Toes", [ball, toe], [0.03, 0.04], mat="bone_dark", sides=6)
    # torn leather wrap over the right shin only
    rk = er.mir(J["knee"]) + Vector((0, 0, 0.05))
    ra = er.mir(J["ank"]) + Vector((0, 0, 0.12))
    b.tube("Z_RWrap", [rk, (rk + ra) * 0.5, ra], [0.085, 0.09, 0.07], mat="leather", jitter=0.55, seed=44,
           cap0=False, cap1=False)

    # torso, rot patch on the belly, torn tunic hanging to mid thigh, belt
    b.tube("Z_Torso", [J["hips"], J["spine"], J["chest"], J["neck"]], [0.19, 0.17, 0.19, 0.12],
           [0.12, 0.14, 0.13, 0.09], mat="flesh", sides=10, jitter=0.14, seed=3)
    b.tube("Z_RotPatch", [Vector((0, 0.0, 0.99)), Vector((0.02, -0.04, 1.10))], [0.205, 0.19], [0.15, 0.14],
           mat="rot", sides=8, jitter=0.5, seed=7, cap0=False, cap1=False)
    b.tube("Z_Tunic", [Vector((0, 0.02, 0.60)), Vector((0, 0.01, 0.76)), Vector((0, 0.0, 0.93))],
           [0.25, 0.23, 0.20], [0.17, 0.16, 0.14], mat="leather", sides=10, jitter=0.45, seed=9,
           cap0=False, cap1=False)
    b.tube("Z_Belt", [Vector((0, 0.0, 0.90)), Vector((0, 0.0, 0.98))], 0.20, 0.13, mat="leather", sides=10)
    b.box((0.0, -0.14, 0.94), (0.07, 0.02, 0.05), "bone_dark")  # buckle
    # kyphotic upper back hump and rounded deltoids carry the hunch in silhouette
    b.blob((0.0, 0.10, 1.30), (0.18, 0.12, 0.17), "flesh", sub=3)
    b.blob((0.02, 0.07, 1.36), (0.11, 0.09, 0.09), "rot", sub=2)
    for s in (-1, 1):
        b.blob((0.19 * s, -0.03, 1.36), (0.09, 0.09, 0.08), "flesh", sub=2)
    b.blob((-0.10, -0.13, 1.05), (0.035, 0.02, 0.03), "blood", sub=1)  # old blood on the tunic

    # neck stays on the spine; the head group below is carried forward and down (hunch)
    b.tube("Z_Neck", [J["neck"], J["head"]], 0.055, mat="flesh", sides=8)
    n0 = len(b.objs)
    b.tube("Z_Skull", [Vector((0, -0.17, 1.52)), Vector((0, -0.17, 1.63))],
           [0.07, 0.09], [0.08, 0.095], mat="flesh", sides=10, jitter=0.08, seed=11, cap1=False)
    b.blob((0.0, -0.17, 1.66), (0.085, 0.095, 0.115), "flesh", sub=3)     # rounded cranium, no flat top
    b.tube("Z_Jaw", [Vector((0, -0.17, 1.52)), Vector((0, -0.23, 1.50)), Vector((0, -0.27, 1.46))],
           [0.05, 0.045, 0.04], [0.04, 0.035, 0.03], mat="bone", sides=8)
    b.blob((0.032, -0.25, 1.64), (0.02, 0.010, 0.02), "eye_milk", sub=1)     # milky left eye
    b.blob((-0.034, -0.245, 1.63), (0.024, 0.012, 0.026), "void", sub=1)     # sunken dark right eye
    b.blob((-0.075, -0.19, 1.60), (0.03, 0.03, 0.025), "bone", sub=1)        # cheek bone showing
    b.blob((0.0, -0.22, 1.67), (0.075, 0.03, 0.028), "bone_dark", sub=1)     # heavy brow ridge
    b.tube("Z_Nose", [Vector((0, -0.25, 1.60)), Vector((0, -0.27, 1.575))], [0.012, 0.006], mat="flesh", sides=4)
    b.tube("Z_TeethL", [Vector((0.03, -0.27, 1.48)), Vector((0.03, -0.285, 1.46))], 0.008, mat="bone", sides=4)
    b.tube("Z_TeethR", [Vector((-0.02, -0.27, 1.48)), Vector((-0.02, -0.28, 1.455))], 0.008, mat="bone", sides=4)
    b.tube("Z_Hair1", [Vector((0.02, -0.10, 1.76)), Vector((0.05, -0.05, 1.70)), Vector((0.08, -0.03, 1.60))],
           [0.012, 0.006, 0.002], mat="leather", sides=4)
    b.tube("Z_Hair2", [Vector((-0.04, -0.12, 1.75)), Vector((-0.06, -0.08, 1.69))], [0.01, 0.003],
           mat="charcoal", sides=4)
    for o in b.objs[n0:]:
        o.location += Vector((0, -0.07, -0.03))

    # arms: both reach forward with claw fingers; left forearm has a broken bone splinter, right sleeve is torn
    for side, f in (("L", lambda p: p), ("R", er.mir)):
        sh, el, wr, he = (f(J[k]) for k in ("sho", "elb", "wri", "hand_end"))
        b.tube(f"Z_{side}Upper", [sh, (sh + el) * 0.5, el], [0.065, 0.06, 0.05], mat="flesh", sides=8)
        b.tube(f"Z_{side}Fore", [el, (el + wr) * 0.5, wr], [0.05, 0.045, 0.035], mat="flesh", sides=8)
        b.tube(f"Z_{side}Palm", [wr, he], [0.04, 0.03], mat="flesh", sides=8)
        for dx in (-0.02, 0.0, 0.02):
            tip = he + Vector((dx, -0.06, -0.06))
            b.tube(f"Z_{side}Claw{dx:+.2f}", [he + Vector((dx, 0, 0)), tip], [0.016, 0.004], mat="bone", sides=5)
    lf = (J["elb"] + J["wri"]) * 0.5
    b.tube("Z_LSplinter", [lf, lf + Vector((0.07, -0.04, -0.02))], [0.012, 0.002], mat="bone", sides=5)
    rsh = er.mir(J["sho"])
    b.tube("Z_RSleeve", [rsh, (rsh + er.mir(J["elb"])) * 0.5], [0.085, 0.07], mat="leather", sides=8,
           jitter=0.5, seed=52, cap0=False, cap1=False)


# --------------------------------------------------------------------------- warden
def build_warden(b, J):
    """Tall, narrow, upright armoured sentinel. Spire helm with a cracked right plate, a bone mask with
    dark eye pits, a torn burgundy tabard, mismatched pauldron lames, and a rigid staff in the right hand."""
    for side, f in (("L", lambda p: p), ("R", er.mir)):
        hip, knee, ank, ball, toe = (f(J[k]) for k in ("hip", "knee", "ank", "ball", "toe"))
        b.tube(f"W_{side}Cloth", [hip, (hip + knee) * 0.5, knee], [0.085, 0.078, 0.07], mat="leather", sides=8)
        b.tube(f"W_{side}Greave", [knee, (knee + ank) * 0.5, ank], [0.09, 0.10, 0.065], mat="charcoal", sides=8)
        b.tube(f"W_{side}Boot", [ank, ball], [0.06, 0.07], mat="leather", sides=8)
        b.tube(f"W_{side}Toe", [ball, toe], [0.04, 0.05], mat="charcoal", sides=6)

    # tabard (torn hem), belt with buckle, cuirass, breastplate, gorget
    b.tube("W_Tabard", [Vector((0, 0, 0.98)), Vector((0, -0.01, 0.85)), Vector((0, -0.02, 0.70))],
           [0.20, 0.21, 0.22], [0.13, 0.14, 0.14], mat="burgundy", sides=10, jitter=0.4, seed=21,
           cap0=False, cap1=False)
    b.tube("W_Belt", [Vector((0, 0, 0.94)), Vector((0, 0, 1.0))], 0.20, 0.13, mat="leather", sides=10)
    b.box((0.0, -0.14, 0.97), (0.06, 0.02, 0.05), "iron")
    b.tube("W_Cuirass", [J["hips"], J["spine"], J["chest"], J["neck"]], [0.18, 0.17, 0.20, 0.13],
           [0.12, 0.12, 0.14, 0.10], mat="charcoal", sides=10, jitter=0.05, seed=5)
    b.tube("W_Breast", [Vector((0, -0.04, 1.02)), Vector((0, -0.06, 1.16)), Vector((0, -0.04, 1.32))],
           [0.16, 0.18, 0.16], [0.12, 0.14, 0.12], mat="iron", sides=10, jitter=0.12, seed=6)
    b.tube("W_Gorget", [Vector((0, 0, 1.44)), Vector((0, 0, 1.50))], [0.12, 0.11], mat="iron", sides=10)

    # pauldrons: left shoulder has three lames, right has two plus a jagged rust shard
    for side, f, lames in (("L", lambda p: p, 3), ("R", er.mir, 2)):
        sh = f(J["sho"])
        for k in range(lames):
            dz = 0.04 - k * 0.035
            b.tube(f"W_{side}Lame{k}", [sh + Vector((0, 0, dz + 0.03)), sh + Vector((0, 0, dz - 0.03))],
                   0.11 + 0.01 * k, mat="iron", sides=10, jitter=0.06 if side == "R" else 0.0, seed=60 + k)
    rs = er.mir(J["sho"])
    b.tube("W_RShard", [rs + Vector((0, 0.03, 0.06)), rs + Vector((-0.02, 0.05, 0.14))], [0.04, 0.005],
           mat="rust", sides=5)

    # arms: charcoal upper arms, iron bracers and gauntlets
    for side, f in (("L", lambda p: p), ("R", er.mir)):
        sh, el, wr, he = (f(J[k]) for k in ("sho", "elb", "wri", "hand_end"))
        b.tube(f"W_{side}Upper", [sh, el], [0.07, 0.06], mat="charcoal", sides=8)
        b.tube(f"W_{side}Bracer", [el, (el + wr) * 0.5], [0.065, 0.06], mat="iron", sides=8)
        b.tube(f"W_{side}Fore", [el, wr], [0.06, 0.045], mat="charcoal", sides=8)
        b.tube(f"W_{side}Gauntlet", [wr, he], [0.055, 0.05], mat="iron", sides=8)

    # neck, spire helm with cracked right plate, visor, bone mask with eye pits, cheek plates
    b.tube("W_NeckCore", [J["neck"], J["head"]], 0.06, mat="charcoal", sides=8)
    b.tube("W_Helm", [Vector((0, 0, 1.56)), Vector((0, -0.005, 1.62)), Vector((0, 0, 1.79))],
           [0.12, 0.135, 0.11], [0.13, 0.14, 0.12], mat="iron", sides=10, jitter=0.05, seed=31)
    b.tube("W_Spire", [Vector((0, 0, 1.79)), Vector((0, 0, 2.00)), Vector((0, 0.005, 2.25))],
           [0.10, 0.06, 0.005], mat="iron", sides=6, jitter=0.12, seed=32)
    b.box((0.0, -0.14, 1.66), (0.14, 0.02, 0.035), "charcoal")
    b.blob((0.0, -0.12, 1.62), (0.10, 0.05, 0.12), "bone", sub=2)
    b.blob((0.04, -0.165, 1.64), (0.02, 0.01, 0.012), "void", sub=1)
    b.blob((-0.04, -0.165, 1.64), (0.02, 0.01, 0.012), "void", sub=1)
    b.box((0.09, -0.10, 1.60), (0.03, 0.08, 0.12), "iron")
    b.box((-0.09, -0.10, 1.60), (0.03, 0.08, 0.12), "iron")

    # staff: a rigid prop held in the right hand (RightHandProp bone follows the grip)
    b.tube("W_Staff", [Vector((-0.66, -0.10, 0.90)), Vector((-0.70, -0.10, 2.40))], [0.028, 0.02],
           mat="leather", sides=6, bone="RightHandProp")
    b.blob((-0.70, -0.10, 2.46), (0.07, 0.07, 0.08), "bone", sub=2, bone="RightHandProp")


def build_ghoul(b):
    """Low, crouched, fast. Long reaching arms to the ground, claws, burgundy mouth. Height ~1.3 m."""
    for s in (-1, 1):
        b.limb((0.17 * s, 0.12, 0.74), (0.22 * s, -0.22, 0.36), 0.085, 0.07, key="flesh")
        b.limb((0.22 * s, -0.22, 0.36), (0.16 * s, 0.06, 0.08), 0.06, 0.04, key="flesh")
        b.box((0.16 * s, 0.10, 0.05), (0.14, 0.26, 0.09), "charcoal")
    b.blob((0, 0.0, 0.92), (0.26, 0.36, 0.22), "flesh", sub=2, rot=(0.5, 0, 0))
    b.blob((0, 0.22, 1.04), (0.20, 0.18, 0.16), "charcoal", sub=1)
    b.blob((0, -0.10, 0.98), (0.21, 0.20, 0.16), "flesh", sub=1)
    b.blob((0, -0.40, 1.00), (0.14, 0.17, 0.13), "bone", sub=2)
    b.box((0, -0.46, 0.90), (0.12, 0.14, 0.04), "burgundy")
    b.limb((-0.05, -0.50, 1.04), (-0.08, -0.62, 1.08), 0.02, 0.005, key="bone", sides=4)
    b.limb((0.05, -0.50, 1.04), (0.08, -0.62, 1.08), 0.02, 0.005, key="bone", sides=4)
    for s in (-1, 1):
        sh = (0.26 * s, -0.16, 0.96)
        el = (0.34 * s, -0.42, 0.50)
        wr = (0.36 * s, -0.56, 0.06)
        b.limb(sh, el, 0.08, 0.06, key="flesh")
        b.limb(el, wr, 0.06, 0.04, key="flesh")
        for dx in (-0.05, 0, 0.05):
            b.limb((wr[0] + dx * s, wr[1] - 0.02, 0.06), (wr[0] + dx * s, wr[1] - 0.04, -0.06), 0.02, 0.0, key="bone", sides=4)
    for i, y in enumerate((0.20, 0.06, -0.06)):
        b.limb((0, y + 0.1, 1.08 - i * 0.03), (0, y + 0.02, 1.26 - i * 0.02), 0.04, 0.0, key="burgundy", sides=5)


def build_brute(b):
    """Heavy, wide, slow. Block torso, iron shoulders, massive fists. Height ~2.7 m with horns."""
    for s in (-1, 1):
        b.limb((0.30 * s, 0.0, 1.16), (0.32 * s, -0.02, 0.60), 0.22, 0.18, key="charcoal")
        b.limb((0.32 * s, -0.02, 0.60), (0.30 * s, 0.0, 0.16), 0.18, 0.15, key="charcoal")
        b.box((0.30 * s, -0.12, 0.10), (0.34, 0.52, 0.20), "leather")
    b.box((0, 0, 1.16), (0.84, 0.52, 0.34), "leather")
    b.box((0, 0, 1.78), (0.98, 0.62, 0.84), "rust")
    b.blob((0, -0.06, 1.92), (0.52, 0.42, 0.40), "flesh", sub=2)
    b.box((0, -0.36, 1.86), (0.42, 0.06, 0.42), "iron")
    for s in (-1, 1):
        b.blob((0.64 * s, 0.0, 2.22), (0.26, 0.26, 0.22), "iron", sub=2)
        b.limb((0.66 * s, 0.0, 2.36), (0.74 * s, 0.02, 2.56), 0.06, 0.0, key="rust", sides=5)
    for s in (-1, 1):
        sh = (0.70 * s, 0.0, 2.05)
        el = (0.80 * s, -0.10, 1.40)
        wr = (0.82 * s, -0.18, 0.80)
        b.limb(sh, el, 0.23, 0.20, key="flesh")
        b.limb(el, wr, 0.20, 0.17, key="flesh")
        b.blob((0.84 * s, -0.24, 0.66), (0.24, 0.24, 0.22), "flesh", sub=2)
        b.box((0.84 * s, -0.28, 0.54), (0.30, 0.10, 0.10), "iron")
    b.box((0, -0.04, 2.32), (0.34, 0.34, 0.32), "flesh")
    b.blob((0, -0.04, 2.46), (0.27, 0.29, 0.16), "iron", sub=2)
    b.limb((-0.20, -0.02, 2.52), (-0.30, 0.02, 2.68), 0.05, 0.0, key="burgundy", sides=5)
    b.limb((0.20, -0.02, 2.52), (0.30, 0.02, 2.68), 0.05, 0.0, key="burgundy", sides=5)


STATIC = {"ghoul": build_ghoul, "brute": build_brute}
RIGGED = {
    # name: (joints, builder, clip style, preview height)
    "zombie": (er.zombie_joints, build_zombie,
               dict(stride=0.32, arm_swing=0.22, lean=0.12, sway=0.10, knee_bend=0.55), 1.8),
    "warden": (er.knight_joints, build_warden,
               dict(stride=0.42, arm_swing=0.12, lean=0.03, sway=0.03, knee_bend=0.35), 2.5),
}


def finalize(b):
    """Join parts, triangulate, flat-shade. Returns the joined object."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in b.objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = b.objs[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.update()
    return obj


def triangle_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export_glb(objs, path, animated=False, active_only=False):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
                  export_materials="EXPORT")
    if animated:
        kwargs.update(export_animations=True, export_animation_mode="ACTIVE_ACTIONS" if active_only else "ACTIONS",
                      export_skins=True)
    bpy.ops.export_scene.gltf(**kwargs)


def render_preview(path, height):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.background_type = "WORLD"
    scene.world = bpy.data.worlds.new("preview_world")
    scene.world.color = (0.07, 0.07, 0.08)
    cam_data = bpy.data.cameras.new("preview_cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("preview_cam", cam_data)
    scene.collection.objects.link(cam)
    s = max(height, 1.4) / 1.75
    target = Vector((0, 0, height * 0.5))
    cam.location = Vector((2.4 * s, -3.4 * s, height * 0.7 + 0.8 * s))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def build_rigged(name, out_dir, preview, live=False, clip_cache=None):
    joints_fn, builder_fn, style, height = RIGGED[name]
    clear_scene()
    coll = bpy.context.scene.collection
    b = Builder()
    J = joints_fn()
    arm, rows = er.build_armature(coll, J, name.capitalize(), live=live)
    builder_fn(b, J)
    for o in b.objs:
        er.skin_object(o, rows, rigid=b.rigid.get(o.name))
    obj = finalize(b)
    er.attach_armature(obj, arm)
    actions, sign = er.make_clips(arm, style, live=live)
    tris = triangle_count(obj)
    if live:
        # Live mode: rigged.glb holds only the mesh and skeleton (clips come from anims.res), plus one
        # anim_<clip>.glb per clip in clip_cache for tools/bake_anims.gd.
        os.makedirs(out_dir, exist_ok=True)
        export_glb([arm, obj], os.path.join(out_dir, "rigged.glb"), animated=False)
        for clip in sorted(actions):
            arm.animation_data.action = actions[clip]
            export_glb([arm, obj], os.path.join(clip_cache, "anim_%s.glb" % clip), animated=True, active_only=True)
        arm.animation_data.action = None
        print("LIVE %s tris=%d bones=%d joints=%s clips=%s out=%s cache=%s" % (
            name, tris, len(arm.data.bones), ",".join(b.name for b in arm.data.bones),
            ",".join(sorted(actions)), out_dir, clip_cache))
        return
    out_path = os.path.join(out_dir, name + "_rigged.glb")
    export_glb([arm, obj], out_path, animated=True)
    print("ENEMY %s tris=%d bones=%d clips=%s fwd_sign=%+.0f glb=%s" % (
        name, tris, len(arm.data.bones), ",".join(sorted(actions)), sign, out_path))
    if preview:
        arm.animation_data_create()
        for clip, frame in (("idle", 1), ("attack", 17)):
            arm.animation_data.action = actions[clip]
            bpy.context.scene.frame_set(frame)
            png = os.path.join(out_dir, "previews", "%s_%s_blender_preview.png" % (name, clip))
            render_preview(png, height)
            print("PREVIEW %s" % png)
        arm.animation_data.action = None


def build_static(name, out_dir, preview):
    clear_scene()
    b = Builder()
    STATIC[name](b)
    obj = finalize(b)
    tris = triangle_count(obj)
    out_path = os.path.join(out_dir, name + "_geo.glb")
    export_glb([obj], out_path)
    print("ENEMY %s tris=%d parts=%d glb=%s" % (name, tris, len(b.objs), out_path))
    if preview:
        png = os.path.join(out_dir, "previews", name + "_blender_preview.png")
        render_preview(png, obj.dimensions.z)
        print("PREVIEW %s" % png)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    which = "all"
    out_dir = os.path.join(os.getcwd(), "assets", "art_staging", "enemies")
    preview = False
    live = False
    clip_cache = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--enemy":
            which = argv[i + 1]
            i += 1
        elif a == "--out":
            out_dir = argv[i + 1]
            i += 1
        elif a == "--preview":
            preview = True
        elif a == "--live":
            live = True
        elif a == "--clip-cache":
            clip_cache = argv[i + 1]
            i += 1
        i += 1
    names = list(RIGGED) + list(STATIC) if which == "all" else [which]
    os.makedirs(os.path.join(out_dir, "previews"), exist_ok=True)
    for name in names:
        if name in RIGGED:
            build_rigged(name, out_dir, preview, live=live, clip_cache=clip_cache)
        else:
            build_static(name, out_dir, preview)


if __name__ == "__main__":
    main()
