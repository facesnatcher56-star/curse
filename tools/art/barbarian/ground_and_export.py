# Blender (barbarian.blend open): stand the rig on the ground (lowest sole vertex at z = 0), export rigged.glb, save.
import bpy
from mathutils import Matrix, Vector
OUT = r"C:\Users\lloyd\OneDrive\Documents\curse\assets\models\barbarian\rigged.glb"
arm = bpy.data.objects["Armature"]
body = bpy.data.objects["body_skin"]
dg = bpy.context.evaluated_depsgraph_get()
me = body.evaluated_get(dg).to_mesh()
lift = -min((body.matrix_world @ v.co).z for v in me.vertices)
body.evaluated_get(dg).to_mesh_clear()
for o in arm.children:
    if o.type == 'MESH':
        local = o.matrix_world.inverted().to_3x3() @ Vector((0, 0, lift))   # world lift in the mesh's own space
        o.data.transform(Matrix.Translation(local))
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
d = arm.matrix_world.inverted().to_3x3() @ Vector((0, 0, lift))
for eb in arm.data.edit_bones:
    eb.head += d; eb.tail += d
bpy.ops.object.mode_set(mode='OBJECT')
for o in bpy.data.objects: o.select_set(o.name == "Armature" or (o.parent and o.parent.name == "Armature"))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
    export_skins=True, export_animations=False, export_materials='EXPORT', export_image_format='AUTO', export_def_bones=True)
bpy.ops.wm.save_mainfile()
dg = bpy.context.evaluated_depsgraph_get()
me = body.evaluated_get(dg).to_mesh()
result = {"lift_m": round(lift, 4), "new_min_z": round(min((body.matrix_world @ v.co).z for v in me.vertices), 4),
          "hips_z_cm": round((arm.data.bones["Hips"].head_local).z, 2)}
