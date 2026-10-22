# Blender: freeze the posed MPFB meshes, build the game skeleton (knight2 names and rest orientations, barbarian joint
# positions, cm bones under an Armature scaled 0.01) and move the weights over to it.
import bpy
from mathutils import Matrix, Vector

MAP = {"Hips": "pelvis", "Spine02": "spine_01", "Spine01": "spine_02", "Spine": "spine_03", "neck": "neck_01", "Head": "head"}
for s, S in (("l", "Left"), ("r", "Right")):
    MAP.update({S + "Shoulder": "clavicle_" + s, S + "Arm": "upperarm_" + s, S + "ForeArm": "lowerarm_" + s, S + "Hand": "hand_" + s,
                S + "UpLeg": "thigh_" + s, S + "Leg": "calf_" + s, S + "Foot": "foot_" + s, S + "ToeBase": "ball_" + s})
GROUPS = {v: k for k, v in MAP.items()}
# Finger bones (Mixamo names): three joints per finger, children of the hand. The game clips do not key them, so they
# hold their rest pose, the weapon grip.
FINGERS = {}
for s, S in (("l", "Left"), ("r", "Right")):
    for f, F in (("index", "Index"), ("middle", "Middle"), ("ring", "Ring"), ("pinky", "Pinky"), ("thumb", "Thumb")):
        for i in (1, 2, 3):
            FINGERS["%s_0%d_%s" % (f, i, s)] = "%sHand%s%d" % (S, F, i)
GROUPS.update(FINGERS)

MAP_INV = {v: k for k, v in MAP.items()}
knight = bpy.data.objects["Armature"]
rig = bpy.data.objects["Barbarian.rig"]
dg = bpy.context.evaluated_depsgraph_get()
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == rig]

# 1. Freeze each mesh in the pose (shape keys mixed in), keeping UVs and vertex groups.
for o in meshes:
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = o.data
    mats = [m for m in old.materials]
    o.modifiers.clear()
    o.data = me
    me.name = o.name + "_mesh"
    if old.users == 0:
        bpy.data.meshes.remove(old)
    mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw

# 2. Joint positions from the posed MPFB rig (world, metres).
def head(n): return rig.matrix_world @ rig.pose.bones[n].head
def tail(n): return rig.matrix_world @ rig.pose.bones[n].tail
kw = knight.matrix_world.to_3x3().normalized()
krot = {b.name: (kw @ b.matrix_local.to_3x3()).normalized() for b in knight.data.bones}
pos = {k: head(v) for k, v in MAP.items()}
top = Vector((pos["Head"].x, pos["Head"].y, max(v.co.z for v in bpy.data.objects["Barbarian"].data.vertices)))
pos["head_end"] = top
face_y = min(v.co.y for v in bpy.data.objects["Barbarian"].data.vertices if abs(v.co.z - pos["Head"].z) < 0.01 and abs(v.co.x) < 0.02)
pos["headfront"] = Vector((pos["Head"].x, face_y, pos["Head"].z))
CHILD = {"Hips": "Spine02", "Spine02": "Spine01", "Spine01": "Spine", "Spine": "neck", "neck": "Head", "Head": "head_end"}
for S in ("Left", "Right"):
    CHILD.update({S + "Shoulder": S + "Arm", S + "Arm": S + "ForeArm", S + "ForeArm": S + "Hand", S + "UpLeg": S + "Leg", S + "Leg": S + "Foot", S + "Foot": S + "ToeBase"})

def length(name):
    if name in CHILD: return max((pos[CHILD[name]] - pos[name]).length, 0.02)
    if name.endswith("Hand"):
        s = "l" if name.startswith("Left") else "r"
        return max((head("middle_03_" + s) - pos[name]).length, 0.05)
    if name.endswith("ToeBase"):
        return max((tail(MAP[name]) - pos[name]).length, 0.04)
    return 0.1

# 3. New armature: same names, parents and rest rotations as knight2; cm bones, object scale 0.01 (as knight2).
old = bpy.data.objects.get("BarbarianArmature")
if old: bpy.data.objects.remove(old, do_unlink=True)
arm_data = bpy.data.armatures.new("BarbarianArmature")
arm = bpy.data.objects.new("BarbarianArmature", arm_data)
bpy.context.scene.collection.objects.link(arm)
arm.scale = (0.01, 0.01, 0.01)
bpy.context.view_layer.objects.active = arm
for o in bpy.context.selected_objects: o.select_set(False)
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
order = [b.name for b in knight.data.bones]   # parents come first
for name in order:
    kb = knight.data.bones[name]
    eb = arm_data.edit_bones.new(name)
    rot = krot[name].to_4x4()
    eb.head = Vector((0, 0, 0)); eb.tail = Vector((0, 1, 0))
    eb.matrix = Matrix.Translation(pos[name] * 100.0) @ rot
    eb.length = length(name) * 100.0
    if kb.parent:
        eb.parent = arm_data.edit_bones[kb.parent.name]
    eb.use_connect = False
# Fingers: placed and oriented as the posed MPFB finger bones (the grip), in cm.
for src, name in FINGERS.items():
    pb = rig.pose.bones[src]
    m = rig.matrix_world @ pb.matrix
    eb = arm_data.edit_bones.new(name)
    eb.head = Vector((0, 0, 0)); eb.tail = Vector((0, 1, 0))
    eb.matrix = Matrix.Translation(m.to_translation() * 100.0) @ m.to_3x3().normalized().to_4x4()
    eb.length = max(pb.length * rig.matrix_world.to_scale().x * 100.0, 0.8)
    psrc = pb.parent.name
    eb.parent = arm_data.edit_bones[FINGERS[psrc] if psrc in FINGERS else MAP_INV[psrc]]
    eb.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')

# 4. Weights: MPFB groups -> game bone names (fingers fold into the hand); everything else dropped.
for o in meshes:
    vg_new = {}
    data = {}
    for v in o.data.vertices:
        for g in v.groups:
            src = o.vertex_groups[g.group].name
            dst = GROUPS.get(src)
            if dst and g.weight > 0:
                data.setdefault(dst, {}).setdefault(v.index, 0.0)
                data[dst][v.index] += g.weight
    o.vertex_groups.clear()
    for dst, ws in data.items():
        g = o.vertex_groups.new(name=dst)
        for i, w in ws.items():
            g.add([i], min(w, 1.0), 'REPLACE')
    o.parent = arm
    o.matrix_parent_inverse = arm.matrix_world.inverted()
    m = o.modifiers.new("Armature", 'ARMATURE'); m.object = arm
result = {"meshes": [o.name for o in meshes], "bones": len(arm_data.bones),
          "groups": {o.name: len(o.vertex_groups) for o in meshes},
          "unweighted": {o.name: sum(1 for v in o.data.vertices if not v.groups) for o in meshes}}
