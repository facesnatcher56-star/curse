class_name CutterThreatLines
extends Node3D
## Map mode readability (issue #81): while an enemy is going for the Cutter, a thin red line runs from it to her and a small red marker floats over
## its head, so the player can focus that enemy or use a power. Only drawn during a fight; one pooled pair of meshes per such enemy.

const LINE_THICKNESS := 0.07
const LINE_HEIGHT := 1.0
const MARKER_LIFT := 0.45   # m above the enemy's head

var _pool: Array[Dictionary] = []   # {line: MeshInstance3D, marker: MeshInstance3D}
var _material: StandardMaterial3D
var _dive_shot_taken: bool = false   # dev autoplay (--mapmode-auto=<dir>) only

func _ready() -> void:
	top_level = true
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(1.0, 0.12, 0.1, 0.85)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = 5

## The enemies drawn right now (also what the selftest reads).
func divers() -> Array[Enemy]:
	var out: Array[Enemy] = []
	var m := get_parent() as MapMode
	if m == null or m.state != MapMode.State.FIGHT:
		return out
	for e in m.fight_enemies():
		if EnemyRoles.targets_cutter(e):
			out.append(e)
	return out

func _process(_delta: float) -> void:
	var list: Array[Enemy] = divers()
	while _pool.size() < list.size():
		_pool.append(_make_pair())
	for i in _pool.size():
		var row: Dictionary = _pool[i]
		var on: bool = i < list.size()
		(row["line"] as MeshInstance3D).visible = on
		(row["marker"] as MeshInstance3D).visible = on
		if not on:
			continue
		var e: Enemy = list[i]
		var from: Vector3 = e.global_position + Vector3(0, LINE_HEIGHT, 0)
		var to: Vector3 = e.target.global_position + Vector3(0, LINE_HEIGHT, 0)
		var line := row["line"] as MeshInstance3D
		var length: float = maxf(from.distance_to(to), 0.01)
		line.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP, true).scaled(Vector3(1, 1, length)), (from + to) * 0.5)
		(row["marker"] as MeshInstance3D).global_position = e.global_position + Vector3(0, e.body_height + MARKER_LIFT, 0)
	if not list.is_empty() and not _dive_shot_taken:
		_autoplay_shot(list[0])

## Dev autoplay only: one screenshot of a dive, while the diver is on its way (between the warrior and the Cutter).
func _autoplay_shot(diver: Enemy) -> void:
	var m := get_parent() as MapMode
	if m == null or m._auto_dir == "":
		return
	var gap: float = diver.flat_distance_to(diver.target)
	if gap > 9.0 or gap < 3.0:
		return
	_dive_shot_taken = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/dive.png" % m._auto_dir)

func _make_pair() -> Dictionary:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(LINE_THICKNESS, LINE_THICKNESS, 1.0)
	line.mesh = box
	line.material_override = _material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
	var marker := MeshInstance3D.new()
	var cone := PrismMesh.new()   # a small downward-pointing red arrow over the diver
	cone.size = Vector3(0.4, 0.45, 0.12)
	marker.mesh = cone
	marker.rotation_degrees = Vector3(0, 0, 180)
	marker.material_override = _material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	return {"line": line, "marker": marker}
