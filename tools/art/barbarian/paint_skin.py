# Run inside Blender (Blender MCP): paints the barbarian's skin from the baked position/normal maps.
import bpy, numpy as np, math

OUT = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\barbarian\source\barbarian_basecolor.png"

def px(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)

SCR = r"C:\Users\lloyd\OneDrive\Documents\curse\tools\art\barbarian"
SRC_DIR = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\barbarian\source"
def baked(kind):
    img = bpy.data.images.get("bake_" + kind)
    if img is None:
        img = bpy.data.images.load(SRC_DIR + "\\bake_%s.exr" % kind); img.name = "bake_" + kind
        img.colorspace_settings.name = "Non-Color"
    return px(img)
pos = baked("pos"); nrm = baked("nrm")
H, W = pos.shape[:2]
src = bpy.data.images.get("middleage_lightskinned_male_diffuse.png") or bpy.data.images.load(
    r"C:\Users\lloyd\AppData\Roaming\Blender Foundation\Blender\5.1\extensions\.user\blender_org\mpfb\data\skins\middleage_caucasian_male\middleage_lightskinned_male_diffuse.png")
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

def fbm(p, freq, oct=4):
    s, a, t = 0, 0.5, 0
    for _ in range(oct):
        s = s + a * vnoise(p, freq); t += a; a *= 0.5; freq *= 2.03
    return s / t

def smooth(e0, e1, x):
    d = e1 - e0
    d = np.where(np.abs(d) < 1e-9, 1e-9, d)
    t = np.clip((x - e0) / d, 0, 1)
    return t * t * (3 - 2 * t)

col = base[..., :3].copy()

# 1. Sun-tanned, weathered skin: warmer and darker, more on the exposed upper body, blotchy.
tan = np.array([0.96, 0.84, 0.74], np.float32)
weather = fbm(P, 9.0)
upper = smooth(1.0, 1.5, Z)
col = col * tan * (0.90 - 0.06 * upper[..., None] + 0.12 * (weather[..., None] - 0.5))
grime = fbm(P + 3.1, 4.0)
col = col * (1 - 0.05 * smooth(0.6, 0.85, grime)[..., None] * np.array([0.8, 1.0, 1.2], np.float32))

def ink(mask, colour, strength):
    global col
    m = np.clip(mask, 0, 1)[..., None] * strength
    col = col * (1 - m) + (col * np.array(colour, np.float32)) * m   # multiply-style ink keeps the skin detail

def paint(mask, colour, strength):
    global col
    m = np.clip(mask, 0, 1)[..., None] * strength
    col = col * (1 - m) + np.array(colour, np.float32) * m

head = (Z > 1.6) & valid
front = smooth(-0.02, -0.07, Y)          # face front is -Y

# Mouth centre (measured from MPFB's lips material slot, slot 2, before the skin material replaced it).
mouth = np.array([0.0, -0.159, 1.698])

# 2. Beard: short, dense dark beard over jaw, chin, upper lip and under the jaw; lips kept clear.
dm = np.sqrt(((X - mouth[0]) / 0.026) ** 2 + ((Z - mouth[2]) / 0.009) ** 2)
lips_clear = smooth(0.9, 1.3, dm) * 1.0
jaw = smooth(mouth[2] + 0.035, mouth[2] + 0.015, Z) * smooth(1.60, 1.635, Z)
cheekline = smooth(-0.035, -0.075, Y) + smooth(0.0, 0.02, -Y) * smooth(mouth[2] + 0.0, mouth[2] - 0.02, Z) * smooth(0.06, 0.04, np.abs(X))
beard = jaw * np.clip(cheekline, 0, 1) * lips_clear * head
stubble = fbm(P + 7.0, 900.0, 2)
hairy = beard * (0.75 + 0.35 * (stubble - 0.5)) * (0.85 + 0.3 * (fbm(P, 60.0, 2) - 0.5))
paint(hairy, (0.05, 0.032, 0.02), 0.75)

# 3. Woad war paint: a ragged band across the eyes, temple to temple, with three drips down the left cheek.
eye_z = 1.773
edge = 0.004 * (fbm(P + 11.0, 120.0) - 0.5) * 2
band = smooth(0.017, 0.012, np.abs(Z - eye_z + 0.002) + edge) * smooth(-0.04, -0.08, Y) * head
drips = 0
for xc, length in ((0.040, 0.050), (0.052, 0.038), (0.064, 0.044)):
    wdt = 0.0045 * smooth(eye_z - 0.02 - length, eye_z - 0.02, Z)
    drips = drips + smooth(wdt, wdt * 0.5, np.abs(X - xc)) * smooth(eye_z - 0.022 - length, eye_z - 0.018 - length, Z) * (Z < eye_z) * smooth(-0.05, -0.09, Y)
dry = 0.75 + 0.35 * (fbm(P + 5.0, 300.0, 3) - 0.5)
paint(np.clip(band + drips, 0, 1) * dry * head, (0.04, 0.07, 0.17), 0.9)

# Scar through the right eyebrow and down onto the cheek: pale, slightly pink.
a = np.array([-0.036, eye_z + 0.040]); b = np.array([-0.022, eye_z - 0.034])
ab = b - a; t = np.clip(((X - a[0]) * ab[0] + (Z - a[1]) * ab[1]) / (ab @ ab), 0, 1)
d = np.hypot(X - (a[0] + ab[0] * t), Z - (a[1] + ab[1] * t))
scar = smooth(0.0016, 0.0007, d) * smooth(-0.06, -0.10, Y) * head * (1 - band * 0.0)
paint(scar, (0.78, 0.55, 0.50), 0.75)

# 4. Tribal tattoos (dark ink). Cylindrical coordinates around a limb.
rig = bpy.data.objects["Barbarian.rig"]
def limb(bone):
    bb = rig.data.bones[bone]
    h = np.array(bb.head_local); tl = np.array(bb.tail_local)
    ax = tl - h; L = np.linalg.norm(ax); ax /= L
    rel = P - h
    t = (rel @ ax) / L
    radial = rel - (rel @ ax)[..., None] * ax
    ref = np.cross(ax, np.array([0, 1.0, 0])); ref /= np.linalg.norm(ref); ref2 = np.cross(ax, ref)
    theta = np.arctan2(radial @ ref2, radial @ ref)
    r = np.linalg.norm(radial, axis=-1)
    return t, theta, r

tattoo = np.zeros((H, W), np.float32)
for side in ("l", "r"):
    t, th, r = limb("upperarm_" + side)
    near = (r < 0.09) & valid
    # Shark-tooth band between two border lines, two thirds down the upper arm.
    t0, t1 = 0.42, 0.66
    lines = smooth(0.012, 0.006, np.abs(t - t0)) + smooth(0.012, 0.006, np.abs(t - t1))
    tb = (t - (t0 + 0.03)) / (t1 - t0 - 0.06)
    tri = np.abs(((th / (2 * math.pi) * 9) % 1.0) - 0.5) * 2
    teeth = smooth(0.03, -0.01, tb - tri * 0.95) * (tb > 0) * (tb < 1)
    tattoo = np.maximum(tattoo, np.clip(lines + teeth, 0, 1) * near)
    # Forearm: three thin rings near the wrist.
    t, th, r = limb("lowerarm_" + side)
    near = (r < 0.07) & valid
    rings = sum(smooth(0.010, 0.005, np.abs(t - c)) for c in (0.70, 0.76, 0.82))
    tattoo = np.maximum(tattoo, np.clip(rings, 0, 1) * near)

# Triskelion over the left pectoral: three spirals around a centre, on the front of the chest.
cx, cz = 0.105, 1.43
chest = (nrm[..., 1] < -0.35) & (Y < 0.0) & (Z > 1.30) & (Z < 1.56) & valid
tri = np.zeros((H, W), np.float32)
for k in range(3):
    ang = k * 2 * math.pi / 3 + math.pi / 2
    sx, sz = cx + 0.022 * math.cos(ang), cz + 0.022 * math.sin(ang)
    dx, dz = X - sx, Z - sz
    rr = np.hypot(dx, dz); ph = np.arctan2(dz, dx) - ang
    turns = rr / 0.0075 - ph / (2 * math.pi)
    arm_line = smooth(0.22, 0.12, np.abs((turns % 1.0) - 0.5)) * (rr < 0.024)
    tri = np.maximum(tri, arm_line)
ring = smooth(0.0035, 0.0018, np.abs(np.hypot(X - cx, Z - cz) - 0.056))
tattoo = np.maximum(tattoo, np.clip(tri + ring, 0, 1) * chest)

# Ink sits in the skin: slightly uneven, faded.
fade = 0.82 + 0.18 * fbm(P + 21.0, 200.0, 3)
ink(tattoo * fade, (0.10, 0.12, 0.16), 0.85)

col = np.where(valid[..., None], col, base[..., :3])

strand = fbm(P * np.array([1.0, 1.0, 0.12], np.float32) + 3.0, 700.0, 3)
tone = 0.75 + 0.5 * fbm(P + 9.0, 80.0, 2)
bcol = np.array([0.15, 0.095, 0.058], np.float32) * (0.55 + 0.9 * strand)[..., None] * tone[..., None]
balpha = np.clip(beard * 1.35 - 0.25 + (strand - 0.5) * 0.9, 0, 1) * valid
bimg = bpy.data.images.get("barbarian_beard") or bpy.data.images.new("barbarian_beard", W, H, alpha=True)
bimg.pixels.foreach_set(np.nan_to_num(np.concatenate([np.clip(bcol, 0, 1), balpha[..., None]], axis=-1)).astype(np.float32).ravel())
bimg.filepath_raw = OUT.replace("basecolor", "beard"); bimg.file_format = 'PNG'; bimg.save()
outpx = np.concatenate([np.clip(col, 0, 1), np.ones((H, W, 1), np.float32)], axis=-1)
img = bpy.data.images.get("barbarian_basecolor") or bpy.data.images.new("barbarian_basecolor", W, H, alpha=False)
if tuple(img.size) != (W, H): img.scale(W, H)
img.pixels.foreach_set(np.nan_to_num(outpx).astype(np.float32).ravel())
img.filepath_raw = OUT; img.file_format = 'PNG'; img.save()
result = {"saved": OUT, "size": [W, H], "mouth": [round(float(v), 3) for v in mouth], "beard_px": int((beard > 0.5).sum()), "paint_px": int((band > 0.5).sum()), "tattoo_px": int((tattoo > 0.5).sum())}
