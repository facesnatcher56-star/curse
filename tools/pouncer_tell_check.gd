extends SceneTree
## Focused check of the pouncer's landing telegraph: the marker is locked at windup start, sits exactly where the ghoul lands, its
## radius is the real hit radius, standing in it hurts and leaving it does not, and nothing leaks after land/stun/death.
## Run: tools/run_godot.sh LOG 120 -- --script res://tools/pouncer_tell_check.gd -- --pouncertell
## (user arguments make it a developer session: the production save is never touched). Exit code 1 if any check fails.

var failures: int = 0
var main: Node
const HERO := Vector3(30, 0, 30)

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  "), label, "  ", detail)
	if not ok:
		failures += 1

func _initialize() -> void:
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_run()

func tells() -> Array:
	return get_nodes_in_group(GroundTell.GROUP).filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion())

func _ghoul(offset: Vector3) -> Enemy:
	var g: Enemy = main.director.spawn_enemy(HERO + offset, "ghoul", 1.0)
	g.aggro_range = 40.0
	(g.behavior as PouncerBehavior)._pounce_cool = 0.0
	g.wake()
	return g

func _reset_hero() -> void:
	main.player.max_health = 5000.0
	main.player.health = 5000.0
	main.player.bleed_time = 0.0
	main.player.bleed_dps = 0.0
	main.player.global_position = HERO
	main.player.reset_physics_interpolation()
	main.player.movement.has_goal = false
	main.player.attack_target = null

func _wait_state(g: Enemy, state: int, limit: float = 9.0) -> bool:
	var t: float = 0.0
	while t < limit and is_instance_valid(g) and (g.behavior as PouncerBehavior)._state != state:
		await physics_frame
		t += 1.0 / 60.0
	return is_instance_valid(g) and (g.behavior as PouncerBehavior)._state == state

func _clear_enemies() -> void:
	for n in get_nodes_in_group("enemies"):
		n.queue_free()
	for n in tells():
		n.queue_free()
	await process_frame
	await process_frame

## One pounce. `hero_offset` (relative to the locked spot) is where the hero stands once the windup is under way; null = stay put.
func _pounce(hero_offset) -> Dictionary:
	_reset_hero()
	var g: Enemy = _ghoul(Vector3(0, 0, -5.5))
	var b: PouncerBehavior = g.behavior
	var out: Dictionary = {}
	out["windup"] = await _wait_state(g, PouncerBehavior.State.WINDUP)
	out["locked"] = b._to
	var marks: Array = tells()
	out["marks"] = marks.size()
	if marks.size() > 0:
		out["mark_pos"] = marks[0].global_position
		out["mark_radius"] = marks[0].radius
	out["hit_radius"] = b.hit_radius()
	if hero_offset != null:
		await physics_frame
		main.player.global_position = b._to + hero_offset
		main.player.reset_physics_interpolation()
	var before: float = main.player.health
	out["leap"] = await _wait_state(g, PouncerBehavior.State.LEAP)
	out["to_after_lock"] = b._to
	out["recover"] = await _wait_state(g, PouncerBehavior.State.RECOVER)
	out["land_pos"] = g.global_position
	out["damage"] = before - main.player.health
	out["marks_after"] = tells().size()
	return out

func _run() -> void:
	for i in 10:
		await process_frame
	_reset_hero()
	await _clear_enemies()

	# Stay put: lands on the marker, normal damage, marker gone after landing.
	var hurt: bool = false
	var stay: Dictionary = {}
	for attempt in 4:
		stay = await _pounce(null)
		hurt = hurt or stay.get("damage", 0.0) > 0.0
		await _clear_enemies()
	check("windup shows exactly one marker", stay["windup"] and stay["marks"] == 1, str(stay.get("marks")))
	var mp: Vector3 = stay["mark_pos"]
	check("marker sits on the locked landing point", Vector2(mp.x, mp.z).distance_to(Vector2(stay["locked"].x, stay["locked"].z)) < 0.01)
	check("marker radius equals the pounce hit radius", is_equal_approx(stay["mark_radius"], stay["hit_radius"]), "%s vs %s" % [stay["mark_radius"], stay["hit_radius"]])
	check("landing point equals the marked point", (stay["land_pos"] as Vector3).distance_to(stay["locked"]) < 0.05 and stay["to_after_lock"] == stay["locked"])
	check("staying in the radius receives pounce damage", hurt)
	check("marker is gone after landing", stay["marks_after"] == 0)

	# Re-aim: moving the hero during windup does not move the landing point.
	var moved: Dictionary = await _pounce(Vector3(hr(stay) + 3.0, 0, 0))
	await _clear_enemies()
	check("no re-aim: landing point unchanged after the hero moves", (moved["land_pos"] as Vector3).distance_to(moved["locked"]) < 0.05 and moved["to_after_lock"] == moved["locked"])
	check("leaving the marker radius avoids damage", moved["damage"] == 0.0, str(moved["damage"]))
	check("marker gone after a dodged landing", moved["marks_after"] == 0)

	# Just inside the radius still hurts (several tries: the hit can be a roll-miss).
	var edge_hurt: bool = false
	for attempt in 10:
		var inside: Dictionary = await _pounce(Vector3(hr(stay) - 0.25, 0, 0))
		edge_hurt = edge_hurt or inside["damage"] > 0.0
		if edge_hurt:
			await _clear_enemies()
			break
		await _clear_enemies()
	check("standing just inside the ring is still hit", edge_hurt)

	# Interrupt (stun) during windup.
	_reset_hero()
	var g: Enemy = _ghoul(Vector3(0, 0, -5.5))
	await _wait_state(g, PouncerBehavior.State.WINDUP)
	var had: int = tells().size()
	g.stun_time = 1.0
	await physics_frame
	await physics_frame
	await process_frame
	check("stun during windup removes the marker", had == 1 and tells().size() == 0 and (g.behavior as PouncerBehavior)._state == PouncerBehavior.State.STALK, "had %d now %d" % [had, tells().size()])
	await _clear_enemies()

	# Death during windup / mid-leap.
	for phase in [PouncerBehavior.State.WINDUP, PouncerBehavior.State.LEAP]:
		_reset_hero()
		var d: Enemy = _ghoul(Vector3(0, 0, -5.5))
		await _wait_state(d, phase)
		d.take_damage_for_test(9999.0) if d.has_method("take_damage_for_test") else _kill(d)
		await physics_frame
		await physics_frame
		await process_frame
		check("death in state %d removes the marker" % phase, d.dead and tells().size() == 0, "marks %d" % tells().size())
		await _clear_enemies()

	# Several pouncers: one marker each, never stacked on one enemy.
	_reset_hero()
	var pack: Array = []
	for i in 4:
		pack.append(_ghoul(Vector3(-6 + i * 4, 0, -6.0)))
	var peak: int = 0
	var t: float = 0.0
	while t < 5.0:
		await physics_frame
		t += 1.0 / 60.0
		peak = maxi(peak, tells().size())
	check("pack of 4 shows at most one marker each", peak >= 1 and peak <= 4, "peak %d" % peak)
	await _clear_enemies()
	_reset_hero()
	await create_timer(0.6).timeout
	check("no leaked markers at the end", tells().size() == 0, "marks %d" % tells().size())
	quit(1 if failures > 0 else 0)

func hr(d: Dictionary) -> float:
	return d["hit_radius"]

func _kill(e: Enemy) -> void:
	var blow: Dictionary = Combat.resolve(main.player, e, 99999.0, Combat.DamageType.PHYSICAL, false, 1.0)
	blow["outcome"] = Combat.Outcome.HIT
	e._pending_gib = ""
	e.receive(blow, e.global_position + Vector3(0, 0, 2.0))
