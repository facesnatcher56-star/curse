"""Builds the dungeon test level's own props: assets/models/dungeon/<name>/model.glb (the Arena loads them by name).

    blender --background --python tools/blender/make_dungeon_props.py

Geometric low-poly dark fantasy, like the environment kit: flat-shaded faceted geometry, muted stone, weathered wood, iron and
clay, all matte. Units are metres. The footprint is centred on the origin and rests on Z = 0 (glTF Y); faces point to Blender -Y,
which is +Z in Godot. Every mesh is triangulated before export. Source .blend files are not kept: only the GLBs are written.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "dungeon")

# The same values as the environment kit (tools/blender/make_environment_kit.py on art/environment-kit): low, matte stone.
PALETTE = {
    "stone_light": ((0.11, 0.107, 0.10), 0.0, 0.92),
    "stone_dark": ((0.06, 0.058, 0.056), 0.0, 0.94),
    "wood_weathered": ((0.30, 0.22, 0.15), 0.0, 0.95),
    "wood_dark": ((0.18, 0.13, 0.09), 0.0, 0.95),
    "iron": ((0.17, 0.17, 0.18), 0.25, 0.75),
    "clay": ((0.30, 0.22, 0.17), 0.0, 0.93),
    "clay_dark": ((0.16, 0.115, 0.09), 0.0, 0.95),
}


def xf(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    return Matrix.Translation(loc) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((*scale, 1.0))


def set_faces(bm, before, mat):
    for f in bm.faces:
        if f not in before:
            f.material_index = mat


def add_box(bm, loc, size, rot=(0, 0, 0), mat=0):
    before = set(bm.faces)
    bmesh.ops.create_cube(bm, size=1.0, matrix=xf(loc, rot, size))
    set_faces(bm, before, mat)


def add_cone(bm, loc, r1, r2, depth, segs, rot=(0, 0, 0), mat=0):
    before = set(bm.faces)
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth,
                          matrix=xf(loc, rot))
    set_faces(bm, before, mat)


def bevel_all(bm):
    """Bevels the blocks so the edges catch the light, as the environment kit does."""
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.025, offset_type="OFFSET", segments=1, profile=0.5,
                    affect="EDGES", clamp_overlap=True)


def jitter(bm, rng, amount):
    for v in bm.verts:
        v.co += Vector((rng.uniform(-amount, amount), rng.uniform(-amount, amount), rng.uniform(-amount, amount)))


def material_slots(obj, keys):
    for key in keys:
        base, metallic, rough = PALETTE[key]
        mat = bpy.data.materials.new(name=key)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*base, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = rough
        obj.data.materials.append(mat)


def finish_and_export(name, build, keys, seed):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    build(bm, random.Random(seed))
    if name in ("crate", "chest", "pillar"):
        bevel_all(bm)
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    material_slots(obj, keys)
    for p in mesh.polygons:
        p.use_smooth = False
    # Triangulate so the GLB triangles are the counted triangles.
    tri = bmesh.new()
    tri.from_mesh(mesh)
    bmesh.ops.triangulate(tri, faces=tri.faces[:])
    tri.to_mesh(mesh)
    count = len(tri.faces)
    tri.free()
    bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = Vector((min(v.x for v in bbox), min(v.y for v in bbox), min(v.z for v in bbox)))
    mx = Vector((max(v.x for v in bbox), max(v.y for v in bbox), max(v.z for v in bbox)))
    shift = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for v in mesh.vertices:
        v.co -= shift
    folder = os.path.join(OUT, name)
    os.makedirs(folder, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(folder, "model.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_materials="EXPORT")
    print(f"DUNGEON {name} triangles={count} size={tuple(round(c, 3) for c in (mx - mn))} path={path}")


def build_pillar(bm, rng):
    """A square stone pillar, 0.8 m wide and 3 m tall, with a plinth and a worn capital."""
    add_box(bm, (0, 0, 0.12), (1.0, 1.0, 0.24), mat=1)
    add_box(bm, (0, 0, 1.6), (0.7, 0.7, 2.9), rot=(0, 0, 0.04), mat=0)
    add_box(bm, (0, 0, 3.12), (0.95, 0.95, 0.24), mat=1)
    jitter(bm, rng, 0.012)


def build_crate(bm, rng):
    """A wooden crate, 0.9 m, with plank bands and iron corner straps."""
    add_box(bm, (0, 0, 0.45), (0.9, 0.9, 0.9), mat=0)
    for z in (0.16, 0.74):
        add_box(bm, (0, 0, z), (0.94, 0.94, 0.05), mat=1)
    for x in (-0.44, 0.44):
        for y in (-0.44, 0.44):
            add_box(bm, (x, y, 0.45), (0.06, 0.06, 0.92), mat=2)
    jitter(bm, rng, 0.008)


def build_urn(bm, rng):
    """A clay urn, 0.7 m: a foot, a round belly, a narrow neck and a lip, faceted at 8 sides."""
    add_cone(bm, (0, 0, 0.1), 0.2, 0.26, 0.2, 8, mat=0)
    add_cone(bm, (0, 0, 0.36), 0.26, 0.36, 0.3, 8, mat=0)
    add_cone(bm, (0, 0, 0.6), 0.36, 0.2, 0.3, 8, mat=1)
    add_cone(bm, (0, 0, 0.72), 0.22, 0.25, 0.06, 8, mat=1)
    jitter(bm, rng, 0.01)


def build_chest(bm, rng):
    """A treasure chest, 1.1 m wide: a box body, a lid, iron bands and a clasp."""
    add_box(bm, (0, 0, 0.3), (1.1, 0.7, 0.6), mat=0)
    add_box(bm, (0, 0, 0.66), (1.12, 0.72, 0.14), mat=1)
    for x in (-0.36, 0.36):
        add_box(bm, (x, 0, 0.3), (0.07, 0.72, 0.62), mat=2)
    add_box(bm, (0, -0.37, 0.52), (0.12, 0.05, 0.14), mat=2)
    jitter(bm, rng, 0.008)


def build_torch_sconce(bm, rng):
    """A wall sconce: an iron bracket on a plate, and a wooden torch that leans out from it."""
    add_box(bm, (0, 0.06, 0.8), (0.2, 0.12, 0.5), mat=2)
    add_box(bm, (0, 0.2, 1.0), (0.1, 0.3, 0.07), mat=2)
    add_cone(bm, (0, 0.28, 1.25), 0.06, 0.04, 0.6, 5, rot=(math.radians(-20), 0, 0), mat=1)
    add_cone(bm, (0, 0.34, 1.6), 0.08, 0.04, 0.12, 5, rot=(math.radians(-20), 0, 0), mat=0)
    jitter(bm, rng, 0.005)


if __name__ == "__main__":
    finish_and_export("pillar", build_pillar, ["stone_light", "stone_dark"], 3)
    finish_and_export("crate", build_crate, ["wood_weathered", "wood_dark", "iron"], 5)
    finish_and_export("urn", build_urn, ["clay", "clay_dark"], 7)
    finish_and_export("chest", build_chest, ["wood_weathered", "iron"], 11)
    finish_and_export("torch_sconce", build_torch_sconce, ["iron", "wood_dark"], 13)
