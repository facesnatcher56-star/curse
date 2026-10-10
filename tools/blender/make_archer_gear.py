"""Build Cutter's worn bow, back quiver, and physical arrow.

Run with Blender 5.1:
  blender.exe --background --python tools/blender/make_archer_gear.py

Dark, grounded equipment: split yew, blackened iron, stained leather, dirty fletching.
Geometry carries vertex colour so it shares Curse's weathered material language without textures.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "archer"))
PALETTE = {
    "wood": ((0.20, 0.12, 0.055), 0.0, 0.86),
    "leather": ((0.15, 0.075, 0.035), 0.0, 0.92),
    "iron": ((0.22, 0.23, 0.24), 0.78, 0.62),
    "cloth": ((0.28, 0.25, 0.19), 0.0, 0.94),
    "string": ((0.12, 0.10, 0.075), 0.0, 0.9),
}


def mat(name):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*PALETTE[name][0], 1)
    m.metallic = PALETTE[name][1]
    m.roughness = PALETTE[name][2]
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*PALETTE[name][0], 1)
    bsdf.inputs["Metallic"].default_value = PALETTE[name][1]
    bsdf.inputs["Roughness"].default_value = PALETTE[name][2]
    return m


def cylinder(name, radius, depth, location, rotation=(0, 0, 0), material="wood", vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat(material))
    return o


def cone(name, r1, r2, depth, location, rotation=(0, 0, 0), material="iron", vertices=10):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=location, rotation=rotation)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat(material))
    return o


def curve_tube(name, points, bevel, material):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 2
    curve.bevel_depth = bevel
    curve.bevel_resolution = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat(material))
    return obj


def join_export(objects, folder, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.convert(target="MESH")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    # A dirty per-vertex tint breaks up otherwise pristine procedural surfaces.
    layer = obj.data.color_attributes.new(name="grime", type="BYTE_COLOR", domain="CORNER")
    for poly in obj.data.polygons:
        for li in poly.loop_indices:
            v = obj.data.vertices[obj.data.loops[li].vertex_index]
            grime = 0.72 + 0.20 * (noise.noise_vector(v.co * 5.0).length / 1.73)
            layer.data[li].color = (grime, grime * 0.94, grime * 0.86, 1.0)
    out = os.path.join(ROOT, folder)
    os.makedirs(out, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, filename), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_vertex_color="ACTIVE", export_materials="EXPORT")


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_bow():
    clear()
    objs = [
        curve_tube("SplitYew", [(0, 0, -0.78), (-0.10, 0, -0.42), (-0.13, 0, 0), (-0.10, 0, 0.42), (0, 0, 0.78)], 0.025, "wood"),
        cylinder("LeatherGrip", 0.035, 0.22, (-0.13, 0, 0), material="leather"),
        curve_tube("BowString", [(0, 0, -0.78), (-0.03, 0, 0), (0, 0, 0.78)], 0.004, "string"),
        cylinder("TopBinding", 0.031, 0.10, (-0.075, 0, 0.54), material="leather"),
        cylinder("BottomBinding", 0.031, 0.10, (-0.075, 0, -0.54), material="leather"),
    ]
    join_export(objs, "bow", "model.glb")


def arrow_parts(offset=(0, 0, 0), scale=1.0):
    x, y, z = offset
    shaft = cylinder("AshShaft", 0.009 * scale, 0.88 * scale, (x, y, z), material="wood", vertices=8)
    head = cone("BarbedHead", 0.035 * scale, 0.0, 0.10 * scale, (x, y, z + 0.49 * scale), material="iron", vertices=6)
    feather_a = cone("FletchingA", 0.026 * scale, 0.010 * scale, 0.14 * scale, (x, y, z - 0.39 * scale), material="cloth", vertices=4)
    return [shaft, head, feather_a]


def make_arrow():
    clear()
    join_export(arrow_parts(), "arrow", "model.glb")


def make_quiver():
    clear()
    objs = [
        cone("QuiverCase", 0.12, 0.15, 0.72, (0, 0, 0), material="leather", vertices=16),
        curve_tube("ShoulderStrap", [(-0.1, 0, -0.32), (-0.22, 0.04, 0.0), (-0.1, 0, 0.34)], 0.018, "leather"),
        cylinder("IronRim", 0.158, 0.025, (0, 0, 0.36), material="iron", vertices=16),
    ]
    for i, angle in enumerate((-0.55, -0.18, 0.18, 0.55)):
        for part in arrow_parts((math.sin(angle) * 0.07, math.cos(angle) * 0.04, 0.53), 0.72):
            part.name += str(i)
            objs.append(part)
    join_export(objs, "quiver", "model.glb")


os.makedirs(ROOT, exist_ok=True)
make_bow()
make_arrow()
make_quiver()
print("Wrote Cutter archer gear to", ROOT)
