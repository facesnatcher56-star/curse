# Blender, with elf_mpfb_editable.blend open: builds the wood elf's game rig and exports assets/models/elf/rigged.glb.
# The shared steps (tools/art/hero) pose him to the knight2 rest directions, build the 54-bone skeleton and stand him on the
# ground; the rest here is his own: plain glTF materials (auburn hair, linen underwear, cut-out eyes, brows and lashes), mouth
# parts reduced, head parts joined into body_skin, base pieces named. Saves elf.blend next to the editable file.
import bpy, os, numpy as np

ROOT = r"C:\Users\lloyd\OneDrive\Documents\curse"
HERO = os.path.join(ROOT, r"tools\art\hero")
SRC = os.path.join(ROOT, r"assets\art_staging\elf\source")
BLEND = os.path.join(SRC, "elf.blend")
KNIGHT = os.path.join(ROOT, r"assets\models\knight2\rigged.glb")
CHAR, FOLDER = "Elf", "elf"
log = {}

def run(name):
    ns = {"CHAR": CHAR, "FOLDER": FOLDER}
    exec(open(os.path.join(HERO, name)).read(), ns)
    return ns.get("result")

# the knight2 skeleton is the reference for rest directions and bone names
coll = bpy.data.collections.new("Knight2Ref"); bpy.context.scene.collection.children.link(coll)
bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children["Knight2Ref"]
bpy.ops.import_scene.gltf(filepath=KNIGHT)
bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection

log["pose"] = run("pose_to_knight.py")
log["rig"] = run("build_game_rig.py")
for n in (CHAR + ".rig", "BakeProbe"):
    o = bpy.data.objects.get(n)
    if o: bpy.data.objects.remove(o, do_unlink=True)
for cn in ("Knight2Ref", "glTF_not_exported"):
    c = bpy.data.collections.get(cn)
    if c:
        for o in list(c.objects): bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c)
arm = bpy.data.objects[CHAR + "Armature"]; arm.name = "Armature"; arm.data.name = "Armature"
names = {"Elf": "Body", "Elf.briefs": "Briefs", "Elf.eyebrow003": "Eyebrows", "Elf.eyelashes01": "Eyelashes",
         "Elf.high-poly": "Eyes", "Elf.ponytail01": "Hair", "Elf.teeth_base": "Teeth", "Elf.tongue01": "Tongue"}
for a, b in names.items():
    bpy.data.objects[a].name = b

def px(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32); img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)

def save(name, arr):
    H, W = arr.shape[:2]
    img = bpy.data.images.get(name) or bpy.data.images.new(name, W, H, alpha=True)
    if tuple(img.size) != (W, H): img.scale(W, H)
    img.pixels.foreach_set(np.nan_to_num(arr).astype(np.float32).ravel())
    img.filepath_raw = os.path.join(SRC, name + ".png"); img.file_format = 'PNG'; img.save(); img.filepath = img.filepath_raw
    return img

def plain(obj_name, img, rough, cutout=False):
    obj = bpy.data.objects[obj_name]
    m = obj.material_slots[0].material
    nt = m.node_tree; nt.nodes.clear()
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = img
    b = nt.nodes.new("ShaderNodeBsdfPrincipled"); o = nt.nodes.new("ShaderNodeOutputMaterial")
    b.inputs["Roughness"].default_value = rough
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    if cutout:   # alpha cut-out (glTF MASK): a Round on the alpha
        r = nt.nodes.new("ShaderNodeMath"); r.operation = 'ROUND'
        nt.links.new(t.outputs["Alpha"], r.inputs[0]); nt.links.new(r.outputs[0], b.inputs["Alpha"])
        m.surface_render_method = 'DITHERED'
    nt.links.new(b.outputs[0], o.inputs[0])

def first_image(obj_name):
    m = bpy.data.objects[obj_name].material_slots[0].material
    return [n.image for n in m.node_tree.nodes if getattr(n, "image", None)][0]

# hair: auburn, a warm red-brown
h = px(first_image("Hair")).copy(); h[..., :3] *= np.array([0.78, 0.42, 0.24], np.float32)
plain("Hair", save("elf_hair", h), 0.55, cutout=True)
for n in ("Eyebrows", "Eyelashes", "Eyes"):
    plain(n, first_image(n), 0.15 if n == "Eyes" else 0.7, cutout=True)
for n in ("Teeth", "Tongue"):
    plain(n, first_image(n), 0.35)
# underwear: undyed moss-green linen, a fine weave
R = 512
yy, xx = np.mgrid[0:R, 0:R].astype(np.float32)
weave = 0.5 + 0.25 * np.sin(xx * 0.9) * np.sign(np.sin(yy * 0.9)) + 0.1 * np.random.default_rng(3).random((R, R))
lin = np.dstack([0.11 * (0.8 + 0.4 * weave), 0.13 * (0.8 + 0.4 * weave), 0.07 * (0.8 + 0.4 * weave), np.ones((R, R))])
plain("Briefs", save("elf_linen", lin.astype(np.float32)), 0.85)
# body: one slot, the painted skin
body = bpy.data.objects["Body"]
for p in body.data.polygons: p.material_index = 0
while len(body.data.materials) > 1: body.data.materials.pop(index=len(body.data.materials) - 1)
for n, ratio in (("Teeth", 0.12), ("Tongue", 0.5)):
    o = bpy.data.objects[n]
    d = o.modifiers.new("Decimate", 'DECIMATE'); d.ratio = ratio
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_move_to_index(modifier="Decimate", index=0)
        bpy.ops.object.modifier_apply(modifier="Decimate")
bpy.ops.object.select_all(action='DESELECT')
for n in ("Eyes", "Eyebrows", "Eyelashes", "Teeth", "Tongue", "Body"): bpy.data.objects[n].select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "body_skin"; body.data.name = "body_skin"
for a, b in {"Hair": "body_hair", "Briefs": "clt_briefs"}.items():
    bpy.data.objects[a].name = b; bpy.data.objects[b].data.name = b
bpy.ops.outliner.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND)
log["ground"] = run("ground_and_export.py")
log["bones"] = len(bpy.data.objects["Armature"].data.bones)
log["objs"] = [o.name for o in bpy.data.objects]
log["tris"] = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH'}
result = log
