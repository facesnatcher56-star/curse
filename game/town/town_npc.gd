class_name TownNpc
extends Node3D
## A townsperson standing in the plaza: a rigged Meshy model on its idle loop, a solid body so the hero cannot walk through, a
## name tag that shows when the hero is close, and a speech line that appears when the sim has them say something.

const BARK_SECONDS := 4.0

var def: NpcDef
var model: CharacterModel
var _tag: Label3D
var _tag_wanted: bool = false   # the hero is close enough to read the name (it is hidden while they speak)
var _bark: Label3D
var _bark_left: float = 0.0
var _body: StaticBody3D
var _look_at: Vector3 = Vector3.ZERO
var _look_blend: float = 0.0

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

func set_tag_visible(on: bool) -> void:
	_tag_wanted = on
	_refresh_tag()

## The name tag and the speech line take turns: the name hides while they talk, so the two never overlap.
func _refresh_tag() -> void:
	_tag.visible = _tag_wanted and not _bark.visible

func _process(delta: float) -> void:
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
