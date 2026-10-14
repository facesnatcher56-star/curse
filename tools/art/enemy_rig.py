"""Shared rig, skinning, clip and mesh-kit helpers for staging enemies (Blender 5.x, headless).

Skeleton convention = Lane A knight (Curse_Knight_Experiment/scripts/build_knight.py):
  22 bones (Root, Hips, Spine, Chest, Neck, Head, and per side Shoulder/UpperArm/LowerArm/Hand/
  UpperLeg/LowerLeg/Foot/Toes) + LeftHandProp and RightHandProp = 24 bones total.
  Character faces -Y, +X is the character's LEFT, ground at Z = 0, metres.
  Bones use align_roll(FWD) for limbs and align_roll(UP) for feet; pitch about local X bends forward.

Compatibility decision (owner review, option a: keep independent, live path unchanged):
  - Live enemies load data/enemies/*.tres model_path -> assets/models/<name>/ (rigged.glb + anims.res),
    via enemy.gd (_build_model, fallback zombie folder). Nothing references assets/art_staging/enemies.
  - Live enemy rigs (zombie, zombie_brute, ghoul) and the player knight2 share one 24-joint Mixamo-style
    skeleton: Hips, Spine, Spine01, Spine02, neck, Head, Left/RightShoulder, Left/RightArm, Left/RightForeArm,
    Left/RightHand, Left/RightUpLeg, Left/RightLeg, Left/RightFoot, Left/RightToeBase.
  - This knight-convention rig matches 9 of its 24 names exactly (Hips, Spine, Head, Shoulders, Hands, Feet).
    The other 15 differ (UpperArm/LowerArm/UpperLeg/LowerLeg/Toes per side, Neck, Chest, Root, props), and the
    live rig has Spine01/Spine02 where this one has Spine and Chest, so clips do not transfer by name.
  - Live clip tracks key on those Mixamo names (anims.res). Required clips idle, walk, attack, hit and death
    exist here. Optional clips (run, scream, charge_run, throw, cast) are requested only through has_clip(), so
    their absence falls back to walk or idle rather than failing.
  - Retargeting (option b) would mean renaming bones, adding the Spine01/Spine02 split and re-authoring the
    optional clips. That waits for the owner to approve a deliberate enemy swap.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

FWD = Vector((0, -1, 0))
UP = Vector((0, 0, 1))
DEFORM_SKIP = {"Root", "LeftHandProp", "RightHandProp"}
CONNECT = {"Spine", "Chest", "Neck", "Head", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand",
           "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "LeftToes", "RightToes"}


def V(x, y, z):
    return Vector((x, y, z))


def mir(v):
    return Vector((-v.x, v.y, v.z))


def knight_joints():
    """Joint positions copied from the knight build (Lane A), so the convention stays identical."""
    sho = V(0.205, 0.01, 1.465)
    elb = sho + V(0.7071, 0.0, -0.7071) * 0.29 + V(0, 0.012, 0)
    fa = V(0.68, -0.12, -0.72).normalized()
    wri = elb + fa * 0.255
    return {
        "root": V(0, 0, 0), "hips": V(0, 0, 0.98), "spine": V(0, 0, 1.08), "chest": V(0, 0.005, 1.22),
        "neck": V(0, 0, 1.50), "head": V(0, -0.005, 1.62), "head_end": V(0, -0.005, 1.86),
        "clav": V(0.035, 0, 1.47), "clav_end": V(0.185, 0.01, 1.485), "sho": sho, "elb": elb, "wri": wri,
        "hand_end": wri + fa * 0.10, "hip": V(0.105, 0, 0.94), "knee": V(0.115, -0.018, 0.52),
        "ank": V(0.125, 0.025, 0.105), "ball": V(0.128, -0.10, 0.028), "toe": V(0.128, -0.205, 0.028),
    }


def zombie_joints():
    """Same bones, hunched: chest and head carried forward, arms reaching forward, knees soft."""
    return {
        "root": V(0, 0, 0), "hips": V(0, 0.01, 0.97), "spine": V(0, -0.02, 1.08), "chest": V(0, -0.09, 1.22),
        "neck": V(0, -0.15, 1.45), "head": V(0, -0.23, 1.52), "head_end": V(0, -0.26, 1.71),
        "clav": V(0.035, -0.02, 1.42), "clav_end": V(0.17, -0.04, 1.43), "sho": V(0.19, -0.05, 1.38),
        "elb": V(0.22, -0.27, 1.15), "wri": V(0.24, -0.50, 0.95), "hand_end": V(0.245, -0.60, 0.88),
        "hip": V(0.105, 0.0, 0.92), "knee": V(0.115, -0.07, 0.50), "ank": V(0.125, 0.0, 0.09),
        "ball": V(0.128, -0.11, 0.028), "toe": V(0.128, -0.21, 0.028),
    }


# Live rig bone Z axes (world, from the live zombie GLB via Blender import). Used by build_armature(live=True)
# so each staging bone takes the same local frame as the live bone, which fixes the 180-degree roll mismatch.
LIVE_Z = {
    "Hips": (0.0000, -0.9992, -0.0411),
    "Spine02": (0.0000, -0.9992, -0.0411),
    "Spine01": (0.0000, -0.9992, -0.0411),
    "neck": (0.0000, -0.9962, -0.0873),
    "Head": (-0.0588, -0.9934, -0.0989),
    "LeftShoulder": (0.0002, -0.0003, 1.0000),
    "LeftArm": (0.5629, -0.8050, 0.1876),
    "LeftForeArm": (-0.1112, -0.5057, -0.8555),
    "LeftHand": (-0.2605, -0.6680, -0.6971),
    "RightShoulder": (-0.0002, -0.0003, 1.0000),
    "RightArm": (-0.5924, -0.7846, 0.1828),
    "RightForeArm": (0.1333, -0.5431, -0.8290),
    "RightHand": (-0.0005, -0.5887, -0.8084),
    "LeftUpLeg": (0.1778, 0.9792, -0.0974),
    "LeftLeg": (0.0694, 0.9538, 0.2922),
    "LeftFoot": (0.6358, 0.7621, -0.1224),
    "LeftToeBase": (-0.0000, 0.0000, 1.0000),
    "RightUpLeg": (-0.1714, 0.9803, -0.0985),
    "RightLeg": (-0.0762, 0.9530, 0.2933),
    "RightFoot": (-0.6725, 0.7371, -0.0669),
    "RightToeBase": (0.0000, -0.0000, 1.0000),
}


# Live Mixamo-style joint names (zombie, zombie_brute, ghoul and knight2 rigs). Applied only when live=True;
# the authoring convention stays the default.
LIVE_SUFFIX = {"UpperArm": "Arm", "LowerArm": "ForeArm", "UpperLeg": "UpLeg", "LowerLeg": "Leg", "Toes": "ToeBase"}
LIVE_EXACT = {"Spine": "Spine01", "Chest": "Spine02", "Neck": "neck"}


def live_name(name):
    if name in LIVE_EXACT:
        return LIVE_EXACT[name]
    for key in sorted(LIVE_SUFFIX, key=len, reverse=True):
        if name.endswith(key):
            return name[: -len(key)] + LIVE_SUFFIX[key]
    return name


def bone_rows(J, live=False):
    """(name, head, tail, parent, roll_axis) for the bones. live=True renames to the live joint names and
    drops Root and the two prop bones (21 bones)."""
    rows = _authoring_rows(J)
    if not live:
        return rows
    out = []
    for name, h, t, parent, roll in rows:
        if name in DEFORM_SKIP:
            continue
        out.append((live_name(name), h, t, live_name(parent) if parent and parent not in DEFORM_SKIP else None, roll))
    return out


def _authoring_rows(J):
    """(name, head, tail, parent, roll_axis) for all 24 bones, mirrored right side from the left."""
    rows = [
        ("Root", J["root"], J["root"] + V(0, 0, 0.25), None, FWD),
        ("Hips", J["hips"], J["spine"], "Root", FWD),
        ("Spine", J["spine"], J["chest"], "Hips", FWD),
        ("Chest", J["chest"], J["neck"], "Spine", FWD),
        ("Neck", J["neck"], J["head"], "Chest", FWD),
        ("Head", J["head"], J["head_end"], "Neck", FWD),
    ]
    for side, f in (("Left", lambda v: v), ("Right", mir)):
        rows += [
            (side + "Shoulder", f(J["clav"]), f(J["clav_end"]), "Chest", FWD),
            (side + "UpperArm", f(J["sho"]), f(J["elb"]), side + "Shoulder", FWD),
            (side + "LowerArm", f(J["elb"]), f(J["wri"]), side + "UpperArm", FWD),
            (side + "Hand", f(J["wri"]), f(J["hand_end"]), side + "LowerArm", FWD),
            (side + "UpperLeg", f(J["hip"]), f(J["knee"]), "Hips", FWD),
            (side + "LowerLeg", f(J["knee"]), f(J["ank"]), side + "UpperLeg", FWD),
            (side + "Foot", f(J["ank"]), f(J["ball"]), side + "LowerLeg", UP),
            (side + "Toes", f(J["ball"]), f(J["toe"]), side + "Foot", UP),
        ]
    for side, f in (("Left", lambda v: v), ("Right", mir)):
        rows.append((side + "HandProp", f(J["hand_end"]), f(J["hand_end"]) + UP * 0.15, side + "Hand", FWD))
    return rows


def build_armature(coll, J, name, live=False):
    arm_data = bpy.data.armatures.new(name + "_Rig")
    arm = bpy.data.objects.new("Armature", arm_data)
    coll.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    rows = bone_rows(J, live=live)
    connect = {live_name(c) for c in CONNECT} if live else CONNECT
    for bname, h, t, parent, roll_axis in rows:
        b = eb.new(bname)
        b.head, b.tail = h, t
        b.align_roll(Vector(LIVE_Z[bname]) if live and bname in LIVE_Z else roll_axis)
        if parent:
            b.parent = eb[parent]
            b.use_connect = bname in connect
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_data.display_type = "OCTAHEDRAL"
    arm.show_in_front = True
    return arm, rows


def deform_rows(rows):
    return [r for r in rows if r[0] not in DEFORM_SKIP]


def _seg_dist(p, a, b):
    ab = b - a
    denom = ab.dot(ab)
    t = 0.0 if denom < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / denom))
    return (p - (a + ab * t)).length


def skin_object(obj, rows, rigid=None):
    """Weights a mesh object to the armature.  rigid = bone name gives every vertex weight 1 on that bone
    (used for hand-held props); otherwise each vertex blends its three nearest bone segments."""
    names = [r[0] for r in deform_rows(rows)]
    groups = {n: obj.vertex_groups.new(name=n) for n in names}
    if rigid:
        if rigid not in groups:
            groups[rigid] = obj.vertex_groups.new(name=rigid)
        groups[rigid].add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        return
    segs = {r[0]: (r[1], r[2]) for r in deform_rows(rows)}
    mw = obj.matrix_world
    for v in obj.data.vertices:
        co = mw @ v.co
        d = sorted(((_seg_dist(co, a, b), n) for n, (a, b) in segs.items()), key=lambda x: x[0])[:3]
        raw = [(n, 1.0 / (dist + 0.03) ** 4) for dist, n in d]
        total = sum(w for _, w in raw)
        for n, w in raw:
            groups[n].add([v.index], w / total, "REPLACE")


def attach_armature(obj, arm):
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def bone_fwd_sign(arm, bname):
    """+1 when a positive pitch about this bone's local X moves its tail toward the front (-Y). Per bone,
    because the live rig and the authoring rig do not share local frames."""
    m = arm.data.bones[bname].matrix_local.to_3x3()
    d = m @ V(0, 1, 0)
    nd = m @ Matrix.Rotation(0.2, 3, "X") @ m.inverted() @ d
    return 1.0 if (nd.y - d.y) < 0 else -1.0


def fwd_sign(arm, live=False):
    """+1 when a positive pitch about the bone's local X swings the limb toward the front (-Y)."""
    bone = arm.data.bones[live_name("LeftUpperLeg") if live else "LeftUpperLeg"]
    m = bone.matrix_local.to_3x3()
    d = m @ V(0, 1, 0)
    rot = Matrix.Rotation(0.2, 3, "X")
    nd = m @ rot @ m.inverted() @ d
    return 1.0 if (nd.y - d.y) < 0 else -1.0


# --------------------------------------------------------------------------- mesh kit
def tube(builder, key, pts, rx, ry=None, sides=8, cap0=True, cap1=True, jitter=0.0, seed=1, bone=None):
    """Lofted tube through points.  rx/ry (scalar or per point) are radii along the lateral and
    front axes of each ring.  jitter adds deterministic irregularity (torn cloth, dents, lumps)."""
    n = len(pts)
    rx = [rx] * n if not isinstance(rx, (list, tuple)) else list(rx)
    ry = rx if ry is None else ([ry] * n if not isinstance(ry, (list, tuple)) else list(ry))
    rng = random.Random(seed)
    me = bpy.data.meshes.new(key)
    bm = bmesh.new()
    rings = []
    for i in range(n):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
        T = t.normalized()
        ref = V(1, 0, 0) if abs(T.x) < 0.9 else V(0, 1, 0)
        U = (ref - T * ref.dot(T)).normalized()
        W = T.cross(U)
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            j1 = 1.0 + jitter * (rng.random() - 0.5)
            j2 = 1.0 + jitter * (rng.random() - 0.5)
            p = pts[i] + U * (rx[i] * j1 * math.cos(a)) + W * (ry[i] * j2 * math.sin(a))
            ring.append(bm.verts.new(p))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]])
    for idx, cap in ((0, cap0), (n - 1, cap1)):
        if not cap:
            continue
        c = bm.verts.new(pts[idx])
        ring = rings[idx]
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new([c, ring[k], ring[k2]] if idx == 0 else [c, ring[k2], ring[k]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.update()
    obj = bpy.data.objects.new(key, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def blob(builder, key, center, radii, sub=2, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=1, location=center, rotation=rot)
    o = bpy.context.active_object
    o.scale = radii
    return o


# --------------------------------------------------------------------------- clips
DEFORM = ["Hips", "Spine", "Chest", "Neck", "Head",
          "LeftShoulder", "RightShoulder",
          "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand",
          "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot",
          "LeftToes", "RightToes"]


def write_clip(arm, name, keys, loop, signs, live=False):
    """keys: list of (frame, {bone: (rx, ry, rz)}) with rx a forward pitch in radians (sign applied here).
    Missing bones keep their last value.  Authoring bone names are mapped to live names when live=True."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    state = {b: (0.0, 0.0, 0.0) for b in DEFORM}
    for frame, upd in keys:
        for bname, vals in upd.items():
            rx, ry, rz = vals
            state[bname] = (rx * signs.get(bname, 1.0), ry, rz)
        for bname in DEFORM:
            pb = arm.pose.bones[live_name(bname) if live else bname]
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = state[bname]
            pb.keyframe_insert("rotation_euler", frame=frame)
    act["kn_loop"] = bool(loop)
    arm.animation_data.action = None
    return act


def make_clips(arm, style, live=False):
    """Five clips shared by all rigged enemies, tuned per enemy by `style`.
    Pitch values are forward-positive; write_clip converts with the calibrated sign."""
    s = style
    st, aw, lean, sway = s["stride"], s["arm_swing"], s["lean"], s["sway"]
    kb = s["knee_bend"]
    clips = []

    # idle: slow breathing, head shift
    idle = [
        (1, {"Chest": (0.0, 0, 0), "Head": (0.0, 0, 0)}),
        (25, {"Chest": (0.035, 0, 0.02), "Head": (-0.05, 0, -0.04), "LeftUpperArm": (-0.04, 0, 0.0),
              "RightUpperArm": (-0.04, 0, 0.0)}),
        (49, {"Chest": (0.0, 0, 0), "Head": (0.0, 0, 0)}),
    ]
    clips.append(("idle", idle, True))

    # walk: 24-frame loop, opposite arm and leg, knee flexes on the swing
    walk = []
    for f in range(1, 26, 3):
        u = (f - 1) / 24.0 * 2 * math.pi
        L, R = math.sin(u), math.sin(u + math.pi)
        kL = -kb * (0.5 - 0.5 * math.cos(u))
        kR = -kb * (0.5 - 0.5 * math.cos(u + math.pi))
        walk.append((f, {
            "LeftUpperLeg": (st * L, 0, 0), "RightUpperLeg": (st * R, 0, 0),
            "LeftLowerLeg": (kL, 0, 0), "RightLowerLeg": (kR, 0, 0),
            "LeftUpperArm": (aw * R, 0, 0), "RightUpperArm": (aw * L, 0, 0),
            "LeftLowerArm": (-0.25, 0, 0), "RightLowerArm": (-0.25, 0, 0),
            "Hips": (0.02 * math.cos(2 * u), 0, sway * math.sin(u)),
            "Chest": (lean + 0.04 * math.cos(2 * u), 0, -sway * math.sin(u) * 0.5),
            "Head": (-lean * 0.4, 0, 0),
        }))
    clips.append(("walk", walk, True))

    # attack: wind up, drive both arms forward, hold, recover (one-shot)
    clips.append(("attack", [
        (1, {}),
        (10, {"LeftUpperArm": (-1.1, 0, 0), "RightUpperArm": (-1.1, 0, 0), "LeftLowerArm": (-0.4, 0, 0),
              "RightLowerArm": (-0.4, 0, 0), "Chest": (-0.2, 0, 0), "Head": (-0.15, 0, 0)}),
        (17, {"LeftUpperArm": (1.35, 0, 0), "RightUpperArm": (1.35, 0, 0), "LeftLowerArm": (0.1, 0, 0),
              "RightLowerArm": (0.1, 0, 0), "Chest": (0.35, 0, 0), "Head": (0.25, 0, 0), "Hips": (0.1, 0, 0)}),
        (22, {"LeftUpperArm": (1.35, 0, 0), "RightUpperArm": (1.35, 0, 0), "LeftLowerArm": (0.1, 0, 0),
              "RightLowerArm": (0.1, 0, 0), "Chest": (0.35, 0, 0), "Head": (0.25, 0, 0), "Hips": (0.1, 0, 0)}),
        (32, {"LeftUpperArm": (0, 0, 0), "RightUpperArm": (0, 0, 0), "LeftLowerArm": (0, 0, 0),
              "RightLowerArm": (0, 0, 0), "Chest": (0, 0, 0), "Head": (0, 0, 0), "Hips": (0, 0, 0)}),
    ], False))

    # hit: flinch back and out, then recover (one-shot, 40 frames at 24 fps = 1.67 s, matching the live hit length)
    clips.append(("hit", [
        (1, {}),
        (5, {"Chest": (-0.30, 0, 0), "Head": (-0.30, 0, 0.10), "LeftUpperArm": (-0.20, 0, 0.35),
             "RightUpperArm": (-0.20, 0, -0.35), "Hips": (-0.05, 0, 0.04)}),
        (16, {"Chest": (-0.10, 0, 0), "Head": (-0.12, 0, 0), "LeftUpperArm": (0, 0, 0.10),
              "RightUpperArm": (0, 0, -0.10), "Hips": (0, 0, 0)}),
        (29, {"Chest": (-0.03, 0, 0), "Head": (-0.03, 0, 0), "LeftUpperArm": (0, 0, 0.02),
              "RightUpperArm": (0, 0, -0.02)}),
        (40, {"Chest": (0, 0, 0), "Head": (0, 0, 0), "LeftUpperArm": (0, 0, 0), "RightUpperArm": (0, 0, 0)}),
    ], False))

    # death: knees buckle and the torso and head fall backward over 85 frames at 24 fps (3.5 s, matching the live
    # death length). Chain rotations add up along Hips, Spine, Chest and Head; they stay near 80 degrees so
    # the body lands on its back instead of folding over.
    clips.append(("death", [
        (1, {}),
        (21, {"Chest": (-0.15, 0, 0), "Head": (-0.10, 0, 0), "Hips": (-0.08, 0, 0),
              "LeftLowerLeg": (-0.35, 0, 0), "RightLowerLeg": (-0.35, 0, 0),
              "LeftUpperArm": (-0.40, 0, 0.20), "RightUpperArm": (-0.40, 0, -0.20)}),
        (48, {"Chest": (-0.45, 0, 0), "Head": (-0.20, 0, 0), "Hips": (-0.25, 0, 0), "Spine": (-0.15, 0, 0),
              "LeftLowerLeg": (-0.70, 0, 0), "RightLowerLeg": (-0.70, 0, 0),
              "LeftUpperArm": (-0.90, 0, 0.45), "RightUpperArm": (-0.90, 0, -0.45)}),
        (85, {"Chest": (-0.55, 0, 0), "Head": (-0.25, 0, 0), "Hips": (-0.35, 0, 0), "Spine": (-0.20, 0, 0),
               "LeftLowerLeg": (-0.85, 0, 0), "RightLowerLeg": (-0.85, 0, 0),
               "LeftUpperArm": (-1.10, 0, 0.55), "RightUpperArm": (-1.10, 0, -0.55)}),
    ], False))

    signs = {b: bone_fwd_sign(arm, live_name(b) if live else b) for b in DEFORM}
    sign = fwd_sign(arm, live)
    out = {}
    for name, keys, loop in clips:
        write_clip(arm, name, keys, loop, signs, live)
        out[name] = bpy.data.actions[name]
    return out, sign
