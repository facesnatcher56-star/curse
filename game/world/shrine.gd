class_name Shrine
extends Node3D
## A shrine of the Sunken Way: visit it once and the whole party is healed and restored (life, mana, stamina). Map mode calls use_shrine() on
## the node visit; in the walking game (issue #112) a living party member who steps within USE_RANGE of it uses it. Nothing here reads the
## mouse. After use the glow goes out.

## Flat metres from the shrine at which a walking party member uses it.
const USE_RANGE := 2.0

var used: bool = false
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("shrines")
	_light = OmniLight3D.new()
	_light.name = "ShrineGlow"
	_light.light_color = Color(0.45, 0.85, 1.0)
	_light.light_energy = 1.8
	_light.omni_range = 7.0
	_light.position = Vector3(0.0, 1.8, 0.0)
	add_child(_light)


func _physics_process(_delta: float) -> void:
	if used or MapMode.active:   # map mode uses it on the node visit
		return
	for member in PartyManager.current().living():
		if Vector2(member.global_position.x - global_position.x, member.global_position.z - global_position.z).length() <= USE_RANGE:
			if use_shrine():
				member.say_banner("Shrine: the party is restored")
			return


## Heals and restores every living party member fully, once. Returns true when it did, false when the shrine was already spent.
func use_shrine() -> bool:
	if used:
		return false
	used = true
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("player"):
			var member := node as Player
			if member == null or member.dead:
				continue
			member.health = member.max_health
			member.stats.mana = member.stats.max_mana
			member.stats.stamina = member.stats.max_stamina
	if _light != null:
		_light.light_energy = 0.0
	set_physics_process(false)
	return true
