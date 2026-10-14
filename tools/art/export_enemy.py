"""Build low-poly staging enemy meshes and export them as GLB (and optional preview renders).

Run headless from the repo root:

    blender.exe -b -P tools/art/export_enemy.py -- --enemy all
    blender.exe -b -P tools/art/export_enemy.py -- --enemy zombie --preview

Options (after the "--"):
    --enemy NAME|all   one of ENEMIES below, or "all" (default: all)
    --out DIR          output folder (default: assets/art_staging/enemies)
    --preview          also write a Workbench preview PNG into <out>/previews

Conventions:
    - Units are metres, origin at the feet, height roughly matches the in-game enemy.
    - Forward is Blender -Y (glTF export maps this to the model's front). The live
      game models are not touched.
    - Flat-shaded faceted geometry, one Principled material per palette entry.
    - Output is triangulated, so the printed triangle count is the real GLB count.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

PALETTE = {
    "bone": (0.60, 0.56, 0.46),
    "flesh": (0.40, 0.42, 0.37),
    "charcoal": (0.15, 0.15, 0.16),
    "iron": (0.30, 0.31, 0.33),
    "moss": (0.26, 0.34, 0.20),
    "burgundy": (0.34, 0.09, 0.11),
    "leather": (0.28, 0.19, 0.12),
    "rust": (0.42, 0.21, 0.11),
}


class Builder:
    def __init__(self):
        self.objs = []
        self.mats = {}

    def mat(self, key):
        if key not in self.mats:
            m = bpy.data.materials.new(name="enemy_" + key)
            m.use_nodes = True
            rgb = PALETTE[key]
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.88
            bsdf.inputs["Metallic"].default_value = 0.0
            m.diffuse_color = (*rgb, 1.0)
            self.mats[key] = m
        return self.mats[key]

    def _place(self, obj, key):
        obj.data.materials.append(self.mat(key))
        self.objs.append(obj)
        return obj

    def box(self, center, size, key, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=rot)
        o = bpy.context.active_object
        o.scale = size
        return self._place(o, key)

    def blob(self, center, radii, key, sub=1, rot=(0, 0, 0)):
        # Detail tiers: body masses (any radius >= 0.15) get subdivision 3 (320 tris),
        # smaller parts get at least 2 (80 tris). Keeps every enemy in the 1.5k-4k budget.
        sub = max(sub, 3) if max(radii) >= 0.15 else max(sub, 2)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=1, location=center, rotation=rot)
        o = bpy.context.active_object
        o.scale = radii
        return self._place(o, key)

    def limb(self, p0, p1, r0, r1=None, key="bone", sides=8):
        """Cylinder (r1 None or equal) or tapered cone from p0 to p1."""
        p0, p1 = Vector(p0), Vector(p1)
        length = (p1 - p0).length
        mid = (p0 + p1) * 0.5
        direction = (p1 - p0).normalized()
        quat = Vector((0, 0, 1)).rotation_difference(direction)
        rot = quat.to_euler()
        r1 = r0 if r1 is None else r1
        if abs(r1 - r0) < 1e-6:
            bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=r0, depth=length, location=mid, rotation=rot)
        else:
            # Cone with radius1 at the base (-Z end) and radius2 at the tip (+Z end).
            bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r0, radius2=r1, depth=length, location=mid, rotation=rot)
        return self._place(bpy.context.active_object, key)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_zombie(b):
    """Shambling, hunched, medium. Arms forward, rags and bone. Height ~1.75 m."""
    # Legs and rag wraps
    b.limb((-0.14, 0.02, 0.06), (-0.15, 0.04, 0.88), 0.09, key="charcoal")
    b.limb((0.14, 0.02, 0.06), (0.15, 0.04, 0.88), 0.09, key="charcoal")
    b.box((-0.16, -0.06, 0.04), (0.18, 0.30, 0.10), "leather")
    b.box((0.16, -0.06, 0.04), (0.18, 0.30, 0.10), "leather")
    b.box((0, 0, 0.92), (0.34, 0.20, 0.16), "leather")                 # hips and belt
    b.blob((0, 0.02, 1.24), (0.27, 0.22, 0.36), "flesh", sub=2, rot=(0.28, 0, 0))  # hunched torso
    b.blob((0.05, -0.02, 1.02), (0.16, 0.14, 0.14), "moss", sub=1)     # belly bulge
    b.blob((0, -0.12, 1.60), (0.15, 0.15, 0.15), "flesh", sub=2)       # head, dropped forward
    b.box((0, -0.24, 1.50), (0.10, 0.08, 0.05), "bone", rot=(0.3, 0, 0))  # jaw
    # Arms reaching forward
    for s in (-1, 1):
        sh = (0.34 * s, -0.04, 1.40)
        el = (0.36 * s, -0.42, 1.28)
        wr = (0.34 * s, -0.66, 1.18)
        b.limb(sh, el, 0.075, key="flesh")
        b.limb(el, wr, 0.065, 0.055, key="flesh")
        b.blob((0.34 * s, -0.72, 1.16), (0.07, 0.07, 0.06), "bone", sub=1)  # hand
        b.limb((0.34 * s, -0.70, 1.14), (0.34 * s, -0.82, 1.05), 0.012, 0.004, key="bone", sides=4)
    # Rag strips and ribs
    b.box((0.10, -0.22, 1.15), (0.04, 0.02, 0.36), "leather", rot=(0.2, 0.15, 0))
    b.box((-0.18, -0.20, 1.04), (0.04, 0.02, 0.32), "leather", rot=(0.2, -0.2, 0))
    for i, z in enumerate((1.12, 1.24, 1.36)):
        b.box((0, -0.25, z), (0.22, 0.02, 0.03), "bone", rot=(0.28, 0, 0))


def build_ghoul(b):
    """Low, crouched, fast. Long reaching arms to the ground, claws, burgundy mouth. Height ~1.3 m."""
    # Crouched digitigrade legs
    for s in (-1, 1):
        b.limb((0.17 * s, 0.12, 0.74), (0.22 * s, -0.22, 0.36), 0.085, 0.07, key="flesh")  # thigh
        b.limb((0.22 * s, -0.22, 0.36), (0.16 * s, 0.06, 0.08), 0.06, 0.04, key="flesh")  # shin
        b.box((0.16 * s, 0.10, 0.05), (0.14, 0.26, 0.09), "charcoal")                    # foot
    # Body, leaning forward
    b.blob((0, 0.0, 0.92), (0.26, 0.36, 0.22), "flesh", sub=2, rot=(0.5, 0, 0))
    b.blob((0, 0.22, 1.04), (0.20, 0.18, 0.16), "charcoal", sub=1)  # hunch
    b.blob((0, -0.10, 0.98), (0.21, 0.20, 0.16), "flesh", sub=1)     # shoulder mass
    # Head and jaw
    b.blob((0, -0.40, 1.00), (0.14, 0.17, 0.13), "bone", sub=2)
    b.box((0, -0.46, 0.90), (0.12, 0.14, 0.04), "burgundy")         # mouth
    b.limb((-0.05, -0.50, 1.04), (-0.08, -0.62, 1.08), 0.02, 0.005, key="bone", sides=4)  # tusks
    b.limb((0.05, -0.50, 1.04), (0.08, -0.62, 1.08), 0.02, 0.005, key="bone", sides=4)
    # Long arms to the ground with claws
    for s in (-1, 1):
        sh = (0.26 * s, -0.16, 0.96)
        el = (0.34 * s, -0.42, 0.50)
        wr = (0.36 * s, -0.56, 0.06)
        b.limb(sh, el, 0.08, 0.06, key="flesh")
        b.limb(el, wr, 0.06, 0.04, key="flesh")
        for dx in (-0.05, 0, 0.05):
            b.limb((wr[0] + dx * s, wr[1] - 0.02, 0.06), (wr[0] + dx * s, wr[1] - 0.04, -0.06), 0.02, 0.0, key="bone", sides=4)
    # Spine spikes
    for i, y in enumerate((0.20, 0.06, -0.06)):
        b.limb((0, y + 0.1, 1.08 - i * 0.03), (0, y + 0.02, 1.26 - i * 0.02), 0.04, 0.0, key="burgundy", sides=5)


def build_brute(b):
    """Heavy, wide, slow. Block torso, iron shoulders, massive fists. Height ~2.4 m."""
    # Thick legs with leather wraps and boots
    for s in (-1, 1):
        b.limb((0.30 * s, 0.0, 1.16), (0.32 * s, -0.02, 0.60), 0.22, 0.18, key="charcoal")
        b.limb((0.32 * s, -0.02, 0.60), (0.30 * s, 0.0, 0.16), 0.18, 0.15, key="charcoal")
        b.box((0.30 * s, -0.12, 0.10), (0.34, 0.52, 0.20), "leather")
    b.box((0, 0, 1.16), (0.84, 0.52, 0.34), "leather")                 # hips and belt
    b.box((0, 0, 1.78), (0.98, 0.62, 0.84), "rust")                    # block torso
    b.blob((0, -0.06, 1.92), (0.52, 0.42, 0.40), "flesh", sub=2)      # chest mass
    b.box((0, -0.36, 1.86), (0.42, 0.06, 0.42), "iron")                 # chest plate
    # Iron shoulders with rust spikes
    for s in (-1, 1):
        b.blob((0.64 * s, 0.0, 2.22), (0.26, 0.26, 0.22), "iron", sub=2)
        b.limb((0.66 * s, 0.0, 2.36), (0.74 * s, 0.02, 2.56), 0.06, 0.0, key="rust", sides=5)
    # Massive arms and fists
    for s in (-1, 1):
        sh = (0.70 * s, 0.0, 2.05)
        el = (0.80 * s, -0.10, 1.40)
        wr = (0.82 * s, -0.18, 0.80)
        b.limb(sh, el, 0.23, 0.20, key="flesh")
        b.limb(el, wr, 0.20, 0.17, key="flesh")
        b.blob((0.84 * s, -0.24, 0.66), (0.24, 0.24, 0.22), "flesh", sub=2)
        b.box((0.84 * s, -0.28, 0.54), (0.30, 0.10, 0.10), "iron")       # knuckle guard
    # Head: small under a heavy iron helm, burgundy horns
    b.box((0, -0.04, 2.32), (0.34, 0.34, 0.32), "flesh")
    b.blob((0, -0.04, 2.46), (0.27, 0.29, 0.16), "iron", sub=2)
    b.limb((-0.20, -0.02, 2.52), (-0.30, 0.02, 2.68), 0.05, 0.0, key="burgundy", sides=5)
    b.limb((0.20, -0.02, 2.52), (0.30, 0.02, 2.68), 0.05, 0.0, key="burgundy", sides=5)


def build_warden(b):
    """Tall, narrow, upright armoured sentinel. Spire helm, burgundy tabard, staff. Height ~2.1 m."""
    # Slender legs in charcoal greaves, leather boots
    for s in (-1, 1):
        b.limb((0.13 * s, 0.0, 0.98), (0.13 * s, 0.0, 0.14), 0.09, 0.07, key="charcoal")
        b.box((0.13 * s, -0.08, 0.06), (0.14, 0.30, 0.12), "leather")
    b.box((0, 0, 0.98), (0.46, 0.30, 0.16), "leather")                 # belt
    b.box((0, -0.15, 1.10), (0.34, 0.04, 0.80), "burgundy")            # tabard
    # Narrow torso with chest plate
    b.box((0, 0, 1.52), (0.40, 0.26, 0.60), "charcoal")
    b.blob((0, -0.13, 1.60), (0.20, 0.13, 0.26), "bone", sub=2)
    # Pauldrons
    for s in (-1, 1):
        b.blob((0.27 * s, 0.0, 1.82), (0.15, 0.15, 0.10), "iron", sub=1)
    # Arms with gauntlets
    for s in (-1, 1):
        sh = (0.28 * s, 0.0, 1.76)
        el = (0.34 * s, -0.08, 1.36)
        wr = (0.34 * s, -0.18, 1.06)
        b.limb(sh, el, 0.07, 0.06, key="charcoal")
        b.limb(el, wr, 0.06, 0.05, key="charcoal")
        b.box((0.34 * s, -0.20, 1.00), (0.12, 0.12, 0.16), "iron")
    # Neck, head, spire helm
    b.box((0, 0, 1.90), (0.14, 0.14, 0.10), "charcoal")
    b.blob((0, 0.0, 2.00), (0.14, 0.14, 0.14), "bone", sub=1)
    b.box((0, -0.11, 2.00), (0.14, 0.04, 0.05), "charcoal")            # visor
    b.limb((0, 0, 2.10), (0, 0, 2.50), 0.14, 0.0, key="iron", sides=4)  # spire helm
    b.limb((0, 0.02, 2.02), (0, 0.02, 2.22), 0.02, 0.02, key="burgundy", sides=4)
    # Staff in right hand, with a bone skull finial
    b.limb((0.44, -0.20, 0.10), (0.46, -0.24, 2.46), 0.028, key="leather", sides=5)
    b.blob((0.46, -0.24, 2.56), (0.07, 0.07, 0.08), "bone", sub=1)


ENEMIES = {
    "zombie": build_zombie,
    "ghoul": build_ghoul,
    "brute": build_brute,
    "warden": build_warden,
}


def finalize(b):
    """Join parts, triangulate, flat-shade. Returns the joined object."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in b.objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = b.objs[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.update()
    return obj


def triangle_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export_glb(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )


def render_preview(obj, path, height):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.background_type = "WORLD"
    scene.world = bpy.data.worlds.new("preview_world")
    scene.world.color = (0.07, 0.07, 0.08)

    cam_data = bpy.data.cameras.new("preview_cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("preview_cam", cam_data)
    scene.collection.objects.link(cam)
    # Three-quarter view from the front (-Y), framed by model height.
    s = max(height, 1.4) / 1.75
    target = Vector((0, 0, height * 0.5))
    cam.location = Vector((2.4 * s, -3.4 * s, height * 0.7 + 0.8 * s))
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    which = "all"
    out_dir = os.path.join(os.getcwd(), "assets", "art_staging", "enemies")
    preview = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--enemy":
            which = argv[i + 1]
            i += 1
        elif a == "--out":
            out_dir = argv[i + 1]
            i += 1
        elif a == "--preview":
            preview = True
        i += 1

    names = list(ENEMIES.keys()) if which == "all" else [which]
    os.makedirs(out_dir, exist_ok=True)
    if preview:
        os.makedirs(os.path.join(out_dir, "previews"), exist_ok=True)

    for name in names:
        clear_scene()
        b = Builder()
        ENEMIES[name](b)
        obj = finalize(b)
        tris = triangle_count(obj)
        dims = obj.dimensions
        out_path = os.path.join(out_dir, name + "_geo.glb")
        export_glb(obj, out_path)
        print("ENEMY %s tris=%d height=%.2f width=%.2f parts=%d glb=%s" % (
            name, tris, dims.z, dims.x, len(b.objs), out_path))
        if preview:
            png = os.path.join(out_dir, "previews", name + "_blender_preview.png")
            render_preview(obj, png, dims.z)
            print("PREVIEW %s" % png)


if __name__ == "__main__":
    main()
