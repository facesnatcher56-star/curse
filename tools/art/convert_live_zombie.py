"""Staging only: convert the LIVE zombie into a faceted low-poly version that keeps its armature and skin.

    blender.exe -b -P tools/art/convert_live_zombie.py -- --target 2500 --out assets/art_staging/enemies/zombie_converted

Steps: import assets/models/zombie/rigged.glb, pick the skinned mesh, collapse-decimate to the target
triangle count, then a planar pass, re-normalise the skin weights, sample each face's colour from the live
texture and posterise it into a small palette (one material per palette entry, so each face is a flat facet),
and export rigged.glb with the original armature. Animations come from the live anims.res, copied next to it.
The live files are read only; nothing under assets/models is written.
"""

import os
import shutil
import sys

from array import array

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
LIVE_GLB = os.path.join(ROOT, "assets/models/zombie/rigged.glb")
LIVE_ANIMS = os.path.join(ROOT, "assets/models/zombie/anims.res")

# Muted palette from docs/ART_DIRECTION.md (earth, iron, bone, ash, sickly green and grey-blue flesh,
# with at most two warm accents: rust and blood).
PALETTE = {
    "bone": (0.62, 0.58, 0.48),
    "ash": (0.42, 0.42, 0.40),
    "grave_grey": (0.24, 0.24, 0.23),
    "charcoal": (0.12, 0.12, 0.12),
    "sick_green": (0.36, 0.42, 0.30),
    "greyblue_flesh": (0.34, 0.38, 0.40),
    "earth": (0.30, 0.22, 0.15),
    "rust": (0.42, 0.22, 0.12),
    "blood": (0.32, 0.07, 0.07),
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    target, out = 2500, os.path.join(ROOT, "assets/art_staging/enemies/zombie_converted")
    i = 0
    while i < len(argv):
        if argv[i] == "--target":
            target = int(argv[i + 1]); i += 1
        elif argv[i] == "--out":
            out = argv[i + 1]; i += 1
        i += 1
    return target, out


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def image_of(mat):
    if mat is None or not mat.use_nodes:
        return None
    for node in mat.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image is not None:
            return node.image
    return None


def sample(image, uv, pixels):
    w, h = image.size
    x = min(max(int(uv.x * w), 0), w - 1)
    y = min(max(int(uv.y * h), 0), h - 1)
    px = pixels
    i = (y * w + x) * 4
    return Vector((px[i], px[i + 1], px[i + 2]))


def nearest_palette(rgb):
    best, best_d = None, 1e9
    for idx, (name, c) in enumerate(PALETTE.items()):
        d = (rgb.x - c[0]) ** 2 + (rgb.y - c[1]) ** 2 + (rgb.z - c[2]) ** 2
        if d < best_d:
            best, best_d = idx, d
    return best


def main():
    target, out_dir = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=LIVE_GLB)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
    if not meshes:
        raise SystemExit("no skinned mesh found")
    obj = max(meshes, key=lambda o: len(o.data.vertices))
    # keep only the skinned body; drop the stray import helper meshes
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    before = tri_count(obj)
    print("LIVE_TRIS %d verts %d groups %d" % (before, len(obj.data.vertices), len(obj.vertex_groups)))

    bpy.context.view_layer.objects.active = obj
    image = image_of(obj.active_material) or next((image_of(m) for m in obj.data.materials if image_of(m)), None)
    print("TEXTURE", image.name if image else None, image.size[:] if image else None)
    pixels = None
    if image is not None:
        pixels = array("f", [0.0]) * (image.size[0] * image.size[1] * 4)
        image.pixels.foreach_get(pixels)

    # decimate: collapse to the target, then a planar pass to flatten near-coplanar faces
    ratio = min(1.0, float(target) / float(before))
    dec = obj.modifiers.new("Collapse", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=dec.name)
    print("AFTER_COLLAPSE %d" % tri_count(obj))
    pl = obj.modifiers.new("Planar", "DECIMATE")
    pl.decimate_type = "DISSOLVE"
    pl.angle_limit = 0.0873  # 5 degrees: merge only near-flat regions
    bpy.ops.object.modifier_apply(modifier=pl.name)
    print("AFTER_PLANAR %d" % tri_count(obj))

    # face colours after decimation: decimate changes the face set, so resample from the original UVs
    # is not possible; instead re-sample from the surviving faces' centres in UV space.
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.active
    colours = []
    for f in bm.faces:
        if image is None or uv_layer is None:
            colours.append(Vector((0.4, 0.4, 0.4)))
            continue
        uvs = [l[uv_layer].uv for l in f.loops]
        colours.append(sample(image, sum(uvs, Vector((0, 0))) / len(uvs), pixels))
    bm.free()

    # posterise: one material per palette entry, each face takes the nearest entry
    mats = []
    for name, rgb in PALETTE.items():
        m = bpy.data.materials.new("zlive_" + name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
        m.diffuse_color = (*rgb, 1.0)
        mats.append(m)
    obj.data.materials.clear()
    for m in mats:
        obj.data.materials.append(m)
    for poly, rgb in zip(mesh.polygons, colours):
        poly.material_index = nearest_palette(rgb)
        poly.use_smooth = False
    mesh.update()

    # re-normalise skin weights after the vertex count change
    for v in mesh.vertices:
        groups = [(g.group, g.weight) for g in v.groups]
        total = sum(w for _, w in groups)
        if total <= 0:
            continue
        for gi, w in groups:
            obj.vertex_groups[gi].add([v.index], w / total, "REPLACE")

    # export: same armature, skin and bone names; animations come from the copied live anims.res
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    out_glb = os.path.join(out_dir, "rigged.glb")
    bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB", use_selection=True, export_apply=False,
                              export_yup=True, export_materials="EXPORT", export_animations=True,
                              export_skins=True)
    shutil.copyfile(LIVE_ANIMS, os.path.join(out_dir, "anims.res"))
    used = {}
    for p in mesh.polygons:
        used[PALETTE and list(PALETTE)[p.material_index]] = used.get(list(PALETTE)[p.material_index], 0) + 1
    print("CONVERTED tris=%d verts=%d groups=%d palette_faces=%s out=%s" % (
        tri_count(obj), len(mesh.vertices), len(obj.vertex_groups), used, out_glb))


if __name__ == "__main__":
    main()
