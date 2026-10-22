# Blender (through the Blender MCP): build the barbarian's basic one-handed sword (the Longsword item) at real size.
# Upright: pommel bottom at the origin, blade up +Z (glTF +Y), blade flat in the XZ plane (edges along X).
# Run on an empty scene: exec(open(path).read(), ns); ns["result"] reports sizes. Textures are made by make_longsword_tex.py.
import bpy, bmesh, math
from mathutils import Vector

L_POMMEL = 0.050      # pommel height (bottom of the grip at this z)
L_GRIP = 0.110        # a fist and a bit
L_GUARD = 0.018
L_BLADE = 0.780
GUARD_W = 0.200
BLADE_W = 0.052
BLADE_T = 0.0068

def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)

def mat(name, color, metallic, rough):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    return m

def blade():
    """Lofted cross-sections: a lenticular steel section with a fuller down the first two thirds, tapering to a point."""
    z0 = L_POMMEL + L_GRIP + L_GUARD
    bm = bmesh.new()
    rings = []
    N = 40
    for i in range(N + 1):
        t = i / N
        z = z0 + t * L_BLADE
        if t < 0.04:   # ricasso: full width, no edge bevel yet
            w = BLADE_W * 0.98
        else:
            w = BLADE_W * (1.0 - 0.62 * ((t - 0.04) / 0.96) ** 1.2)
        if t > 0.88:   # the point
            w *= max(0.0, (1.0 - t) / 0.12) ** 0.8
        th = BLADE_T * (1.0 - 0.55 * t) * (1.0 if t <= 0.88 else max(0.08, (1.0 - t) / 0.12))
        fuller = 0.0 if t < 0.05 or t > 0.66 else min(1.0, (t - 0.05) / 0.04, (0.66 - t) / 0.06) * 0.0026
        # half section from edge (+x) across to edge (-x), front face (+y) then back face (-y)
        xs = [1.0, 0.82, 0.55, 0.28, 0.12, 0.0, -0.12, -0.28, -0.55, -0.82, -1.0]
        ring = []
        for face in (1, -1):
            seq = xs if face == 1 else list(reversed(xs))[1:-1]
            for x in seq:
                ax = abs(x)
                y = th * 0.5 * (1.0 - ax ** 1.6)            # lens: thick at the spine, a fine edge
                if ax < 0.3:
                    y -= fuller * (1.0 - (ax / 0.3) ** 2)   # fuller groove
                ring.append(bm.verts.new((x * w * 0.5, face * max(y, 0.0002), z)))
        rings.append(ring)
    for a, b in zip(rings[:-1], rings[1:]):
        n = len(a)
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00005)
    me = bpy.data.meshes.new("Blade"); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new("Blade", me); bpy.context.scene.collection.objects.link(o)
    return o

def guard():
    z = L_POMMEL + L_GRIP
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, z + L_GUARD * 0.5))
    o = bpy.context.active_object; o.name = "Guard"
    o.scale = (GUARD_W, 0.022, L_GUARD)
    bpy.ops.object.transform_apply(scale=True)
    me = o.data
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.x - e.verts[1].co.x) > 0.1], cuts=8)
    for v in bm.verts:   # quillons taper toward the tips and droop slightly toward the blade
        f = abs(v.co.x) / (GUARD_W * 0.5)
        v.co.y *= 1.0 - 0.35 * f
        v.co.z = z + L_GUARD * 0.5 + (v.co.z - (z + L_GUARD * 0.5)) * (1.0 - 0.3 * f) + 0.006 * f * f
    bm.to_mesh(me); bm.free()
    bev = o.modifiers.new("Bevel", 'BEVEL'); bev.width = 0.0025; bev.segments = 3
    for side in (-1, 1):   # knobs at the quillon ends
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.0085, location=(side * GUARD_W * 0.5, 0, z + L_GUARD * 0.5 + 0.006), segments=16, ring_count=10)
        k = bpy.context.active_object; k.name = "GuardKnob"
    return o

def grip():
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.0145, depth=L_GRIP, location=(0, 0, L_POMMEL + L_GRIP * 0.5))
    o = bpy.context.active_object; o.name = "Grip"
    o.scale = (1.0, 0.82, 1.0)   # oval, so the edge alignment can be felt in the hand
    bpy.ops.object.transform_apply(scale=True)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.05], cuts=10)
    for v in bm.verts:   # swell in the middle, as a wrapped grip does
        t = (v.co.z - L_POMMEL) / L_GRIP
        s = 1.0 + 0.10 * math.sin(math.pi * min(max(t, 0), 1))
        v.co.x *= s; v.co.y *= s
    bm.to_mesh(o.data); bm.free()
    return o

def pommel():
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.026, depth=0.022, location=(0, 0, 0.027), rotation=(math.pi / 2, 0, 0))
    o = bpy.context.active_object; o.name = "Pommel"
    bev = o.modifiers.new("Bevel", 'BEVEL'); bev.width = 0.006; bev.segments = 4
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.0115, depth=0.03, location=(0, 0, 0.027), rotation=(math.pi / 2, 0, 0))
    boss = bpy.context.active_object; boss.name = "PommelBoss"
    bev = boss.modifiers.new("Bevel", 'BEVEL'); bev.width = 0.003; bev.segments = 3
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.011, depth=0.012, location=(0, 0, 0.047))
    neck = bpy.context.active_object; neck.name = "PommelNeck"
    return o

clear()
steel = mat("longsword_steel", (0.62, 0.63, 0.65), 1.0, 0.32)
iron = mat("longsword_iron", (0.35, 0.33, 0.31), 1.0, 0.45)
leather = mat("longsword_leather", (0.16, 0.09, 0.05), 0.0, 0.7)
parts = {"Blade": blade(), "Guard": guard(), "Grip": grip(), "Pommel": pommel()}
for o in bpy.data.objects:
    o.data.materials.clear()
    o.data.materials.append(steel if o.name == "Blade" else leather if o.name == "Grip" else iron)
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        with bpy.context.temp_override(object=o, active_object=o):
            bpy.ops.object.modifier_apply(modifier=m.name)
    for p in o.data.polygons:
        p.use_smooth = o.name != "Blade"
# one object, three materials
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects: o.select_set(True)
bpy.context.view_layer.objects.active = bpy.data.objects["Blade"]
bpy.ops.object.join()
sword = bpy.context.active_object; sword.name = "Longsword"; sword.data.name = "Longsword"
sword.data.shade_auto_smooth(angle=math.radians(40)) if hasattr(sword.data, "shade_auto_smooth") else None
bpy.context.view_layer.update()
result = {"length_m": round(sword.dimensions.z, 3), "guard_m": round(sword.dimensions.x, 3),
          "tris": sum(len(p.vertices) - 2 for p in sword.data.polygons),
          "grip_centre_fraction": round((L_POMMEL + L_GRIP * 0.5) / sword.dimensions.z, 3)}
