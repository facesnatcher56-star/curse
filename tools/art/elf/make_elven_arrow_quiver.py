# Blender (Blender MCP), on an empty scene: the wood elf's arrow and quiver, matching his bow (make_elven_bow.py).
#
# Contracts (game/player/bow_attack.gd, game/companion_arrow.gd):
#   arrow  - upright, the point at the top (+Blender Z = glTF +Y), the nock at the bottom; built at its real length, 0.92 m
#            (the drawn arrow is scaled to 0.92, the flying one is used at its own size).
#   quiver - upright, opening at the top, 0.78 m tall including the arrows standing in it (it is scaled to 0.78); worn on
#            the upper back, so its back face (+Blender Y) lies against the spine.
# Arrow: pale ash shaft, a leaf-shaped steel head, three moss-green fletchings (the cock feather cream), horn nock, thread
# wraps. Quiver: oiled dark-brown leather tube, a tooled band of leaves at the mouth and the foot, a wooden rim, stitched
# seam, a bronze buckle stub for the strap; seven arrows standing in it. Exports arrow.glb and quiver.glb.
import bpy, bmesh, math, os, numpy as np
from mathutils import Vector, Matrix

SRC = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\elf\source"
OUT = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\models\elf\items"
ARROW_LEN = 0.92
SHAFT_R = 0.0042
rng = np.random.default_rng(5)

def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)

def image(name, rgb, non_color=False):
    H, W = rgb.shape[:2]
    img = bpy.data.images.get(name) or bpy.data.images.new(name, W, H, alpha=False)
    if tuple(img.size) != (W, H): img.scale(W, H)
    img.pixels.foreach_set(np.concatenate([np.clip(rgb, 0, 1), np.ones((H, W, 1))], 2).astype(np.float32).ravel())
    img.filepath_raw = os.path.join(SRC, name + ".png"); img.file_format = 'PNG'; img.save(); img.filepath = img.filepath_raw
    if non_color: img.colorspace_settings.name = "Non-Color"
    return img

def noise(H, W, rows, cols, octaves=4):
    out = np.zeros((H, W), np.float32); amp = 1.0; tot = 0.0
    for o in range(octaves):
        h = max(2, int(rows * 2 ** o)); w = max(2, int(cols * 2 ** o))
        small = rng.random((h, w)).astype(np.float32)
        yi = np.linspace(0, h - 1, H); xi = np.linspace(0, w - 1, W)
        y0 = np.floor(yi).astype(int); x0 = np.floor(xi).astype(int); y1 = np.minimum(y0 + 1, h - 1); x1 = np.minimum(x0 + 1, w - 1)
        fy = (yi - y0)[:, None]; fx = (xi - x0)[None, :]
        a = small[y0][:, x0]; b = small[y0][:, x1]; c = small[y1][:, x0]; d = small[y1][:, x1]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy); tot += amp; amp *= 0.5
    return out / tot

def material(name, base, rough, metal, normal=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    b = nt.nodes.new("ShaderNodeBsdfPrincipled"); o = nt.nodes.new("ShaderNodeOutputMaterial")
    if isinstance(base, tuple):
        b.inputs["Base Color"].default_value = (*base, 1.0)
    else:
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = base; nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    if normal is not None:
        tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = normal
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    nt.links.new(b.outputs[0], o.inputs[0])
    return m

def normal_map(height, strength):
    gy, gx = np.gradient(height.astype(np.float32))
    n = np.dstack([-gx * strength, -gy * strength, np.ones_like(height)]); n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5

def textures():
    # shaft: pale ash, fine straight grain along v
    H, W = 512, 64
    g = noise(H, W, 6, 40, 3)
    ash = np.dstack([0.78 + 0.1 * (g - 0.5), 0.70 + 0.1 * (g - 0.5), 0.55 + 0.08 * (g - 0.5)])
    # feathers: barbs as fine diagonal lines, the shaft (rachis) a pale line along the root
    Hf, Wf = 256, 256
    yy, xx = np.mgrid[0:Hf, 0:Wf] / float(Hf)
    barbs = 0.85 + 0.15 * np.sin((xx * 1.0 + yy * 0.6) * 260.0)
    rachis = np.clip(1 - np.abs(yy - 0.04) / 0.02, 0, 1)
    def feather(col):
        c = np.array(col)[None, None, :] * barbs[..., None]
        return c * (1 - rachis[..., None]) + np.array([0.85, 0.82, 0.72]) * rachis[..., None]
    green = feather([0.20, 0.30, 0.16]); cream = feather([0.82, 0.78, 0.66])
    # quiver leather: oiled dark brown, a tooled band of leaves near the mouth and the foot, a stitched seam at the back
    Hq, Wq = 1024, 512
    v = np.linspace(0, 1, Hq)[:, None].repeat(Wq, 1); u = np.linspace(0, 1, Wq)[None, :].repeat(Hq, 0)
    grain = noise(Hq, Wq, 60, 40, 4)
    col = np.dstack([0.24, 0.13, 0.07]) * (0.8 + 0.4 * grain[..., None])
    height = (grain - 0.5) * 0.4
    for band_v in (0.12, 0.88):                     # u wraps round the tube, v runs foot (0) to mouth (1)
        in_band = np.abs(v - band_v) < 0.05
        border = (np.abs(np.abs(v - band_v) - 0.05) < 0.004)
        phase = (u * 14.0) % 1.0
        leaf = np.clip(1 - (((phase - 0.5) / 0.32) ** 2 + ((v - band_v) / 0.032) ** 2), 0, 1) ** 0.5
        leaf = leaf * in_band
        tooled = np.clip(leaf + border, 0, 1)
        col = col * (1 - 0.35 * tooled[..., None]); height -= tooled * 1.2
    seam = np.abs(u - 0.25) < 0.006   # u 0.25 is +Y, the back against the spine
    stitch = seam & (((v * 120.0) % 1.0) < 0.55)
    col = np.where(stitch[..., None], np.array([0.34, 0.27, 0.18]), col); height = np.where(seam, height - 0.6, height)
    return {"ash": image("elven_arrow_shaft", ash), "green": image("elven_arrow_feather", green),
            "cream": image("elven_arrow_cockfeather", cream),
            "leather": image("elven_quiver_leather", col), "leather_n": image("elven_quiver_normal", normal_map(height, 2.5), True)}

def loft(name, rings, mat_index=0, caps=(True, True), inward=False):
    """rings: list of (z, radius_x, radius_y, sides); returns a lofted smooth tube, capped at the (bottom, top) ends asked
    for; inward=True faces it inward (the inside wall of an open tube)."""
    bm = bmesh.new(); uv = bm.loops.layers.uv.new("UVMap")
    verts = []
    z0, z1 = rings[0][0], rings[-1][0]
    for z, rx, ry, n in rings:
        verts.append([bm.verts.new((rx * math.cos(2 * math.pi * k / n), ry * math.sin(2 * math.pi * k / n), z)) for k in range(n)])
    for i in range(len(rings) - 1):
        n = len(verts[i])
        for k in range(n):
            f = bm.faces.new((verts[i][k], verts[i][(k + 1) % n], verts[i + 1][(k + 1) % n], verts[i + 1][k]))
            for loop, (kk, ii) in zip(f.loops, ((k, i), (k + 1, i), (k + 1, i + 1), (k, i + 1))):
                loop[uv].uv = (kk / n, (rings[ii][0] - z0) / max(z1 - z0, 1e-6))
    for ring, cap in ((verts[0], caps[0]), (verts[-1], caps[1])):
        if cap and len(ring) > 2:
            bm.faces.new(ring if ring is verts[-1] else list(reversed(ring)))
    if inward:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True; p.material_index = mat_index
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    return o

def vane(name, z_root, length, height, angle, mat_index):
    """one fletching: a shield-shaped thin solid standing off the shaft at `angle` (radians round the shaft)."""
    bm = bmesh.new(); uv = bm.loops.layers.uv.new("UVMap")
    N = 12; T = 0.0004
    top, bot = [], []
    for i in range(N + 1):
        t = i / N
        h = height * (math.sin(math.pi * min(t * 1.25, 1.0)) ** 0.6) * (0.55 + 0.45 * t)   # low at the back, high near the front, rounded
        z = z_root + t * length
        top.append((h, z)); bot.append((0.0, z))
    sides = []
    for off in (-T, T):
        row_b = [bm.verts.new((0, 0, 0)) for _ in range(N + 1)]
        row_t = [bm.verts.new((0, 0, 0)) for _ in range(N + 1)]
        for i in range(N + 1):
            for vtx, (r, z) in ((row_b[i], bot[i]), (row_t[i], top[i])):
                rr = SHAFT_R + r
                vtx.co = Vector((rr * math.cos(angle) - off * math.sin(angle), rr * math.sin(angle) + off * math.cos(angle), z))
        sides.append((row_b, row_t))
    for s, (rb, rt) in enumerate(sides):
        for i in range(N):
            quad = (rb[i], rb[i + 1], rt[i + 1], rt[i]) if s == 1 else (rb[i], rt[i], rt[i + 1], rb[i + 1])
            f = bm.faces.new(quad)
            for loop in f.loops:
                c = loop.vert.co
                loop[uv].uv = ((c.z - z_root) / length, (math.hypot(c.x, c.y) - SHAFT_R) / max(height, 1e-6))
    (b0, t0), (b1, t1) = sides
    for i in range(N):   # the edge round the top
        bm.faces.new((t0[i], t0[i + 1], t1[i + 1], t1[i]))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.material_index = mat_index
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    return o

def arrow(name, mats, top_only=None):
    """an arrow, nock at z=0 and point at z=ARROW_LEN. top_only: keep only z >= that (for arrows standing in the quiver,
    which show their fletched ends: the arrow is then flipped, nock up). Returns the joined object."""
    parts = []
    head_len = 0.072
    shaft_end = ARROW_LEN - head_len + 0.012
    parts.append(loft(name + "_shaft", [(0.012, SHAFT_R * 0.95, SHAFT_R * 0.95, 10), (shaft_end, SHAFT_R, SHAFT_R, 10)], 0))
    # horn nock with its slot as a dark ring
    parts.append(loft(name + "_nock", [(0.0, SHAFT_R * 0.8, SHAFT_R * 0.8, 10), (0.004, SHAFT_R * 1.2, SHAFT_R * 1.2, 10),
                                       (0.014, SHAFT_R * 1.05, SHAFT_R * 1.05, 10)], 3))
    # thread wraps at both ends of the fletching
    for z in (0.028, 0.152):
        parts.append(loft(name + "_wrap", [(z, SHAFT_R * 1.05, SHAFT_R * 1.05, 10), (z + 0.006, SHAFT_R * 1.05, SHAFT_R * 1.05, 10)], 4))
    # three vanes, the cock feather (cream) at 0
    for k in range(3):
        parts.append(vane(name + "_vane", 0.035, 0.115, 0.016, 2 * math.pi * k / 3 + math.pi / 2, 2 if k == 0 else 1))
    # head: a round socket over the shaft, then a flat leaf blade (diamond section, a ridge down the middle) widest a third of
    # the way up and tapering straight to the point; flat-shaded so the edges and the ridge stay crisp
    socket = [(ARROW_LEN - head_len + t * 0.016, SHAFT_R * (1.08 + 0.12 * t), SHAFT_R * (1.08 + 0.12 * t), 10) for t in (0.0, 0.5, 1.0)]
    parts.append(loft(name + "_socket", socket, 5))
    rings = []
    blade0 = ARROW_LEN - head_len + 0.012
    for i in range(12):
        t = i / 11.0
        z = blade0 + t * (ARROW_LEN - blade0)
        w = 0.0115 * (t / 0.33) ** 0.6 if t < 0.33 else 0.0115 * (1.0 - (t - 0.33) / 0.67) ** 0.95
        w = max(w, SHAFT_R * 1.15 * (1.0 - t)) + 0.0002
        rings.append((z, w, max(min(w * 0.16, 0.0019), 0.0003), 4))
    head = loft(name + "_head", rings, 5, caps=(True, False))
    for p in head.data.polygons:
        p.use_smooth = False
    parts.append(head)
    for p in parts:   # every part carries the full slot list before the join, so the join keeps each face's material
        for m in mats:
            p.data.materials.append(m)
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts: p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object; o.name = name; o.data.name = name
    if top_only is not None:
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > top_only], context='VERTS')
        bm.to_mesh(o.data); bm.free()
    return o

def export(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                              export_materials='EXPORT', export_tangents=True)

clear()
os.makedirs(OUT, exist_ok=True)
tex = textures()
arrow_mats = [material("elven_arrow_shaft", tex["ash"], 0.55, 0.0), material("elven_arrow_feather", tex["green"], 0.8, 0.0),
              material("elven_arrow_cockfeather", tex["cream"], 0.8, 0.0), material("elven_arrow_horn", (0.86, 0.82, 0.70), 0.4, 0.0),
              material("elven_arrow_thread", (0.07, 0.09, 0.05), 0.75, 0.0), material("elven_arrow_steel", (0.70, 0.71, 0.73), 0.3, 0.6)]
# --- the arrow
a = arrow("ElvenArrow", arrow_mats)
a.modifiers.new("Triangulate", 'TRIANGULATE')
export([a], os.path.join(OUT, "elven_arrow.glb"))
arrow_tris = sum(len(p.vertices) - 2 for p in a.data.polygons)
arrow_dims = list(a.dimensions)
a.hide_set(True)

# --- the quiver: a slightly flattened leather tube, foot at z=0, mouth at TUBE
TUBE = 0.58
leather = material("elven_quiver_leather", tex["leather"], 0.62, 0.0, tex["leather_n"])
wood = material("elven_quiver_rim", (0.30, 0.17, 0.09), 0.5, 0.0)
bronze = material("elven_quiver_bronze", (0.62, 0.45, 0.24), 0.35, 0.85)
tube = loft("QuiverTube", [(0.0, 0.040, 0.030, 24), (0.012, 0.046, 0.034, 24), (TUBE * 0.5, 0.050, 0.037, 24),
                           (TUBE - 0.01, 0.055, 0.041, 24), (TUBE, 0.055, 0.041, 24)], 0, caps=(True, False))
inner = loft("QuiverInner", [(0.02, 0.043, 0.032, 24), (TUBE * 0.5, 0.047, 0.034, 24), (TUBE + 0.002, 0.052, 0.038, 24)], 0,
             caps=(True, False), inward=True)   # the open mouth shows a dark inside
rim = loft("QuiverRim", [(TUBE - 0.012, 0.058, 0.044, 24), (TUBE + 0.004, 0.058, 0.044, 24), (TUBE + 0.004, 0.052, 0.038, 24),
                         (TUBE - 0.006, 0.052, 0.038, 24)], 1, caps=(False, False))   # a wooden ring with an inner lip
foot = loft("QuiverFoot", [(-0.004, 0.044, 0.033, 24), (0.02, 0.048, 0.036, 24)], 1)
buckles = [loft("QuiverBuckle", [(z - 0.012, 0.012, 0.006, 6), (z + 0.012, 0.012, 0.006, 6)], 2) for z in (0.12, TUBE - 0.08)]
for bk in buckles:
    bk.location = (0.0, 0.040, 0.0)   # on the back, against the spine
arrows_in = []
spots = [(0.0, 0.0), (0.024, 0.012), (-0.024, 0.012), (0.026, -0.014), (-0.026, -0.014), (0.0, 0.022), (0.0, -0.022)]
for i, (x, y) in enumerate(spots):
    q = arrow("QuiverArrow%d" % i, arrow_mats, top_only=0.32)   # the fletched end; flipped so the nock is up
    q.rotation_euler = (math.pi + rng.normal(0, 0.05), rng.normal(0, 0.05), rng.random() * 6.28)
    q.location = (x, y, TUBE + 0.19 + rng.normal(0, 0.008))
    arrows_in.append(q)
parts = [tube, inner, rim, foot] + buckles + arrows_in
for p in (tube, inner): p.data.materials.append(leather)
for p in (rim, foot): p.data.materials.append(leather); p.data.materials.append(wood)
for p in buckles: p.data.materials.append(leather); p.data.materials.append(wood); p.data.materials.append(bronze)
bpy.ops.object.select_all(action='DESELECT')
for p in parts: p.select_set(True)
bpy.context.view_layer.objects.active = tube
bpy.ops.object.join()
quiver = bpy.context.active_object; quiver.name = "ElvenQuiver"; quiver.data.name = "ElvenQuiver"
quiver.modifiers.new("Triangulate", 'TRIANGULATE')
export([quiver], os.path.join(OUT, "elven_quiver.glb"))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "elven_arrow_quiver.blend"))
result = {"arrow_dims": [round(d, 4) for d in arrow_dims], "arrow_tris": arrow_tris, "quiver_dims": [round(d, 4) for d in quiver.dimensions],
          "quiver_tris": sum(len(p.vertices) - 2 for p in quiver.data.polygons), "quiver_mats": [m.name for m in quiver.data.materials]}
