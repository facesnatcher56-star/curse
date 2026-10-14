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
    def __init__(self, c, ax, rx, ry, w, mod=None):
        self.c = Vector(c); self.ax = Vector(ax).normalized()
        self.rx, self.ry, self.w, self.mod = rx, ry, w, mod   # mod(angle) -> (radius scale, offset along axis)

def frame(ax):
    ref = Vector((0, 1, 0)) if abs(ax.dot(Vector((0, 1, 0)))) < 0.9 else Vector((0, 0, 1))
    u = ref.cross(ax).normalized()
    w = ax.cross(u).normalized()
    return u, w

def loft(bm, dl, rings, n=8, mats=None, cap0=False, cap1=False, rot=0.0, arc=None, solidify=0.0):
    """Ring.w is dict bone->weight, or callable(pos)->dict. mats[i] = material of segment i->i+1.
    arc=(a0, a1) builds an open strip (n segments); solidify=t makes it a thin double-sided shell."""
    def pass_(off, reverse):
        grid = []
        cnt = n + 1 if arc else n
        for r in rings:
            u, w = frame(r.ax)
            row = []
            for k in range(cnt):
                a = arc[0] + (arc[1] - arc[0]) * k / n if arc else rot + 2 * math.pi * k / n
                sc, dz = r.mod(a) if r.mod else (1.0, 0.0)
                p = r.c + u * (math.cos(a) * (r.rx * sc + off)) + w * (math.sin(a) * (r.ry * sc + off)) + r.ax * dz
                v = bm.verts.new(p)
                wd = r.w(p) if callable(r.w) else r.w
                for bn, wt in wd.items():
                    if wt > 0:
                        v[dl][BI[bn]] = wt
                row.append(v)
            grid.append(row)
        segs = cnt - 1 if arc else cnt
        for i in range(len(grid) - 1):
            a_, b_ = grid[i], grid[i + 1]
            for k in range(segs):
                k2 = (k + 1) % cnt
                quad = (a_[k], a_[k2], b_[k2], b_[k])
                f = bm.faces.new(quad[::-1] if reverse else quad)
                f.material_index = mats[i] if mats else 0
        return grid
    grid = pass_(0.0, False)
    if solidify > 0:
        pass_(-solidify, True)
    # rings wind CCW about +axis, so segment quads face outward; cap0 must be reversed
    if cap0 and not arc:
        bm.faces.new(grid[0][::-1])
    if cap1 and not arc:
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

# ---------------------------------------------------------------- 2-5. body, ranger, mage and head pieces
exec(compile(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "modular_detail.py")).read(), "modular_detail.py", "exec"))

# ---------------------------------------------------------------- 6. bow (rigid prop)
# Prop space = the game's archer bow convention (assets/models/archer/bow): upright along +Z here (Godot +Y),
# belly toward -X, thin along Y, ~1.57 m tall, centred on the grip. Mounted rigidly on LeftHand with BoneAttachment3D
# and an identity basis, exactly like BowAttack._attach_gear, so it keeps its pose in every clip and in the aim pose.
def bow(bm, dl):
    Wt = W(LeftHandProp=1)   # ignored: props are exported unskinned
    N = 7
    half = 0.78
    def pt(t):
        # recurved: belly bulges to -X at the grip, tips curl back toward +X then slightly forward
        x = -0.14 * (1 - t * t) + 0.03 * max(0.0, abs(t) - 0.8) / 0.2
        return Vector((x, 0.0, half * t))
    pts = [pt(i / N) for i in range(-N, N + 1)]
    rings = []
    for i, p in enumerate(pts):
        t = abs(i / N)
        r = 0.026 * (1 - t) + 0.011 * t
        ax = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        rings.append(Ring(p, ax, r * 0.95, r * 0.75, Wt))
    loft(bm, dl, rings, n=6, cap0=True, cap1=True, rot=math.pi / 6)
    # riser / grip wrap
    g0 = pt(0)
    gr = [Ring(g0 + Vector((0, 0, z)), (0, 0, 1), rx, ry, Wt) for z, rx, ry in
          ((-0.12, 0.030, 0.026), (-0.095, 0.040, 0.034), (-0.06, 0.036, 0.030), (0.06, 0.036, 0.030),
           (0.095, 0.040, 0.034), (0.12, 0.030, 0.026))]
    loft(bm, dl, gr, n=6, mats=[1, 1, 1, 1, 1], cap0=True, cap1=True)
    # arrow shelf and nock tips
    box(bm, dl, g0 + Vector((0.035, 0, 0.02)), (0.03, 0.02, 0.05), Wt, mat=0)
    for s in (1, -1):
        loft(bm, dl, [Ring(pts[-1 if s > 0 else 0] + Vector((0, 0, 0.0)), (0, 0, s), 0.014, 0.014, Wt),
                      Ring(pts[-1 if s > 0 else 0] + Vector((0.012, 0, 0.03 * s)), (0, 0, s), 0.009, 0.009, Wt)],
             n=5, mats=[1], cap1=True)
    s0 = pts[0]; s1 = pts[-1]
    loft(bm, dl, [Ring(s0, s1 - s0, 0.003, 0.003, Wt), Ring(s1, s1 - s0, 0.003, 0.003, Wt)], n=3, mats=[2])
build("WPN_Bow", [M_Wood, M_LeatherDk, M_Bone], bow)

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
