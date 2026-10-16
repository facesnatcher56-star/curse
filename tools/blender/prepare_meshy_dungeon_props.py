"""Prepare Meshy output for the functional dungeon chest and breakable crate.

Run after `python tools/meshy.py build 'dungeon/chest' 'dungeon/crate'`:
    blender --background --python tools/blender/prepare_meshy_dungeon_props.py

The chest's upper shell is separated from the body, attached to a real rear hinge
pivot, and given simple dark interior boards. The crate's Meshy shell is closed
with low-poly boards and iron straps. Meshy textures are muted and reduced to the
project's 1024 px texture limit. Decorative stash props are not touched.
"""
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CHEST = os.path.join(ROOT, "assets", "models", "dungeon", "chest", "model.glb")
CRATE = os.path.join(ROOT, "assets", "models", "dungeon", "crate", "model.glb")
OUT = os.path.join(ROOT, ".dev_output", "meshy-props-prepared")


def reset_and_import(path: str):
	if not os.path.isfile(path):
		raise FileNotFoundError(f"Meshy model is missing: {path}")
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=path)
	meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and len(obj.data.polygons) > 100]
	if not meshes:
		raise RuntimeError(f"No generated prop mesh found in {path}")
	prop = max(meshes, key=lambda obj: len(obj.data.polygons))
	# Bake the imported GLTF node transform into geometry so all split parts share
	# one coordinate space and the hinge stays aligned after export.
	world = prop.matrix_world.copy()
	for vertex in prop.data.vertices:
		vertex.co = world @ vertex.co
	prop.matrix_world.identity()
	for obj in list(bpy.context.scene.objects):
		if obj != prop:
			bpy.data.objects.remove(obj, do_unlink=True)
	return prop


def tone_and_resize(prop, factor: tuple[float, float, float]) -> None:
	seen = set()
	for material in prop.data.materials:
		if material is None or not material.use_nodes:
			continue
		for node in material.node_tree.nodes:
			image = getattr(node, "image", None)
			if node.type != "TEX_IMAGE" or image is None or image.name in seen:
				continue
			seen.add(image.name)
			if image.size[0] > 1024 or image.size[1] > 1024:
				image.scale(min(image.size[0], 1024), min(image.size[1], 1024))
			if image.name.lower().endswith("0") or "albedo" in image.name.lower() or "basecolor" in image.name.lower():
				# The first Meshy map is the base colour; warm white areas into the
				# project's muted wood/iron range without changing the UV layout.
				from array import array
				pixels = array("f", [0.0]) * (image.size[0] * image.size[1] * 4)
				image.pixels.foreach_get(pixels)
				for offset in range(0, len(pixels), 4):
					pixels[offset] *= factor[0]
					pixels[offset + 1] *= factor[1]
					pixels[offset + 2] *= factor[2]
				image.pixels.foreach_set(pixels)
			image.pack()


def make_subset_mesh(source, name: str, keep_lid: bool, split_y: float):
	source_bm = bmesh.new()
	source_bm.from_mesh(source.data)
	part = source_bm.copy()
	# Bisect across the entire mesh rather than classifying whole triangles by
	# centre: Meshy sometimes makes a single long face from the body base to lid.
	bmesh.ops.bisect_plane(part, geom=list(part.verts) + list(part.edges) + list(part.faces),
						plane_co=Vector((0.0, split_y, 0.0)), plane_no=Vector((0.0, 1.0, 0.0)),
						dist=0.00001, clear_inner=keep_lid, clear_outer=not keep_lid)
	loose_verts = [vertex for vertex in part.verts if not vertex.link_faces]
	if loose_verts:
		bmesh.ops.delete(part, geom=loose_verts, context="VERTS")
	part.normal_update()
	mesh = bpy.data.meshes.new(name)
	part.to_mesh(mesh)
	part.free()
	source_bm.free()
	for material in source.data.materials:
		mesh.materials.append(material)
	mesh.update()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(obj)
	return obj


def set_mesh_material(obj, material) -> None:
	obj.data.materials.clear()
	obj.data.materials.append(material)
	for polygon in obj.data.polygons:
		polygon.material_index = 0
		polygon.use_smooth = False


def matte_material(name: str, color: tuple[float, float, float], metallic: float = 0.0):
	material = bpy.data.materials.new(name)
	material.diffuse_color = (*color, 1.0)
	material.use_nodes = True
	bsdf = material.node_tree.nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = 0.86 if metallic == 0.0 else 0.72
	return material


def box(name: str, center: Vector, size: Vector, material, parent=None):
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
	obj = bpy.context.object
	obj.name = name
	obj.dimensions = size
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	set_mesh_material(obj, material)
	if parent is not None:
		world = obj.matrix_world.copy()
		obj.parent = parent
		obj.matrix_world = world
	return obj


def parent_keep_world(obj, parent) -> None:
	world = obj.matrix_world.copy()
	obj.parent = parent
	obj.matrix_world = world


def export_selected(path: str) -> int:
	os.makedirs(os.path.dirname(path), exist_ok=True)
	bpy.ops.object.select_all(action="SELECT")
	bpy.context.view_layer.objects.active = next(obj for obj in bpy.context.selected_objects if obj.type == "MESH")
	triangles = sum(max(0, len(poly.vertices) - 2) for obj in bpy.context.selected_objects if obj.type == "MESH" for poly in obj.data.polygons)
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
						  export_image_format="AUTO", export_materials="EXPORT")
	return triangles


def prepare_chest() -> None:
	prop = reset_and_import(CHEST)
	tone_and_resize(prop, (0.74, 0.68, 0.56))
	bounds = [prop.matrix_world @ Vector(corner) for corner in prop.bound_box]
	minimum = Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
	maximum = Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
	width = maximum.x - minimum.x
	height = maximum.y - minimum.y
	depth = maximum.z - minimum.z
	center_x = (minimum.x + maximum.x) * 0.5
	center_z = (minimum.z + maximum.z) * 0.5
	split_y = minimum.y + height * 0.66

	body = make_subset_mesh(prop, "ChestBodyMesh", False, split_y)
	lid_mesh = make_subset_mesh(prop, "ChestLidMesh", True, split_y)
	bpy.data.objects.remove(prop, do_unlink=True)

	body.name = "ChestBody"
	hinge = bpy.data.objects.new("ChestLid", None)
	hinge.empty_display_type = "PLAIN_AXES"
	hinge.location = (center_x, split_y, minimum.z)
	bpy.context.collection.objects.link(hinge)
	parent_keep_world(lid_mesh, hinge)

	wood_inner = matte_material("chest_inner_dark_wood", (0.12, 0.075, 0.045))
	box("ChestInteriorFloor", Vector((center_x, minimum.y + height * 0.24, center_z)),
		Vector((width * 0.70, height * 0.018, depth * 0.68)), wood_inner, body)
	box("ChestLidInterior", Vector((center_x, split_y - height * 0.026, center_z)),
		Vector((width * 0.90, height * 0.018, depth * 0.88)), wood_inner, hinge)

	output = os.path.join(OUT, "chest", "model.glb")
	triangles = export_selected(output)
	print(f"PREPARED chest triangles={triangles} split_y={split_y:.3f} output={output}")


def prepare_crate() -> None:
	prop = reset_and_import(CRATE)
	tone_and_resize(prop, (0.50, 0.44, 0.36))
	bounds = [prop.matrix_world @ Vector(corner) for corner in prop.bound_box]
	minimum = Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
	maximum = Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
	width = maximum.x - minimum.x
	height = maximum.y - minimum.y
	depth = maximum.z - minimum.z
	center_x = (minimum.x + maximum.x) * 0.5
	center_z = (minimum.z + maximum.z) * 0.5
	top_y = maximum.y - height * 0.012

	wood = matte_material("crate_top_weathered_wood", (0.16, 0.105, 0.065))
	iron = matte_material("crate_top_rusted_iron", (0.095, 0.075, 0.06), 0.28)
	# The generated crate has useful rough plank sides but an open top. These three
	# boards close it while leaving thin seams, so it reads as a breakable crate.
	board_depth = depth * 0.275
	for index, fraction in enumerate((0.18, 0.50, 0.82)):
		box(f"CrateTopBoard{index}", Vector((center_x, top_y, minimum.z + depth * fraction)),
			Vector((width * 0.84, height * 0.065, board_depth)), wood)
	strap_width = width * 0.045
	for index, fraction in enumerate((0.28, 0.72)):
		box(f"CrateTopIronStrap{index}", Vector((minimum.x + width * fraction, top_y + height * 0.035, center_z)),
			Vector((strap_width, height * 0.026, depth * 0.93)), iron)

	output = os.path.join(OUT, "crate", "model.glb")
	triangles = export_selected(output)
	print(f"PREPARED crate triangles={triangles} output={output}")


if __name__ == "__main__":
	prepare_chest()
	prepare_crate()
