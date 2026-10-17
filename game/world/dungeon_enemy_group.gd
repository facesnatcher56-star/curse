@tool
class_name DungeonEnemyGroup
extends Marker3D
## One group of enemies in the dungeon level scene (`game/world/dungeon_level.tscn`, under `EnemyGroups`). Drag it where the group should
## stand; the node's position is its home. Everything about the group is set here, in the editor:
##
##   * WHAT: `kinds` (kind and how many of each).
##   * LEVEL: by default the level of its `area` (the level the hero is projected to be on reaching it, see TestDungeon.project); a
##     `level_offset` makes them tougher or weaker than that; a `fixed_level` above 0 overrides it altogether.
##   * WHERE: they scatter round the home by `spread` metres, or, if the group has child markers named `Spawn...`, they stand exactly on
##     those (the first member on the first marker, and so on; extras scatter).
##   * WHAT THEY DO until they notice the hero: `behaviour` stands guard, wanders about the home (`roam_radius`), or hunches over a
##     child marker named `FeedPoint`. A wandering group follows a patrol loop if it has child markers named `Patrol...` (in order).
##
## Add the child markers with right-click > Add Child Node > Marker3D, and name them as above. In the editor the node draws what it holds;
## in the game it is only read (TestDungeon.read_groups). A group is woken together: when one of them notices the hero, all of them do.

enum Behaviour { STAND, WANDER, FEED }

## An index into TestDungeon.AREAS: 0 is the entry, 1 corridor_1, 2 hall_1, ... 10 hall_5 (the final hall).
@export_range(0, 10) var area: int = 0:
	set(value):
		area = value
		_refresh()
## Added to the area's level (negative: weaker). Ignored when `fixed_level` is set.
@export_range(-10, 10) var level_offset: int = 0:
	set(value):
		level_offset = value
		_refresh()
## 0 follows the area's level; anything above is the level these enemies are, whatever the hero's level.
@export_range(0, 100) var fixed_level: int = 0:
	set(value):
		fixed_level = value
		_refresh()
@export var behaviour: Behaviour = Behaviour.STAND:
	set(value):
		behaviour = value
		_refresh()
## [kind, count] pairs, e.g. [["zombie", 2], ["ghoul", 1]]. Kinds: zombie, ghoul, rock_thrower, brute, warden.
@export var kinds: Array = []:
	set(value):
		kinds = value
		_refresh()
## How far members scatter from the home when there are no `Spawn...` markers.
@export_range(0.0, 10.0, 0.1) var spread: float = 1.6
## How far a wandering group strolls from its home (when it has no patrol loop).
@export_range(0.0, 20.0, 0.1) var roam_radius: float = 4.0

var _label: Label3D
var _lines: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_marker()
		_refresh()
		set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_routes()


## "" stands, "wander" strolls, "feed" hunches over its FeedPoint: what Enemy.idle_mode wants.
func idle_mode() -> String:
	match behaviour:
		Behaviour.WANDER: return "wander"
		Behaviour.FEED: return "feed"
	return ""


## The marker children whose names start with `prefix`, in order, as ground points (x, z).
func marker_points(prefix: String) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for child in get_children():
		if child is Marker3D and String(child.name).begins_with(prefix):
			var spot: Vector3 = (child as Marker3D).global_position if is_inside_tree() else position + (child as Marker3D).position
			points.append(Vector2(spot.x, spot.z))
	return points


## What the editor draws: a small flame-coloured post and a label over it (never saved, never built in the game).
func _build_marker() -> void:
	var post := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.12
	mesh.height = 2.2
	post.mesh = mesh
	post.position.y = 1.1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.35, 0.2)
	material.emission_enabled = true
	material.emission = Color(0.95, 0.35, 0.2)
	material.emission_energy_multiplier = 0.6
	post.material_override = material
	add_child(post)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.012
	_label.position.y = 2.7
	_label.outline_size = 8
	add_child(_label)
	_lines = MeshInstance3D.new()
	_lines.top_level = true
	var material_lines := StandardMaterial3D.new()
	material_lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_lines.albedo_color = Color(1.0, 0.8, 0.2)
	material_lines.no_depth_test = true
	_lines.material_override = material_lines
	add_child(_lines)


func _refresh() -> void:
	if _label == null:
		return
	var parts: PackedStringArray = []
	for pair in kinds:
		if pair is Array and (pair as Array).size() == 2:
			parts.append("%s x%d" % [String((pair as Array)[0]), int((pair as Array)[1])])
	var level_text: String = "level %d" % fixed_level if fixed_level > 0 else "area %d%s" % [area, ("%+d" % level_offset) if level_offset != 0 else ""]
	_label.text = "%s, %s\n%s" % [level_text, Behaviour.keys()[behaviour].to_lower(), ", ".join(parts)]


## Lines in the editor: the patrol loop (yellow), and a spoke to each spawn point and the feed point.
func _draw_routes() -> void:
	if _lines == null or not is_inside_tree():
		return
	var mesh := ImmediateMesh.new()
	var patrol: Array[Vector2] = marker_points("Patrol")
	var lift := Vector3(0, 0.3, 0)
	if patrol.size() > 1:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in patrol:
			mesh.surface_add_vertex(Vector3(p.x, global_position.y, p.y) + lift)
		mesh.surface_add_vertex(Vector3(patrol[0].x, global_position.y, patrol[0].y) + lift)
		mesh.surface_end()
	var spokes: Array[Vector2] = marker_points("Spawn") + marker_points("FeedPoint")
	if not spokes.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for p in spokes:
			mesh.surface_add_vertex(global_position + lift)
			mesh.surface_add_vertex(Vector3(p.x, global_position.y, p.y) + lift)
		mesh.surface_end()
	_lines.global_transform = Transform3D.IDENTITY
	_lines.mesh = mesh
