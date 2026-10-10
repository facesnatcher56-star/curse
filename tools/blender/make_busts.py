"""Sculpts the two HUD busts that flank the health and mana vessels: assets/ui/busts/<name>.png (transparent, head and shoulders).

    "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background --python tools/blender/make_busts.py -- [knight priest]

Art direction (docs/ART_DIRECTION.md): carved, weathered stone-and-bronze statuary, low-key, warm ember key light with a cold rim. The knight is the
hero (closed helm, gorget, heavy pauldrons); the other is a hooded, faceless mourner. Both are built from primitives, then chiselled with a
displacement of layered noise so no surface is clean. The bottom of the render is faded to nothing by tools/fade_busts.py-style post (done here in
`finish`), so the figure rises out of the dark under the vessel.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "ui", "busts")
SIZE = 640


def clear() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def stone_material(tint=(0.24, 0.215, 0.19), metal=0.92, rough=0.34) -> bpy.types.Material:
    mat = bpy.data.materials.new("stone")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coords = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9.0
    noise.inputs["Detail"].default_value = 12.0
    noise.inputs["Roughness"].default_value = 0.65
    fine = nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 90.0
    fine.inputs["Detail"].default_value = 6.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (tint[0] * 0.45, tint[1] * 0.45, tint[2] * 0.45, 1.0)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (tint[0] * 1.35, tint[1] * 1.3, tint[2] * 1.25, 1.0)
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = 0.02
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    links.new(coords.outputs["Object"], fine.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(fine.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    return mat


def chisel(obj, strength=0.025, scale=0.18, levels=2) -> None:
    """Subdivide, then displace with clouds so every plane is slightly uneven, as if cut with a chisel."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = levels
    sub.render_levels = levels
    tex = bpy.data.textures.new("chisel", "CLOUDS")
    tex.noise_scale = scale
    tex.noise_depth = 4
    disp = obj.modifiers.new("chisel", "DISPLACE")
    disp.texture = tex
    disp.strength = strength
    disp.mid_level = 0.5


def part(kind, loc, scale, rot=(0, 0, 0), name="p", **kw):
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1.0, location=loc)
    elif kind == "cube":
        bpy.ops.mesh.primitive_cube_add(size=2.0, location=loc)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=1.0, depth=2.0, location=loc)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=1.0, radius2=kw.get("top", 0.0), depth=2.0, location=loc)
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=kw.get("minor", 0.18), major_segments=48, minor_segments=16, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = [math.radians(a) for a in rot]
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return obj


def bevel(obj, width=0.04) -> None:
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = 3


def cut(target, cutter) -> None:
    mod = target.modifiers.new("cut", "BOOLEAN")
    mod.object = cutter
    mod.operation = "DIFFERENCE"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


MODELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models")


def import_model(model: str) -> list:
    """The game's own character, in its rest pose, stripped of colour: the statue is cut from the same silhouette as the figure in the world."""
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(os.path.join(MODELS, model, "rigged.glb")))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    return meshes


def build_knight() -> list:
    return import_model("knight2")


def build_priest() -> list:
    return import_model("priest")


def aim(arm, bone: str, target: Vector) -> None:
    """Swing a bone about its head so it points at `target` (armature space, cm)."""
    pb = arm.pose.bones[bone]
    head, tail = pb.head.copy(), pb.tail.copy()
    rot = (tail - head).normalized().rotation_difference((target - head).normalized()).to_matrix().to_4x4()
    move = Matrix.Translation(head) @ rot @ Matrix.Translation(-head)
    pb.matrix = move @ pb.matrix
    bpy.context.view_layer.update()


def seat(arm) -> None:
    """The reference's pose: shoulders squared, upper arms dropped, forearms folded across the lap with the hands low and together, the head and
    chest turned toward the vessel (the turn itself is the pivot's yaw)."""
    for side, sx in (("Left", 1.0), ("Right", -1.0)):
        shoulder = arm.pose.bones[side + "Arm"].head
        aim(arm, side + "Arm", Vector((sx * 19.0, shoulder.y + 3.0, shoulder.z - 22.0)))
        aim(arm, side + "ForeArm", Vector((sx * 5.0, shoulder.y - 24.0, shoulder.z - 30.0)))
    for name, lean in (("Spine", 6.0), ("neck", 4.0)):
        pb = arm.pose.bones[name]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler.x += math.radians(lean)
    bpy.context.view_layer.update()


BUILDERS = {"knight": (build_knight, 38.0), "priest": (build_priest, -36.0)}
FOCUS = [1.8]


def render(name: str, builder, yaw: float) -> str:
    clear()
    parts = builder()
    mat = stone_material()
    top = -1e9
    for p in parts:
        p.data.materials.clear()
        p.data.materials.append(mat)
        for corner in p.bound_box:
            top = max(top, (p.matrix_world @ Vector(corner)).z)
    arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if arm:
        for action in bpy.data.actions:
            arm[0].animation_data_clear()
        seat(arm[0])
    root = arm[0] if arm else bpy.data.objects.new("root", None)
    if not arm:
        bpy.context.collection.objects.link(root)
    # the figure is turned toward the vessel; the camera looks at the head and shoulders only
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.collection.objects.link(pivot)
    root.parent = pivot
    pivot.rotation_euler = (0, 0, math.radians(yaw))
    FOCUS[0] = top
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.image_settings.color_mode = "RGBA"
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = 0.98
    cam_obj = bpy.data.objects.new("cam", cam)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (0, -9, FOCUS[0] - 0.41)
    cam_obj.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam_obj
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.06, 0.065, 0.08, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    for loc, energy, col, size in (((-3.2, -3.5, 4.5), 2600.0, (1.0, 0.86, 0.68), 2.2),   # hard key from the upper left: the glints on the helm
                                    ((4.5, 1.5, 2.5), 900.0, (0.55, 0.65, 0.9), 3.0),     # cold rim from behind, right
                                    ((0.5, -4.5, 0.2), 380.0, (1.0, 0.55, 0.28), 4.0),    # warm ember bounce low in front
                                    ((0.0, -3.0, 6.0), 500.0, (1.0, 0.95, 0.9), 5.0)):    # soft top light so the metal has a sky to reflect
        light_data = bpy.data.lights.new("l", "AREA")
        light_data.energy = energy
        light_data.color = col
        light_data.size = size
        light = bpy.data.objects.new("l", light_data)
        bpy.context.collection.objects.link(light)
        light.location = loc
        direction = Vector((0, 0, 0.5)) - Vector(loc)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "raw_%s.png" % name)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in args or list(BUILDERS):
        builder, yaw = BUILDERS[name]
        print("BUST", name, render(name, builder, yaw))


main()
