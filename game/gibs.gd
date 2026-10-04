class_name Gibs
extends RefCounted
## Bursting a body into pieces. "gore" is what a critical kill does; "fire" is a fireball kill: the same blast, but the
## pieces fly out charred and burning, like a bomb went off.

const MAX_LIVE := 90

## Chunk recipes: [mesh kind, size (x, y, z) as a fraction of the body height, count]. Kinds: box, capsule, sphere.
const PARTS: Array = [
	["box", Vector3(0.2, 0.24, 0.13), 1],        # torso
	["sphere", Vector3(0.09, 0.09, 0.09), 1],    # head
	["capsule", Vector3(0.06, 0.28, 0.06), 2],   # arms
	["capsule", Vector3(0.075, 0.32, 0.075), 2], # legs
	["box", Vector3(0.07, 0.05, 0.06), 6],       # meat
]

static func explode(actor: Actor, mode: String, from_pos: Vector3) -> void:
	var burning: bool = mode == "fire"
	var scene: Node = actor.get_tree().current_scene
	var centre: Vector3 = actor.global_position + Vector3(0, actor.body_height * 0.55, 0)
	var away: Vector3 = actor.global_position - from_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.ZERO
	var skin: Color = actor._gib_color()
	var live: Array[Node] = actor.get_tree().get_nodes_in_group("gibs")
	for part in PARTS:
		for i in int(part[2]):
			if live.size() > MAX_LIVE:
				live.pop_front().queue_free()
			var chunk := GibChunk.new()
			chunk.burning = burning
			chunk.setup(String(part[0]), (part[1] as Vector3) * actor.body_height, skin)
			scene.add_child(chunk)
			chunk.global_position = centre + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.3), randf_range(-0.2, 0.2))
			var spread: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			var horizontal: Vector3 = (spread + away * 0.9).normalized() * randf_range(3.5, 9.5)
			chunk.velocity = horizontal + Vector3(0, randf_range(4.5, 10.5), 0)
			chunk.spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	# The blast itself.
	var blood: Color = Color(0.5, 0.04, 0.03)
	Fx.burst(actor, centre, Vector3.UP, blood, 60, 9.0, 0.035)
	Fx.burst(actor, centre, away + Vector3.UP * 0.5, blood.darkened(0.2), 40, 12.0, 0.03)
	Fx.blood_decal(actor, actor.global_position, 2.4, blood.darkened(0.4))
	for i in 3:
		Fx.blood_decal(actor, actor.global_position + Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6)), randf_range(0.5, 1.0), blood.darkened(0.45))
	Fx.shake(actor, 0.35 if burning else 0.22)
	Fx.punch(actor, 3.0 if burning else 1.8)
	if burning:
		Fx.light_flash(actor, centre, Color(1.0, 0.6, 0.25), 8.0, 0.35)
		Fx.ring(actor, actor.global_position, 4.2, Color(1.0, 0.6, 0.25))
		Fx.burst(actor, centre, Vector3.UP, Color(1.0, 0.65, 0.2), 50, 11.0, 0.04, true)
		SkillFx.dust(actor, actor.global_position, 1.8, 16, Color(0.16, 0.14, 0.13, 0.5), 1.4, 1.4)
	else:
		Fx.ring(actor, actor.global_position, 2.6, Color(0.8, 0.15, 0.1))
