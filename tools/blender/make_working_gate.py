"""Separate the existing textured town gate into a fixed arch and two hinged doors.
Preserves its worn stone, wood and iron instead of regenerating the asset.
Run with Blender --background --python tools/blender/make_working_gate.py.
"""
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/models/town_gate/model.glb'))
source=next(o for o in bpy.context.scene.objects if o.type=='MESH')
# Apply transforms before cutting so thresholds refer to original world metres.
bpy.context.view_layer.objects.active=source
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
coords=[v.co for v in source.data.vertices]
bottom=min(v.z for v in coords); top=max(v.z for v in coords)
scale=6/(top-bottom)
# The doors occupy the rectangular opening below the arch. Face centres keep UVs intact.
def part(face):
 c=face.calc_center_median()
 if abs(c.x)<.465 and c.z<.13:
  return 'Left' if c.x<0 else 'Right'
 return 'Arch'
for name in ['Arch','Left','Right']:
 mesh=source.data.copy(); bm=bmesh.new();bm.from_mesh(mesh)
 bmesh.ops.delete(bm, geom=[f for f in bm.faces if part(f)!=name], context='FACES')
 loose=[v for v in bm.verts if not v.link_faces]
 if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
 pivot=Vector((-.465 if name=='Left' else .465 if name=='Right' else 0,0,bottom))
 for v in bm.verts:v.co=(v.co-pivot)*scale
 bm.to_mesh(mesh);bm.free()
 obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
 obj.location=Vector((pivot.x*scale,0,0))
bpy.data.objects.remove(source,do_unlink=True)
path=ROOT/'assets/models/town/working_gate/model.glb';path.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True)
