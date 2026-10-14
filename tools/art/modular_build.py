"""Build the modular character kit from the preserved Knight experiment.

Run:  blender.exe -b <Curse_Knight.blend> -P tools/art/modular_build.py -- <out_dir>
Outputs <out_dir>/Curse_Modular.blend and <out_dir>/curse_modular.glb

Naming convention  SLOT_Style[_Variant]   (all skinned to Character_Rig, bone names unchanged)
  BODY_  neutral skin body        CLT_  base clothing under armor     TOR_  torso armor/garment
  ARM_   shoulders+arms armor     GLV_  hands                          LEG_  leg armor
  BTS_   feet                     HLM_  head                           SHD_  shield (rigid, LeftHandProp)
  WPN_   weapon (rigid, Left/RightHandProp)
"""
import bpy, bmesh, sys, math, os
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
rig = bpy.data.objects["Knight_Rig"]
rig.name = "Character_Rig"
rig.data.name = "Character_Rig"
coll = bpy.data.collections["Knight"]
BONES = [b.name for b in rig.data.bones]
BI = {n: i for i, n in enumerate(BONES)}

# ---------------------------------------------------------------- materials
def mk_mat(name, col, rough=0.8, metal=0.0):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    col = tuple(c ** 2.2 for c in col)   # author in sRGB-ish values, store linear
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*col, 1)
    return m
M_Skin = mk_mat("M_Skin", (0.50, 0.34, 0.26), 0.85)
M_LeatherBr = mk_mat("M_LeatherBrown", (0.24, 0.14, 0.08), 0.85)
M_LeatherDk = mk_mat("M_LeatherDark", (0.12, 0.08, 0.05), 0.85)
M_Robe = mk_mat("M_Robe", (0.26, 0.06, 0.09), 0.9)
M_RobeTrim = mk_mat("M_RobeTrim", (0.48, 0.40, 0.27), 0.8)
M_Bone = mk_mat("M_Bone", (0.62, 0.57, 0.45), 0.8)
M_Sash = mk_mat("M_Sash", (0.13, 0.12, 0.10), 0.9)
M_Wood = bpy.data.materials["M_Wood"]
M_Steel = bpy.data.materials["M_Steel"]

# ---------------------------------------------------------------- helpers
def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

class Ring:
    def __init__(self, c, ax, rx, ry, w):
        self.c = Vector(c); self.ax = Vector(ax).normalized()
        self.rx, self.ry, self.w = rx, ry, w

def frame(ax):
    ref = Vector((0, 1, 0)) if abs(ax.dot(Vector((0, 1, 0)))) < 0.9 else Vector((0, 0, 1))
    u = ref.cross(ax).normalized()
    w = ax.cross(u).normalized()
    return u, w

def loft(bm, dl, rings, n=8, mats=None, cap0=False, cap1=False, rot=0.0):
    """Ring.w is dict bone->weight, or callable(pos)->dict. mats[i] = material of segment i->i+1."""
    grid = []
    for r in rings:
        u, w = frame(r.ax)
        row = []
        for k in range(n):
            a = rot + 2 * math.pi * k / n
            p = r.c + u * (math.cos(a) * r.rx) + w * (math.sin(a) * r.ry)
            v = bm.verts.new(p)
            wd = r.w(p) if callable(r.w) else r.w
            for bn, wt in wd.items():
                if wt > 0:
                    v[dl][BI[bn]] = wt
            row.append(v)
        grid.append(row)
    for i in range(len(grid) - 1):
        a, b = grid[i], grid[i + 1]
        for k in range(n):
            f = bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
            f.material_index = mats[i] if mats else 0
    # rings wind CCW about +axis, so segment quads face outward; cap0 must be reversed
    if cap0:
        bm.faces.new(grid[0][::-1])
    if cap1:
        bm.faces.new(grid[-1])
    return grid

def box(bm, dl, c, size, w, mat=0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r["verts"]
    for v in vs:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(c)
        for bn, wt in w.items():
            v[dl][BI[bn]] = wt
    for f in set(f for v in vs for f in v.link_faces):
        f.material_index = mat

def new_mesh_obj(name, mats):
    me = bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    o.parent = rig
    for m in mats:
        me.materials.append(m)
    for bn in BONES:
        o.vertex_groups.new(name=bn)
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return o

def build(name, mats, fn):
    o = new_mesh_obj(name, mats)
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    fn(bm, dl)
    for f in bm.faces:
        f.smooth = False
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    return o

def W(**k):
    return k

def P(s, x, y, z):
    return (s * x, y, z)

# ---------------------------------------------------------------- 1. split reusable knight parts
def loose_parts(o):
    bm = bmesh.new(); bm.from_mesh(o.data); bm.verts.ensure_lookup_table()
    dl = bm.verts.layers.deform.active
    seen, comps = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        st, comp = [v], []
        seen.add(v.index)
        while st:
            x = st.pop(); comp.append(x.index)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index); st.append(y)
        cnt = {}
        for i in comp:
            for gi, w in bm.verts[i][dl].items():
                n = o.vertex_groups[gi].name
                cnt[n] = cnt.get(n, 0) + w
        comps.append((comp, max(cnt, key=cnt.get) if cnt else None))
    bm.free()
    return comps

def extract(src, newname, keep_idx):
    keep = set(keep_idx)
    o = src.copy(); o.data = src.data.copy(); o.name = newname; o.data.name = newname
    coll.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(o.data); bm.verts.ensure_lookup_table()
    kill = [v for v in bm.verts if v.index not in keep]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(o.data); bm.free()
    o.data.update()
    return o

def split(srcname, pred_a, name_a, name_b):
    src = bpy.data.objects[srcname]
    ca, cb = [], []
    for comp, dom in loose_parts(src):
        (ca if pred_a(dom) else cb).extend(comp)
    extract(src, name_a, ca)
    extract(src, name_b, cb)
    bpy.data.objects.remove(src)

split("KN_Arms", lambda d: d and d.endswith("Hand"), "GLV_Plate", "ARM_Plate")
split("KN_Legs", lambda d: d and (d.endswith("Foot") or d.endswith("Toes")), "BTS_Plate", "LEG_Plate")
for old, new in (("KN_Body", "CLT_Gambeson"), ("KN_Torso", "TOR_Plate"), ("KN_Helmet", "HLM_Great"),
                 ("KN_Shield", "SHD_Kite"), ("KN_Sword", "WPN_Sword")):
    bpy.data.objects[old].name = new
    bpy.data.objects[new].data.name = new

# ---------------------------------------------------------------- 2. neutral skin body
JN = {b.name: b for b in rig.data.bones}
def hp(n):
    return Vector(JN[n].head_local)

def side_of(s):
    return "Left" if s > 0 else "Right"

def leg_rings(s, infl=0.0):
    knee = Vector(P(s, 0.115, -0.018, 0.52)); ank = Vector(P(s, 0.125, 0.025, 0.105))
    up = (knee - Vector(P(s, 0.105, 0.0, 0.94))).normalized(); lo = (ank - knee).normalized()
    sd = side_of(s); d = infl
    return [
        Ring(P(s, 0.105, 0.0, 0.99), up, 0.085 + d, 0.09 + d, W(Hips=0.5, **{sd + "UpperLeg": 0.5})),
        Ring(P(s, 0.110, -0.010, 0.74), up, 0.078 + d, 0.080 + d, W(**{sd + "UpperLeg": 1})),
        Ring(tuple(knee), up, 0.058 + d, 0.060 + d, W(**{sd + "UpperLeg": 0.5, sd + "LowerLeg": 0.5})),
        Ring(P(s, 0.120, 0.005, 0.32), lo, 0.060 + d, 0.064 + d, W(**{sd + "LowerLeg": 1})),
        Ring(tuple(ank + Vector((0, 0, 0.03))), lo, 0.042 + d, 0.046 + d,
             W(**{sd + "LowerLeg": 0.5, sd + "Foot": 0.5})),
    ]

def foot_rings(s, infl=0.0, sole=0.0):
    sd = side_of(s); d = infl
    ax = Vector((0, -1, -0.05))
    return [
        Ring(P(s, 0.125, 0.065, 0.07 + sole), ax, 0.046 + d, 0.048 + d + sole, W(**{sd + "Foot": 1})),
        Ring(P(s, 0.125, 0.0, 0.058 + sole * 0.5), ax, 0.048 + d, 0.040 + d + sole, W(**{sd + "Foot": 1})),
        Ring(P(s, 0.128, -0.10, 0.04 + sole * 0.5), ax, 0.050 + d, 0.030 + d + sole,
             W(**{sd + "Foot": 0.5, sd + "Toes": 0.5})),
        Ring(P(s, 0.128, -0.19, 0.032 + sole * 0.5), ax, 0.038 + d, 0.020 + d + sole, W(**{sd + "Toes": 1})),
    ]

def arm_path(s):
    return (Vector(P(s, 0.205, 0.01, 1.465)), Vector(P(s, 0.41, 0.022, 1.26)),
            Vector(P(s, 0.584, -0.009, 1.076)), Vector(P(s, 0.652, -0.021, 1.004)))

def arm_rings(s, infl=0.0, radii=(0.052, 0.047, 0.041, 0.036, 0.030), flare=0.0):
    sh, el, wr, hd = arm_path(s)
    sd = side_of(s)
    a1 = (el - sh).normalized(); a2 = (wr - el).normalized()
    d = infl
    return [
        Ring(sh.lerp(el, 0.05), a1, radii[0] + d, radii[0] + d, W(**{sd + "Shoulder": 0.4, sd + "UpperArm": 0.6})),
        Ring(sh.lerp(el, 0.5), a1, radii[1] + d, radii[1] + d, W(**{sd + "UpperArm": 1})),
        Ring(el, (a1 + a2).normalized(), radii[2] + d, radii[2] + d,
             W(**{sd + "UpperArm": 0.5, sd + "LowerArm": 0.5})),
        Ring(el.lerp(wr, 0.5), a2, radii[3] + d + flare * 0.5, radii[3] + d + flare * 0.5, W(**{sd + "LowerArm": 1})),
        Ring(wr, a2, radii[4] + d + flare, radii[4] + d + flare, W(**{sd + "LowerArm": 0.5, sd + "Hand": 0.5})),
    ]

def hand_rings(s, infl=0.0):
    sh, el, wr, hd = arm_path(s)
    sd = side_of(s)
    ax = (hd - wr).normalized(); d = infl
    end = wr + (hd - wr) * 1.3
    return [
        Ring(wr, ax, 0.022 + d, 0.032 + d, W(**{sd + "Hand": 1})),
        Ring(wr.lerp(end, 0.5), ax, 0.020 + d, 0.042 + d, W(**{sd + "Hand": 1})),
        Ring(end, ax, 0.014 + d, 0.036 + d, W(**{sd + "Hand": 1})),
    ]

def skin(bm, dl):
    Z = (0, 0, 1)
    def C(z, y=0.0):
        return (0, y, z)
    rings = [
        Ring(C(0.92), Z, 0.165, 0.105, W(Hips=1)),
        Ring(C(1.00), Z, 0.160, 0.100, W(Hips=0.7, Spine=0.3)),
        Ring(C(1.12), Z, 0.140, 0.095, W(Spine=1)),
        Ring(C(1.28), Z, 0.150, 0.100, W(Spine=0.3, Chest=0.7)),
        Ring(C(1.42), Z, 0.165, 0.105, W(Chest=1)),
        Ring(C(1.51), Z, 0.120, 0.085, W(Chest=1)),
        Ring(C(1.56), Z, 0.050, 0.052, W(Chest=0.5, Neck=0.5)),
        Ring(C(1.63), Z, 0.048, 0.050, W(Neck=0.5, Head=0.5)),
        Ring(C(1.66, -0.01), Z, 0.072, 0.088, W(Head=1)),      # jaw
        Ring(C(1.72, -0.005), Z, 0.086, 0.100, W(Head=1)),     # cheek
        Ring(C(1.78, -0.005), Z, 0.088, 0.104, W(Head=1)),     # brow
        Ring(C(1.84, 0.0), Z, 0.074, 0.090, W(Head=1)),        # crown
        Ring(C(1.875, 0.005), Z, 0.035, 0.046, W(Head=1)),
    ]
    loft(bm, dl, rings, n=8, cap0=True, cap1=True, rot=math.pi / 8)
    box(bm, dl, (0, -0.105, 1.735), (0.026, 0.034, 0.06), W(Head=1))   # nose
    box(bm, dl, (0, -0.092, 1.775), (0.14, 0.03, 0.020), W(Head=1))    # brow ridge
    for s in (1, -1):
        loft(bm, dl, leg_rings(s), n=7, cap1=True)
        loft(bm, dl, foot_rings(s), n=6, cap1=True)
        loft(bm, dl, arm_rings(s), n=6)
        loft(bm, dl, hand_rings(s), n=6, cap1=True)

build("BODY_Skin", [M_Skin], skin)

# ---------------------------------------------------------------- 3. leather set
def jerkin(bm, dl):
    Z = (0, 0, 1)
    def skirt_w(p):
        leg = smooth(0.96, 0.82, p.z) * 0.55
        sl = smooth(-0.07, 0.07, p.x)
        return W(Hips=1 - leg, LeftUpperLeg=leg * sl, RightUpperLeg=leg * (1 - sl))
    rings = [
        Ring((0, 0, 0.80), Z, 0.245, 0.170, skirt_w),
        Ring((0, 0, 0.90), Z, 0.235, 0.160, skirt_w),
        Ring((0, 0, 1.00), Z, 0.225, 0.145, W(Hips=0.8, Spine=0.2)),
        Ring((0, 0, 1.07), Z, 0.195, 0.135, W(Hips=0.3, Spine=0.7)),
        Ring((0, 0, 1.13), Z, 0.185, 0.135, W(Spine=1)),
        Ring((0, 0, 1.28), Z, 0.205, 0.148, W(Spine=0.3, Chest=0.7)),
        Ring((0, 0, 1.42), Z, 0.210, 0.148, W(Chest=1)),
        Ring((0, 0, 1.50), Z, 0.160, 0.112, W(Chest=1)),
        Ring((0, 0, 1.545), Z, 0.090, 0.080, W(Chest=0.6, Neck=0.4)),
    ]
    loft(bm, dl, rings, n=10, mats=[0, 0, 1, 1, 0, 0, 0, 0])
    for s in (1, -1):  # short leather shoulder caps
        sd = side_of(s)
        sh = hp(sd + "UpperArm")
        a = (hp(sd + "LowerArm") - sh).normalized()
        loft(bm, dl, [
            Ring(sh + Vector((0, 0, 0.04)) - a * 0.02, a, 0.075, 0.075,
                 W(**{sd + "Shoulder": 0.5, sd + "UpperArm": 0.5})),
            Ring(sh + a * 0.07, a, 0.072, 0.072, W(**{sd + "UpperArm": 1})),
        ], n=7, cap0=True)
    box(bm, dl, (0, -0.125, 1.045), (0.05, 0.03, 0.05), W(Spine=1), mat=1)   # buckle
    box(bm, dl, (0.235, -0.06, 0.98), (0.07, 0.09, 0.10), W(Hips=1), mat=1)   # pouch

build("TOR_Leather", [M_LeatherBr, M_LeatherDk], jerkin)

def gloves(bm, dl):
    for s in (1, -1):
        loft(bm, dl, arm_rings(s, infl=0.012, radii=(0, 0, 0, 0.046, 0.040))[3:], n=7)
        loft(bm, dl, hand_rings(s, infl=0.012), n=7, cap1=True)
build("GLV_Leather", [M_LeatherBr], gloves)

def boots(bm, dl):
    for s in (1, -1):
        sd = side_of(s)
        knee = Vector(P(s, 0.115, -0.018, 0.52)); ank = Vector(P(s, 0.125, 0.025, 0.105))
        lo = (ank - knee).normalized()
        loft(bm, dl, [
            Ring(P(s, 0.117, -0.01, 0.40), lo, 0.082, 0.086, W(**{sd + "LowerLeg": 1})),
            Ring(P(s, 0.120, 0.005, 0.32), lo, 0.072, 0.076, W(**{sd + "LowerLeg": 1})),
            Ring(tuple(ank + Vector((0, 0, 0.03))), lo, 0.056, 0.060,
                 W(**{sd + "LowerLeg": 0.5, sd + "Foot": 0.5})),
        ], n=7)
        loft(bm, dl, foot_rings(s, infl=0.01, sole=0.01), n=7, cap1=True)
build("BTS_Leather", [M_LeatherDk], boots)

# ---------------------------------------------------------------- 4. robe
def robe(bm, dl):
    Z = (0, 0, 1)
    def skirt_w(p):
        leg = smooth(0.97, 0.30, p.z) * 1.0
        sl = smooth(-0.12, 0.12, p.x)
        up = leg
        return W(Hips=1 - leg, LeftUpperLeg=up * sl, RightUpperLeg=up * (1 - sl),
                 LeftLowerLeg=(leg - up) * sl, RightLowerLeg=(leg - up) * (1 - sl))
    rings = [
        Ring((0, 0, 1.555), Z, 0.095, 0.085, W(Chest=0.6, Neck=0.4)),
        Ring((0, 0, 1.50), Z, 0.200, 0.140, W(Chest=1)),
        Ring((0, 0, 1.38), Z, 0.215, 0.150, W(Chest=1)),
        Ring((0, 0, 1.22), Z, 0.190, 0.138, W(Chest=0.6, Spine=0.4)),
        Ring((0, 0, 1.10), Z, 0.170, 0.125, W(Spine=1)),
        Ring((0, 0, 1.03), Z, 0.185, 0.132, W(Spine=0.4, Hips=0.6)),
        Ring((0, 0, 0.92), Z, 0.240, 0.175, skirt_w),
        Ring((0, 0, 0.62), Z, 0.290, 0.275, skirt_w),
        Ring((0, 0, 0.34), Z, 0.330, 0.305, skirt_w),
        Ring((0, 0, 0.07), Z, 0.350, 0.330, skirt_w),
    ]
    # materials: collar trim, body x3, sash x1 (1.10->1.03), body skirt x3, hem handled below
    loft(bm, dl, rings, n=10, mats=[1, 0, 0, 0, 3, 3, 0, 0, 1])
    for s in (1, -1):
        loft(bm, dl, arm_rings(s, infl=0.028, radii=(0.052, 0.050, 0.050, 0.055, 0.060), flare=0.05),
             n=8, mats=[0, 0, 0, 1])
build("ROBE_Mage", [M_Robe, M_RobeTrim, M_RobeTrim, M_Sash], robe)

# ---------------------------------------------------------------- 5. helmets
def kettle(bm, dl):
    Z = (0, 0, 1); H = W(Head=1)
    rings = [
        Ring((0, -0.005, 1.745), Z, 0.120, 0.135, H),
        Ring((0, -0.005, 1.752), Z, 0.215, 0.235, H),
        Ring((0, -0.005, 1.766), Z, 0.215, 0.235, H),
        Ring((0, -0.005, 1.780), Z, 0.126, 0.142, H),
        Ring((0, -0.005, 1.805), Z, 0.116, 0.132, H),
        Ring((0, -0.003, 1.850), Z, 0.096, 0.112, H),
        Ring((0, 0.0, 1.895), Z, 0.050, 0.062, H),
    ]
    loft(bm, dl, rings, n=10, cap1=True)
build("HLM_Kettle", [M_Steel], kettle)

def hood(bm, dl):
    Z = (0, 0, 1)
    rings = [
        Ring((0, 0.0, 1.46), Z, 0.230, 0.170, W(Chest=1)),
        Ring((0, 0.0, 1.56), Z, 0.160, 0.130, W(Chest=0.5, Neck=0.5)),
        Ring((0, 0.0, 1.66), Z, 0.130, 0.140, W(Neck=0.4, Head=0.6)),
        Ring((0, 0.0, 1.74), Z, 0.125, 0.140, W(Head=1)),
        Ring((0, 0.0, 1.82), Z, 0.105, 0.125, W(Head=1)),
        Ring((0, 0.03, 1.90), Z, 0.060, 0.085, W(Head=1)),
        Ring((0, 0.09, 1.98), Z, 0.012, 0.020, W(Head=1)),
    ]
    loft(bm, dl, rings, n=10, cap1=True)
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.y < -0.07 and 1.64 < c.z < 1.83 and abs(c.x) < 0.1:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES_ONLY')
    orphan = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=orphan, context='VERTS')
build("HLM_Hood", [M_Robe], hood)

# ---------------------------------------------------------------- 6. bow (rigid, LeftHandProp)
def idle_hand_matrix():
    """rest->posed transform of LeftHandProp in the first Idle_Combat frame, plus posed hand position"""
    rig.animation_data.action = bpy.data.actions["Idle_Combat"]
    bpy.context.scene.frame_set(1)
    pb = rig.pose.bones["LeftHandProp"]
    M = pb.matrix @ rig.data.bones["LeftHandProp"].matrix_local.inverted()
    return M, pb.head.copy()

def bow(bm, dl):
    Wt = W(LeftHandProp=1)
    M, hand = idle_hand_matrix()
    Minv = M.inverted()
    g = Vector((0.0, 0.0, 0.0))
    half = 0.50
    N = 6
    pts = [g + Vector((0.0, 0.17 * (i / N) ** 2, half * i / N)) for i in range(-N, N + 1)]
    rings = []
    for i, p in enumerate(pts):
        t = abs((i - N) / N)
        r = 0.024 * (1 - t) + 0.010 * t
        ax = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        rings.append(Ring(p, ax, r * 0.8, r * 1.2, Wt))
    loft(bm, dl, rings, n=4, cap0=True, cap1=True, rot=math.pi / 4)
    gr = [Ring(g + Vector((0, -0.002, z)), (0, 0, 1), 0.031, 0.034, Wt) for z in (-0.08, -0.07, 0.07, 0.08)]
    loft(bm, dl, gr, n=6, mats=[0, 1, 0], cap0=True, cap1=True)
    s0 = pts[0] + Vector((0, 0.005, 0)); s1 = pts[-1] + Vector((0, 0.005, 0))
    loft(bm, dl, [Ring(s0, s1 - s0, 0.003, 0.003, Wt), Ring(s1, s1 - s0, 0.003, 0.003, Wt)], n=3, mats=[2])
bow_obj = build("WPN_Bow", [M_Wood, M_LeatherDk, M_Bone], bow)
# bow was modelled upright around the origin in the idle pose: move it onto the posed fist,
# then map back to rest space so skinning to LeftHandProp reproduces the upright bow in idle
_M, _hand = idle_hand_matrix()
_Mi = _M.inverted()
for v in bow_obj.data.vertices:
    v.co = _Mi @ (v.co + _hand + Vector((0.0, -0.01, 0.0)))
bow_obj.data.update()
bpy.context.scene.frame_set(1)

# ---------------------------------------------------------------- save + export
os.makedirs(OUT, exist_ok=True)
for me in [m for m in bpy.data.meshes if m.users == 0]:
    bpy.data.meshes.remove(me)

tot = 0
for o in sorted(bpy.data.objects, key=lambda x: x.name):
    if o.type == 'MESH':
        o.data.calc_loop_triangles(); t = len(o.data.loop_triangles); tot += t
        print("TRIS", o.name, t)
print("KIT_TOTAL_TRIS", tot)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Curse_Modular.blend"), copy=True)
bpy.ops.export_scene.gltf(
    filepath=os.path.join(OUT, "curse_modular.glb"), export_format='GLB',
    export_animations=True, export_animation_mode='NLA_TRACKS', export_skins=True,
    export_apply=False, export_yup=True, export_cameras=False, export_lights=False,
    export_force_sampling=True, export_optimize_animation_size=False,
    export_normals=True, export_materials='EXPORT')
print("EXPORT_DONE")
