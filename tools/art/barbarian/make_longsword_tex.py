# Blender (after make_longsword.py): UVs and procedural textures for the Longsword, one texture set per material:
# base colour, metal/roughness (glTF: G roughness, B metallic) and a normal map, 1024 px, saved next to the .blend.
import bpy, bmesh, math, os, numpy as np

OUT = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\items\longsword\source"
R = 1024
os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, ".gdignore"), "a").close()
rng = np.random.default_rng(7)
sword = bpy.data.objects["Longsword"]
me = sword.data
mats = [m.name for m in me.materials]

# --- UVs: blade planar (width x, length z), grip cylindrical, iron fittings box-projected by their main axes
bm = bmesh.new(); bm.from_mesh(me)
uv = bm.loops.layers.uv.verify()
for f in bm.faces:
    name = mats[f.material_index]
    for l in f.loops:
        x, y, z = l.vert.co
        if name == "longsword_steel":
            l[uv].uv = (x / 0.06 + 0.5, (z - 0.17) / 0.8)
        elif name == "longsword_leather":
            l[uv].uv = (math.atan2(y, x) / (2 * math.pi) + 0.5, (z - 0.05) / 0.11)
        else:
            n = f.normal
            if abs(n.y) >= max(abs(n.x), abs(n.z)):
                l[uv].uv = (x / 0.25 + 0.5, z / 0.25 + 0.1)
            elif abs(n.x) >= abs(n.z):
                l[uv].uv = (y / 0.25 + 0.5, z / 0.25 + 0.1)
            else:
                l[uv].uv = (x / 0.25 + 0.5, y / 0.25 + 0.5)
bm.to_mesh(me); bm.free()

def noise(shape, scale, octaves=4, stretch=(1, 1)):
    out = np.zeros(shape, np.float32); amp, tot = 1.0, 0.0
    for o in range(octaves):
        h = max(2, int(shape[0] / scale / stretch[0] * 2 ** o)); w = max(2, int(shape[1] / scale / stretch[1] * 2 ** o))
        small = rng.random((h, w)).astype(np.float32)
        yi = np.linspace(0, h - 1, shape[0]); xi = np.linspace(0, w - 1, shape[1])
        y0 = np.floor(yi).astype(int); x0 = np.floor(xi).astype(int)
        y1 = np.minimum(y0 + 1, h - 1); x1 = np.minimum(x0 + 1, w - 1)
        fy = (yi - y0)[:, None]; fx = (xi - x0)[None, :]
        a = small[y0][:, x0]; b = small[y0][:, x1]; c = small[y1][:, x0]; d = small[y1][:, x1]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        tot += amp; amp *= 0.5
    return out / tot

def scratches(n, length, width):
    img = np.zeros((R, R), np.float32)
    for _ in range(n):
        x, y = rng.random() * R, rng.random() * R
        ang = rng.normal(0, 0.35) + (math.pi / 2 if rng.random() < 0.3 else 0)
        ln = length * (0.3 + rng.random())
        for s in np.linspace(0, ln, int(ln)):
            px, py = int(x + math.cos(ang) * s) % R, int(y + math.sin(ang) * s) % R
            img[py, max(px - width, 0):px + width + 1] = np.maximum(img[py, max(px - width, 0):px + width + 1], rng.random() * 0.6 + 0.4)
    return img

def normal_from_height(h, strength):
    gy, gx = np.gradient(h)
    n = np.dstack([-gx * strength, -gy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5

def save(name, rgb, non_color=False):
    img = bpy.data.images.get(name) or bpy.data.images.new(name, R, R, alpha=False)
    if tuple(img.size) != (R, R): img.scale(R, R)
    px = np.concatenate([np.clip(rgb, 0, 1), np.ones((R, R, 1), np.float32)], axis=2)
    img.pixels.foreach_set(px[::-1].astype(np.float32).ravel())   # rows top-down -> Blender bottom-up
    img.filepath_raw = os.path.join(OUT, name + ".png"); img.file_format = 'PNG'; img.save()
    img.filepath = img.filepath_raw
    if non_color: img.colorspace_settings.name = "Non-Color"
    return img

def hook(mat_name, base, orm, nrm):
    m = bpy.data.materials[mat_name]; nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    for n in list(nt.nodes):
        if n.bl_idname in ("ShaderNodeTexImage", "ShaderNodeSeparateColor", "ShaderNodeNormalMap"): nt.nodes.remove(n)
    tb = nt.nodes.new("ShaderNodeTexImage"); tb.image = base
    to = nt.nodes.new("ShaderNodeTexImage"); to.image = orm
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = nrm
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tb.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])

# --- blade: polished steel with grinding lines along the length, scuffs, a brighter honed edge
u = np.linspace(0, 1, R)[None, :].repeat(R, 0)
grind = noise((R, R), 2, 3, stretch=(40, 1))          # long streaks down the blade (v is rows)
scuff = scratches(90, 45, 0) * 0.5
edge = np.clip((np.abs(u - 0.5) - 0.36) / 0.08, 0, 1)   # outer bevel of the blade, honed brighter
blot = noise((R, R), 60, 3)
col = 0.66 + 0.06 * (grind - 0.5) + 0.10 * edge - 0.05 * (blot - 0.5)
base = np.dstack([col * 0.98, col, col * 1.03])
rough = np.clip(0.34 + 0.10 * (grind - 0.5) + 0.15 * scuff + 0.10 * (blot - 0.5) - 0.08 * edge, 0.12, 0.75)
# metallic below 1: the game's dungeons have little for a mirror to reflect, and full metal reads black there
orm = np.dstack([np.ones((R, R)), rough, np.full((R, R), 0.55)])
steel = [save("longsword_steel_basecolor", base), save("longsword_steel_orm", orm, True),
         save("longsword_steel_normal", normal_from_height(grind * 0.4 - scuff * 0.4, 1.5), True)]

# --- grip: dark leather cord wound in a spiral, with grain
v = np.linspace(0, 1, R)[:, None].repeat(R, 1)
phase = (u + v * 9.0) % 1.0                                   # nine turns of cord down the grip
cord = np.sin(phase * math.pi) ** 0.6                         # rounded cord section, groove between turns
grain = noise((R, R), 6, 4)
col = (0.035 + 0.055 * cord + 0.02 * (grain - 0.5))
base = np.dstack([col * 1.6, col * 1.0, col * 0.62])
rough = np.clip(0.62 + 0.15 * (1 - cord) + 0.08 * (grain - 0.5), 0, 1)
orm = np.dstack([np.ones((R, R)), rough, np.zeros((R, R))])
leather = [save("longsword_leather_basecolor", base), save("longsword_leather_orm", orm, True),
           save("longsword_leather_normal", normal_from_height(cord * 3.0 + grain * 0.4, 3.0), True)]

# --- guard and pommel: dark forged iron, pitted, rubbed brighter where hands wear it
pit = noise((R, R), 1.2, 3)
patina = noise((R, R), 40, 3)
col = 0.30 + 0.06 * (patina - 0.5) - 0.03 * np.clip((pit - 0.7) * 6, 0, 1)
base = np.dstack([col * 1.05, col, col * 0.95])
rough = np.clip(0.42 + 0.15 * (patina - 0.5) + 0.12 * np.clip((pit - 0.7) * 5, 0, 1), 0, 1)
orm = np.dstack([np.ones((R, R)), rough, np.full((R, R), 0.5)])
iron = [save("longsword_iron_basecolor", base), save("longsword_iron_orm", orm, True),
        save("longsword_iron_normal", normal_from_height(-np.clip((pit - 0.7) * 3, 0, 1), 1.2), True)]

hook("longsword_steel", *steel); hook("longsword_leather", *leather); hook("longsword_iron", *iron)
result = {"textures": 9, "out": OUT}
