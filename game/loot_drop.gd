class_name LootDrop
extends Node3D
## An item lying on the ground after a monster died. It is tossed out from the body, lands, and is picked up when the hero walks over
## it. Rares and uniques glow (a low light and a faint column) in their rarity colour so they can be spotted from the far zoom, and
## a drop is shown as the item's picture, and its details appear when it is pointed at.

## How close the hero has to be to take a drop. Nothing is picked up by walking over it: click it (or its name), or press the use key.
const REACH := 2.2
const LAND_TIME := 0.45
const LIFETIME := 150.0

## How long (metres, its longest side) a drop lies on the ground, whatever the model's own size: a greatsword is not two metres of
## steel on the floor. The camera makes them a little larger when pulled far back (see _camera_scale); the marker above them and the
## name and the light beam are what find them from far away.
const FIT_LENGTH := {Items.Slot.WEAPON: 0.7, Items.Slot.ARMOR: 0.5, Items.Slot.TRINKET: 0.3}

var item: Dictionary = {}
var _fit: float = 1.0   # the model's scale that makes its longest side FIT_LENGTH
var landed: bool = false
## The drop the mouse (or controller) is pointing at, set by the HUD each frame: it is drawn brighter and its name is shown.
static var focused: LootDrop = null
var _age: float = 0.0
var _light: OmniLight3D
var _column: MeshInstance3D
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
		var bounds: AABB = CharacterModel._bounds_of(node)
		var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		_fit = clampf(float(FIT_LENGTH.get(slot, 0.5)) / maxf(longest, 0.01), 0.2, 6.0)
		node.scale = Vector3.ONE * _fit
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

## Bigger the farther the camera is: at the far zoom a plain sword would be a few pixels.
func in_reach(hero: Node3D) -> bool:
	var offset: Vector3 = hero.global_position - global_position
	offset.y = 0.0
	return landed and offset.length() <= REACH

## The hero takes it: worn if the slot is empty, otherwise into the bag.
func pick_up(hero: Player) -> void:
	hero.stats.pickup(item)
	queue_free()

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
	_end = Arena.clamp_point(get_tree(), _end, 1.0)
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
		_model.scale = Vector3.ONE * _fit * lerpf(1.0, zoom, 0.4)   # only partly compensates for the camera: at the far zoom the name and the beam find it
	if _column != null:
		_column.scale = Vector3(zoom, 1.0 + (zoom - 1.0) * 0.6, zoom)
		_column.position.y = _column_base * (1.0 + (zoom - 1.0) * 0.6) * 0.5
