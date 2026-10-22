# Blender (elf_mpfb_editable.blend open): paints the wood elf's skin from the baked position/normal maps
# (tools/art/hero/bake_position_maps.py): a light sun-touched tone, a few freckles, a vine tattoo spiralling up the left
# forearm, and a short curve of small leaf marks at the outer corner of each eye. Writes elf_basecolor.png.
import bpy, numpy as np, math

SRC_DIR = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\elf\source"
OUT = SRC_DIR + r"\elf_basecolor.png"
SKIN = r"C:\Users\lloyd\AppData\Roaming\Blender Foundation\Blender\5.1\extensions\.user\blender_org\mpfb\data\skins\young_caucasian_male\young_lightskinned_male_diffuse.png"

def px(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)

def baked(kind):
    img = bpy.data.images.get("bake_" + kind)
    if img is None:
        img = bpy.data.images.load(SRC_DIR + "\\bake_%s.exr" % kind); img.name = "bake_" + kind
        img.colorspace_settings.name = "Non-Color"
    return px(img)

pos = baked("pos"); nrm = baked("nrm")
H, W = pos.shape[:2]
import os
skin_path = SKIN if os.path.exists(SKIN) else [os.path.join(os.path.dirname(SKIN), f) for f in os.listdir(os.path.dirname(SKIN)) if f.endswith("diffuse.png")][0]
src = bpy.data.images.load(skin_path, check_existing=True)
if tuple(src.size) != (W, H):
    s2 = src.copy(); s2.scale(W, H); base = px(s2); bpy.data.images.remove(s2)
else:
    base = px(src)
valid = pos[..., 3] > 0.5
X, Y, Z = pos[..., 0], pos[..., 1], pos[..., 2]
P = pos[..., :3]

def hash3(i, j, k):
    h = (i * 73856093) ^ (j * 19349663) ^ (k * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF).astype(np.float32) / 65535.0

def vnoise(p, freq):
    q = p * freq
    i = np.floor(q).astype(np.int64); f = q - i
    f = f * f * (3 - 2 * f)
    acc = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                acc = acc + w * hash3(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz)
    return acc

def fbm(p, freq, octaves=4):
    s, a, t = 0, 0.5, 0
    for _ in range(octaves):
        s = s + a * vnoise(p, freq); t += a; a *= 0.5; freq *= 2.03
    return s / t

def smooth(e0, e1, x):
    d = e1 - e0
    d = np.where(np.abs(d) < 1e-9, 1e-9, d)
    t = np.clip((x - e0) / d, 0, 1)
    return t * t * (3 - 2 * t)

col = base[..., :3].copy()
# light, sun-touched skin: a little warmer and darker on the exposed upper body, gently uneven
tan = np.array([0.97, 0.88, 0.78], np.float32)
upper = smooth(1.1, 1.6, Z)
col = col * tan * (0.97 - 0.05 * upper[..., None] + 0.06 * (fbm(P, 9.0)[..., None] - 0.5))

def ink(mask, colour, strength):
    global col
    m = np.clip(np.nan_to_num(mask), 0, 1)[..., None] * strength
    col = col * (1 - m) + (col * np.array(colour, np.float32)) * m

head = (Z > 1.65) & valid
# freckles across the nose and cheeks
eyes = bpy.data.objects["Elf.high-poly"]
dg = bpy.context.evaluated_depsgraph_get()
em = eyes.evaluated_get(dg).to_mesh()
ev = np.array([tuple(eyes.matrix_world @ v.co) for v in em.vertices])
eyes.evaluated_get(dg).to_mesh_clear()
eye_l = ev[ev[:, 0] > 0].mean(axis=0); eye_r = ev[ev[:, 0] < 0].mean(axis=0)
eye_z = float((eye_l[2] + eye_r[2]) * 0.5)
face = smooth(-0.04, -0.08, Y) * head
freck_zone = smooth(0.06, 0.03, np.abs(Z - (eye_z - 0.03))) * smooth(0.07, 0.05, np.abs(X)) * face
speck = smooth(0.78, 0.86, fbm(P + 4.0, 700.0, 2))
ink(freck_zone * speck, (0.62, 0.45, 0.32), 0.55)

# leaf marks: a short curve of small leaf shapes from the outer corner of each eye, up toward the temple
leaves = np.zeros((H, W), np.float32)
for e, side in ((eye_l, 1.0), (eye_r, -1.0)):
    for k in range(4):
        t = k / 3.0
        cx = e[0] + side * (0.026 + 0.012 * t)
        cz = e[2] - 0.006 + 0.022 * t
        ang = math.radians(60 + 25 * t) * side
        dx, dz = X - cx, Z - cz
        u = dx * math.cos(ang) + dz * math.sin(ang)
        v = -dx * math.sin(ang) + dz * math.cos(ang)
        size = 0.0048 - 0.0006 * k
        # a leaf: pointed at both ends, widest in the middle, with a fine midrib left in skin
        width = size * 0.36 * np.clip(1.0 - (u / size) ** 2, 0.0, 1.0)
        leaf = smooth(1.05, 0.85, np.abs(v) / np.maximum(width, 1e-6)) * (np.abs(u) < size)
        leaf *= smooth(0.00025, 0.0006, np.abs(v)) * 0.35 + 0.65
        leaves = np.maximum(leaves, leaf * smooth(-0.03, -0.07, Y) * head)
ink(leaves, (0.26, 0.4, 0.3), 0.7)

# vine tattoo spiralling up the left forearm, with leaves along it
rig = bpy.data.objects["Elf.rig"]
bb = rig.data.bones["lowerarm_l"]
h = np.array(bb.head_local); tl = np.array(bb.tail_local)
ax = tl - h; L = np.linalg.norm(ax); ax /= L
rel = P - h
t = (rel @ ax) / L
radial = rel - (rel @ ax)[..., None] * ax
ref = np.cross(ax, np.array([0, 1.0, 0])); ref /= np.linalg.norm(ref); ref2 = np.cross(ax, ref)
theta = np.arctan2(radial @ ref2, radial @ ref)
r = np.linalg.norm(radial, axis=-1)
near = (r < 0.07) & valid & (t > 0.12) & (t < 0.92)
turns = 1.6
phase = (theta / (2 * math.pi) - t * turns) % 1.0
vine = smooth(0.035, 0.02, np.abs(phase - 0.5)) * near
leafy = np.zeros((H, W), np.float32)
for k in range(7):
    tk = 0.18 + 0.1 * k
    th = 2 * math.pi * (tk * turns + 0.5) + (0.35 if k % 2 else -0.35)
    dth = np.angle(np.exp(1j * (theta - th)))
    leafy = np.maximum(leafy, smooth(1.0, 0.7, (dth / 0.32) ** 2 + ((t - tk) / 0.035) ** 2) * near)
ink(np.maximum(vine, leafy), (0.16, 0.30, 0.18), 0.8)

col = np.where(valid[..., None], col, base[..., :3])
img = bpy.data.images.get("elf_basecolor") or bpy.data.images.new("elf_basecolor", W, H, alpha=False)
if tuple(img.size) != (W, H): img.scale(W, H)
img.pixels.foreach_set(np.nan_to_num(np.concatenate([np.clip(col, 0, 1), np.ones((H, W, 1), np.float32)], -1)).astype(np.float32).ravel())
img.filepath_raw = OUT; img.file_format = 'PNG'; img.save(); img.filepath = OUT
result = {"saved": OUT, "skin": skin_path, "eye_z": round(eye_z, 3), "leaf_px": int((leaves > 0.5).sum()), "vine_px": int((vine > 0.5).sum())}
