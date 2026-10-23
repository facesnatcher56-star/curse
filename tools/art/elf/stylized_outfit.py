# Blender (a Cutter rig file open: "Armature" + body_skin): a stylized ranger outfit, every piece cut from his own body surface so
# it fits him and moves with the same skin weights (same skeleton, same clips). Cloth and leather cover every big joint (hood
# and shoulder mantle, long-sleeved tunic, bracers, gloves, belt, trousers, boots), so a bent elbow or shoulder never shows
# stretched skin. Body faces fully under the clothes are removed, so nothing pokes through. Flat, bold colours.
# Run with exec(); rebuilds the pieces each time.
import bpy, bmesh, math
from mathutils import Vector

arm = bpy.data.objects["Armature"]
body = bpy.data.objects["body_skin"]
COL = {  # name -> (base colour as sRGB, roughness): deep forest greens and worn browns
    "tunic": ((0.20, 0.38, 0.16), 0.85), "mantle": ((0.10, 0.22, 0.10), 0.9), "cowl": ((0.10, 0.22, 0.10), 0.9),
    "trousers": ((0.24, 0.17, 0.11), 0.85), "boots": ((0.36, 0.21, 0.11), 0.65), "gloves": ((0.30, 0.18, 0.09), 0.65),
    "bracers": ((0.48, 0.30, 0.14), 0.55), "belt": ((0.18, 0.10, 0.05), 0.55),
}
def linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)
# piece -> (offset from the skin, m; solidify thickness)
OFF = {"trousers": (0.008, 0.004), "tunic": (0.016, 0.005), "boots": (0.022, 0.006), "gloves": (0.004, 0.002),
       "bracers": (0.03, 0.008), "belt": (0.035, 0.01)}
# (a shoulder mantle and a cowl were tried: layered over the tunic they cut through it wherever the arm is raised; left out)
FLARE = 0.06   # the tunic's skirt hangs this much further out at its hem than at the belt

groups = {g.index: g.name for g in body.vertex_groups if g.name in arm.data.bones}   # bone groups only
me0 = body.data
def dom(v):
    best = max((g for g in v.groups if g.group in groups), key=lambda g: g.weight, default=None)
    return groups[best.group] if best else ""
D = [dom(v) for v in me0.vertices]
P = [body.matrix_world @ v.co for v in me0.vertices]
N = [(body.matrix_world.to_3x3() @ v.normal).normalized() for v in me0.vertices]
def joint(n): return arm.matrix_world @ arm.data.bones[n].head_local
waist = joint("Spine02").z + 0.02
ankle = joint("LeftFoot").z
head = joint("Head")
starts = lambda n, *ps: any(n.startswith(p) for p in ps)

def along(i, a, b):
    ax = joint(b) - joint(a)
    return (P[i] - joint(a)).dot(ax) / ax.length_squared

def region(name, i):
    n, p = D[i], P[i]
    hand = starts(n, "LeftHand", "RightHand")
    arm_part = starts(n, "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow")
    torso = starts(n, "Spine", "Hips", "neck", "NeckHelp")
    leg = starts(n, "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg")
    foot = starts(n, "LeftFoot", "RightFoot", "LeftToe", "RightToe")
    if name == "tunic":   # torso from mid-thigh up to the base of the neck, long sleeves to the wrist
        return (torso and p.z < joint("neck").z - 0.01 and (p.z > waist - 0.2 or not n.startswith("Hips"))) or arm_part or \
            (leg and p.z > waist - 0.22)
    if name == "trousers":
        return (torso and n.startswith("Hips") and p.z < waist + 0.02) or (leg and p.z > ankle + 0.1)
    if name == "boots":
        return foot or (leg and p.z < ankle + 0.24)
    if name == "gloves":
        return hand
    if name == "bracers":
        if not starts(n, "LeftForeArm", "RightForeArm"):
            return False
        side = "Left" if n.startswith("Left") else "Right"
        t = along(i, side + "ForeArm", side + "Hand")
        return 0.38 < t < 0.98
    if name == "belt":
        return torso and abs(p.z - waist) < 0.03
    if name == "mantle":   # a short cape over the shoulders and upper back
        if not (torso or starts(n, "LeftShoulder", "RightShoulder", "LeftArm", "RightArm")):
            return False
        if starts(n, "LeftArm", "RightArm") and not n.endswith("Help"):
            side = "Left" if n.startswith("Left") else "Right"
            return along(i, side + "Arm", side + "ForeArm") < 0.32
        return p.z > joint("Spine").z + 0.1 and p.z < joint("neck").z + 0.03
    if name == "cowl":   # a soft collar round the lower neck
        return starts(n, "neck", "NeckHelp", "Spine") and joint("neck").z - 0.02 < p.z < joint("neck").z + 0.07
    return False

def build_piece(name):
    old = bpy.data.objects.get("out_" + name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    keep = {i for i in range(len(me0.vertices)) if region(name, i)}
    me = me0.copy(); me.name = "out_" + name
    ob = bpy.data.objects.new("out_" + name, me)
    body.users_collection[0].objects.link(ob)
    ob.parent = body.parent; ob.matrix_world = body.matrix_world.copy()
    bm = bmesh.new(); bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not all(v.index in keep for v in f.verts)], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    # soften the cut edge: relax boundary loops a little so hems read as lines, not stair steps
    for _ in range(8):
        moves = {}
        for v in bm.verts:
            if any(e.is_boundary for e in v.link_edges):
                nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
                if len(nb) == 2:
                    moves[v] = (nb[0].co + nb[1].co) * 0.5
        for v, c in moves.items():
            v.co = v.co.lerp(c, 0.5)
    bm.normal_update()
    off, thick = OFF[name]
    inv = ob.matrix_world.inverted().to_3x3()
    sc = ob.matrix_world.to_scale().x
    for v in bm.verts:
        extra = 0.0
        if name == "tunic":   # the skirt below the belt hangs out, more toward the hem
            z = (ob.matrix_world @ v.co).z
            extra = FLARE * max(0.0, min(1.0, (waist - z) / 0.2)) ** 1.3
        v.co += v.normal * ((off + extra) / sc)
    bm.to_mesh(me); bm.free()
    for m in list(ob.modifiers): ob.modifiers.remove(m)
    ob.modifiers.new("Armature", 'ARMATURE').object = arm
    s = ob.modifiers.new("Solidify", 'SOLIDIFY'); s.thickness = thick / ob.matrix_world.to_scale().x; s.offset = 1
    mat = bpy.data.materials.get("out_" + name) or bpy.data.materials.new("out_" + name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    c, r = COL[name]
    b.inputs["Base Color"].default_value = (*linear(c), 1.0); b.inputs["Roughness"].default_value = r
    me.materials.clear(); me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = True
    return keep

covered = {}
for name in OFF:
    covered[name] = build_piece(name)

# the body under the clothes: faces wholly inside a covering piece (one ring kept at each hem) go
under = set()
for name in ("tunic", "trousers", "boots", "gloves"):
    under |= covered[name]
bm = bmesh.new(); bm.from_mesh(me0); bm.verts.ensure_lookup_table()
inner = {v.index for v in bm.verts if v.index in under and all(e.other_vert(v).index in under for e in v.link_edges)}
mask = body.vertex_groups.get("hidden_under_clothes") or body.vertex_groups.new(name="hidden_under_clothes")
mask.remove(list(range(len(me0.vertices))))
mask.add(list(inner), 1.0, 'REPLACE')
bm.free()
for m in list(body.modifiers):
    if m.type == 'MASK': body.modifiers.remove(m)
mk = body.modifiers.new("HideUnderClothes", 'MASK'); mk.vertex_group = "hidden_under_clothes"; mk.invert_vertex_group = True
hair = bpy.data.objects.get("body_hair")
if hair: hair.hide_viewport = hair.hide_render = False
old = bpy.data.objects.get("out_hood")
if old: bpy.data.objects.remove(old, do_unlink=True)
for gone in ("out_mantle", "out_cowl"):
    o = bpy.data.objects.get(gone)
    if o: bpy.data.objects.remove(o, do_unlink=True)
result = {n: len(v) for n, v in covered.items()}
