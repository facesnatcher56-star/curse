@tool
class_name DungeonEnemyGroup
extends Marker3D
## One group of monsters in the dungeon. Move this marker to where the group should stand (the group's "home" is wherever this node sits).
## Select it and use the Inspector on the right: every setting below has a plain explanation that shows when you hold the mouse over its name.
##
## To give a group a patrol route, exact starting spots, or a place to feed, add child Marker3D nodes to it and NAME them like this:
##   Patrol1, Patrol2, Patrol3 ... : a loop they walk round, in order (only for groups set to Wander).
##   Spawn1, Spawn2 ...            : the exact spots the monsters start on (the first monster stands on Spawn1, and so on).
##   FeedPoint                     : the spot a group set to Feed crouches over.
## The editor draws a yellow line along a patrol loop and a line from the group to each spawn and feed spot.

enum Behaviour { STAND_GUARD, WANDER, FEED }

const AREA_NAMES := "Entry hall,Corridor 1,Hall 1,Corridor 2,Hall 2,Corridor 3,Hall 3,Corridor 4,Hall 4,Corridor 5,Hall 5 (final hall)"

## The saved form of the group's contents: [["zombie", 2], ["ghoul", 1]]. You do not edit this; the number boxes below do.
@export_storage var kinds: Array = []

@export_group("Who is in the group")
## How many zombies. The weakest, slowest monster.
@export_custom(PROPERTY_HINT_RANGE, "0,20,1", PROPERTY_USAGE_EDITOR) var zombies: int:
	get: return _count("zombie")
	set(value): _set_count("zombie", value)
## How many ghouls. Faster and tougher than a zombie.
@export_custom(PROPERTY_HINT_RANGE, "0,20,1", PROPERTY_USAGE_EDITOR) var ghouls: int:
	get: return _count("ghoul")
	set(value): _set_count("ghoul", value)
## How many rock throwers. They stay back and throw rocks at you.
@export_custom(PROPERTY_HINT_RANGE, "0,20,1", PROPERTY_USAGE_EDITOR) var rock_throwers: int:
	get: return _count("rock_thrower")
	set(value): _set_count("rock_thrower", value)
## How many brutes. Big, strong and hit hard.
@export_custom(PROPERTY_HINT_RANGE, "0,20,1", PROPERTY_USAGE_EDITOR) var brutes: int:
	get: return _count("brute")
	set(value): _set_count("brute", value)
## How many wardens. The boss-type monster. Use one at most, and only in the final hall.
@export_custom(PROPERTY_HINT_RANGE, "0,20,1", PROPERTY_USAGE_EDITOR) var wardens: int:
	get: return _count("warden")
	set(value): _set_count("warden", value)

@export_group("How strong they are")
## Which part of the dungeon this group belongs to. This is what decides their level: monsters in the later parts are higher level, because
## the game works out what level you should be by the time you get there. Moving the marker does NOT change this; change it here.
@export_enum("Entry hall", "Corridor 1", "Hall 1", "Corridor 2", "Hall 2", "Corridor 3", "Hall 3", "Corridor 4", "Hall 4", "Corridor 5", "Hall 5 (final hall)") var area: int = 0:
	set(value):
		area = value
		_refresh()
## Makes this group tougher or weaker than normal for its part of the dungeon. 0 is normal. +2 means two levels higher than normal,
## -1 means one level lower. Ignored if "Fixed Level" below is set.
@export_range(-10, 10) var level_offset: int = 0:
	set(value):
		level_offset = value
		_refresh()
## Leave this at 0 to use the normal level for the group's part of the dungeon. Type a number (1 to 100) to make these monsters exactly
## that level, whatever your level is and wherever they stand.
@export_range(0, 100) var fixed_level: int = 0:
	set(value):
		fixed_level = value
		_refresh()

@export_group("What they do before they notice you")
## What the group does until it spots you. STAND GUARD: stays where it is. WANDER: strolls around its home (or follows the patrol route if
## you added one). FEED: crouches over its Feed Point if you added one. Whenever one of the group notices you, the whole group comes for you.
@export var behaviour: Behaviour = Behaviour.STAND_GUARD:
	set(value):
		behaviour = value
		_refresh()
## How far from the marker the monsters start. They are scattered at random inside this many metres. Ignored for monsters that have their
## own Spawn marker.
@export_range(0.0, 10.0, 0.1) var spread: float = 1.6
## For a group set to Wander without a patrol route: how far from home, in metres, it will stroll.
@export_range(0.0, 20.0, 0.1) var roam_radius: float = 4.0

var _label: Label3D
var _lines: MeshInstance3D


func _init() -> void:
	editor_description = "Move this marker to where the group stands. Hold the mouse over any setting in the Inspector for a plain explanation. " \
		+ "Patrol route: add child Marker3Ds named Patrol1, Patrol2... Exact start spots: Spawn1, Spawn2... Feeding spot: FeedPoint."


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_marker()
		_refresh()
		set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_routes()


func _count(kind: String) -> int:
	for pair in kinds:
		if pair is Array and (pair as Array).size() == 2 and String((pair as Array)[0]) == kind:
			return int((pair as Array)[1])
	return 0


func _set_count(kind: String, value: int) -> void:
	var rebuilt: Array = []
	var done: bool = false
	for pair in kinds:
		if pair is Array and (pair as Array).size() == 2 and String((pair as Array)[0]) == kind:
			if value > 0:
				rebuilt.append([kind, value])
			done = true
		else:
			rebuilt.append(pair)
	if not done and value > 0:
		rebuilt.append([kind, value])
	kinds = rebuilt
	_refresh()


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
	var area_names: PackedStringArray = AREA_NAMES.split(",")
	var area_name: String = area_names[clampi(area, 0, area_names.size() - 1)]
	var level_text: String = "level %d" % fixed_level if fixed_level > 0 else "%s%s" % [area_name, (" %+d" % level_offset) if level_offset != 0 else ""]
	var behaviour_text: String = ["guards", "wanders", "feeds"][behaviour]
	_label.text = "%s - %s\n%s" % [level_text, behaviour_text, ", ".join(parts)]


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
