# Blender, after opening barbarian_mpfb_editable.blend: pose, rig (with fingers), clean up, materials, export, save.
import bpy, os
SCR = r"C:\Users\lloyd\OneDrive\Documents\curse\tools\art\barbarian"
SRC_DIR = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\barbarian\source"
OUT = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\models\barbarian\rigged.glb"
BLEND = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\art_staging\barbarian\source\barbarian.blend"
HERO = r"C:\Users\lloyd\OneDrive\Documents\curse\tools\art\hero"
SHARED = ("pose_to_knight.py", "build_game_rig.py", "ground_and_export.py")
def run(name):
    ns = {"CHAR": "Barbarian", "FOLDER": "barbarian"}
    exec(open(os.path.join(HERO if name in SHARED else SCR, name)).read(), ns)
    return ns.get("result")
log = {}
log["pose"] = run("pose_to_knight.py")
log["rig"] = run("build_game_rig.py")
for n in ["Barbarian.rig", "BakeProbe"]:
    o = bpy.data.objects.get(n)
    if o: bpy.data.objects.remove(o, do_unlink=True)
for cn in ["Knight2Ref", "glTF_not_exported"]:
    c = bpy.data.collections.get(cn)
    if c:
        for o in list(c.objects): bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(c)
arm = bpy.data.objects["BarbarianArmature"]; arm.name = "Armature"; arm.data.name = "Armature"
for a, b in {"Barbarian": "Body", "Barbarian.beard": "Beard", "Barbarian.briefs": "Briefs", "Barbarian.eyebrow010": "Eyebrows",
             "Barbarian.eyelashes01": "Eyelashes", "Barbarian.high-poly": "Eyes", "Barbarian.long01": "Hair",
             "Barbarian.teeth_base": "Teeth", "Barbarian.tongue01": "Tongue"}.items():
    bpy.data.objects[a].name = b
log["prep"] = run("export_prep.py")
for mn in ["barbarian_beard", "Barbarian.eyebrow010", "Barbarian.eyelashes01", "Barbarian.long01", "Barbarian.high-poly"]:   # cut-out alpha (the eyes: the clear cornea)
    nt = bpy.data.materials[mn].node_tree
    t = [n for n in nt.nodes if n.bl_idname == "ShaderNodeTexImage"][0]
    b = [n for n in nt.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"][0]
    for l in list(nt.links):
        if l.to_socket == b.inputs["Alpha"]: nt.links.remove(l)
    r = nt.nodes.new("ShaderNodeMath"); r.operation = 'ROUND'
    nt.links.new(t.outputs["Alpha"], r.inputs[0]); nt.links.new(r.outputs[0], b.inputs["Alpha"])
body = bpy.data.objects["Body"]
bpy.ops.object.select_all(action='DESELECT')
for n in ["Eyes", "Eyebrows", "Eyelashes", "Teeth", "Tongue", "Body"]: bpy.data.objects[n].select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "body_skin"; body.data.name = "body_skin"
for a, b in {"Hair": "body_hair", "Beard": "body_beard", "Briefs": "clt_briefs"}.items():
    bpy.data.objects[a].name = b; bpy.data.objects[b].data.name = b
bpy.ops.outliner.orphans_purge(do_recursive=True)
for o in bpy.data.objects: o.select_set(o.name == "Armature" or (o.parent and o.parent.name == "Armature"))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
    export_skins=True, export_animations=False, export_materials='EXPORT', export_image_format='AUTO', export_def_bones=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND)
log["ground"] = run("ground_and_export.py")   # feet on the ground, export again
log["bones"] = len(bpy.data.objects["Armature"].data.bones)
log["objs"] = [o.name for o in bpy.data.objects]
result = log
