# Blender: pose the MPFB game_engine rig so every mapped bone points the way the knight2 bone does, and close the hands.
import bpy, math
from mathutils import Matrix, Vector, Quaternion

MAP = {"Hips": "pelvis", "Spine02": "spine_01", "Spine01": "spine_02", "Spine": "spine_03", "neck": "neck_01", "Head": "head"}
for s, S in (("l", "Left"), ("r", "Right")):
    MAP.update({S + "Shoulder": "clavicle_" + s, S + "Arm": "upperarm_" + s, S + "ForeArm": "lowerarm_" + s, S + "Hand": "hand_" + s,
                S + "UpLeg": "thigh_" + s, S + "Leg": "calf_" + s, S + "Foot": "foot_" + s, S + "ToeBase": "ball_" + s})
ALIGN = [k for k in MAP if k not in ("Hips", "Spine02", "Spine01", "Spine", "neck", "Head")]

knight = bpy.data.objects["Armature"]
rig = bpy.data.objects["Barbarian.rig"]
kdir = {b.name: (knight.matrix_world.to_3x3().normalized() @ b.matrix_local.to_3x3() @ Vector((0, 1, 0))).normalized() for b in knight.data.bones}
# The knight's hand bone runs along the hand; the MPFB hand bone is a stub, so align the hand by wrist -> middle knuckle.
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='POSE')
for pb in rig.pose.bones:
    pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = Quaternion(); pb.location = Vector(); pb.scale = Vector((1, 1, 1))
bpy.context.view_layer.update()

def world_dir(pb, tip=None):
    mw = rig.matrix_world
    h = mw @ pb.head
    t = mw @ (rig.pose.bones[tip].head if tip else pb.tail)
    return (t - h).normalized()

def aim(kname):
    pb = rig.pose.bones[MAP[kname]]
    tip = MAP[kname].replace("hand_", "middle_01_") if kname.endswith("Hand") else None
    cur = world_dir(pb, tip); want = kdir[kname]
    q = cur.rotation_difference(want)
    m = pb.matrix.copy()
    loc = m.to_translation()
    pb.matrix = Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ m
    bpy.context.view_layer.update()

order = ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
         "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
for k in order:
    aim(k)

# Close the hands into a grip around a weapon handle: curl each finger joint about its local X axis.
CURL = {"index": (55, 70, 45), "middle": (60, 75, 45), "ring": (65, 75, 45), "pinky": (70, 75, 45), "thumb": (10, 35, 30)}
SIGN = float(__import__("os").environ.get("CURL_SIGN", "1"))
for s in "lr":
    for f, angs in CURL.items():
        for i, a in enumerate(angs, start=1):
            pb = rig.pose.bones["%s_0%d_%s" % (f, i, s)]
            pb.rotation_quaternion = Quaternion(Vector((1, 0, 0)), math.radians(a) * SIGN)
bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode='OBJECT')
result = {"err_deg": {k: round(math.degrees(world_dir(rig.pose.bones[MAP[k]], MAP[k].replace("hand_", "middle_01_") if k.endswith("Hand") else None).angle(kdir[k])), 2) for k in order}}
