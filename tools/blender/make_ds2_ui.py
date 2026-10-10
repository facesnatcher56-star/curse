"""Blender asset generator for Dungeon Siege II-adapted UI elements.
Follows Curse art direction (docs/ART_DIRECTION.md):
- Dark, grounded, worn-out fantasy.
- Weathered black iron, tarnished bronze, deep alchemical fluid.
- Lit with upper-left warm key light and cold fill.

Run:
    "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background --python tools/blender/make_ds2_ui.py
"""
import math
import os
import random
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/ui/ds2"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(1337)

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'AgX'

    # World lighting: dim ash background
    world = bpy.data.worlds.new('Dim Ash')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.05, 0.05, 0.06, 1.0)
    scene.world = world

    # Orthographic Camera from front (+Z facing downward at XY plane)
    bpy.ops.object.camera_add(location=(0, 0, 8))
    camera = bpy.context.object
    camera.name = "UICam"
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 2.8
    camera.rotation_euler = (0, 0, 0)
    scene.camera = camera

    # Key light: Warm upper-left
    bpy.ops.object.light_add(type='AREA', location=(-3.5, 4.0, 6.0))
    key = bpy.context.object
    key.name = "KeyLight"
    key.data.energy = 450
    key.data.color = (1.0, 0.85, 0.68)
    key.data.shape = 'DISK'
    key.data.size = 4.0
    key.rotation_euler = (-key.location).to_track_quat('-Z', 'Y').to_euler()

    # Fill light: Cold bottom-right
    bpy.ops.object.light_add(type='AREA', location=(3.5, -2.0, 5.0))
    fill = bpy.context.object
    fill.name = "FillLight"
    fill.data.energy = 140
    fill.data.color = (0.55, 0.66, 0.82)
    fill.data.shape = 'DISK'
    fill.data.size = 3.5
    fill.rotation_euler = (-fill.location).to_track_quat('-Z', 'Y').to_euler()

    return scene, camera

def create_pitted_material(name, base_rgb, metal=0.75, rough=0.65, noise_scale=22.0, bump_str=0.35):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough

    coord = nodes.new('ShaderNodeTexCoord')
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = noise_scale
    noise.inputs['Detail'].default_value = 4.0
    noise.inputs['Roughness'].default_value = 0.7
    links.new(coord.outputs['Generated'], noise.inputs['Vector'])

    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (base_rgb[0] * 0.45, base_rgb[1] * 0.45, base_rgb[2] * 0.45, 1.0)
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[1].color = (base_rgb[0] * 1.15, base_rgb[1] * 1.12, base_rgb[2] * 1.08, 1.0)
    links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])

    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = bump_str
    bump.inputs['Distance'].default_value = 0.04
    links.new(noise.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    return mat

def create_liquid_material(name, fluid_color, emit_strength=0.9):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs['Base Color'].default_value = (*fluid_color, 1.0)
    bsdf.inputs['Roughness'].default_value = 0.15
    bsdf.inputs['Emission Color'].default_value = (*fluid_color, 1.0)
    bsdf.inputs['Emission Strength'].default_value = emit_strength
    return mat

def create_glass_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs['Base Color'].default_value = (0.92, 0.96, 1.0, 1.0)
    bsdf.inputs['Roughness'].default_value = 0.04
    # In Blender 4.0+ / 5.1, transmission is 'Transmission Weight'
    if 'Transmission Weight' in bsdf.inputs:
        bsdf.inputs['Transmission Weight'].default_value = 0.92
    elif 'Transmission' in bsdf.inputs:
        bsdf.inputs['Transmission'].default_value = 0.92
    bsdf.inputs['IOR'].default_value = 1.45
    return mat

# Geometry helpers
def add_beveled_box(name, location, size, material, bevel_width=0.03):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    mod = obj.modifiers.new('Bevel', 'BEVEL')
    mod.width = bevel_width
    mod.segments = 3
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj

def add_sphere(name, location, scale, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(material)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj

def add_torus(name, location, r_major, r_minor, material):
    bpy.ops.mesh.primitive_torus_add(major_segments=96, minor_segments=20, location=location,
                                     major_radius=r_major, minor_radius=r_minor)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj

def render_image(filename, width=512, height=512, ortho_scale=2.8):
    scene = bpy.context.scene
    camera = scene.camera
    camera.data.ortho_scale = ortho_scale
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    filepath = str(OUT / f"{filename}.png")
    scene.render.filepath = filepath
    bpy.ops.render.render(write_still=True)
    print(f"[DS2 UI ASSET RENDERED] {filename}.png -> {filepath}", flush=True)

# Builders
def build_portrait_frame():
    clear_scene()
    iron = create_pitted_material("Iron", (0.14, 0.14, 0.15), metal=0.82, rough=0.68)
    bronze = create_pitted_material("Bronze", (0.42, 0.28, 0.14), metal=0.85, rough=0.52)
    dark_aperture = create_pitted_material("DarkAperture", (0.05, 0.045, 0.04), metal=0.1, rough=0.9)

    # Outer cast iron frame
    frame_outer = 1.85
    frame_thick = 0.22
    add_beveled_box("TopIron", (0, frame_outer/2, 0.04), (frame_outer + frame_thick, frame_thick, 0.14), iron, 0.025)
    add_beveled_box("BottomIron", (0, -frame_outer/2, 0.04), (frame_outer + frame_thick, frame_thick, 0.14), iron, 0.025)
    add_beveled_box("LeftIron", (-frame_outer/2, 0, 0.04), (frame_thick, frame_outer + frame_thick, 0.14), iron, 0.025)
    add_beveled_box("RightIron", (frame_outer/2, 0, 0.04), (frame_thick, frame_outer + frame_thick, 0.14), iron, 0.025)

    # Inset bronze lip
    lip_size = frame_outer - 0.12
    lip_thick = 0.08
    add_beveled_box("TopBronze", (0, lip_size/2, 0.09), (lip_size, lip_thick, 0.08), bronze, 0.015)
    add_beveled_box("BottomBronze", (0, -lip_size/2, 0.09), (lip_size, lip_thick, 0.08), bronze, 0.015)
    add_beveled_box("LeftBronze", (-lip_size/2, 0, 0.09), (lip_thick, lip_size, 0.08), bronze, 0.015)
    add_beveled_box("RightBronze", (lip_size/2, 0, 0.09), (lip_thick, lip_size, 0.08), bronze, 0.015)

    # Corner bracket studs
    corner = frame_outer/2 + 0.02
    for cx in (-corner, corner):
        for cy in (-corner, corner):
            add_beveled_box("CornerBracket", (cx, cy, 0.08), (0.24, 0.24, 0.16), iron, 0.03)
            add_sphere("CornerRivet", (cx, cy, 0.17), (0.05, 0.05, 0.035), bronze)

    # Top-right discipline tab mount
    tab_x = frame_outer/2 + 0.06
    tab_y = frame_outer/2 + 0.06
    add_beveled_box("DisciplineTab", (tab_x - 0.05, tab_y - 0.05, 0.06), (0.35, 0.35, 0.12), bronze, 0.02)

    # Recessed dark backing for the bust/portrait
    add_beveled_box("RecessedBacking", (0, 0, -0.05), (frame_outer - 0.18, frame_outer - 0.18, 0.04), dark_aperture, 0.01)

    render_image("portrait_frame", 512, 512, ortho_scale=2.7)

def build_vitals_bars_frame():
    clear_scene()
    iron = create_pitted_material("Iron", (0.13, 0.13, 0.14), metal=0.8, rough=0.7)
    bronze = create_pitted_material("Bronze", (0.42, 0.29, 0.14), metal=0.85, rough=0.55)
    trough = create_pitted_material("Trough", (0.05, 0.045, 0.04), metal=0.2, rough=0.92)

    width = 2.4
    height = 0.8
    # Outer casing
    add_beveled_box("VitalsFrameOuter", (0, 0, 0.02), (width, height, 0.12), iron, 0.03)

    # 3 horizontal recessed channels
    bar_y_positions = [0.22, 0.0, -0.22]
    for i, y in enumerate(bar_y_positions):
        # Dark trough
        add_beveled_box(f"Trough_{i}", (0, y, 0.06), (width - 0.2, 0.14, 0.06), trough, 0.015)
        # Bronze border around channel
        add_beveled_box(f"BronzeBorder_{i}", (0, y, 0.07), (width - 0.16, 0.16, 0.03), bronze, 0.01)

    # Left and right end clasps with rivets
    for end_x in (-width/2 + 0.08, width/2 - 0.08):
        add_beveled_box("EndClasp", (end_x, 0, 0.09), (0.16, height + 0.04, 0.15), bronze, 0.02)
        for y in bar_y_positions:
            add_sphere("EndRivet", (end_x, y, 0.17), (0.035, 0.035, 0.025), iron)

    render_image("vitals_bars_frame", 512, 180, ortho_scale=2.6)

def build_action_slot_bezel():
    clear_scene()
    iron = create_pitted_material("Iron", (0.14, 0.14, 0.15), metal=0.82, rough=0.68)
    bronze = create_pitted_material("Bronze", (0.44, 0.30, 0.14), metal=0.86, rough=0.5)

    size = 1.3
    add_beveled_box("SlotOuter", (0, 0, 0.03), (size, size, 0.12), iron, 0.03)
    add_beveled_box("SlotInnerLip", (0, 0, 0.07), (size - 0.22, size - 0.22, 0.08), bronze, 0.02)
    corner = size/2 - 0.1
    for cx in (-corner, corner):
        for cy in (-corner, corner):
            add_sphere("CornerRivet", (cx, cy, 0.11), (0.04, 0.04, 0.03), bronze)

    render_image("action_slot_bezel", 256, 256, ortho_scale=1.7)

def build_power_bezel():
    clear_scene()
    iron = create_pitted_material("Iron", (0.14, 0.14, 0.15), metal=0.82, rough=0.68)
    bronze = create_pitted_material("Bronze", (0.45, 0.32, 0.15), metal=0.86, rough=0.48)
    amber_accent = create_pitted_material("AmberAccent", (0.85, 0.52, 0.18), metal=0.8, rough=0.4)

    # Square inner socket
    sq_size = 1.15
    add_beveled_box("PowerInnerSocket", (0, 0, 0.04), (sq_size, sq_size, 0.14), iron, 0.025)
    add_beveled_box("PowerBronzeLip", (0, 0, 0.08), (sq_size - 0.18, sq_size - 0.18, 0.08), bronze, 0.015)

    # Concentric circular power charge channel / ring
    add_torus("PowerRingChannelOuter", (0, 0, 0.09), 0.82, 0.08, iron)
    add_torus("PowerRingBronzeRib", (0, 0, 0.12), 0.82, 0.03, bronze)
    add_torus("PowerRingInnerLip", (0, 0, 0.07), 0.72, 0.025, bronze)

    # 4 Cardinal lock claws
    for i in range(4):
        ang = i * (math.pi / 2)
        x = math.cos(ang) * 0.84
        y = math.sin(ang) * 0.84
        add_beveled_box("CardinalClaw", (x, y, 0.14), (0.18, 0.18, 0.1), bronze, 0.02)
        add_sphere("CardinalStud", (x, y, 0.20), (0.04, 0.04, 0.03), amber_accent)

    render_image("power_bezel", 256, 256, ortho_scale=2.2)

def build_potion_flask(name, fluid_color):
    clear_scene()
    iron = create_pitted_material("Iron", (0.15, 0.15, 0.16), metal=0.8, rough=0.68)
    bronze = create_pitted_material("Bronze", (0.42, 0.30, 0.15), metal=0.84, rough=0.52)
    glass = create_glass_material("Glass")
    fluid = create_liquid_material("Liquid", fluid_color, emit_strength=1.0)
    cork = create_pitted_material("Cork", (0.32, 0.23, 0.14), metal=0.0, rough=0.92, noise_scale=40.0)

    # Round bulbous flask body
    add_sphere("FlaskFluid", (0, -0.15, 0.0), (0.78, 0.78, 0.78), fluid)
    add_sphere("FlaskGlass", (0, -0.15, 0.0), (0.83, 0.83, 0.83), glass)
    add_torus("FlaskBronzeEquator", (0, -0.15, 0.0), 0.84, 0.035, bronze)

    # Heavy iron clawed base
    add_beveled_box("IronBaseStand", (0, -0.92, 0.0), (1.1, 0.22, 0.35), iron, 0.04)
    for sign in (-1, 1):
        add_beveled_box("IronClaw", (sign * 0.62, -0.45, 0.0), (0.14, 0.65, 0.2), iron, 0.03)

    # Banded neck
    add_beveled_box("FlaskNeckGlass", (0, 0.62, 0.0), (0.42, 0.55, 0.42), glass, 0.04)
    add_torus("NeckBronzeBand", (0, 0.55, 0.0), 0.24, 0.04, bronze)
    add_torus("LipBronzeRim", (0, 0.86, 0.0), 0.26, 0.045, bronze)

    # Cork stopper
    add_beveled_box("CorkStopper", (0, 1.02, 0.0), (0.32, 0.32, 0.32), cork, 0.02)

    render_image(name, 256, 320, ortho_scale=2.7)

def build_target_banner():
    clear_scene()
    bronze = create_pitted_material("Bronze", (0.43, 0.30, 0.15), metal=0.85, rough=0.55)
    iron = create_pitted_material("Iron", (0.14, 0.14, 0.15), metal=0.8, rough=0.7)
    plaque = create_pitted_material("PlaqueSlate", (0.07, 0.065, 0.06), metal=0.1, rough=0.92)

    width = 3.6
    height = 0.72

    # Slate inner text plate
    add_beveled_box("PlaqueBacking", (0, 0, 0.02), (width - 0.2, height - 0.15, 0.08), plaque, 0.02)

    # Stepped bronze outer trim
    add_beveled_box("TopBronzeRail", (0, height/2 - 0.05, 0.06), (width, 0.10, 0.12), bronze, 0.02)
    add_beveled_box("BottomBronzeRail", (0, -height/2 + 0.05, 0.06), (width, 0.10, 0.12), bronze, 0.02)

    # Side clasps with rivets
    for end_x in (-width/2 + 0.12, width/2 - 0.12):
        add_beveled_box("SideGothicCap", (end_x, 0, 0.08), (0.24, height, 0.16), iron, 0.03)
        add_sphere("CapStud", (end_x, 0, 0.18), (0.05, 0.05, 0.035), bronze)

    # Center crest / seal
    add_beveled_box("CenterSeal", (0, height/2 - 0.03, 0.10), (0.42, 0.22, 0.15), bronze, 0.03)
    add_sphere("CenterGem", (0, height/2 - 0.03, 0.19), (0.07, 0.07, 0.04), iron)

    render_image("target_banner", 768, 160, ortho_scale=3.8)

def build_compass_ring():
    clear_scene()
    iron = create_pitted_material("Iron", (0.14, 0.14, 0.15), metal=0.82, rough=0.68)
    bronze = create_pitted_material("Bronze", (0.45, 0.32, 0.15), metal=0.86, rough=0.5)

    # Heavy outer iron ring
    add_torus("OuterIronRing", (0, 0, 0.05), 1.15, 0.11, iron)

    # Bronze inner compass bezel
    add_torus("InnerBronzeLip", (0, 0, 0.08), 1.05, 0.03, bronze)
    add_torus("BevelGuide", (0, 0, 0.09), 0.96, 0.02, bronze)

    # 4 Cardinal wedges (N, S, E, W markers)
    for i in range(4):
        ang = i * (math.pi / 2)
        x = math.cos(ang) * 1.05
        y = math.sin(ang) * 1.05
        add_beveled_box(f"CardinalWedge_{i}", (x, y, 0.12), (0.16, 0.16, 0.08), bronze, 0.02)
        add_sphere(f"CardinalStud_{i}", (x, y, 0.17), (0.04, 0.04, 0.03), iron)

    # 4 Diagonal rivets
    for i in range(4):
        ang = (math.pi / 4) + i * (math.pi / 2)
        x = math.cos(ang) * 1.15
        y = math.sin(ang) * 1.15
        add_sphere(f"DiagStud_{i}", (x, y, 0.15), (0.045, 0.045, 0.03), bronze)

    render_image("compass_ring", 512, 512, ortho_scale=2.7)

def main():
    print("=== Generating Dungeon Siege II Adapted UI Assets ===", flush=True)
    build_portrait_frame()
    build_vitals_bars_frame()
    build_action_slot_bezel()
    build_power_bezel()
    build_potion_flask("potion_flask_health", (0.75, 0.10, 0.08))
    build_potion_flask("potion_flask_mana", (0.15, 0.34, 0.78))
    build_target_banner()
    build_compass_ring()
    print("=== All DS2 UI Assets Generated Successfully! ===", flush=True)

if __name__ == "__main__":
    main()
