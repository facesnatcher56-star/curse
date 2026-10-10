extends SceneTree
## Focused check of the plague priest's finite summons: the cast still telegraphs, every cast raises zombies up to a per-priest
## budget, then the priest stops summoning (but can still ward), and raised zombies stay XP-free.
## Run: tools/run_godot.sh LOG 120 -- --script res://tools/priest_summon_check.gd -- --priestcheck
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

func _zombies() -> Array:
	return get_nodes_in_group("enemies").filter(func(n: Node) -> bool: return (n as Enemy).variant == "zombie" and not (n as Enemy).dead)

func _run() -> void:
	for i in 10:
		await process_frame
	var p: Player = main.player
	p.max_health = 99999.0
	p.health = 99999.0
	p.global_position = HERO
	p.reset_physics_interpolation()
	main.rig.global_position = HERO
	for n in get_nodes_in_group("enemies"):
		n.queue_free()
	await process_frame

	var priest: Enemy = main.director.spawn_enemy(HERO + Vector3(0, 0, -9), "priest", 1.0)
	priest._aggro = true
	var sb: SupportBehavior = priest.behavior as SupportBehavior
	var budget: int = int(priest.def.param("summon_budget", 6))
	var per_cast: int = int(priest.def.param("summon_count", 2))
	check("priest uses SupportBehavior", sb != null)
	check("budget is finite and covers at least one cast", budget >= per_cast and budget <= 12, str(budget))
	check("budget starts full", sb.summons_left() == budget)

	var saw_cast_telegraph := false
	var casts := 0
	var prev_total := 0
	var killed := 0
	var all_xp_free := true
	for frame in 2400:
		sb._summon_cd = 0.0   # compress the 15s interval; the cast itself runs in real (physics) time
		if sb._state == SupportBehavior.State.CAST and priest.is_telegraphing():
			saw_cast_telegraph = true
		if sb._raised_total != prev_total:
			casts += 1
			prev_total = sb._raised_total
		# Keep the summon_max concurrency cap out of the way: remove raised zombies as they appear.
		for z in _zombies():
			all_xp_free = all_xp_free and not (z as Enemy).xp_eligible
			(z as Enemy).free()
			killed += 1
		priest.global_position = HERO + Vector3(0, 0, -9)   # stay out of flee range
		await physics_frame
	check("summon cast showed its telegraph", saw_cast_telegraph)
	check("priest raised exactly its budget", sb._raised_total == budget and killed == budget, "raised=%d removed=%d budget=%d" % [sb._raised_total, killed, budget])
	check("budget spent after finitely many casts", casts == int(ceil(float(budget) / per_cast)), "casts=%d" % casts)
	check("no summons left", sb.summons_left() == 0)
	check("no more zombies appear afterwards", _zombies().is_empty())

	# A priest that is still alive can still ward after its budget is spent.
	var ally: Enemy = main.director.spawn_enemy(HERO + Vector3(2, 0, -9), "zombie", 1.0)
	ally.aggro_range = 0.0
	sb._ward_cd = 0.0
	for frame in 90:
		await physics_frame
	check("spent priest still casts wards", ally.ward_source == priest)
	check("raised zombies pay no XP", all_xp_free)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
