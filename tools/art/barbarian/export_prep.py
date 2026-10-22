# Blender: make every material glTF-plain (image -> Principled), merge the body's slots, decimate hidden mouth parts.
import bpy, numpy as np, os
SRC = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\barbarian\source"
ns = {}
exec(open(r"C:\Users\lloyd\OneDrive\Documents\curse\tools\art\barbarian\paint_skin.py").read().split("col = base[..., :3].copy()")[0], ns)
fbm, smooth = ns["fbm"], ns["smooth"]

def px(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32); img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)

def save(name, arr):
    H, W = arr.shape[:2]
    img = bpy.data.images.get(name) or bpy.data.images.new(name, W, H, alpha=True)
    if tuple(img.size) != (W, H): img.scale(W, H)
    img.pixels.foreach_set(np.nan_to_num(arr).astype(np.float32).ravel())
    img.filepath_raw = os.path.join(SRC, name + ".png"); img.file_format = 'PNG'; img.save()
    img.filepath = img.filepath_raw
    return img

def plain(mat, img, rough, alpha=False):
    nt = mat.node_tree; nt.nodes.clear()
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = img
    b = nt.nodes.new("ShaderNodeBsdfPrincipled"); o = nt.nodes.new("ShaderNodeOutputMaterial")
    b.inputs["Roughness"].default_value = rough
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if alpha:
        nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
        mat.surface_render_method = 'DITHERED'
    nt.links.new(b.outputs[0], o.inputs[0])

# Hair: the dark chestnut tint baked into the texture.
hair_src = [n.image for n in bpy.data.materials["Barbarian.long01"].node_tree.nodes if getattr(n, "image", None)][0]
h = px(hair_src).copy(); h[..., :3] *= np.array([0.55, 0.42, 0.33], np.float32)
plain(bpy.data.materials["Barbarian.long01"], save("barbarian_hair", h), 0.6, alpha=True)
for mn in ("Barbarian.eyebrow010", "Barbarian.eyelashes01"):
    m = bpy.data.materials[mn]
    img = [n.image for n in m.node_tree.nodes if getattr(n, "image", None)][0]
    plain(m, img, 0.7, alpha=True)
for mn, r in (("Barbarian.high-poly", 0.15), ("Barbarian.teeth_base", 0.35), ("Barbarian.tongue01", 0.4)):
    m = bpy.data.materials[mn]
    img = [n.image for n in m.node_tree.nodes if getattr(n, "image", None)][0]
    plain(m, img, r)

# Briefs: worn dark leather, grain and creases, stitched hem along the waist (same UVs as the body).
P, Z = ns["P"], ns["Z"]
grain = fbm(P + 2.0, 600.0, 3); crease = fbm(P * np.array([1, 1, 3.0], np.float32), 40.0, 3)
lc = np.array([0.11, 0.07, 0.042], np.float32) * (0.75 + 0.5 * grain[..., None]) * (0.8 + 0.4 * crease[..., None])
stitch = smooth(0.0012, 0.0006, np.abs(Z - 1.050)) * (np.sin(P[..., 0] * 900.0 + P[..., 1] * 900.0) > 0.2)
lc = lc * (1 - 0.6 * stitch[..., None])
H, W = lc.shape[:2]
plain(bpy.data.materials["barbarian_briefs"], save("barbarian_leather", np.concatenate([np.clip(lc, 0, 1), np.ones((H, W, 1), np.float32)], -1)), 0.7)

# Body: one material slot.
body = bpy.data.objects["Body"]
for p in body.data.polygons: p.material_index = 0
while len(body.data.materials) > 1: body.data.materials.pop(index=len(body.data.materials) - 1)

# Mouth parts sit behind the lips: keep them light.
for n, ratio in (("Teeth", 0.12), ("Tongue", 0.5)):
    o = bpy.data.objects[n]
    d = o.modifiers.new("Decimate", 'DECIMATE'); d.ratio = ratio
    bpy.context.view_layer.objects.active = o
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_move_to_index(modifier="Decimate", index=0)
        bpy.ops.object.modifier_apply(modifier="Decimate")
result = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH'}
result["total"] = sum(result.values())
