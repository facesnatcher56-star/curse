class_name TownNpc
extends Node3D
## A townsperson standing in the plaza: a rigged Meshy model on its idle loop, a solid body so the hero cannot walk through, a
## name tag that shows when the hero is close, and a speech line that appears when the sim has them say something.

signal arrived

const BARK_SECONDS := 4.0
const WALK_SPEED := 1.7
## Tests make everyone walk faster; nothing else touches it.
static var speed_scale: float = 1.0

var def: NpcDef
var model: CharacterModel
var _tag: Label3D
var _tag_wanted: bool = false   # the hero is close enough to read the name (it is hidden while they speak)
var _bark: Label3D
var _bark_left: float = 0.0
var _body: StaticBody3D
var _look_at: Vector3 = Vector3.ZERO
var _look_blend: float = 0.0
var home: Vector3 = Vector3.ZERO   # where they stand when they have nothing to do
var busy: bool = false             # in the middle of a scene, so the stage gives them nothing else
var _path: PackedVector3Array = PackedVector3Array()
var _tween: Tween
var _reward: Sprite3D   # the coin that floats over the head of someone who has something to hand over (see set_reward_marker)
var _reward_clock: float = 0.0

static func create(npc_def: NpcDef) -> TownNpc:
	var npc := TownNpc.new()
	npc.def = npc_def
	return npc

func _ready() -> void:
	add_to_group("town_npcs")
	_body = StaticBody3D.new()
	_body.collision_layer = Actor.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = def.height
	shape.shape = capsule
	shape.position.y = def.height * 0.5
	_body.add_child(shape)
	add_child(_body)

	if ResourceLoader.exists(def.model_path + "/rigged.glb"):
		model = CharacterModel.build(def.model_path, def.clips)
		add_child(model)
		model.loop("idle", randf_range(0.9, 1.05))
		model.anim.seek(randf() * 2.0, true)   # neighbours should not breathe in step
	else:
		_add_placeholder()

	_tag = _label("%s\n%s" % [def.display_name, def.title], def.height + 0.45, 30, Color(0.92, 0.82, 0.62))
	_tag.visible = false
	_bark = _label("", def.height + 0.35, 34, Color(1.0, 0.97, 0.9))
	_bark.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM   # grows upward from just above the head, never down over the name
	_bark.visible = false
	_bark.width = 520.0
	_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

## A stand-in shown until the model has been generated (see tools/meshy.py): a dark post the height of the person.
func _add_placeholder() -> void:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = def.height
	mesh.mesh = capsule
	mesh.position.y = def.height * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.22, 0.2)
	mat.roughness = 1.0
	mesh.material_override = mat
	add_child(mesh)

func _label(text: String, height: float, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position.y = height
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.0075
	label.font_size = size
	label.outline_size = 10
	label.modulate = color
	label.outline_modulate = Color(0.03, 0.03, 0.04)
	add_child(label)
	return label

## Shows a spoken line above their head for a few seconds.
func say(text: String) -> void:
	_bark.text = text
	_bark.visible = true
	_bark_left = BARK_SECONDS
	_refresh_tag()

func is_speaking() -> bool:
	return _bark.visible

## Turns to look at a point (the hero, or whoever they are talking to) for a while, then back to their place.
func face_toward(point: Vector3) -> void:
	_look_at = point
	_look_blend = 4.0

## Walks to `target` round the props (along the navigation mesh, or straight if there is no path) and emits `arrived`.
func walk_to(target: Vector3) -> void:
	var map: RID = get_world_3d().navigation_map
	var from: Vector3 = global_position
	_path = NavigationServer3D.map_get_path(map, from, NavigationServer3D.map_get_closest_point(map, target), true)
	if _path.is_empty():
		_path = PackedVector3Array([target])
	elif _path.size() > 1:
		_path.remove_at(0)
	if from.distance_to(target) < 0.3:
		_path = PackedVector3Array()
		arrived.emit.call_deferred()

func is_walking() -> bool:
	return not _path.is_empty()

func walk_home() -> void:
	walk_to(home)

## Back at their place: turn to face the middle of the plaza again.
func settle_at_home() -> void:
	face_toward(Vector3(0, 0, -1))

## A shove: a quick step in at `target` and back (the body stays put, only the model moves).
func shove(target: Vector3) -> void:
	_nudge((target - global_position).normalized() * 0.55, 0.12, 0.3)

## Knocked back from `source`: a step away and a stagger back.
func recoil(source: Vector3) -> void:
	_nudge((global_position - source).normalized() * 0.7, 0.14, 0.5)

func _nudge(offset: Vector3, out_time: float, back_time: float) -> void:
	if model == null:
		return
	offset.y = 0.0
	offset = global_transform.basis.inverse() * offset
	if _tween != null and _tween.is_valid():
		_tween.kill()
	model.position = Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(model, "position", offset, out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(model, "position", Vector3.ZERO, back_time).set_trans(Tween.TRANS_SINE)

func set_tag_visible(on: bool) -> void:
	_tag_wanted = on
	_refresh_tag()

## A coin floating over the head: this person has a reward waiting for the hero (a finished quest). Always visible, never hidden by
## distance or by the name tag, so it can be seen from across the plaza.
func set_reward_marker(on: bool) -> void:
	if on and _reward == null:
		var icon: Texture2D = UiTheme.status_icon("gold")
		if icon == null:
			return
		_reward = Sprite3D.new()
		_reward.texture = icon
		_reward.pixel_size = 0.0075
		_reward.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_reward.shaded = false
		_reward.no_depth_test = true   # drawn over whatever is between the camera and the head
		_reward.render_priority = 5
		_reward.position = Vector3(0, def.height + 1.15, 0)
		add_child(_reward)
	if _reward != null:
		_reward.visible = on

func has_reward_marker() -> bool:
	return _reward != null and _reward.visible

## The name tag and the speech line take turns: the name hides while they talk, so the two never overlap.
func _refresh_tag() -> void:
	_tag.visible = _tag_wanted and not _bark.visible

func _process(delta: float) -> void:
	_walk(delta)
	if _reward != null and _reward.visible:   # it bobs and pulses, so it reads as something to go and get
		_reward_clock += delta
		_reward.position.y = def.height + 1.15 + sin(_reward_clock * 3.0) * 0.08
		var glow: float = 1.0 + 0.35 * (0.5 + 0.5 * sin(_reward_clock * 4.0))
		_reward.modulate = Color(glow, glow * 0.95, glow * 0.8)
	if _bark_left > 0.0:
		_bark_left -= delta
		if _bark_left <= 0.0:
			_bark.visible = false
			_refresh_tag()
	if _look_blend > 0.0:
		_look_blend -= delta
		var flat: Vector3 = _look_at - global_position
		if flat.length() > 0.1:
			var want: float = atan2(flat.x, flat.z)
			rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-6.0 * delta))

func _walk(delta: float) -> void:
	if _path.is_empty():
		if model != null and model.current == "walk":
			model.loop("idle", randf_range(0.9, 1.05))
		return
	var step: float = WALK_SPEED * speed_scale * delta
	var done: bool = false
	while step > 0.0 and not _path.is_empty():
		var flat: Vector3 = _path[0] - global_position
		flat.y = 0.0
		var d: float = flat.length()
		if d <= step:
			global_position = Vector3(_path[0].x, global_position.y, _path[0].z)
			step -= d
			_path.remove_at(0)
			done = _path.is_empty()
		else:
			global_position += flat / d * step
			rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 1.0 - exp(-10.0 * delta))
			step = 0.0
	_look_blend = 0.0
	if model != null and not done:
		model.loop("walk", minf(speed_scale, 3.0))
	if done:
		arrived.emit()
