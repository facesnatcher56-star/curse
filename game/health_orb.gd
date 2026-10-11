class_name HealthOrb
extends Node3D
## Small healing orb dropped by kills; walk over it to collect.

const HEAL := 15.0
const LIFETIME := 18.0

## A potion pickup instead of a healing orb (red, collected as +1 potion).
var is_potion: bool = false

## Healing is scarce but fair: orbs drop more often the more hurt the hero is, potions drop rarely, and a big monster always pays out.
static func drop_for_kill(player: Player, enemy: Actor) -> void:
	var missing: float = 1.0 - clampf(player.health / player.max_health, 0.0, 1.0)
	var big: bool = enemy.is_big()
	var orbs: int = 0
	var potions: int = 0
	if big:
		orbs = 2
		potions = 1 if randf() < 0.6 else 0
	else:
		var chance: float = 0.09 + 0.22 * missing
		orbs = 1 if randf() < chance else 0
		potions = 1 if randf() < 0.025 + 0.04 * missing else 0
	for i in orbs + potions:
		var orb := HealthOrb.new()
		orb.is_potion = i >= orbs
		player.get_tree().current_scene.add_child(orb)
		orb.global_position = enemy.global_position + Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7))

var _age: float = 0.0
var _base_y: float = 0.6

func _ready() -> void:
	add_to_group("orbs")
	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.26 if is_potion else 0.2
	mesh.height = 0.52 if is_potion else 0.4
	orb.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.3) if is_potion else Color(0.4, 1.0, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.12) if is_potion else Color(0.2, 1.0, 0.35)
	mat.emission_energy_multiplier = 2.5
	orb.material_override = mat
	add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.3) if is_potion else Color(0.4, 1.0, 0.5)
	light.light_energy = 0.9
	light.omni_range = 3.0
	add_child(light)

func _process(delta: float) -> void:
	_age += delta
	position.y = _base_y + sin(_age * 3.0) * 0.08
	if _age > LIFETIME - 3.0:
		visible = int(_age * 8.0) % 2 == 0  # blink before disappearing
	if _age >= LIFETIME:
		queue_free()
