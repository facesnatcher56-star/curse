extends Node3D
## Original weathered gate, split in Blender at its two hinges. The opening stays
## navigable; proximity from either side opens it before the hero reaches the doors.

var leaves: Array[Node3D] = []
var openness: float = 0.0
var wanted: bool = false

func _ready() -> void:
	var scene := load("res://assets/models/town/working_gate/model.glb") as PackedScene
	var model := scene.instantiate()
	add_child(model)
	for side in ["Left", "Right"]:
		var leaf := model.find_child(side, true, false) as Node3D
		leaves.append(leaf)

func set_open(on: bool) -> void:
	wanted = on

func _process(delta: float) -> void:
	openness = move_toward(openness, 1.0 if wanted else 0.0, delta * 1.5)
	for i in leaves.size():
		if leaves[i] != null:
			leaves[i].rotation.y = (1.0 if i == 0 else -1.0) * openness * PI * 0.5
