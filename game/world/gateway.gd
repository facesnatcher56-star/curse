class_name Gateway
extends Node3D
## A corridor's gateway (assets/models/gateway, made in Blender: source/gateway.blend): two stone jambs, an arch and a pair of iron-bound doors
## across an 8 m opening. The model's origin is the middle of the opening on the wall line, its X runs along the wall and its -Z points into the
## corridor; each door leaf's pivot is its hinge. The doors swing open into the corridor, flat against its side walls, when a living party member
## comes within OPEN_RANGE, and stay open. They have no collision: nothing ever waits on them. The jambs do.
## A `low` gateway (an opening in a room's south wall, which faces the camera) keeps only waist-high jambs, as the kit's south walls are low barriers.

const MODEL := "res://assets/models/gateway/gateway.glb"
const OPEN_RANGE := 7.0       # m from the middle of the opening
const OPEN_SECONDS := 0.85
const OPEN_ANGLE := 90.0      # degrees: flat against the corridor's side walls
const JAMB_SIZE := Vector3(1.2, 4.4, 1.4)
const JAMB_X := 4.6           # m from the middle: the jambs' inner faces sit on the opening's edges (8 m clear)
const LOW_SCALE := 0.3        # a low gateway's jambs, of their full height

@export var low: bool = false

var opened: bool = false
var _door_l: Node3D
var _door_r: Node3D


func _ready() -> void:
	add_to_group("gateways")
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	_door_l = model.find_child("DoorL", true, false) as Node3D
	_door_r = model.find_child("DoorR", true, false) as Node3D
	if low:
		for part in ["Arch", "DoorL", "DoorR"]:
			var n := model.find_child(part, true, false) as Node3D
			if n != null:
				n.queue_free()
		for part in ["JambL", "JambR"]:
			var j := model.find_child(part, true, false) as Node3D
			if j != null:
				j.scale.y = LOW_SCALE
		_door_l = null
		_door_r = null
		opened = true
	for side in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		body.collision_layer = Actor.LAYER_WORLD
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var height: float = JAMB_SIZE.y * (LOW_SCALE if low else 1.0)
		box.size = Vector3(JAMB_SIZE.x, height, JAMB_SIZE.z)
		shape.shape = box
		shape.position = Vector3(side * JAMB_X, height * 0.5, 0.0)
		body.add_child(shape)
		add_child(body)
	set_physics_process(not opened)


func _physics_process(_delta: float) -> void:
	for member in PartyManager.current().living():
		var gap := Vector2(member.global_position.x - global_position.x, member.global_position.z - global_position.z)
		if gap.length() <= OPEN_RANGE:
			open()
			return


## Swings both leaves open (eased), once.
func open() -> void:
	if opened:
		return
	opened = true
	set_physics_process(false)
	if _door_l == null or _door_r == null:
		return
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_door_l, "rotation:y", deg_to_rad(OPEN_ANGLE), OPEN_SECONDS)
	tween.tween_property(_door_r, "rotation:y", deg_to_rad(-OPEN_ANGLE), OPEN_SECONDS)
