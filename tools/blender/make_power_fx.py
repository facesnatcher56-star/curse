"""Builds the Power Strike effect meshes for Curse in Blender: assets/models/fx/<name>/model.glb.

    "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background --python tools/blender/make_power_fx.py

  power_wave:   a crescent of torn earth that runs out along the ground in front of the blow (the shockwave): a low ramp of turf with
                a ridge of broken rock along its leading edge, and jagged shards standing out of the ridge.

Art direction (docs/ART_DIRECTION.md): dark, grounded, worn. Earth and stone in muted browns and greys, with a warm ember glow only
where the energy is (the crest and the cracks), never a neon sheet. Colour is on the vertices (colour and alpha: the trailing edge
fades out); Godot draws them unshaded with its own material and fades the whole thing as it travels. The wave faces glTF +Z (the way
the hero faces).

Each model is built in Blender with -Y as "forward" (the glTF exporter turns that into +Z).
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector, noise

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "fx")

EARTH_DARK = (0.14, 0.11, 0.09)
EARTH = (0.34, 0.27, 0.2)
STONE = (0.52, 0.47, 0.41)
EMBER = (1.0, 0.45, 0.12)


def lin(c):
    """Palette colours are written as they should look; vertex colours are stored linear."""
    return tuple(max(x, 0.0) ** 2.2 for x in c)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


def p_x(b, index):
    return b.verts[index][0]


def p_y(b, index):
    return b.verts[index][1]


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            block.remove(item)


def make_object(name, verts, faces, colors):
    """verts: [(x, y, z)], faces: [(i, j, k, ...)], colors: [(r, g, b, a)] per vertex."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    for i, col in enumerate(colors):
        attr.data[i].color = col
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    node = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    node.layer_name = "Col"
    mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    obj.data.materials.append(mat)
    return obj


def export(obj, name):
    folder = os.path.normpath(os.path.join(OUT, name))
    os.makedirs(folder, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(folder, "model.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_vertex_color="ACTIVE", export_materials="EXPORT")
    print("wrote", path)


class Builder:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.colors = []

    def v(self, p, c):
        self.verts.append(tuple(p))
        self.colors.append(c)
        return len(self.verts) - 1

    def tri(self, a, b, c):
        self.faces.append((a, b, c))

    def quad(self, a, b, c, d):
        self.faces.append((a, b, c, d))


# --- The wave ---------------------------------------------------------------------------------------------------------------

def build_wave():
    rng = random.Random(7)
    b = Builder()
    radius = 3.2          # of the crescent's front edge
    half_angle = math.radians(62)
    depth = 1.5           # front to back at the middle
    peak = 0.9            # height of the ridge
    steps = 44
    across = 7            # rows from the leading edge to the trailing edge
    grid = []
    for i in range(steps + 1):
        a = -half_angle + 2.0 * half_angle * i / steps
        taper = math.cos(a / half_angle * math.pi / 2.0)
        front_x = radius * math.sin(a)
        front_y = -radius * (math.cos(a) - math.cos(half_angle))     # centre furthest forward (-Y)
        row = []
        for j in range(across):
            s = j / (across - 1)
            ridge = (1.0 - s) ** 1.6 * (0.55 + 0.45 * math.sin(s * math.pi * 0.9 + 0.3))
            jag = 0.75 + 0.5 * noise.noise(Vector((a * 3.1, s * 2.0, 4.0)))
            h = peak * taper * (0.35 + 0.65 * ridge) * jag
            x = front_x + 0.12 * noise.noise(Vector((a * 5.0, s * 3.0, 1.0)))
            y = front_y + s * depth * taper
            glow = max(0.0, 1.0 - s * 2.2) * taper
            base = mix(EARTH_DARK, EARTH, 0.5 + 0.5 * noise.noise(Vector((a * 4.0, s * 3.0, 8.0))))
            col = mix(base, EMBER, glow * 0.85 * max(0.0, noise.noise(Vector((a * 9.0, s * 5.0, 2.0))) * 0.6 + 0.55))
            alpha = (1.0 - s) ** 0.8 * (0.35 + 0.65 * taper)
            r = lin(col)
            row.append(b.v((x, y, h), (r[0], r[1], r[2], alpha)))
        grid.append(row)
    for i in range(steps):
        for j in range(across - 1):
            b.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
    # Broken rock standing out of the ridge: tilted spikes along the leading edge, bigger toward the middle.
    for k in range(26):
        t = (k + rng.random() * 0.7) / 26.0
        a = -half_angle * 0.92 + 2.0 * half_angle * 0.92 * t
        taper = math.cos(a / half_angle * math.pi / 2.0)
        cx = radius * math.sin(a)
        cy = -radius * (math.cos(a) - math.cos(half_angle)) + rng.uniform(0.05, 0.45)
        height = (0.6 + 1.5 * taper) * rng.uniform(0.7, 1.25)
        width = rng.uniform(0.14, 0.26) * (0.6 + taper)
        lean = Vector((math.sin(a) * 0.15, -rng.uniform(0.1, 0.45), 0.0))     # leaning forward (-Y) and a little outward
        shade = mix(STONE, EARTH, rng.random() * 0.6)
        base_c = lin(mix(shade, EARTH_DARK, 0.5))
        tip_c = lin(mix(shade, EMBER, 0.3 + 0.4 * taper))
        a0 = b.v((cx - width, cy - width * 0.6, 0.0), (base_c[0], base_c[1], base_c[2], 1.0))
        a1 = b.v((cx + width, cy - width * 0.6, 0.0), (base_c[0], base_c[1], base_c[2], 1.0))
        a2 = b.v((cx + width * 0.2, cy + width, 0.0), (base_c[0], base_c[1], base_c[2], 1.0))
        a3 = b.v((cx - width * 0.7, cy + width * 0.7, 0.0), (base_c[0], base_c[1], base_c[2], 1.0))
        tip = b.v((cx + lean.x * height, cy + lean.y * height, height), (tip_c[0], tip_c[1], tip_c[2], 0.95))
        for p, q in ((a0, a1), (a1, a2), (a2, a3), (a3, a0)):
            b.tri(p, q, tip)
    return make_object("power_wave", b.verts, b.faces, b.colors)


def main():
    for name, builder in (("power_wave", build_wave),):
        reset_scene()
        obj = builder()
        # Blender Z-up: the wave runs toward -Y. The exporter turns that into Y-up with the front on +Z.
        export(obj, name)


main()
