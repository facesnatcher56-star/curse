"""Retarget the modular kit (built by modular_build.py on the Knight rig) onto the game's Meshy skeleton and
export one GLB per equipment piece.

Run:  blender.exe -b assets/art_staging/knight/source/Curse_Modular.blend -P tools/art/modular_export.py -- <out_dir>

Why: the game's clips (Player.CLIPS, ~36 of them) are authored on the Meshy skeleton of assets/models/knight2.
Meshes must therefore be bound to *that* skeleton. Each kit mesh is rest-pose-retargeted with linear blend
skinning from the Knight rest pose to the Meshy rest pose (per-bone rotation + length scale), its weights are
renamed to Meshy bone names, and it is written in the Meshy skeleton's own space (centimetres, Godot axes after
glTF conversion) so the runtime can bind it with the character's real bind poses (game/modular_appearance.gd).

Rigid props (WPN_*, authored in prop space) are exported as plain meshes.
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)

# Meshy skeleton global rest heads, Godot skeleton space, centimetres (dumped by tools/art/dump_skel.gd)
MESHY_GODOT = {
    "Hips": (1.197261, 101.9191, -5.366863), "Spine02": (1.065562, 113.535, -4.982733),
    "Spine01": (0.933864, 125.1509, -4.598602), "Spine": (0.798174, 137.1188, -4.202831),
    "neck": (0.594853, 144.8044, -3.950482), "Head": (0.399087, 152.2045, -3.70751),
    "head_end": (0.594306, 177.2868, -2.722329),
    "LeftShoulder": (4.945942, 142.3891, -3.963056), "LeftArm": (22.3503, 142.3891, -11.17054),
    "LeftForeArm": (31.929, 121.6352, -12.40734), "LeftHand": (45.89786, 116.4468, 3.799914),
    "RightShoulder": (-3.91436, 142.7882, -4.087701), "RightArm": (-21.95121, 142.7882, -11.22029),
    "RightForeArm": (-30.73174, 122.0342, -12.33682), "RightHand": (-45.49877, 117.245, 1.217739),
    "LeftUpLeg": (10.62302, 91.97318, -5.366864), "LeftLeg": (14.76728, 52.18955, -5.290439),
    "LeftFoot": (16.4112, 14.56327, -10.2628), "LeftToeBase": (20.14185, 3.999096, -1.419589),
    "RightUpLeg": (-9.254478, 91.89337, -5.366864), "RightLeg": (-13.96889, 51.79047, -5.290422),
    "RightFoot": (-15.64213, 14.53111, -10.39352), "RightToeBase": (-19.7995, 4.096107, -1.387869),
}
PARENT = {"Spine02": "Hips", "Spine01": "Spine02", "Spine": "Spine01", "neck": "Spine", "Head": "neck",
          "head_end": "Head", "LeftShoulder": "Spine", "LeftArm": "LeftShoulder", "LeftForeArm": "LeftArm",
          "LeftHand": "LeftForeArm", "RightShoulder": "Spine", "RightArm": "RightShoulder",
          "RightForeArm": "RightArm", "RightHand": "RightForeArm", "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg",
          "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot", "RightUpLeg": "Hips", "RightLeg": "RightUpLeg",
          "RightFoot": "RightLeg", "RightToeBase": "RightFoot"}

def blender_cm(g):
    """Godot skeleton space (x, y up, z forward) -> Blender frame (x, -z, y) in cm; the glTF exporter maps it back."""
    return Vector((g[0], -g[2], g[1]))

MP = {k: blender_cm(v) for k, v in MESHY_GODOT.items()}

def hand_end(side):
    h, f = MP[side + "Hand"], MP[side + "ForeArm"]
    return h + (h - f).normalized() * 11.0

def toe_end(side):
    t, f = MP[side + "ToeBase"], MP[side + "Foot"]
    d = t - f; d.z = 0
    return t + d.normalized() * 10.0

# kit bone -> (meshy head point, meshy tail point)
def seg_map():
    m = {"Hips": (MP["Hips"], MP["Spine02"]), "Spine": (MP["Spine02"], MP["Spine01"]),
         "Chest": (MP["Spine01"], MP["neck"]), "Neck": (MP["neck"], MP["Head"]), "Head": (MP["Head"], MP["head_end"])}
    for s, S in (("Left", "Left"), ("Right", "Right")):
        m[s + "Shoulder"] = (MP[S + "Shoulder"], MP[S + "Arm"])
        m[s + "UpperArm"] = (MP[S + "Arm"], MP[S + "ForeArm"])
        m[s + "LowerArm"] = (MP[S + "ForeArm"], MP[S + "Hand"])
        m[s + "Hand"] = (MP[S + "Hand"], hand_end(S))
        m[s + "UpperLeg"] = (MP[S + "UpLeg"], MP[S + "Leg"])
        m[s + "LowerLeg"] = (MP[S + "Leg"], MP[S + "Foot"])
        m[s + "Foot"] = (MP[S + "Foot"], MP[S + "ToeBase"])
        m[s + "Toes"] = (MP[S + "ToeBase"], toe_end(S))
    return m

NAME_MAP = {"Hips": "Hips", "Spine": "Spine02", "Neck": "neck", "Head": "Head"}
for s in ("Left", "Right"):
    NAME_MAP.update({s + "Shoulder": s + "Shoulder", s + "UpperArm": s + "Arm", s + "LowerArm": s + "ForeArm",
                     s + "Hand": s + "Hand", s + "UpperLeg": s + "UpLeg", s + "LowerLeg": s + "Leg",
                     s + "Foot": s + "Foot", s + "Toes": s + "ToeBase"})

rig = bpy.data.objects["Character_Rig"]
SEG = seg_map()
LAT = 0.95  # Meshy is 1.77 m, the kit 1.88 m: lateral scale

def kit_seg(bone):
    bone = bone.replace("HandProp", "Hand")
    b = rig.data.bones[bone]
    return Vector(b.head_local), Vector(b.tail_local)

XF = {}
for bone, (mh, mt) in SEG.items():
    kh, kt = kit_seg(bone)
    kd, md = kt - kh, mt - mh
    XF[bone] = (kh, kd.normalized(), kd.length, mh, md.normalized(), md.length)
for s_ in ("Left", "Right"):   # the shield's prop bone follows the hand segment but is skinned to the forearm
    XF[s_ + "HandProp"] = XF[s_ + "Hand"]
    NAME_MAP_EXTRA = None

def apply_bone_cm(bone, p):
    """p in kit metres -> Meshy rest space in centimetres (axial part scaled by the segment length ratio)."""
    kh, kdir, kl, mh, mdir, ml = XF[bone]
    q = p - kh
    a = q.dot(kdir)
    lat = q - kdir * a
    R = kdir.rotation_difference(mdir)
    return mh + R @ (kdir * (a * ml / kl) + lat * (LAT * 100.0))

NAME_MAP["LeftHandProp"] = "LeftForeArm"
NAME_MAP["RightHandProp"] = "RightForeArm"

def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

def retarget_weights(v, obj):
    """-> {kit bone: weight}"""
    out = {}
    for g in v.groups:
        n = obj.vertex_groups[g.group].name
        if g.weight > 0:
            out[n] = out.get(n, 0) + g.weight
    s = sum(out.values()) or 1.0
    return {k: w / s for k, w in out.items()}

def new_pos(p, w):
    r = Vector((0, 0, 0))
    for bone, wt in w.items():
        r += apply_bone_cm(bone, p) * wt
    return r

def meshy_weights(w, p):
    out = {}
    for bone, wt in w.items():
        if bone == "Chest":
            t = smooth(0.3, 0.9, (p.z - 1.22) / 0.28)
            out["Spine01"] = out.get("Spine01", 0) + wt * (1 - t)
            out["Spine"] = out.get("Spine", 0) + wt * t
        elif bone in NAME_MAP:
            out[NAME_MAP[bone]] = out.get(NAME_MAP[bone], 0) + wt
    return out

# ---------------------------------------------------------------- the Meshy armature used for skinning/export
def make_armature():
    arm = bpy.data.armatures.new("MeshyRig")
    ao = bpy.data.objects.new("MeshyRig", arm)
    bpy.context.scene.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode='EDIT')
    kids = {}
    for k, p in PARENT.items():
        kids.setdefault(p, []).append(k)
    ebs = {}
    for name, pos in MP.items():
        eb = arm.edit_bones.new(name)
        eb.head = pos
        if name in kids:
            eb.tail = MP[kids[name][0]] if name != "Hips" else MP["Spine02"]
        else:
            eb.tail = pos + Vector((0, 0, 4)) if name != "head_end" else pos + Vector((0, 0, 3))
        if (eb.tail - eb.head).length < 0.5:
            eb.tail = eb.head + Vector((0, 0, 2))
        ebs[name] = eb
    for k, p in PARENT.items():
        ebs[k].parent = ebs[p]
    bpy.ops.object.mode_set(mode='OBJECT')
    return ao

meshy = make_armature()

def select_only(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

def export(objs, name):
    select_only(objs)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format='GLB', use_selection=True,
                              export_animations=False, export_skins=True, export_apply=False, export_yup=True,
                              export_materials='EXPORT', export_normals=True)

report = []
skinned = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == rig and
           not o.name.startswith(("WPN_",))]
skinned = [o for o in skinned if o.name != "WPN_Sword"]
for o in skinned:
    src = o.data
    me = bpy.data.meshes.new(o.name + "_meshy")
    verts, groups = [], []
    for v in src.vertices:
        w = retarget_weights(v, o)
        p = Vector(v.co)
        verts.append(new_pos(p, w))
        groups.append(meshy_weights(w, p))
    me.from_pydata(verts, [], [tuple(pl.vertices) for pl in src.polygons])
    for i, pl in enumerate(src.polygons):
        me.polygons[i].material_index = pl.material_index
        me.polygons[i].use_smooth = pl.use_smooth
    for m in src.materials:
        me.materials.append(m)
    me.update()
    no = bpy.data.objects.new(o.name, me)
    bpy.context.scene.collection.objects.link(no)
    no.parent = meshy
    for bn in MP:
        no.vertex_groups.new(name=bn)
    for i, gw in enumerate(groups):
        for bn, wt in gw.items():
            no.vertex_groups[bn].add([i], wt, 'REPLACE')
    mod = no.modifiers.new("Armature", "ARMATURE"); mod.object = meshy
    # hide the kit original so it is not exported with the selection
    o.hide_set(True)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    export([no, meshy], o.name.lower())
    report.append((o.name, tris))
    no.hide_set(True)

# rigid props: exported as plain meshes in prop space (see modular_build.py)
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.name == "WPN_Bow"]:
    o.parent = None
    for g in list(o.vertex_groups):
        o.vertex_groups.remove(g)
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    export([o], o.name.lower())
    report.append((o.name, tris))

for n, t in report:
    print("PIECE", n, t)
print("RETARGET_EXPORT_DONE")
