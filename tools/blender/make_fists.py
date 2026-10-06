"""The Knight's gauntlet fists: assets/models/knight2/fist_r.glb and fist_l.glb.

    blender --background --python /absolute/path/tools/blender/make_fists.py -- [--preview]

Meshy gave the Knight a flat, open hand (no finger bones, so it cannot close), and the sword's grip pushed straight through the
palm. These are closed gauntlets that take its place: the game collapses the open hand mesh and puts one of these on each hand
bone (`CharacterModel._give_fists`), so the fingers really are wrapped round the grip. Same rules as every other asset
(docs/ART_DIRECTION.md): worn dark steel and leather, hand-painted on the vertices, no gloss.

Built in the hand bone's own space, in rig units (cm), with the bone origin at the wrist:
  +Y runs along the forearm toward the fingers; the palm faces -X (the right hand: its thumb is +Z, the way the blade goes);
  the grip is a rod along Z through GRIP, the same point the sword is attached at (Player.HAND_GRIP_POINT).
The left fist is the right one with X negated (the left hand bone is a mirror image of the right).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
import bmesh
import mathutils
import make_items as mi
import make_crypt_props as cp
from make_items import Parts, box, cylinder, sphere

V = mathutils.Vector
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models", "knight2"))
GRIP = V((-0.8, 15.0, 0.5))
ROD = 2.5      # the space left for the sword's grip
FINGER = 1.15  # finger radius


def limb(bm, a, b, radius, radius2=None, segs=10):
    """A cylinder (or cone) from point a to point b."""
    a, b = V(a), V(b)
    d = b - a
    if d.length < 1e-5:
        return
    m = mathutils.Matrix.Translation((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=radius if radius2 is None else radius2,
                          depth=d.length, matrix=m)


def build_fist(parts, mirror=False):
    def P(x, y, z):
        return V((-x if mirror else x, y, z))

    steel = parts.bm("dark_steel")
    plate = parts.bm("steel")
    brass = parts.bm("brass")
    leather = parts.bm("leather_dark")
    gx, gy, gz = GRIP.x, GRIP.y, GRIP.z
    # the cuff, flaring at the lip, with a brass band where it meets the hand
    limb(steel, P(0.2, -1.5, 0.3), P(0.2, 4.6, 0.3), 5.0, 5.5, segs=14)
    limb(brass, P(0.2, 4.4, 0.3), P(0.2, 5.4, 0.3), 5.6, 5.2, segs=14)
    # the back of the hand: three overlapping lames, then the knuckle bar with a stud on each knuckle
    for i, (y, h, w) in enumerate(((7.2, 4.8, 9.6), (11.2, 4.2, 9.4), (14.8, 3.6, 9.2))):
        box(plate if i == 1 else steel, P(3.1 + 0.15 * i, y, gz), (3.0 - 0.1 * i, h, w), cuts=1)
    limb(steel, P(2.6, 18.2, gz - 4.7), P(2.6, 18.2, gz + 4.7), 2.1)
    for k in (-3.45, -1.15, 1.15, 3.45):
        sphere(plate, P(3.0, 18.9, gz + k), 1.35, segs=10, rings=7)
    # the palm, leather over the heel of the hand
    box(leather, P(0.9, 9.0, gz), (2.6, 5.6, 8.6), cuts=1)
    # four fingers wrapped over the grip: from the knuckle across the top, down the far side and back to the palm
    radius = ROD + FINGER
    for k in (-3.45, -1.15, 1.15, 3.45):
        z = gz + k
        steps = 9
        path = [P(2.6, gy + radius + 0.2, z)]
        for s in range(steps + 1):
            phi = math.pi * s / steps
            path.append(P(gx - radius * math.sin(phi), gy + radius * math.cos(phi), z))
        path.append(P(0.9, gy - radius + 0.1, z))
        for i in range(len(path) - 1):
            limb(steel, path[i], path[i + 1], FINGER, FINGER * (0.92 if i == len(path) - 2 else 1.0))
        for i in range(1, len(path) - 1):
            sphere(steel, path[i], FINGER, segs=10, rings=6)   # round the joint so the bend is smooth
        for i in (2, 5, 8):   # a plate band over each finger's joints
            limb(plate, path[i] + (path[i + 1] - path[i]) * 0.1, path[i] + (path[i + 1] - path[i]) * 0.9, FINGER * 1.2, FINGER * 1.2)
        sphere(steel, path[-1], FINGER * 0.95, segs=8, rings=6)
    # the thumb: from the heel of the hand on the blade side, across the underside of the grip
    base, mid, tip = P(1.2, 8.4, gz + 5.0), P(-1.4, 10.8, gz + 4.5), P(-3.3, 12.8, gz + 3.4)
    sphere(steel, base, 1.8, segs=10, rings=7)
    limb(steel, base, mid, 1.45, 1.3)
    sphere(plate, mid, 1.45, segs=8, rings=6)
    limb(steel, mid, tip, 1.3, 1.1)
    sphere(plate, tip, 1.2, segs=8, rings=6)
    # a brass rivet or two so the plates read as plates
    for z in (-3.2, 3.8):
        sphere(brass, P(4.7, 7.4, gz + z), 0.55, segs=6, rings=4)
        sphere(brass, P(4.9, 11.2, gz + z), 0.5, segs=6, rings=4)


def to_blender_frame(obj):
    """The model was built in the hand bone's frame (a glTF, Y-up one): turn it so Blender's exporter turns it back."""
    for v in obj.data.vertices:
        v.co = V((v.co.x, -v.co.z, v.co.y))
    obj.data.update()


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    pieces = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in pieces:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_vertex_color="ACTIVE", export_materials="EXPORT")
    print("wrote", path, "pieces", len(pieces))
    return pieces


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for side, mirror in (("r", False), ("l", True)):
        mi.reset_scene()
        parts = Parts()
        build_fist(parts, mirror)
        obj = cp.make_object("fist_" + side, parts, 90 + (1 if mirror else 0))
        for poly in obj.data.polygons:
            poly.use_smooth = True
        if mirror:
            for poly in obj.data.polygons:
                poly.use_smooth = True
        to_blender_frame(obj)
        os.makedirs(OUT, exist_ok=True)
        pieces = export(obj, os.path.join(OUT, "fist_%s.glb" % side))
        if "--preview" in args and not mirror:
            cp.preview(pieces[0], "fist")


if __name__ == "__main__":
    main()
