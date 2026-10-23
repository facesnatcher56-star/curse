# Blender (Blender MCP), on an empty scene: the wood elf's bow, a yew longbow with an elven riser.
#
# Built to the game's bow contract (game/player/bow_attack.gd): upright (limbs along Blender Z = glTF Y), 1.58 m tip to
# tip, the belly toward Blender -X (the target) and the string side toward +X (the archer). Centred on its bounding box,
# the string line is at x = +0.065 and the nocks at z = +-0.78 (the game draws the string between those points), and
# the grip is 0.065 toward the target from the centre. So: handle face at x = -0.065, limb tips at x = +0.065.
#
# Real yew: pale sapwood on the target side, red-brown heartwood on the archer side; a leather-wrapped grip; a silvered
# vine inlaid along the riser; horn tip caps that curl forward past the nocks. One material with base colour,
# metal/roughness and normal maps (1024 x 2048, v along the bow), saved to the elf's source folder.
import bpy, bmesh, math, os, numpy as np

OUT = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\elf\source"
HALF = 0.79            # tip to centre
NOCK = 0.78            # where the string ties on
FRONT = -0.065         # handle face (target side)
BACK = 0.065           # string line, = limb tips' back face
GRIP = 0.065           # half length of the leather grip
RINGS = 120
SIDES = 16

def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)

def section(s):
    """centre x, depth (along x) and width (along y) of the bow at distance s from the middle."""
    if s <= 0.07:                                   # handle: deep, rounded
        depth, width = 0.036, 0.030
    else:                                           # fades into the limb, then a leaf-shaped taper to the tip
        f = smooth(0.07, 0.15, s)
        u = min(max((s - 0.15) / (NOCK - 0.15), 0.0), 1.0)
        leaf = 1.0 + 0.12 * math.sin(math.pi * min(u * 1.4, 1.0))   # swells a little, like a leaf, then narrows
        depth = 0.036 + f * (0.022 - 0.036) - u * 0.011
        width = 0.030 + f * (0.034 - 0.030)
        width = width * leaf * (1.0 - 0.62 * u ** 1.3)
    if s > NOCK - 0.006:                            # horn cap: swells at the string groove, then rounds off to a blunt point
        k = min(max((s - (NOCK - 0.006)) / (HALF - (NOCK - 0.006)), 0.0), 1.0)
        round_off = math.sqrt(max(1.0 - k ** 2.2, 0.0))
        depth *= (1.0 + 0.25 * math.sin(math.pi * min(k * 2.0, 1.0))) * max(round_off, 0.12)
        width *= (1.0 + 0.15 * math.sin(math.pi * min(k * 2.0, 1.0))) * max(round_off, 0.12)
    # the back face (toward the string) follows a curve from the handle to the string line at the nock
    back_handle = FRONT + 0.036
    u = min(max((s - 0.07) / (NOCK - 0.07), 0.0), 1.0)
    back = back_handle + (BACK - back_handle) * u ** 1.7
    if s > NOCK:                                    # the cap curls forward past the nock
        back -= 0.014 * ((s - NOCK) / (HALF - NOCK)) ** 1.5
    return back - depth * 0.5, depth, width

def build_mesh():
    bm = bmesh.new()
    rings = []
    # even rings along the limbs, dense at the tips so the 1 cm horn caps are round, not chopped
    body = [0.765 * (2.0 * i / RINGS - 1.0) for i in range(RINGS + 1)]
    tip = [0.765 + (HALF - 0.765) * (j / 10.0) ** 0.8 for j in range(1, 11)]
    zs = [-t for t in reversed(tip)] + body + tip
    rings_n = len(zs) - 1
    for z in zs:
        cx, d, w = section(abs(z))
        ring = []
        for k in range(SIDES):
            a = 2 * math.pi * k / SIDES
            c, s = math.cos(a), math.sin(a)
            # a squared-off ellipse: flat-ish sides, rounded belly and back
            ex = math.copysign(abs(c) ** 0.7, c); ey = math.copysign(abs(s) ** 0.7, s)
            ring.append(bm.verts.new((cx + ex * d * 0.5, ey * w * 0.5, z)))
        rings.append(ring)
    uv = bm.loops.layers.uv.new("UVMap")
    for i in range(rings_n):
        for k in range(SIDES):
            k2 = (k + 1) % SIDES
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            for loop, (kk, ii) in zip(f.loops, ((k, i), (k + 1, i), (k + 1, i + 1), (k, i + 1))):
                loop[uv].uv = (kk / SIDES, (zs[ii] + HALF) / (2 * HALF))
    for ring, v in ((rings[0], 0.0), (rings[-1], 1.0)):
        f = bm.faces.new(ring if v > 0.5 else list(reversed(ring)))
        for loop in f.loops:
            loop[uv].uv = (0.5, v)
    bm.normal_update()
    me = bpy.data.meshes.new("ElvenBow"); bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new("ElvenBow", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob

def textures():
    """base colour, ORM (glTF: R unused, G roughness, B metallic) and normal maps; rows run tip (v=0) to tip (v=1)."""
    W, H = 1024, 2048
    rng = np.random.default_rng(11)
    u = np.linspace(0, 1, W)[None, :].repeat(H, 0)          # around the section: 0 = archer side (+x), 0.5 = target side
    v = np.linspace(0, 1, H)[:, None].repeat(W, 1)
    s = np.abs(v * 2 * HALF - HALF)                          # distance from the middle (m)
    ang = u * 2 * math.pi
    target_side = 0.5 - 0.5 * np.cos(ang)                    # 0 on the archer side, 1 on the target side
    def noise(rows, cols, scale_r, scale_c, octaves=4):
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
    grain = noise(40, 6, 0, 0, 4)                            # long streaks along the bow
    fine = noise(400, 30, 0, 0, 3)
    sap = np.array([0.82, 0.68, 0.48]); heart = np.array([0.50, 0.27, 0.14])
    mix = np.clip((target_side - 0.35) / 0.3, 0, 1)[..., None]   # the sap/heart boundary runs down the sides
    wood = heart * (1 - mix) + sap * mix
    wood = wood * (0.82 + 0.3 * (grain[..., None] - 0.5) + 0.1 * (fine[..., None] - 0.5))
    rough = 0.42 + 0.12 * (grain - 0.5)
    metal = np.zeros((H, W)); height = (grain - 0.5) * 0.3
    # grip: dark green-brown leather cord, wound in a spiral
    grip = (s < GRIP)
    cord = np.sin(((u + v * 2 * HALF / 0.006) % 1.0) * math.pi) ** 0.6
    leather = np.array([0.07, 0.075, 0.045]) * (0.8 + 0.4 * cord[..., None])
    wood = np.where(grip[..., None], leather, wood)
    rough = np.where(grip, 0.68 + 0.1 * (1 - cord), rough); height = np.where(grip, cord * 0.35, height)
    # silvered vine inlaid along both flat sides of the riser, outside the grip
    riser = (s > GRIP + 0.01) & (s < 0.26)
    for side_u in (0.25, 0.75):
        du = (u - side_u) * 2 * math.pi * 0.012              # metres across the face (about)
        z = s
        wave = 0.0045 * np.sin(z * 2 * math.pi / 0.06 + (0 if side_u < 0.5 else math.pi))
        stem = np.clip(1 - np.abs(du - wave) / 0.0013, 0, 1)
        leaves = np.zeros_like(stem)
        for k in range(6):
            zk = GRIP + 0.025 + k * 0.03
            dz = z - zk; dx = du - (0.0045 * math.sin(zk * 2 * math.pi / 0.06) + (0.003 if k % 2 else -0.003))
            leaves = np.maximum(leaves, np.clip(1 - ((dz / 0.006) ** 2 + (dx / 0.0026) ** 2), 0, 1) ** 0.3)
        inlay = np.clip(stem + leaves, 0, 1) * riser
        wood = wood * (1 - inlay[..., None]) + np.array([0.72, 0.76, 0.70]) * inlay[..., None]
        rough = rough * (1 - inlay) + 0.3 * inlay; metal = np.maximum(metal, inlay * 0.85); height -= inlay * 0.6
    # horn tip caps past the nocks, with a thin dark ring where the string ties on
    cap = s > NOCK - 0.004
    horn = np.array([0.86, 0.82, 0.70]) * (0.9 + 0.15 * (fine[..., None] - 0.5))
    wood = np.where(cap[..., None], horn, wood)
    rough = np.where(cap, 0.35, rough)
    tie = np.abs(s - (NOCK - 0.006)) < 0.0025
    wood = np.where(tie[..., None], np.array([0.12, 0.1, 0.08]), wood)
    gy, gx = np.gradient(height.astype(np.float32))
    n = np.dstack([-gx * 2.0, -gy * 2.0, np.ones((H, W))]); n /= np.linalg.norm(n, axis=2, keepdims=True)
    orm = np.dstack([np.ones((H, W)), np.clip(rough, 0, 1), np.clip(metal, 0, 1)])
    return {"basecolor": np.clip(wood, 0, 1), "orm": orm, "normal": n * 0.5 + 0.5}

def save(name, rgb, non_color):
    H, W = rgb.shape[:2]
    img = bpy.data.images.get(name) or bpy.data.images.new(name, W, H, alpha=False)
    if tuple(img.size) != (W, H): img.scale(W, H)
    px = np.concatenate([rgb, np.ones((H, W, 1))], axis=2).astype(np.float32)
    img.pixels.foreach_set(px.ravel())                        # row 0 = v 0 (Blender images are bottom-up, so is v)
    img.filepath_raw = os.path.join(OUT, name + ".png"); img.file_format = 'PNG'; img.save(); img.filepath = img.filepath_raw
    if non_color: img.colorspace_settings.name = "Non-Color"
    return img

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bow = build_mesh()
maps = textures()
imgs = {k: save("elven_bow_" + k, maps[k], k != "basecolor") for k in maps}
m = bpy.data.materials.get("elven_bow") or bpy.data.materials.new("elven_bow")
m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
b = nt.nodes.new("ShaderNodeBsdfPrincipled"); o = nt.nodes.new("ShaderNodeOutputMaterial")
tb = nt.nodes.new("ShaderNodeTexImage"); tb.image = imgs["basecolor"]
to = nt.nodes.new("ShaderNodeTexImage"); to.image = imgs["orm"]
tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = imgs["normal"]
sep = nt.nodes.new("ShaderNodeSeparateColor"); nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tb.outputs["Color"], b.inputs["Base Color"])
nt.links.new(to.outputs["Color"], sep.inputs["Color"])
nt.links.new(sep.outputs["Green"], b.inputs["Roughness"]); nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
nt.links.new(tn.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
nt.links.new(b.outputs[0], o.inputs[0])
bow.data.materials.append(m)
bow.modifiers.new("Triangulate", 'TRIANGULATE')
bpy.context.view_layer.update()
bb = [bow.matrix_world @ __import__("mathutils").Vector(c) for c in bow.bound_box]
mn = [min(c[i] for c in bb) for i in range(3)]; mx = [max(c[i] for c in bb) for i in range(3)]
centre = [(a + c) * 0.5 for a, c in zip(mn, mx)]
result = {"size": [round(c - a, 4) for a, c in zip(mn, mx)], "centre": [round(c, 4) for c in centre],
          "back_minus_centre": round(mx[0] - centre[0], 4), "tris": sum(len(p.vertices) - 2 for p in bow.data.polygons)}
