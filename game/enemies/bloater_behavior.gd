class_name BloaterBehavior
extends EnemyBehavior
## The bloater: slow and relentless, and it never attacks. Close enough, it swells for a second and bursts; it also bursts when
## killed. The blast hurts everyone near it (including other enemies) and leaves a poison cloud. Kill it at range, or with fire,
## which sets off the gas: a fireball makes it a bomb that burns the crowd around it.

var _fusing: bool = false
var _fuse_t: float = 0.0
var _detonated: bool = false
var _base_scale: Vector3 = Vector3.ONE

func is_attacking() -> bool:
	return _fusing

func setup(enemy: Enemy) -> void:
	super.setup(enemy)
	_base_scale = enemy.visual.scale

func on_interrupted() -> void:
	# Knocked about it keeps swelling; a stun only delays it.
	pass

func tick(delta: float, dist: float) -> void:
	if _fusing:
		_fuse_t += delta
		var fuse: float = float(e.def.param("fuse_time", 1.0))
		var u: float = clampf(_fuse_t / fuse, 0.0, 1.0)
		e.visual.scale = _base_scale * (1.0 + 0.3 * u + 0.05 * sin(_fuse_t * 28.0))
		e.telegraph(0.25 + 0.4 * u)
		e.move_with(Vector3.ZERO)
		if _fuse_t >= fuse:
			_burst(false)
		return
	if dist <= float(e.def.param("fuse_range", 2.3)):
		_fusing = true
		e._attacking = true
		_fuse_t = 0.0
		if e.has_clip("scream"):
			e.model.once("scream", 0.0, 1.6, 0.1)
		Sfx.play(e, "groan", -2.0, 0.7)
		return
	e.walk_to(e.target.global_position, delta, 1.0, dist > 3.5)

func on_death(killing_blow: Dictionary) -> void:
	var by_fire: bool = killing_blow.get("type", 0) == Combat.DamageType.FIRE and not killing_blow.get("secondary", false)
	_burst(by_fire)

## The blast. `by_fire`: it was shot with fire, so the gas ignites and the explosion is a firebomb.
func _burst(by_fire: bool) -> void:
	if _detonated:
		return
	_detonated = true
	e.visual.scale = _base_scale
	var centre: Vector3 = e.global_position
	var radius: float = float(e.def.param("blast_radius", 3.2))
	var damage: float = float(e.def.param("blast_damage", 22.0)) * (1.0 + 0.4 * (e.level_scale - 1.0))
	var scene: Node = e.get_tree().current_scene
	# Everyone close takes it: the hero, and other enemies (so luring a Bloater into a pack is a plan).
	for node in e.get_tree().get_nodes_in_group("player"):
		_blast_actor(node as Actor, centre, radius, damage)
	for node in e.get_tree().get_nodes_in_group("enemies"):
		var other := node as Actor
		if other != null and other != e:
			var amount: float = damage * 0.6
			if by_fire:
				amount += float(e.def.param("fire_blast_damage", 32.0))
			_blast_actor(other, centre, radius, amount, by_fire)
	if by_fire:
		Fx.light_flash(scene, centre + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.25), 9.0, 0.35)
		Fx.ring(scene, centre, radius * 1.4, Color(1.0, 0.6, 0.25))
		Fx.burst(scene, centre + Vector3(0, 1.0, 0), Vector3.UP, Color(1.0, 0.65, 0.2), 60, 10.0, 0.04, true)
		SkillFx.dust(scene, centre, radius * 0.6, 20, Color(0.2, 0.17, 0.14, 0.5), 1.5, 1.4)
	else:
		Fx.light_flash(scene, centre + Vector3(0, 1.0, 0), Color(0.5, 0.95, 0.2), 5.0, 0.3)
		Fx.ring(scene, centre, radius * 1.2, Color(0.55, 1.0, 0.25))
		Fx.burst(scene, centre + Vector3(0, 1.0, 0), Vector3.UP, Color(0.5, 0.9, 0.2), 50, 8.0, 0.045, true)
		var cloud := HazardZone.new()
		cloud.radius = radius * 0.9
		cloud.lifetime = float(e.def.param("cloud_time", 4.5))
		cloud.dps = float(e.def.param("cloud_dps", 5.0))
		cloud.slow = 0.35
		cloud.source = e
		scene.add_child(cloud)
		cloud.global_position = Vector3(centre.x, 0.0, centre.z)
	Fx.shake(scene, 0.4)
	Fx.punch(scene, 3.0)
	Sfx.play(e, "explosion", -2.0)
	if not e.dead:
		# It burst itself: it dies in pieces.
		e._pending_gib = "fire" if by_fire else "gore"
		e._gib_from = centre
		e._apply_damage(e.health + 1.0)

func _blast_actor(actor: Actor, centre: Vector3, radius: float, damage: float, ignite: bool = false) -> void:
	if actor == null or actor.dead:
		return
	var gap: Vector3 = actor.global_position - centre
	gap.y = 0.0
	if gap.length() > radius + actor.body_radius * 0.5:
		return
	var falloff: float = 1.0 - clampf(gap.length() / (radius + 0.01), 0.0, 1.0) * 0.5
	var result: Dictionary = Combat.resolve(e, actor, damage * falloff, Combat.DamageType.FIRE, false, 2.2)
	result["secondary"] = true
	actor.receive(result, centre)
	if is_instance_valid(actor) and not actor.dead and ignite:
		actor.apply_burn(4.0, 4.0)
