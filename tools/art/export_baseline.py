"""Export the untouched Knight experiment as a baseline GLB.
blender.exe -b Curse_Knight.blend -P tools/art/export_baseline.py -- <out.glb>"""
import bpy, sys
out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=True,
    export_animation_mode='NLA_TRACKS', export_skins=True, export_apply=False, export_yup=True,
    export_cameras=False, export_lights=False, export_force_sampling=True,
    export_optimize_animation_size=False, export_materials='EXPORT')
print("BASELINE_EXPORT_DONE")
