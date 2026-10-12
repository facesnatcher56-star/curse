class_name RockThrowerBehavior
extends SpitterBehavior
## Reuse navigation, spacing and committed throw handling, not the acid payload.
func _spit() -> void:
	var rock := RockProjectile.new()
	rock.source = e
	rock.position = e.global_position + Vector3(0, e.body_height * 0.75, 0)
	rock.destination = e.target.global_position + Vector3(0, e.target.body_height * 0.5, 0)
	rock.damage = randf_range(e.damage_min, e.damage_max)
	e.get_tree().current_scene.add_child(rock)
