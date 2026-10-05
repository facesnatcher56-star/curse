class_name EmberTrail
extends Node3D
## The trail of embers an Ember-Treaded dodge roll leaves behind: glowing patches on the ground along the path of the roll that set any
## enemy crossing them alight, and burn out after a few seconds.

const SPACING := 0.45            # metres between patches
const LIFETIME := 3.0
const BURN_DPS := 6.0
const BURN_TIME := 3.0
const REACH := 1.0               # how close an enemy has to be to a patch to catch fire

var _points: Array[Dictionary] = []   # {pos, age, node}
var _player: Player
var _following: bool = true
var _last: Vector3

## Starts a trail that follows the player until their roll ends.
static func follow(player: Player) -> EmberTrail:
	var trail := EmberTrail.new()
	trail._player = player
	player.get_tree().current_scene.add_child(trail)
	trail._last = player.global_position
	trail._drop(player.global_position)
	return trail

func _physics_process(delta: float) -> void:
	if _following and _player != null and is_instance_valid(_player):
		var pos: Vector3 = _player.global_position
		while _last.distance_to(pos) >= SPACING:
			_last = _last.move_toward(pos, SPACING)
			_drop(_last)
		if not _player.movement.rolling:
			_following = false
	elif _following:
		_following = false
	for i in range(_points.size() - 1, -1, -1):
		var point: Dictionary = _points[i]
		point["age"] = float(point["age"]) + delta
		var glow: MeshInstance3D = point["node"]
		var fade: float = clampf(1.0 - float(point["age"]) / LIFETIME, 0.0, 1.0)
		glow.scale = Vector3(1.0, 1.0, 1.0) * (0.7 + 0.5 * fade)
		(glow.material_override as StandardMaterial3D).albedo_color.a = 0.75 * fade
		if float(point["age"]) >= LIFETIME:
			glow.queue_free()
			_points.remove_at(i)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or (e.is_burning() and e.burn_time > 1.0):
			continue
		for point in _points:
			if e.flat_distance_to_point(point["pos"]) <= REACH:
				e.apply_burn(BURN_DPS, BURN_TIME)
				break
	if not _following and _points.is_empty():
		queue_free()

func _drop(pos: Vector3) -> void:
	var glow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.45
	disc.bottom_radius = 0.45
	disc.height = 0.03
	disc.radial_segments = 14
	glow.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.42, 0.1, 0.75)
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	glow.global_position = Vector3(pos.x, 0.05, pos.z)
	_points.append({"pos": Vector3(pos.x, 0.0, pos.z), "age": 0.0, "node": glow})
	Fx.burst(self, Vector3(pos.x, 0.2, pos.z), Vector3.UP, Color(1.0, 0.55, 0.12), 4, 3.0, 0.03, true)
