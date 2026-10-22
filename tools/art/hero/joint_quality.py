# Shared by every playable character (Blender, the game rig open: "Armature" + its skinned meshes). Two fixes for the joints that
# linear skinning folds into points and stretches the texture over:
#   1. Forearm twist bones, LeftForeArmTwist / RightForeArmTwist: children of the forearm, lying along it. The forearm's skin is
#      shared between the forearm and its twist bone on a ramp from the elbow (all forearm) to the wrist (all twist), so a hand
#      turned about the forearm (pronation) is spread down the forearm the way the radius turns, not wrung at the wrist. Clips key
#      the twist bone with the hand's roll (bow_anims.py: set_twist); a clip that does not key it leaves it at rest, as before.
#      LeftArmTwist / RightArmTwist do the same for the upper arm at the shoulder end: keyed with the arm's roll taken back, so
#      the shoulder does not wring when the arm turns about its length (bow_anims.py: set_twist).
#   2. Joint weights re-blended: inside a sphere round each big joint (shoulder, elbow, wrist, hip, knee, neck) every deform weight
#      is smoothed with its neighbours a few times and renormalised, so a bend is shared by many rows of the mesh instead of folding
#      a few.
# Run with exec() in Blender; idempotent (the twist bones are rebuilt, the weights smoothed from the current ones: run once per
# freshly built rig). Optional globals: MESHES (names, default every mesh with an Armature modifier on "Armature").
import bpy, math
from mathutils import Vector

arm = bpy.data.objects["Armature"]
meshes = [bpy.data.objects[n] for n in globals().get("MESHES", [])] or \
    [o for o in bpy.data.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == arm for m in o.modifiers)]
# half-joint helper -> (parent bone, child bone, radius of the skin it takes over round the joint, m)
HELPERS = {"LeftShoulderHelp": ("LeftShoulder", "LeftArm", 0.09), "RightShoulderHelp": ("RightShoulder", "RightArm", 0.09),
           "LeftElbowHelp": ("LeftArm", "LeftForeArm", 0.07), "RightElbowHelp": ("RightArm", "RightForeArm", 0.07),
           "NeckHelp": ("Spine", "neck", 0.05)}
ZONES = {"Arm": 0.11, "ForeArm": 0.08, "Hand": 0.05, "UpLeg": 0.11, "Leg": 0.09}
SMOOTH_STEPS = 6

def world(p):
    return arm.matrix_world @ p

# 1. twist bones
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
for side in ("Left", "Right"):
    name = side + "ForeArmTwist"
    if name in eb:
        eb.remove(eb[name])
    fa, hand = eb[side + "ForeArm"], eb[side + "Hand"]
    t = eb.new(name)
    t.head = fa.head.lerp(hand.head, 0.5)
    t.tail = t.head + (hand.head - fa.head).normalized() * (hand.head - fa.head).length * 0.4
    t.roll = fa.roll
    t.align_roll(fa.z_axis)
    t.parent = fa
    t.use_connect = False
    t.use_deform = True
    # the upper arm's twist bone sits near the shoulder: it takes back the arm's roll there, so the shoulder is not wrung
    name = side + "ArmTwist"
    if name in eb:
        eb.remove(eb[name])
    ua, fa = eb[side + "Arm"], eb[side + "ForeArm"]
    t = eb.new(name)
    t.head = ua.head.lerp(fa.head, 0.25)
    t.tail = t.head + (fa.head - ua.head) * 0.3
    t.align_roll(ua.z_axis)
    t.parent = ua
    t.use_connect = False
    t.use_deform = True
# half-joint helpers: at the joint, rest-aligned with the child bone, parented to the parent bone; turned half the child's bend
# (driven: game/joint_helpers.gd in Godot, bow_anims.drive_helpers in Blender), they keep a bent joint round, not pointed.
for name, (parent, child, r) in HELPERS.items():
    if name in eb:
        eb.remove(eb[name])
    c = eb[child]
    h = eb.new(name)
    h.head = c.head.copy(); h.tail = c.head + (c.tail - c.head).normalized() * 3.0
    h.align_roll(c.z_axis)
    h.parent = eb[parent]; h.use_connect = False; h.use_deform = True
bpy.ops.object.mode_set(mode='OBJECT')

def joint(name):
    return world(arm.data.bones[name].head_local)

for o in meshes:
    me = o.data
    groups = {g.name: g for g in o.vertex_groups}
    for side in ("Left", "Right"):
        fa = groups.get(side + "ForeArm")
        if fa is None:
            continue
        tw = groups.get(side + "ForeArmTwist") or o.vertex_groups.new(name=side + "ForeArmTwist")
        e, w = joint(side + "ForeArm"), joint(side + "Hand")
        axis = w - e
        for v in me.vertices:
            for g in v.groups:
                if g.group == fa.index and g.weight > 0:
                    t = max(0.0, min(1.0, (o.matrix_world @ v.co - e).dot(axis) / axis.length_squared))
                    r = t * t * (3 - 2 * t)
                    r = max(0.0, min(1.0, (r - 0.1) / 0.85))
                    wt = g.weight
                    fa.add([v.index], wt * (1 - r), 'REPLACE')
                    tw.add([v.index], wt * r, 'REPLACE')
                    break

        # the upper arm: shoulder end all twist bone, fading to all upper arm by its middle
        ua = groups.get(side + "Arm")
        utw = groups.get(side + "ArmTwist") or o.vertex_groups.new(name=side + "ArmTwist")
        s0, e0 = joint(side + "Arm"), joint(side + "ForeArm")
        axis = e0 - s0
        for v in me.vertices:
            for g in v.groups:
                if ua is not None and g.group == ua.index and g.weight > 0:
                    t = max(0.0, min(1.0, (o.matrix_world @ v.co - s0).dot(axis) / axis.length_squared))
                    r = 1.0 - max(0.0, min(1.0, t / 0.6))
                    r = r * r * (3 - 2 * r)
                    wt = g.weight
                    ua.add([v.index], wt * (1 - r), 'REPLACE')
                    utw.add([v.index], wt * r, 'REPLACE')
                    break

# helper weights: round each joint, a share (a soft ball, all at the joint centre) of the parent's and child's weights
for o in meshes:
    me = o.data
    for name, (parent, child, r) in HELPERS.items():
        src = [o.vertex_groups[n] for n in (parent, child, child + "Twist", parent + "Twist") if n in o.vertex_groups]
        if not src:
            continue
        hg = o.vertex_groups.get(name) or o.vertex_groups.new(name=name)
        c = joint(child)
        axis = (world(arm.data.bones[child].tail_local) - c).normalized()
        idx = {g.index for g in src}
        for v in me.vertices:
            p = o.matrix_world @ v.co - c
            d = abs(p.dot(axis))   # along the limb: the whole ring of skin round the joint takes part
            if d >= r or p.length > r * 2.5:
                continue
            k = 0.85 * (1 - (d / r) ** 2) ** 2
            moved = 0.0
            for g in v.groups:
                if g.group in idx and g.weight > 0:
                    o.vertex_groups[g.group].add([v.index], g.weight * (1 - k), 'REPLACE')
                    moved += g.weight * k
            if moved > 0:
                hg.add([v.index], moved, 'ADD')

# 2. smooth the deform weights inside the joint spheres
deform = {b.name for b in arm.data.bones if b.use_deform}
for o in meshes:
    me = o.data
    names = {g.index: g.name for g in o.vertex_groups if g.name in deform}
    centres = []
    for side in ("Left", "Right"):
        for part, r in ZONES.items():
            centres.append((joint(side + part), r))
    centres.append((joint("neck"), 0.08))
    zone = [i for i, v in enumerate(me.vertices) if any((o.matrix_world @ v.co - c).length < r for c, r in centres)]
    zset = set(zone)
    nbr = {i: [] for i in zone}
    for e in me.edges:
        a, b = e.vertices
        if a in zset: nbr[a].append(b)
        if b in zset: nbr[b].append(a)
    W = [{g.group: g.weight for g in v.groups if g.group in names} for v in me.vertices]
    for _ in range(SMOOTH_STEPS):
        new = {}
        for i in zone:
            acc = dict((k, 0.5 * x) for k, x in W[i].items())
            n = nbr[i]
            for j in n:
                for k, x in W[j].items():
                    acc[k] = acc.get(k, 0.0) + 0.5 * x / len(n)
            s = sum(acc.values())
            new[i] = {k: x / s for k, x in acc.items() if x / s > 0.002} if s > 0 else W[i]
        for i, d in new.items():
            W[i] = d
    for i in zone:
        for k in names:
            o.vertex_groups[k].remove([i])
        s = sum(W[i].values())
        for k, x in W[i].items():
            o.vertex_groups[k].add([i], x / s, 'REPLACE')
result = {"twist_bones": [b.name for b in arm.data.bones if b.name.endswith("Twist")], "meshes": [o.name for o in meshes]}

# 3. at most four bones per vertex (the game's skinning, and glTF's), strongest kept, renormalised: what Blender shows is what
# the game draws
for o in meshes:
    me = o.data
    for v in me.vertices:
        gs = sorted([(g.group, g.weight) for g in v.groups if o.vertex_groups[g.group].name in deform and g.weight > 0], key=lambda t: -t[1])
        if len(gs) <= 4 and abs(sum(w for _, w in gs) - 1.0) < 1e-3:
            continue
        keep = gs[:4]
        s = sum(w for _, w in keep) or 1.0
        for gi, _ in gs[4:]:
            o.vertex_groups[gi].remove([v.index])
        for gi, w in keep:
            o.vertex_groups[gi].add([v.index], w / s, 'REPLACE')
result = {"twist_bones": [b.name for b in arm.data.bones if b.name.endswith("Twist")], "helpers": list(HELPERS), "meshes": [o.name for o in meshes]}
