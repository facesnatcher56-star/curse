extends SceneTree
## Display-independent check of enemy death / ragdoll presentation: ordinary death, a heavy (high-energy) death, repeated callbacks, a
## corpse settling to a frozen pose, and cleanup. Numeric only (poses, speeds, settle state); no window or focus needed.
## Run: tools/run_godot.sh LOG 90 -- --script res://tools/ragdoll_death_check.gd -- --ragdolldeath
## (user arguments make it a developer session: the production save is never touched). Exit code 1 if any check fails.

var failures: int = 0
var main: Node

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  "), label, "  ", detail)
	if not ok:
		failures += 1

func _initialize() -> void:
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_run()

func _spawn(pos: Vector3) -> Enemy:
	var e: Enemy = main.director.spawn_enemy(pos, "zombie", 1.0)
	e.aggro_range = 0.0
	e.max_health = 1.0
	e.health = 1.0
	return e

func _kill(e: Enemy, weight: float) -> void:
	var blow: Dictionary = Combat.resolve(main.player, e, 500.0, Combat.DamageType.PHYSICAL, false, weight)
	blow["outcome"] = Combat.Outcome.HIT
	e._pending_gib = ""
	e.receive(blow, e.global_position + Vector3(0, 0, 2.0))

## Samples the ragdoll each physics frame for `seconds`; returns peak horizontal speed, peak travel, and the time it reached LYING.
func _watch(e: Enemy, seconds: float) -> Dictionary:
	var start: Vector3 = e.global_position
	var peak_speed: float = 0.0
	var peak_travel: float = 0.0
	var lying_at: float = -1.0
	var t: float = 0.0
	var last: Vector3 = start
	while t < seconds:
		await physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
		peak_speed = maxf(peak_speed, (e.global_position - last).length() * Engine.physics_ticks_per_second)
		last = e.global_position
		peak_travel = maxf(peak_travel, (e.global_position - start).length())
		if lying_at < 0.0 and e.ragdoll != null and e.ragdoll.state == Ragdoll.State.LYING:
			lying_at = t
	return {"speed": peak_speed, "travel": peak_travel, "lying_at": lying_at}

func _pose_hash(e: Enemy) -> Array:
	var sk: Skeleton3D = e.ragdoll.skeleton
	var out: Array = [e.visual.transform]
	for i in sk.get_bone_count():
		out.append(sk.get_bone_pose_rotation(i))
	return out

func _same_pose(a: Array, b: Array) -> bool:
	if not (a[0] as Transform3D).is_equal_approx(b[0]):
		return false
	for i in range(1, a.size()):
		if not (a[i] as Quaternion).is_equal_approx(b[i]):
			return false
	return true

func _run() -> void:
	for i in 10:
		await process_frame
	main.player.global_position = Vector3(30, 0, 30)

	# Ordinary death.
	var a: Enemy = _spawn(Vector3(-4, 0, -6))
	await create_timer(0.2).timeout
	_kill(a, 1.0)
	check("ordinary death goes ragdoll and dead", a.dead and a.is_ragdolled())
	var wa: Dictionary = await _watch(a, 3.0)
	check("ordinary death settles lying", a.ragdoll.state == Ragdoll.State.LYING and a.ragdoll.permanent, str(wa))
	check("ordinary death stays within a sane distance", wa["travel"] < 6.0, str(wa))
	check("ordinary corpse is frozen (settled)", a.ragdoll._settled)
	var p1: Array = _pose_hash(a)
	await create_timer(0.5).timeout
	check("settled corpse pose does not move (no jitter)", _same_pose(p1, _pose_hash(a)))
	var pos_a: Vector3 = a.global_position
	# Repeated callbacks must not restart anything.
	a.ragdoll_launch(Vector3(5, 0, 0), 4.0, Vector3(3, 3, 3))
	a.ragdoll.stay_down()
	await create_timer(0.3).timeout
	check("repeated launch/stay_down on a settled corpse is ignored",
		a.ragdoll.state == Ragdoll.State.LYING and a.ragdoll._settled and a.global_position.is_equal_approx(pos_a))

	# High-energy death: the heaviest blow must be capped.
	var b: Enemy = _spawn(Vector3(4, 0, -6))
	await create_timer(0.2).timeout
	_kill(b, 3.5)
	check("heavy death goes ragdoll", b.dead and b.is_ragdolled())
	check("heavy death launch speed is capped", b.ragdoll._velocity.length() <= Ragdoll.DEAD_MAX_SPEED + 0.01, str(b.ragdoll._velocity))
	check("heavy death lift is capped", b.ragdoll._vy <= Ragdoll.DEAD_MAX_LIFT + 0.01, str(b.ragdoll._vy))
	check("heavy death spin is capped", b.ragdoll._omega.length() <= Ragdoll.DEAD_MAX_SPIN + 0.01, str(b.ragdoll._omega))
	var wb: Dictionary = await _watch(b, Ragdoll.DEAD_FLIGHT_MAX + 2.5)
	check("heavy death settles lying and frozen before the sink timer (5s)", b.ragdoll.state == Ragdoll.State.LYING and b.ragdoll._settled and wb["lying_at"] > 0.0 and wb["lying_at"] < 4.0, str(wb))
	check("heavy death travel stays bounded", wb["travel"] < 9.0, str(wb))

	# Wall impact: a corpse launched into the world edge/props still resolves to a settled corpse.
	var c: Enemy = _spawn(Vector3(0, 0, -6))
	await create_timer(0.2).timeout
	_kill(c, 1.0)
	c.ragdoll._velocity = Vector3(0, 0, -12)   # drive hard at whatever is there
	var wc: Dictionary = await _watch(c, Ragdoll.DEAD_FLIGHT_MAX + 3.0)
	check("fast corpse still settles (wall or open ground)", c.ragdoll.state == Ragdoll.State.LYING and c.ragdoll._settled, str(wc))

	# Cleanup: once settled, the sink tween owns the visual (the ragdoll no longer rewrites it) and the enemy is freed.
	var e: Enemy = _spawn(Vector3(8, 0, -6))
	await create_timer(0.2).timeout
	_kill(e, 1.0)
	await create_timer(6.2).timeout   # 5 s lie, then the 2 s sink begins
	check("settled corpse is sinking (visual y falls)", is_instance_valid(e) and e.visual.position.y < -0.05, str(e.visual.position.y if is_instance_valid(e) else "freed"))
	await create_timer(2.5).timeout
	check("corpse is removed after sinking", not is_instance_valid(e))

	# Alive launch is untouched by the corpse caps.
	var d: Enemy = _spawn(Vector3(-8, 0, -6))
	d.max_health = 500.0
	d.health = 500.0
	await create_timer(0.2).timeout
	d.ragdoll_launch(Vector3(0, 0, -10), 6.0, Vector3(0, 0, 12))
	check("living launch keeps full energy", d.ragdoll._velocity.length() > Ragdoll.DEAD_MAX_SPEED and d.ragdoll._vy > Ragdoll.DEAD_MAX_LIFT - 0.01)
	var wd: Dictionary = await _watch(d, 6.0)
	check("living launch still gets back up", d.ragdoll == null or d.ragdoll.state == Ragdoll.State.OFF or d.ragdoll.state == Ragdoll.State.RISING, str(wd))
	quit(1 if failures > 0 else 0)
