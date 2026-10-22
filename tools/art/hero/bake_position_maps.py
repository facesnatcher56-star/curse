# Shared by every playable character: bakes the MPFB body's object-space position and normal into its UV layout
# (bake_pos.exr, bake_nrm.exr in OUT_DIR), so a skin painter can place paint in 3D (see tools/art/barbarian/paint_skin.py).
# Run with CHAR (the MPFB base mesh name) and OUT_DIR in the namespace. Cycles, 2048 px, half float.
import bpy, os

CHAR = globals().get("CHAR", "Barbarian")
OUT_DIR = globals()["OUT_DIR"]
R = 2048
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.samples = 1
src = bpy.data.objects[CHAR]
probe = src.copy(); probe.data = src.data.copy(); probe.name = "BakeProbe"
sc.collection.objects.link(probe)
probe.parent = None; probe.matrix_world = src.matrix_world.copy()
for md in list(probe.modifiers):
    if md.type == 'ARMATURE':
        probe.modifiers.remove(md)
mat = bpy.data.materials.new("BakeProbeMat"); mat.use_nodes = True
nt = mat.node_tree; nt.nodes.clear()
tc = nt.nodes.new("ShaderNodeTexCoord"); em = nt.nodes.new("ShaderNodeEmission"); out = nt.nodes.new("ShaderNodeOutputMaterial")
tex = nt.nodes.new("ShaderNodeTexImage")
nt.links.new(em.outputs[0], out.inputs[0])
probe.data.materials.clear(); probe.data.materials.append(mat)
for p in probe.data.polygons:
    p.material_index = 0
bpy.ops.object.select_all(action='DESELECT'); probe.select_set(True); bpy.context.view_layer.objects.active = probe
saved = {}
for kind, sock in (("pos", "Object"), ("nrm", "Normal")):
    img = bpy.data.images.new("bake_" + kind, R, R, float_buffer=True, alpha=True)
    for l in list(nt.links):
        if l.to_node == em:
            nt.links.remove(l)
    nt.links.new(tc.outputs[sock], em.inputs[0])
    tex.image = img; nt.nodes.active = tex
    bpy.ops.object.bake(type='EMIT', margin=4, use_clear=True)
    img.filepath_raw = os.path.join(OUT_DIR, "bake_%s.exr" % kind)
    img.file_format = 'OPEN_EXR'
    sc.render.image_settings.exr_codec = 'ZIP'
    img.save()
    saved[kind] = img.filepath_raw
bpy.data.objects.remove(probe, do_unlink=True)
result = saved
