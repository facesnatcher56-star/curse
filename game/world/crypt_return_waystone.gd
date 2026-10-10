class_name CryptReturnWaystone
extends Node3D
## Grounded in-world return waystone at the sealed Crypt Gate steps.
## Revealed/enabled upon Forecourt and Crypt Warden clear, providing
## an in-world interaction to return safely to Last Hearth town plaza.

signal revealed()
signal activated()

const MODEL_PATH := "res://assets/models/healthstone/model.glb"
const TARGET_HEIGHT := 2.6
const INTERACT_LABEL := "Return to Last Hearth"

var active: bool = false
var _transitioning: bool = false

var _model: Node3D
var _light: OmniLight3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D

func _ready() -> void:
	_build_visuals_and_collision()
	set_active(active)

func _build_visuals_and_collision() -> void:
	if _model != null:
		return
	if ResourceLoader.exists(MODEL_PATH):
		var scene: PackedScene = load(MODEL_PATH)
		if scene != null:
			_model = scene.instantiate() as Node3D
			var bounds: AABB = CharacterModel._bounds_of(_model)
			var factor: float = TARGET_HEIGHT / maxf(bounds.size.y, 0.001)
			_model.scale = Vector3.ONE * factor
			_model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * factor
			add_child(_model)

	# Static collision so the monolith is physically grounded in the world
	_collision_body = StaticBody3D.new()
	_collision_body.collision_layer = Actor.LAYER_WORLD
	_collision_shape = CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.65
	cylinder.height = TARGET_HEIGHT
	_collision_shape.shape = cylinder
	_collision_shape.position = Vector3(0.0, TARGET_HEIGHT * 0.5, 0.0)
	_collision_body.add_child(_collision_shape)
	add_child(_collision_body)

	# Warm ember / hearth soul-light
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.28)
	_light.light_energy = 2.2
	_light.omni_range = 8.5
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 30.0
	_light.distance_fade_length = 10.0
	_light.position = Vector3(0.0, TARGET_HEIGHT * 0.65, 0.0)
	add_child(_light)
	var flicker := FlickerLight.new()
	_light.add_child(flicker)

func set_active(p_active: bool) -> void:
	active = p_active
	visible = p_active
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", not p_active)
	if _light != null:
		_light.visible = p_active

func reveal() -> void:
	if active:
		return
	set_active(true)
	_transitioning = false
	revealed.emit()

func hide_waystone() -> void:
	set_active(false)
	_transitioning = false

func can_interact() -> bool:
	return active and not _transitioning

func mark_used() -> void:
	_transitioning = true
	activated.emit()

func reset_used() -> void:
	_transitioning = false

func use(player: Player, town_scene: Node = null, director: RunDirector = null) -> void:
	if not can_interact():
		return
	mark_used()
	if town_scene != null and town_scene.has_method("_use_return_waystone"):
		town_scene.call("_use_return_waystone")
	elif director != null and director.has_method("request_exit"):
		director.request_exit()
