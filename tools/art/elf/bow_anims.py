# Blender (elf_bow_anims.blend open, through the Blender MCP): Cutter's bow clips, keyed on his 54-bone game rig with an IK control
# rig (collection BowRig: Fist_L/Fist_R fist targets that carry the hands, Elbow_*/Knee_* poles, Foot_* foot targets) and the
# elven bow held rigidly in the left fist, its string hooked to the right fingers (Nock) and the arrow tracking nock -> rest.
#
# World frame (Blender): he faces -Y (the target), +X is his left, +Z up. Clips (30 fps):
#   bow_idle     loop: standing with the bow lowered in the left hand, breathing.
#   bow_draw     from bow_idle: raise, nock (hands meet in front of the chest), push-pull to the anchor at the corner of the
#                mouth, side-on stance. Ends held at full draw. Its nock frame is NOCK_FRAME (the arrow shows from then).
#   bow_release  from full draw: the loose (string fingers open, hand slides back past the jaw), a follow-through hold, then
#                back down to bow_idle.
# Run: exec(open(r".../tools/art/elf/bow_anims.py").read()) with BUILD = True to key all clips (BUILD False only defines helpers).
import bpy, math
from mathutils import Matrix, Vector, Quaternion

FPS = 30
TH = 0.6          # the bow's belly is the fist's wrist-to-fist direction turned this far about the handle (knuckles across)
arm = bpy.data.objects["Armature"]
pb = arm.pose.bones
UP = Vector((0, 0, 1)); FWD = Vector((0, -1, 0)); LEFT = Vector((1, 0, 0))
BODY = ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head", "LeftShoulder", "RightShoulder"]
FINGERS = [s + "Hand" + f + str(i) for s in ("Left", "Right") for f in ("Thumb", "Index", "Middle", "Ring", "Pinky") for i in (1, 2, 3)]
CONTROLS = ["Fist_L", "Fist_R", "Elbow_L", "Elbow_R", "Foot_L", "Foot_R", "Knee_L", "Knee_R"]

def upd():
    bpy.context.view_layer.update()

def head(name):
    return arm.matrix_world @ pb[name].head

def reset():
    for b in pb:
        b.rotation_mode = 'QUATERNION'
        b.rotation_quaternion = Quaternion(); b.location = Vector()
    upd()

def turn(name, axis, angle):
    """Turns a bone about a world axis through its own joint, on top of its current pose."""
    b = pb[name]
    m = b.matrix.copy()   # armature space (the armature object is unrotated, scaled 0.01)
    pivot = m.translation.copy()
    r = Matrix.Rotation(angle, 4, axis)
    m = Matrix.Translation(pivot) @ r @ Matrix.Translation(-pivot) @ m
    b.matrix = m
    upd()

def frame(fwd, up):
    up = up.normalized(); fwd = (fwd - up * fwd.dot(up)).normalized()
    return Matrix((fwd, up, fwd.cross(up))).transposed()

def bow_fist(handle, up, belly):
    """Fist_L from where the bow's handle is and how the bow stands (its top `up`, its belly `belly`)."""
    up = up.normalized()
    fwd = Matrix.Rotation(-TH, 3, up) @ belly
    m = frame(fwd, up).to_4x4(); m.translation = handle
    bpy.data.objects["Fist_L"].matrix_world = m

def string_fist(fist, fwd, up):
    m = frame(fwd, up).to_4x4(); m.translation = fist
    bpy.data.objects["Fist_R"].matrix_world = m

def place(name, at):
    bpy.data.objects[name].location = at

def curl(side, amount, thumb=0.0):
    """Opens (amount < 0) or closes the fingers from their rest grip, about each joint's own X (the knuckle hinge)."""
    for f in ("Index", "Middle", "Ring", "Pinky"):
        for i in (1, 2, 3):
            pb[side + "Hand" + f + str(i)].rotation_quaternion = Quaternion((1, 0, 0), amount * (1.0 if i > 1 else 0.6))
    for i in (1, 2, 3):
        pb[side + "HandThumb" + str(i)].rotation_quaternion = Quaternion((1, 0, 0), thumb)

def key(f):
    for n in BODY + FINGERS:
        pb[n].keyframe_insert("rotation_quaternion", frame=f)
    pb["Hips"].keyframe_insert("location", frame=f)
    for n in CONTROLS:
        o = bpy.data.objects[n]
        o.keyframe_insert("location", frame=f); o.keyframe_insert("rotation_euler", frame=f)
    sn = bpy.data.objects["StringNock"]
    sn.constraints["Pull"].keyframe_insert("influence", frame=f)
    a = bpy.data.objects["ElvenArrow"]
    a.keyframe_insert("hide_viewport", frame=f); a.keyframe_insert("hide_render", frame=f)

def arrow(on, pull):
    a = bpy.data.objects["ElvenArrow"]; a.hide_viewport = not on; a.hide_render = not on
    bpy.data.objects["StringNock"].constraints["Pull"].influence = pull

FOOT_PITCH = -20.0   # degrees about his lateral axis (toes up)
FOOT_DROP = 0.068
HIP_DROP = 3.5       # cm (the armature's units)
FEET_TURN = 1.3      # radians the toes turn toward his right in the archer's stance

def stance(w, lift=0.0):
    """Feet planted, blended by w from the idle stance (the left a little forward, the right back) to the archer's: feet on
    the line to the target, toes turned toward his right (side-on). `lift` raises the stepping feet mid-step."""
    # the archer's feet: both on the line to the target, shoulder width apart, toes across it (toward his right)
    for s, a, b, yaw in (("L", Vector((0.15, -0.06, 0)), Vector((0.03, -0.19, 0)), 0.15), ("R", Vector((-0.16, 0.08, 0)), Vector((-0.03, 0.18, 0)), -0.2)):
        f = bpy.data.objects["Foot_" + s]
        rest = arm.matrix_world @ arm.data.bones[("Left" if s == "L" else "Right") + "Foot"].matrix_local
        at = a.lerp(b, w)
        # flat feet: the rig's rest foot points down (heel 6 cm up: the knight's foot angle), so each foot is pitched up
        # FOOT_PITCH to level the sole and lowered FOOT_DROP to put it on the floor (the hips drop and the knees soften for it)
        f.location = Vector((at.x, at.y, rest.translation.z - FOOT_DROP + lift))
        rot = Matrix.Rotation(yaw - FEET_TURN * w, 3, 'Z') @ Matrix.Rotation(math.radians(FOOT_PITCH), 3, 'X') @ rest.to_quaternion().to_matrix()
        f.rotation_mode = 'QUATERNION'
        f.rotation_quaternion = rot.to_quaternion()
        toes = Matrix.Rotation(yaw - FEET_TURN * w, 3, 'Z') @ Vector((0, -1, 0))
        place("Knee_" + s, at + toes * 0.6 + Vector((0, 0, 0.5)))   # knees over the toes

PREVIEW = r"C:\Users\lloyd\AppData\Local\Temp\claude\C--Users-lloyd-OneDrive-Documents-curse\e5531f6f-7d98-4aa0-85d0-23b5ac7d3b91\scratchpad\bowclips"
VIEWS = {"front": (0.9, -2.6, 1.5), "left": (2.8, -0.3, 1.5), "right": (-2.8, -0.2, 1.5), "back": (-0.6, 2.7, 1.6),
         "top": (0.3, -0.6, 3.6), "face": (-0.55, -0.75, 1.8), "fq": (-1.2, -1.9, 1.6)}

def render(tag, views=("front", "left", "right", "back", "top", "face")):
    """Preview stills of the current pose (the render camera is PreviewCam; images go to PREVIEW)."""
    import os
    os.makedirs(PREVIEW, exist_ok=True)
    sc = bpy.context.scene; cam = bpy.data.objects["PreviewCam"]
    for v in views:
        cam.location = Vector(VIEWS[v])
        look = Vector((0, -0.1, 1.72)) if v == "face" else Vector((0, -0.15, 1.15))
        cam.data.lens = 50 if v == "face" else 32
        cam.rotation_euler = (look - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(PREVIEW, "%s_%s.png" % (tag, v))
        bpy.ops.render.render(write_still=True)

AIM = Vector((0, -1, 0))
CANT = 0.12        # the bow's top leans toward his back (radians): the lower limb and string swing out in front of the chest
REST_UP = 0.05     # ArrowRest's height above the fist centre, on the bow
ARROW_SIDE = 0.022 # and how far it sits off the bow's centre line, on his left of the riser

def rest_local(name, world):
    """A rest-pose world point in the rest frame of bone `name` (unit scale)."""
    H = arm.matrix_world @ arm.data.bones[name].matrix_local
    return Matrix.LocRotScale(H.translation, H.to_quaternion(), None).inverted() @ world

def bone_frame(name):
    M = arm.matrix_world @ pb[name].matrix
    return Matrix.LocRotScale(M.translation, M.to_quaternion(), None)

MOUTH = Vector((-0.027, -0.164, 1.785))   # the right corner of his mouth in the rest pose (measured on body_skin)

def anchor():
    return bone_frame("Head") @ rest_local("Head", MOUTH)

def nock_in_fist():
    F = bpy.data.objects["Fist_R"].matrix_world
    return F.inverted() @ bpy.data.objects["Nock"].matrix_world.translation

def set_rest_side():
    """Puts ArrowRest on his left of the riser (the bow's local Y sign chosen from the bow's current world frame)."""
    bow = bpy.data.objects["ElvenBow"]
    y_world = bow.matrix_world.to_3x3().normalized() @ Vector((0, 1, 0))
    side = 1.0 if y_world.dot(LEFT) > 0 else -1.0
    bpy.data.objects["ArrowRest"].location = (-0.047, side * ARROW_SIDE, GRIP_Z + REST_UP)
    return side

def clearance():
    """Closest approach (m, negative = inside) of the bow, string, arrow and quiver to his skin, skipping the skin of the hand
    that holds each by design (bow: left fist; string and arrow: right fingers, and the arrow's rest on the left fist)."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    skin = bpy.data.objects["body_skin"].evaluated_get(dg)
    me = skin.to_mesh()
    mw = skin.matrix_world
    verts = [mw @ v.co for v in me.vertices]
    groups = {g.index: g.name for g in bpy.data.objects["body_skin"].vertex_groups}
    def dominant(v):
        best = max(v.groups, key=lambda g: g.weight, default=None)
        return groups.get(best.group, "") if best else ""
    owner = [dominant(v) for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    skin.to_mesh_clear()
    allow = {"bow": ("LeftHand",), "string": ("RightHand",), "arrow": ("RightHand", "LeftHand"), "quiver": ()}
    keep = {k: [i for i, f in enumerate(polys) if not any(owner[f[0]].startswith(a) for a in allow[k])] for k in allow}
    out = {}
    bow = bpy.data.objects["ElvenBow"]
    grip = bow.matrix_world @ Vector((-0.047, 0, 0))
    nock = bpy.data.objects["StringNock"].matrix_world.translation
    held = {"bow": [(grip, 0.07)], "string": [(nock, 0.05)], "arrow": [(nock, 0.05)], "quiver": []}   # in the hand by design
    for part, names in (("bow", ["ElvenBow"]), ("string", ["BowString"]), ("arrow", ["ElvenArrow"]), ("quiver", ["ElvenQuiver"])):
        tree = BVHTree.FromPolygons(verts, [polys[i] for i in keep[part]])
        worst = (9.0, None)
        for n in names:
            o = bpy.data.objects[n]
            if o.hide_viewport:
                continue
            e = o.evaluated_get(dg); m = e.to_mesh()
            for k, v in enumerate(m.vertices):
                if k % 2:
                    continue
                p = e.matrix_world @ v.co
                if any((p - c).length < r for c, r in held[part]):
                    continue
                hit = tree.find_nearest(p, 0.08)
                if hit[0] is None:
                    continue
                d = (p - hit[0]).length * (1 if (p - hit[0]).dot(hit[1]) >= 0 else -1)
                if d < worst[0]:
                    worst = (round(d, 3), [round(x, 2) for x in p])
            e.to_mesh_clear()
        out[part] = worst
    return out

def ring(tag, at, dist=0.45, lens=55, size=420):
    """Close-ups all round a point (8 around, from above, from below): every contact gets looked at, not only whole views."""
    import os
    sc = bpy.context.scene; cam = bpy.data.objects["PreviewCam"]
    rx, ry = sc.render.resolution_x, sc.render.resolution_y
    sc.render.resolution_x = sc.render.resolution_y = size
    cam.data.lens = lens
    spots = [("a%d" % k, Vector((math.sin(k * math.pi / 4) * dist, -math.cos(k * math.pi / 4) * dist, dist * 0.25))) for k in range(8)]
    spots += [("top", Vector((0.05, -0.05, dist))), ("under", Vector((0.08, -0.1, -dist * 0.9)))]
    for n, off in spots:
        cam.location = at + off
        cam.rotation_euler = (at - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(PREVIEW, "%s_%s.png" % (tag, n)); bpy.ops.render.render(write_still=True)
    sc.render.resolution_x, sc.render.resolution_y = rx, ry

def fist_rest(side):
    def j(n): return arm.matrix_world @ arm.data.bones[n].head_local
    c = Vector()
    for f in ("Index", "Middle", "Ring", "Pinky"):
        c += j(side + "Hand" + f + "1") + j(side + "Hand" + f + "3")
    c /= 8
    up = (j(side + "HandIndex1") - j(side + "HandPinky1")).normalized()
    fwd = c - j(side + "Hand"); fwd = (fwd - up * fwd.dot(up)).normalized()
    m = Matrix((fwd, up, fwd.cross(up))).transposed().to_4x4(); m.translation = c
    return m

def nock_offset():
    """The string's place in the right fingers (Nock), in the right fist's frame: constant, measured at rest."""
    def j(n): return arm.matrix_world @ arm.data.bones[n].head_local
    return fist_rest("Right").inverted() @ ((j("RightHandIndex3") + j("RightHandMiddle3")) / 2)

def real_fist(side):
    """Where the fist actually is (the IK may fall short of its control)."""
    H = bone_frame(side + "Hand")
    def j(n): return arm.matrix_world @ arm.data.bones[n].head_local
    G = Matrix.LocRotScale(*(arm.matrix_world @ arm.data.bones[side + "Hand"].matrix_local).decompose()[:2], None).inverted() @ fist_rest(side)
    return H @ G

def string_at(point, fwd, up=UP):
    """Fist_R placed so the string sits at `point` in his fingers."""
    m = frame(fwd, up).to_4x4()
    m.translation = point - m.to_3x3() @ nock_offset()
    bpy.data.objects["Fist_R"].matrix_world = m

def bow_at(fist, up, belly):
    bow_fist(fist, up, belly)

def side_on(w, feet=1.0):
    """The archer's stance, blended by w: hips and spine turned so the bow shoulder points at the target, head turned back to it."""
    pb["Hips"].location = Vector((0, 0, 0)); upd()
    m = pb["Hips"].matrix.copy(); m.translation.z -= HIP_DROP; pb["Hips"].matrix = m; upd()
    # the hips carry most of the turn, over the turned feet; the spine adds a little, so the body turns as one, not at the waist
    turn("Hips", UP, -0.08 * (1 - w) - 1.2 * w)
    turn("Spine02", UP, -0.1 * w); turn("Spine01", UP, -0.1 * w); turn("Spine", UP, 0.05 * (1 - w) - 0.07 * w)
    turn("neck", UP, 0.62 * w); turn("Head", UP, 0.04 * (1 - w) + 0.8 * w)

# Human joint ranges (degrees) the clips must stay inside: elbow 0-145 flexion; wrist 70 flexion / 65 extension, 20 radial / 35
# ulnar deviation; forearm twist (pronation/supination) within 85 of the rest grip.
def joint_report():
    """Elbow bend, wrist bend (split into flexion/extension and deviation) and forearm twist for both arms, from the posed bones."""
    out = {}
    for side in ("Left", "Right"):
        s, e, w = head(side + "Arm"), head(side + "ForeArm"), head(side + "Hand")
        upper, fore = (e - s).normalized(), (w - e).normalized()
        elbow = math.degrees(upper.angle(fore))
        # the hand relative to the forearm, compared with the rest pose (where the wrist is straight and untwisted)
        def rel(posed):
            f = arm.matrix_world.to_quaternion()
            if posed:
                return (pb[side + "ForeArm"].matrix.to_quaternion().inverted() @ pb[side + "Hand"].matrix.to_quaternion())
            return (arm.data.bones[side + "ForeArm"].matrix_local.to_quaternion().inverted() @ arm.data.bones[side + "Hand"].matrix_local.to_quaternion())
        d = rel(False).inverted() @ rel(True)   # in the hand's rest frame: Y runs along the hand (Blender bone axis)
        swing, twist = d.to_swing_twist('Y')
        sw = swing.to_euler('XYZ')
        # the forearm relative to the upper arm: an elbow bends about one hinge; turning about the forearm is pronation
        fr = (arm.data.bones[side + "Arm"].matrix_local.to_quaternion().inverted() @ arm.data.bones[side + "ForeArm"].matrix_local.to_quaternion())
        fp = (pb[side + "Arm"].matrix.to_quaternion().inverted() @ pb[side + "ForeArm"].matrix.to_quaternion())
        fsw, ftw = (fr.inverted() @ fp).to_swing_twist('Y')
        fe = fsw.to_euler('XYZ')
        out[side] = {"elbow_bend": round(elbow), "elbow_hinge_xz": [round(math.degrees(fe.x)), round(math.degrees(fe.z))],
                     "forearm_twist": round(math.degrees(ftw)), "wrist_flex": round(math.degrees(sw.x)), "wrist_dev": round(math.degrees(sw.z)),
                     "hand_twist": round(math.degrees(twist))}
    return out

GRIP_Z = 0.035    # the fist sits this far up the bow from its centre: in the middle of the leather wrap

def grip_matrix():
    """The bow in the rest fist frame (columns: wrist-to-fist, handle axis, side): belly turned TH about the handle, the
    handle's centre (bow local (-0.047, 0, GRIP_Z)) at the fist centre."""
    c, s = math.cos(TH), math.sin(TH)
    X = Vector((-c, 0, s)); Y = Vector((s, 0, c)); Z = Vector((0, 1, 0))
    B = Matrix((X, Y, Z)).transposed().to_4x4(); B.translation = X * 0.047 - Z * GRIP_Z
    return B

def attach_bow():
    """Holds the bow in the LeftHand bone (Child Of, bound in the rest pose) at grip_matrix()."""
    bow = bpy.data.objects["ElvenBow"]
    arm.data.pose_position = 'REST'; upd()
    for cn in list(bow.constraints): bow.constraints.remove(cn)
    bow.parent = None
    bow.matrix_world = fist_rest("Left") @ grip_matrix(); upd()
    co = bow.constraints.new('CHILD_OF'); co.name = "Grip"; co.target = arm; co.subtarget = "LeftHand"; upd()
    co.inverse_matrix = (arm.matrix_world @ pb["LeftHand"].matrix).inverted()
    arm.data.pose_position = 'POSE'; upd()

def place_quiver():
    q = bpy.data.objects["ElvenQuiver"]
    arm.data.pose_position = 'REST'; upd()
    q.matrix_world = Matrix.Translation((0.03, 0.135, 1.2)) @ Matrix.Rotation(0.2, 4, 'Y') @ Matrix.Rotation(math.pi, 4, 'Z')
    arm.data.pose_position = 'POSE'; upd()

def cant_up(amount=1.0):
    up = Matrix.Rotation(CANT * amount, 3, AIM) @ UP
    return up if up.x >= 0 else Matrix.Rotation(-CANT * amount, 3, AIM) @ UP   # top toward his back (+X)

def full_draw_fist(A, up):
    """The bow fist where the straight bow arm reaches along the arrow line from the anchor A: the longest draw the arm makes."""
    S = head("LeftArm"); D = None
    for i in range(50):
        d = 0.5 + i * 0.01
        fist = A + AIM * d - up * REST_UP - LEFT * ARROW_SIDE
        bow_at(fist, up, AIM); place("Elbow_L", S + Vector((0.35, -0.15, -0.25))); upd()
        if (real_fist("Left").translation - fist).length < 0.004:
            D = d
    return A + AIM * D - up * REST_UP - LEFT * ARROW_SIDE, D

# The anchor: the string just under the right corner of the mouth, the hooked fingers upright against the jaw (the
# Mediterranean draw: index above the arrow). Elbow out behind at shoulder height. The hand's roll is shared between the
# forearm and the wrist after the bake (share_twist), as the radius does, so neither wrings.
ANCHOR_SHIFT = Vector((-0.045, 0.0, -0.015))
DRAW_ELBOW = Vector((-0.05, 0.45, 0.05))   # from the right shoulder

def draw_up():
    return UP

def pose_full():
    freeze_arms(False); reset(); stance(1.0); side_on(1.0)
    A = anchor() + ANCHOR_SHIFT; up = cant_up()
    fist, D = full_draw_fist(A, up)
    bow_at(fist, up, AIM)
    place("Elbow_R", head("RightArm") + DRAW_ELBOW)
    string_at(A, AIM, draw_up())
    arrow(True, 1.0); set_rest_side(); upd()
    return A, D

def hand_clearance(side="Right"):
    """The hand's own skin against the rest of him (its forearm excluded): min signed distance (m) and where."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    src = bpy.data.objects["body_skin"]; skin = src.evaluated_get(dg); me = skin.to_mesh()
    groups = {g.index: g.name for g in src.vertex_groups}
    own = []
    for v in me.vertices:
        g = max(v.groups, key=lambda g: g.weight, default=None)
        own.append(groups.get(g.group, "") if g else "")
    verts = [skin.matrix_world @ v.co for v in me.vertices]
    mine = lambda n: n.startswith(side + "Hand") or n.startswith(side + "ForeArm")
    polys = [tuple(p.vertices) for p in me.polygons if not any(mine(own[i]) for i in p.vertices)]
    pts = [verts[i] for i, n in enumerate(own) if n.startswith(side + "Hand")]
    skin.to_mesh_clear()
    tree = BVHTree.FromPolygons(verts, polys)
    worst = (9.0, None)
    for k, p in enumerate(pts):
        if k % 2:
            continue
        hit = tree.find_nearest(p, 0.06)
        if hit[0] is None:
            continue
        d = (p - hit[0]).length * (1 if (p - hit[0]).dot(hit[1]) >= 0 else -1)
        if d < worst[0]:
            worst = (round(d, 3), [round(x, 2) for x in p])
    return worst

def share_twist(side, share=0.55):
    """The hand's roll against its forearm (relative to the rest pose) moved partly into the forearm, the hand keeping its
    world pose: real forearms turn along their length. Works on the FK pose (constraints muted)."""
    hand_world = pb[side + "Hand"].matrix.copy()
    tw = joint_report()[side]["hand_twist"]
    fa = pb[side + "ForeArm"]
    fa.rotation_quaternion = fa.rotation_quaternion @ Quaternion((0, 1, 0), math.radians(tw * share))
    upd()
    pb[side + "Hand"].matrix = hand_world
    upd()

def freeze_arms(on=True):
    """FK preview of the constrained pose: the arms keep where the IK put them, constraints muted (on=False unmutes)."""
    names = ("LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot",
             "RightUpLeg", "RightLeg", "RightFoot")
    if on:
        mats = {n: pb[n].matrix.copy() for n in names}
    for n in names:
        for c in pb[n].constraints:
            c.mute = on
    upd()
    if on:
        for n in names:
            pb[n].matrix = mats[n]; upd()

# ---- key poses -------------------------------------------------------------------------------------------------------------
def pose_idle(breath=0.0):
    freeze_arms(False); reset(); stance(0.0); side_on(0.0)
    turn("Spine", Vector((1, 0, 0)), -0.025 * breath); turn("neck", Vector((1, 0, 0)), 0.02 * breath)
    m = frame(Vector((0.05, 0.0, -1.0)), Vector((0, -0.94, -0.34))).to_4x4(); m.translation = Vector((0.27, -0.06, 0.93 + 0.005 * breath))
    bpy.data.objects["Fist_L"].matrix_world = m
    place("Elbow_L", Vector((0.3, 0.35, 1.3)))
    string_fist(Vector((-0.27, -0.02, 0.93 + 0.005 * breath)), Vector((0, -0.2, -1)), Vector((0, -1, 0)))
    place("Elbow_R", Vector((-0.3, 0.35, 1.3)))
    curl("Right", 0.0); arrow(False, 0.0); upd()

def string_rest_point():
    """Where the braced string crosses the arrow's height: the nocking point at rest."""
    bow = bpy.data.objects["ElvenBow"]
    return bow.matrix_world @ Vector((0.065, 0, GRIP_Z + REST_UP))

def _fist_world(name):
    return bpy.data.objects[name].matrix_world.copy()

def pose_between(pose_a, pose_b, t, lift_out=Vector(), t_rot=None):
    """An in-between whose fists sit between two key poses (orientations slerped, so the wrists hold their set as the arms move),
    pushed out by `lift_out` (clear of the body); stance and turn between the two."""
    pose_a(); A = {n: _fist_world(n) for n in ("Fist_L", "Fist_R")}
    pose_b(); B = {n: _fist_world(n) for n in ("Fist_L", "Fist_R")}
    for n in ("Fist_L", "Fist_R"):
        qa, qb = A[n].to_quaternion(), B[n].to_quaternion()
        m = qa.slerp(qb, t if t_rot is None else t_rot).to_matrix().to_4x4()
        m.translation = A[n].translation.lerp(B[n].translation, t) + (lift_out if n == "Fist_L" else lift_out * 0.5)
        bpy.data.objects[n].matrix_world = m
    upd()

def pose_upright_low():
    """The first move of the draw: the elbow bends and the forearm comes forward, standing the bow upright in front of the hip
    (held like a torch: the wrist straight, belly forward)."""
    pose_idle()
    keep_r = _fist_world("Fist_R")
    freeze_arms(False); reset(); stance(0.15); side_on(0.1)
    bow_at(Vector((0.22, -0.3, 1.2)), UP, AIM)
    bpy.data.objects["Fist_R"].matrix_world = keep_r
    place("Elbow_L", head("LeftArm") + Vector((0.2, 0.15, -0.5)))
    place("Elbow_R", Vector((-0.3, 0.35, 1.3)))
    arrow(False, 0.0); upd()

def pose_raise():
    """The bow comes up and out in front, the string hand on its way to the string; arrow not yet out."""
    pose_between(pose_upright_low, pose_nock, 0.5, Vector((0.05, -0.12, 0.0)))   # coming up in front, already upright
    freeze_arms(False)
    # body halfway, the poses above reset it: set stance and turn between, keep the fists
    keep = {n: _fist_world(n) for n in ("Fist_L", "Fist_R")}
    reset(); stance(0.35, lift=0.02); side_on(0.3)
    for n, m in keep.items():
        bpy.data.objects[n].matrix_world = m
    place("Elbow_L", head("LeftArm") + Vector((0.3, 0.1, -0.35)))
    place("Elbow_R", head("RightArm") + Vector((-0.4, 0.0, -0.4)))
    arrow(False, 0.0); upd()

def pose_nock():
    freeze_arms(False); reset(); stance(0.75); side_on(0.6)
    up = cant_up(0.6)
    # in front of his chest (which faces his right, -X, in the turned stance), not out past the bow shoulder: the string hand
    # reaches straight forward to the string, its elbow down and out in front, never across or into the body
    fist = head("Spine") + AIM * 0.42 - LEFT * 0.22 + UP * 0.06
    bow_at(fist, up, AIM)
    place("Elbow_L", head("LeftArm") + Vector((0.2, -0.1, -0.4)))
    upd()
    string_at(string_rest_point(), AIM, UP)
    place("Elbow_R", head("RightArm") + Vector((-0.45, -0.05, -0.3)))
    curl("Right", 0.0); arrow(True, 1.0); set_rest_side(); upd()

def pose_pull():
    """Mid-draw: the string hand halfway to the anchor, a little out from the jaw; the bow arm almost out."""
    pose_between(pose_nock, pose_full, 0.6)
    keep = {n: _fist_world(n) for n in ("Fist_L", "Fist_R")}
    freeze_arms(False); reset(); stance(0.9); side_on(0.85)
    for n, m in keep.items():
        bpy.data.objects[n].matrix_world = m
    m = bpy.data.objects["Fist_R"].matrix_world.copy(); m.translation -= LEFT * 0.065
    bpy.data.objects["Fist_R"].matrix_world = m
    place("Elbow_L", head("LeftArm") + Vector((0.35, -0.1, -0.28)))
    place("Elbow_R", head("RightArm") + Vector((-0.35, 0.25, -0.12)))   # swinging round the outside, from in front to behind
    arrow(True, 1.0); upd()

def pose_lower():
    """Coming down after the shot: the bow swung out in front and down, clear of the legs."""
    pose_between(lambda: pose_loose(1.0), pose_idle, 0.5, Vector((0.12, -0.2, 0.05)))
    keep = {n: _fist_world(n) for n in ("Fist_L", "Fist_R")}
    freeze_arms(False); reset(); stance(0.5); side_on(0.45)
    for n, m in keep.items():
        bpy.data.objects[n].matrix_world = m
    place("Elbow_L", head("LeftArm") + Vector((0.3, 0.1, -0.35)))
    place("Elbow_R", head("RightArm") + Vector((-0.2, 0.25, -0.4)))
    arrow(False, 0.0); upd()

def pose_loose(follow):
    """After the loose: the string fingers open and the hand slides back along the jaw (follow 0..1); the bow arm holds."""
    A, D = pose_full()
    fist = real_fist("Left").translation
    up = cant_up()
    bow_at(fist + AIM * 0.02 * follow - UP * 0.03 * follow, up, AIM)
    back = A - AIM * (0.03 + 0.05 * follow) - LEFT * (0.1 + 0.08 * follow) + UP * 0.01 * follow   # out past the cheek, clear of the ear
    string_at(back, AIM, UP)
    curl("Right", -0.45 - 0.15 * follow, thumb=-0.2)
    arrow(False, 0.0); upd()
    return A

JOINTS = ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg", "neck"]

def stretch(radius=0.09):
    """Texture stretch near each joint: for the skin's edges within `radius` of the joint, how far their posed length strays
    from their rest length (worst and 95th percentile, as a fraction: 0.3 = 30% stretched or squashed)."""
    dg = bpy.context.evaluated_depsgraph_get()
    src = bpy.data.objects["body_skin"]
    rest = [src.matrix_world @ v.co for v in src.data.vertices]
    e = src.evaluated_get(dg); me = e.to_mesh(); posed = [e.matrix_world @ v.co for v in me.vertices]; e.to_mesh_clear()
    edges = [tuple(ed.vertices) for ed in src.data.edges]
    out = {}
    for j in JOINTS:
        c = arm.matrix_world @ arm.data.bones[j].head_local
        devs = []
        for a, b in edges:
            if (rest[a] - c).length < radius:
                lr = (rest[a] - rest[b]).length
                if lr > 1e-5:
                    devs.append(abs((posed[a] - posed[b]).length / lr - 1.0))
        devs.sort()
        out[j] = [round(devs[-1], 2), round(devs[int(len(devs) * 0.95)], 2)] if devs else None
    return out

def set_twist():
    """Each forearm twist bone (tools/art/hero/joint_quality.py) takes its hand's roll against the forearm, so the turn spreads
    down the forearm's skin. On the FK pose (after freeze_arms)."""
    for side in ("Left", "Right"):
        t = pb.get(side + "ForeArmTwist")
        if t is None:
            continue
        t.rotation_mode = 'QUATERNION'
        t.rotation_quaternion = Quaternion()
        upd()
        t.rotation_quaternion = Quaternion((0, 1, 0), math.radians(joint_report()[side]["hand_twist"]))
        u = pb.get(side + "ArmTwist")
        if u is not None:
            # the upper arm's roll against its collarbone, compared with the rest pose, taken back at the shoulder
            u.rotation_mode = 'QUATERNION'
            rel = lambda a, b: a.inverted() @ b
            r0 = rel(arm.data.bones[side + "Shoulder"].matrix_local.to_quaternion(), arm.data.bones[side + "Arm"].matrix_local.to_quaternion())
            r1 = rel(pb[side + "Shoulder"].matrix.to_quaternion(), pb[side + "Arm"].matrix.to_quaternion())
            sw, tw = (r0.inverted() @ r1).to_swing_twist('Y')
            u.rotation_quaternion = Quaternion((0, 1, 0), -tw)
    upd()

def fk(pose_fn, *a):
    """A key pose, frozen to FK with the twist bones set."""
    r = pose_fn(*a)
    freeze_arms(True); set_twist()
    return r


HELPERS = {"LeftShoulderHelp": ("LeftShoulder", "LeftArm"), "RightShoulderHelp": ("RightShoulder", "RightArm"),
           "LeftElbowHelp": ("LeftArm", "LeftForeArm"), "RightElbowHelp": ("RightArm", "RightForeArm"), "NeckHelp": ("Spine", "neck")}

def drive_helpers():
    """Twist bones (set_twist) and the half-joint helpers: each helper turns half of its child's bend (swing, no roll; the neck
    helper also half its turn) against the parent, measured from the rest pose. The same rule runs in the game (game/joint_helpers.gd)."""
    set_twist()
    for name, (parent, child) in HELPERS.items():
        h = pb.get(name)
        if h is None:
            continue
        h.rotation_mode = 'QUATERNION'
        rest = arm.data.bones[parent].matrix_local.to_quaternion().inverted() @ arm.data.bones[child].matrix_local.to_quaternion()
        now = pb[parent].matrix.to_quaternion().inverted() @ pb[child].matrix.to_quaternion()
        sw, tw = (rest.inverted() @ now).to_swing_twist('Y')
        h.rotation_quaternion = Quaternion().slerp(rest.inverted() @ now if name == "NeckHelp" else sw, 0.5)   # the neck shares its turn too
    upd()

def fk(pose_fn, *a):
    r = pose_fn(*a)
    freeze_arms(True); drive_helpers()
    return r

# ---- clips -----------------------------------------------------------------------------------------------------------------
CLIPS = {
    "bow_draw": [(0, pose_idle, ()), (2, pose_upright_low, ()), (4, pose_raise, ()), (7, pose_nock, ()), (12, pose_pull, ()), (17, pose_full, ()),
                 (19, pose_full, ())],
    "bow_release": [(0, pose_full, ()), (2, pose_loose, (0.0,)), (7, pose_loose, (1.0,)), (11, pose_lower, ()), (16, pose_idle, ())],
    "bow_idle": [(0, pose_idle, (0.0,)), (30, pose_idle, (1.0,)), (60, pose_idle, (0.0,))],
}
NOCK_FRAME = 7       # bow_draw: the arrow is on the string from here (the game shows its arrow from this share of the draw)
STATE_OBJECTS = ["ElvenArrow", "StringNock"]

def _clear_anim(o):
    if o.animation_data:
        o.animation_data.action = None

def key_controls(f, actions):
    for n in CONTROLS:
        o = bpy.data.objects[n]
        o.rotation_mode = 'QUATERNION'
        q = o.matrix_world.to_quaternion() if o.parent is None else o.matrix_basis.to_quaternion()
        prev = actions.setdefault(n + "_q", None)
        if prev is not None and q.dot(prev) < 0:
            q = -q
        actions[n + "_q"] = q
        o.rotation_quaternion = q
        o.keyframe_insert("location", frame=f); o.keyframe_insert("rotation_quaternion", frame=f)
    for n in BODY + FINGERS:
        pb[n].keyframe_insert("rotation_quaternion", frame=f)
    pb["Hips"].keyframe_insert("location", frame=f)
    sn = bpy.data.objects["StringNock"]; sn.constraints["Pull"].keyframe_insert("influence", frame=f)
    a = bpy.data.objects["ElvenArrow"]; a.keyframe_insert("hide_viewport", frame=f); a.keyframe_insert("hide_render", frame=f)

def build_clip(name):
    """Keys the clip's poses on the control rig, then bakes every frame to plain bone rotations (action `name`), with the twist
    bones and joint helpers driven. The controls keep their keys in actions named ctrl_<name>, for previewing the rig."""
    sc = bpy.context.scene
    keys = CLIPS[name]
    end = keys[-1][0]
    for n in CONTROLS + STATE_OBJECTS:
        _clear_anim(bpy.data.objects[n])
    freeze_arms(False)
    arm.animation_data_create()
    work = bpy.data.actions.get("keys_" + name)
    if work: bpy.data.actions.remove(work)
    arm.animation_data.action = bpy.data.actions.new("keys_" + name)
    memo = {}
    for f, fn, args in keys:
        sc.frame_set(f)
        fn(*args)
        key_controls(f, memo)
    for n in CONTROLS + STATE_OBJECTS:
        o = bpy.data.objects[n]
        if o.animation_data and o.animation_data.action:
            o.animation_data.action.name = "ctrl_%s_%s" % (name, n)
    # sample the constrained pose on every frame
    names = [b.name for b in arm.data.bones]
    order = [b.name for b in sorted(arm.data.bones, key=lambda b: len(b.parent_recursive))]   # parents before children
    frames = {}
    for f in range(0, end + 1):
        sc.frame_set(f)
        frames[f] = {n: pb[n].matrix.copy() for n in order}
    # bake
    out = bpy.data.actions.get(name)
    if out: bpy.data.actions.remove(out)
    arm.animation_data.action = bpy.data.actions.new(name)
    freeze_arms(True)
    for f in range(0, end + 1):
        sc.frame_set(f)
        for n in order:
            pb[n].matrix = frames[f][n]
            upd()   # a child's matrix is read against its parent's: refresh before the next bone
        drive_helpers()
        for n in order:
            pb[n].rotation_mode = 'QUATERNION'
            pb[n].keyframe_insert("rotation_quaternion", frame=f)
        pb["Hips"].keyframe_insert("location", frame=f)
    act = arm.animation_data.action
    act.use_fake_user = True
    sc.frame_start, sc.frame_end = 0, end
    return {"frames": end + 1}

def check_clip(name):
    """Per frame of a baked clip: prop clearance, both hands against the body, and the joints (with the worst values listed)."""
    sc = bpy.context.scene
    arm.animation_data.action = bpy.data.actions[name]
    for n in CONTROLS + STATE_OBJECTS:
        o = bpy.data.objects[n]
        a = bpy.data.actions.get("ctrl_%s_%s" % (name, n))
        if a:
            o.animation_data_create(); o.animation_data.action = a
    rows = []
    end = int(bpy.data.actions[name].frame_range[1])
    for f in range(0, end + 1):
        sc.frame_set(f)
        c = clearance(); j = joint_report()
        rows.append({"f": f, "bow": c["bow"][0], "string": c["string"][0], "arrow": c["arrow"][0], "quiver": c["quiver"][0],
                     "hR": hand_clearance("Right")[0], "hL": hand_clearance("Left")[0],
                     "wristR": [j["Right"]["wrist_flex"], j["Right"]["wrist_dev"]], "wristL": [j["Left"]["wrist_flex"], j["Left"]["wrist_dev"]],
                     "elbowR": j["Right"]["elbow_bend"], "elbowL": j["Left"]["elbow_bend"]})
    return rows

def render_clip(name, views=("fq", "left"), size=(480, 600)):
    import os
    sc = bpy.context.scene; cam = bpy.data.objects["PreviewCam"]
    sc.render.resolution_x, sc.render.resolution_y = size
    end = int(bpy.data.actions[name].frame_range[1])
    for v in views:
        cam.location = Vector(VIEWS[v]); cam.data.lens = 32
        look = Vector((0, -0.15, 1.15))
        cam.rotation_euler = (look - cam.location).to_track_quat('-Z', 'Y').to_euler()
        for f in range(0, end + 1):
            sc.frame_set(f)
            sc.render.filepath = os.path.join(PREVIEW, "clip_%s_%s_%03d.png" % (name, v, f))
            bpy.ops.render.render(write_still=True)

def sequence(parts=(("bow_idle", 0, 24), ("bow_draw", 0, 19), ("bow_draw", 19, 19), ("bow_draw", 19, 19), ("bow_draw", 19, 19),
                    ("bow_release", 0, 16), ("bow_idle", 0, 20))):
    """The firing played through on the timeline (NLA strips back to back, the controls' actions alongside so the string and
    arrow follow), for watching in Blender and rendering. Returns the frame list [(clip, frame)]."""
    sc = bpy.context.scene
    objs = [arm] + [bpy.data.objects[n] for n in CONTROLS + STATE_OBJECTS]
    for o in objs:
        o.animation_data_create()
        o.animation_data.action = None
        for t in list(o.animation_data.nla_tracks):
            o.animation_data.nla_tracks.remove(t)
    start = 0
    frames = []
    for i, (clip, a, b) in enumerate(parts):
        for o in objs:
            act = bpy.data.actions.get(clip if o == arm else "ctrl_%s_%s" % (clip, o.name))
            if act is None:
                continue
            tr = o.animation_data.nla_tracks.new(); tr.name = "seq%d" % i
            st = tr.strips.new(clip, start, act)
            st.action_frame_start, st.action_frame_end = a, max(b, a + 0.01)
            st.frame_end = start + (b - a) + 1
            st.extrapolation = 'NOTHING'
        frames += [(clip, f) for f in range(a, b + 1)]
        start += (b - a) + 1
    sc.frame_start, sc.frame_end = 0, start - 1
    freeze_arms(True)
    return frames

def arm_clearance(side):
    """The whole arm's skin (upper arm, forearm, elbow, wrist, hand) against the torso, head and legs: min signed distance (m)."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    src = bpy.data.objects["body_skin"]; skin = src.evaluated_get(dg); me = skin.to_mesh()
    groups = {g.index: g.name for g in src.vertex_groups}
    own = [groups.get(max(v.groups, key=lambda g: g.weight).group, "") if len(v.groups) else "" for v in me.vertices]
    verts = [skin.matrix_world @ v.co for v in me.vertices]
    mine = lambda n: n.startswith(side) and not n.startswith(side + "UpLeg") and not n.startswith(side + "Leg") and not n.startswith(side + "Foot") \
        and not n.startswith(side + "Toe")
    polys = [tuple(p.vertices) for p in me.polygons if not any(mine(own[i]) for i in p.vertices)]
    sh = head(side + "Arm")
    pts = [verts[i] for i, n in enumerate(own) if mine(n) and not n.startswith(side + "Shoulder") and (verts[i] - sh).length > 0.14]   # the armpit joins by design
    skin.to_mesh_clear()
    tree = BVHTree.FromPolygons(verts, polys)
    worst = (9.0, None)
    for k, p in enumerate(pts):
        if k % 3:
            continue
        hit = tree.find_nearest(p, 0.08)
        if hit[0] is None:
            continue
        d = (p - hit[0]).length * (1 if (p - hit[0]).dot(hit[1]) >= 0 else -1)
        if d < worst[0]:
            worst = (round(d, 3), [round(x, 2) for x in p])
    return worst

def preview_action(parts=(("bow_idle", 0, 24), ("bow_draw", 0, 19), ("bow_draw", 19, 19), ("bow_draw", 19, 19), ("bow_draw", 19, 19),
                          ("bow_release", 0, 16), ("bow_idle", 0, 20))):
    """One continuous action, preview_fire, copied frame by frame from the clips (and the string/arrow states alongside), for
    playing the whole shot in Blender's viewport and rendering it."""
    sc = bpy.context.scene
    objs = [bpy.data.objects[n] for n in STATE_OBJECTS]
    for o in [arm] + [bpy.data.objects[n] for n in CONTROLS] + objs:
        o.animation_data_create()
        for t in list(o.animation_data.nla_tracks):
            o.animation_data.nla_tracks.remove(t)
    freeze_arms(True)
    samples = []
    for clip, a, b in parts:
        for f in range(a, b + 1):
            arm.animation_data.action = bpy.data.actions[clip]
            for o in objs:
                o.animation_data.action = bpy.data.actions.get("ctrl_%s_%s" % (clip, o.name))
            sc.frame_set(f)
            samples.append(({n: pb[n].rotation_quaternion.copy() for n in pb.keys()}, pb["Hips"].location.copy(),
                            bpy.data.objects["StringNock"].constraints["Pull"].influence, bpy.data.objects["ElvenArrow"].hide_render))
    for n in ("preview_fire", "preview_fire_string", "preview_fire_arrow"):
        if bpy.data.actions.get(n): bpy.data.actions.remove(bpy.data.actions[n])
    arm.animation_data.action = bpy.data.actions.new("preview_fire")
    sn, ar = bpy.data.objects["StringNock"], bpy.data.objects["ElvenArrow"]
    sn.animation_data.action = bpy.data.actions.new("preview_fire_string")
    ar.animation_data.action = bpy.data.actions.new("preview_fire_arrow")
    for i, (rots, hips, pull, hidden) in enumerate(samples):
        for n, q in rots.items():
            pb[n].rotation_quaternion = q; pb[n].keyframe_insert("rotation_quaternion", frame=i)
        pb["Hips"].location = hips; pb["Hips"].keyframe_insert("location", frame=i)
        sn.constraints["Pull"].influence = pull; sn.constraints["Pull"].keyframe_insert("influence", frame=i)
        ar.hide_render = hidden; ar.hide_viewport = hidden
        ar.keyframe_insert("hide_render", frame=i); ar.keyframe_insert("hide_viewport", frame=i)
    sc.frame_start, sc.frame_end = 0, len(samples) - 1
    sc.render.fps = FPS
    return len(samples)
