class_name RockProjectile
extends Node3D
## DS2 Forest Golem-style physical rock: speed 15, one impact, no acid/slow/puddle/splash.
var source: Enemy
var destination := Vector3.ZERO
var damage := 0.0
var _direction := Vector3.ZERO
var _age := 0.0

func _ready() -> void:
	_direction = (destination - global_position).normalized()
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.32
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.33, 0.3)
	material.roughness = 1.0
	visual.material_override = material
	add_child(visual)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age > 3.0 or not is_instance_valid(source):
		queue_free()
		return
	var next := global_position + _direction * 15.0 * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, Actor.LAYER_WORLD | Actor.LAYER_PLAYER, [source.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var victim := hit.collider as Actor
		if victim != null and not victim.dead:
			victim.receive(Combat.resolve(source, victim, damage, Combat.DamageType.PHYSICAL, false, 0.5), global_position)
		queue_free()
	else: global_position = next
