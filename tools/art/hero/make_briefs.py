# Shared by every playable character: the base underwear (briefs with a natural bulge) cut from the MPFB body's own surface,
# so it fits whatever shape the body has. Run with CHAR (the MPFB base mesh name) and optionally COLOR in the namespace;
# makes "<CHAR>.briefs" parented to the MPFB rig with an armature modifier, and the material "<char>_briefs".
import bpy, bmesh, math
from mathutils import Vector

CHAR = globals().get("CHAR", "Barbarian")
COLOR = globals().get("COLOR", (0.075, 0.048, 0.03, 1.0))
body = bpy.data.objects[CHAR]
dg = bpy.context.evaluated_depsgraph_get()
me = bpy.data.meshes.new_from_object(body.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
me.name = CHAR + "BriefsMesh"
old = bpy.data.objects.get(CHAR + ".briefs")
if old:
    bpy.data.objects.remove(old, do_unlink=True)
ob = bpy.data.objects.new(CHAR + ".briefs", me)
bpy.context.scene.collection.objects.link(ob)
bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
# the crotch is the lowest point between the thighs; the front of the body just above it
crotch = min((v.co for v in bm.verts if abs(v.co.x) < 0.012 and 0.6 < v.co.z < 1.1), key=lambda c: c.z)
cz = crotch.z
fy = min(v.co.y for v in bm.verts if abs(v.co.x) < 0.02 and abs(v.co.z - (cz + 0.05)) < 0.01)
W = cz + 0.236   # waistband height above the crotch (the barbarian's proportions: 1.06 m waist over a 0.824 m crotch)
def leg(c): return min(cz - 0.004 + 0.95 * max(abs(c.x) - 0.018, 0), W - 0.045)   # high-cut leg line, a band at the hip
def inside(c): return leg(c) < c.z < W and abs(c.x) < 0.3 and c.z > cz - 0.05
keep = set(f for f in bm.faces if any(inside(v.co) for v in f.verts))
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context='FACES')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
bm.normal_update()
for v in bm.verts:   # clean edges: boundary vertices snap to the waist line or the leg line, whichever is nearer
    if any(e.is_boundary for e in v.link_edges):
        l = leg(v.co)
        v.co.z = W if abs(v.co.z - W) < abs(v.co.z - l) else l
bc = Vector((0.0, fy, cz + 0.05))
for v in bm.verts:
    v.co += v.normal * 0.004
    d = v.co - bc
    if v.co.y < fy + 0.04:   # the bulge
        g = math.exp(-(d.x / 0.034) ** 2 - (d.z / 0.04) ** 2)
        v.co.y -= 0.026 * g; v.co.z -= 0.006 * g
bm.to_mesh(me); bm.free()
if me.shape_keys:
    ob.shape_key_clear()
ob.parent = body.parent
ob.modifiers.new("Armature", 'ARMATURE').object = body.parent
sol = ob.modifiers.new("Solidify", 'SOLIDIFY'); sol.thickness = 0.003; sol.offset = 1
m = bpy.data.materials.get(CHAR.lower() + "_briefs") or bpy.data.materials.new(CHAR.lower() + "_briefs")
m.use_nodes = True
b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = COLOR; b.inputs["Roughness"].default_value = 0.8
me.materials.clear(); me.materials.append(m)
result = {"briefs_verts": len(me.vertices), "crotch_z": round(cz, 3), "waist_z": round(W, 3)}
