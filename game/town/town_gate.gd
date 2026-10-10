extends Node3D
## Original weathered gate, split in Blender at its two hinges. The opening stays
## navigable; proximity from either side opens it before the hero reaches the doors.

var leaves: Array[Node3D] = []
var openness: float = 0.0
var wanted: bool = false
var _tag: Label3D

func _ready() -> void:
	var scene := load("res://assets/models/town/working_gate/model.glb") as PackedScene
	var model := scene.instantiate()
	add_child(model)
	for side in ["Left", "Right"]:
		var leaf := model.find_child(side, true, false) as Node3D
		leaves.append(leaf)
	_setup_gate_tag()

func _setup_gate_tag() -> void:
	_tag = Label3D.new()
	_tag.name = "GateTag"
	_tag.text = "North Gate\nTo Crypt Road"
	_tag.position = Vector3(0.0, 4.5, 0.0)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.fixed_size = true
	_tag.pixel_size = 0.0015
	_tag.font_size = 22
	_tag.outline_size = 8
	_tag.modulate = Color(0.92, 0.86, 0.76)
	_tag.outline_modulate = Color(0.04, 0.04, 0.05)
	_tag.visible = false
	add_child(_tag)

func set_tag_visible(on: bool) -> void:
	if _tag != null:
		_tag.visible = on

func set_open(on: bool) -> void:
	wanted = on

func _process(delta: float) -> void:
	openness = move_toward(openness, 1.0 if wanted else 0.0, delta * 1.5)
	for i in leaves.size():
		if leaves[i] != null:
			leaves[i].rotation.y = (1.0 if i == 0 else -1.0) * openness * PI * 0.5

