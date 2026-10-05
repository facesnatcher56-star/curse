class_name LootDrop
extends Node3D
## An item lying on the ground after a monster died. It is tossed out from the body, lands, and is picked up when the hero walks over
## it. Rares and uniques glow (a low light and a faint column) in their rarity colour so they can be spotted from the far zoom, and
## a drop is shown as the item's picture, and its details appear when it is pointed at.

const PICKUP_RADIUS := 1.5
const LAND_TIME := 0.45
const LIFETIME := 150.0

## Drops are shown a little larger than life so they read from the far zoom: weapons and armour a quarter bigger, trinkets tripled.
const SLOT_SCALE := {Items.Slot.WEAPON: 1.3, Items.Slot.ARMOR: 1.2, Items.Slot.TRINKET: 3.0}

var item: Dictionary = {}
var landed: bool = false
## The drop the mouse (or controller) is pointing at, set by the HUD each frame: it is drawn brighter and its name is shown.
static var focused: LootDrop = null
var _age: float = 0.0
var _light: OmniLight3D
var _column: MeshInstance3D
var _marker: Sprite3D
var _model: Node3D
var _column_base: float = 1.0
var _start: Vector3
var _end: Vector3

static func create(drop_item: Dictionary) -> LootDrop:
	var drop := LootDrop.new()
	drop.item = drop_item
	return drop

func _ready() -> void:
	add_to_group("loot")
	var rarity: int = int(item["rarity"])
	var color: Color = Items.RARITY_COLORS[rarity]
	_add_model(int(item["slot"]))
	_add_marker(color, rarity)
	if rarity > Items.Rarity.COMMON:
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 0.35 if rarity == Items.Rarity.RARE else 0.7
		_light.omni_range = 3.0 if rarity == Items.Rarity.RARE else 4.0
		_light.position = Vector3(0, 1.8, 0)
		_light.shadow_enabled = false
		add_child(_light)
		_add_column(color, rarity)

func _add_model(slot: int) -> void:
	var path: String = Items.model_path(item)
	var node: Node3D
	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate()
		_use_vertex_colours(node)
		node.scale = Vector3.ONE * float(SLOT_SCALE.get(slot, 1.0))
	else:
		# No model yet for this base: a plain slab in the rarity colour so the item can still be found and picked up.
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.06, 0.2)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Items.RARITY_COLORS[int(item["rarity"])] * 0.5
		mat.roughness = 0.8
		mesh.material_override = mat
		mesh.position.y = 0.03
		node = mesh
	node.name = "Model"
	add_child(node)
	node.rotation.y = randf() * TAU
	_model = node

## The models are painted on their vertices (tools/blender/make_items.py). Godot's importer leaves the first material of a model
## without vertex colours switched on, so switch them on for every surface.
static func _use_vertex_colours(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			if mat != null:
				mat.vertex_color_use_as_albedo = true

func _add_column(color: Color, rarity: int) -> void:
	_column = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.1
	cylinder.height = 2.6 if rarity == Items.Rarity.RARE else 3.6
	cylinder.radial_segments = 8
	_column.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.09)
	mat.no_depth_test = false
	_column.material_override = mat
	_column.position.y = cylinder.height * 0.5
	_column_base = cylinder.height
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_column)

## The item's picture in a rarity-coloured frame, hovering over it and the same size on screen however far the camera is: a drop can
## always be found from the far zoom, and told apart by its picture. Rares and uniques are drawn larger. The name is in the hover card.
func _add_marker(_color: Color, rarity: int) -> void:
	_marker = Sprite3D.new()
	_marker.texture = ItemIcons.badge(item)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.fixed_size = true
	_marker.no_depth_test = true
	_marker.shaded = false
	_marker.pixel_size = {Items.Rarity.COMMON: 0.00031, Items.Rarity.RARE: 0.00042, Items.Rarity.UNIQUE: 0.00052}[rarity]
	_marker.position = Vector3(0, 1.5, 0)
	_marker.render_priority = 5
	add_child(_marker)

## Bigger the farther the camera is: at the far zoom a plain sword would be a few pixels.
func _camera_scale() -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return 1.0
	return clampf(camera.global_position.distance_to(global_position) / 13.0, 1.0, 2.6)

## Starts the drop at a monster's body and tosses it to a nearby spot on the ground.
func toss_from(origin: Vector3) -> void:
	var angle: float = randf() * TAU
	_start = Vector3(origin.x, maxf(origin.y, 0.0) + 1.0, origin.z)
	_end = Vector3(origin.x + cos(angle) * randf_range(0.6, 1.8), 0.0, origin.z + sin(angle) * randf_range(0.6, 1.8))
	var half: Vector2 = Arena.bounds_of(get_tree()) - Vector2(1.0, 1.0)
	_end.x = clampf(_end.x, -half.x, half.x)
	_end.z = clampf(_end.z, -half.y, half.y)
	global_position = _start

func _process(delta: float) -> void:
	_age += delta
	if not landed:
		var t: float = clampf(_age / LAND_TIME, 0.0, 1.0)
		var pos: Vector3 = _start.lerp(_end, t)
		pos.y = lerpf(_start.y, 0.0, t * t) + sin(t * PI) * 0.8
		global_position = pos
		if t >= 1.0:
			landed = true
			global_position = _end
		return
	if _age >= LIFETIME:
		queue_free()
		return
	var zoom: float = _camera_scale()
	if _model != null:
		_model.scale = Vector3.ONE * float(SLOT_SCALE.get(int(item["slot"]), 1.0)) * zoom
	if _column != null:
		_column.scale = Vector3(zoom, 1.0 + (zoom - 1.0) * 0.6, zoom)
		_column.position.y = _column_base * (1.0 + (zoom - 1.0) * 0.6) * 0.5
	if _marker != null and int(item["rarity"]) == Items.Rarity.UNIQUE:
		_marker.modulate = Color(1, 1, 1, 0.82 + 0.18 * sin(_age * 5.0))
	var is_focus: bool = focused == self
	if _marker != null:
		_marker.scale = Vector3.ONE * (1.35 if is_focus else 1.0)
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var offset: Vector3 = player.global_position - global_position
	offset.y = 0.0
	var dist: float = offset.length()
	if dist <= PICKUP_RADIUS and not bool(player.get("dead")):
		(player.get("stats") as PlayerStats).pickup(item)
		queue_free()
