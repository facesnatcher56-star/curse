extends DevSuite
## Map mode enemy roles + dash formation (issue #81): each role picks its target, Provoke overrides them, the Cutter lands 8-10 m behind the warrior,
## a ghoul dives the Cutter, and with the flag off targeting is exactly the default game's (closest, sticky).

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _hit(who: Actor, amount: float) -> Dictionary:
	return {"source": who, "damage": amount}

func _test_map_mode_roles() -> void:
	var cutter: Player = game.companion
	var cutter_was_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = false
	var base: Vector3 = player.global_position
	# --- Flag off: the default game's targeting is untouched -------------------------------------------------------------------------
	expect("flag off at the start", not MapMode.active)
	var ghoul_off: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(4.0, 0.0, 0.0)), "ghoul", 1.0)
	var brute_off: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-4.0, 0.0, 0.0)), "brute", 1.0)
	cutter.global_position = Nav.snap(cutter, base + Vector3(9.0, 0.0, 0.0))
	player.attack_target = null
	for e in [ghoul_off, brute_off]:
		e.wake()
	await _frames(3)
	var hero_gap: float = ghoul_off.flat_distance_to(player)
	var cutter_gap: float = ghoul_off.flat_distance_to(cutter)
	expect("flag off: a ghoul keeps the default closest target (hero %.1f m, Cutter %.1f m)" % [hero_gap, cutter_gap], ghoul_off.target == (player if hero_gap <= cutter_gap else cutter))
	var ghoul_goal := Vector3(ghoul_off.global_position.x + 3.0, 0.0, ghoul_off.global_position.z)
	expect("flag off: route_goal hands the goal back unchanged", EnemyRoles.route_goal(ghoul_off, ghoul_goal) == ghoul_goal)
	ghoul_off.target = cutter
	await _frames(4)
	expect("flag off: a sticky target is never swapped (the hand-off Provoke uses)", ghoul_off.target == cutter)
	var hits_before: int = EnemyRoles.state_of(brute_off).hits.size()
	brute_off.receive({"source": player, "damage": 5.0, "outcome": Combat.Outcome.HIT, "weight": 1.0}, base)
	expect("flag off: no hit history is kept", EnemyRoles.state_of(brute_off).hits.size() == hits_before)
	for e in [ghoul_off, brute_off]:
		e._apply_damage(e.max_health + 10.0)

	# --- Each role picks the right target (the rule itself, with a fixed clock) -------------------------------------------------------
	player.global_position = Nav.snap(player, base)
	cutter.global_position = Nav.snap(cutter, base + Vector3(9.0, 0.0, 0.0))
	var members: Array = [player, cutter]
	var zombie: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-2.0, 0.0, 2.0)), "zombie", 1.0)
	var ghoul: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-3.0, 0.0, -2.0)), "ghoul", 1.0)
	var thrower: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-3.0, 0.0, 4.0)), "rock_thrower", 1.0)
	var brute: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-5.0, 0.0, 0.0)), "brute", 1.0)
	var warden: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-5.0, 0.0, 3.0)), "warden", 1.0)
	for e in [zombie, ghoul, thrower, brute, warden]:
		e.set_physics_process(false)   # the rules are driven by hand here
	expect("the role table names every role kind in one place", EnemyRoles.ROLES.keys().size() == 5 and EnemyRoles.rule_of(ghoul) == "flanker" and EnemyRoles.rule_of(zombie) == "closest")
	expect("zombie: no opinion, so the sticky closest target stays", EnemyRoles.choose(zombie, members, 100.0) == null)
	expect("ghoul: the Cutter, though the hero is closer", EnemyRoles.choose(ghoul, members, 100.0) == cutter)
	expect("ghoul: the hero when the Cutter is down", EnemyRoles.choose(ghoul, [player], 100.0) == player)
	expect("rock thrower: closest (no opinion) before anyone hit it", EnemyRoles.choose(thrower, members, 100.0) == null)
	EnemyRoles.note_hit(thrower, _hit(player, 5.0), thrower.global_position + Vector3(1.0, 0.0, 0.0), 100.0)   # a melee blow
	expect("rock thrower: a melee hit does not count", EnemyRoles.choose(thrower, members, 100.5) == null)
	EnemyRoles.note_hit(thrower, _hit(cutter, 5.0), thrower.global_position + Vector3(12.0, 0.0, 0.0), 101.0)   # an arrow
	expect("rock thrower: whoever last hit it from range (the Cutter)", EnemyRoles.choose(thrower, members, 102.0) == cutter)
	EnemyRoles.note_hit(thrower, _hit(player, 5.0), thrower.global_position + Vector3(8.0, 0.0, 0.0), 103.0)
	expect("rock thrower: the latest ranged hitter wins (the hero)", EnemyRoles.choose(thrower, members, 103.5) == player)
	expect("rock thrower: forgotten after its memory runs out", EnemyRoles.choose(thrower, members, 103.0 + float(EnemyRoles.ROLES["rock_thrower"]["memory"]) + 1.0) == null)
	EnemyRoles.note_hit(brute, _hit(player, 40.0), brute.global_position, 200.0)
	EnemyRoles.note_hit(brute, _hit(cutter, 15.0), brute.global_position, 200.5)
	EnemyRoles.note_hit(brute, _hit(cutter, 15.0), brute.global_position, 201.0)
	expect("brute: the biggest damage dealer in the last 5 s (the hero, 40 against 30)", EnemyRoles.choose(brute, members, 201.5) == player)
	EnemyRoles.note_hit(brute, _hit(cutter, 30.0), brute.global_position, 202.0)
	expect("brute: it only re-checks every 2 s (no new opinion at +0.5 s)", EnemyRoles.choose(brute, members, 202.0) == null)
	expect("brute: after the re-check the Cutter leads (60 against 40)", EnemyRoles.choose(brute, members, 203.6) == cutter)
	expect("brute: damage older than 5 s counts for nothing", EnemyRoles.choose(brute, members, 215.0) == null)
	var every: float = float(EnemyRoles.ROLES["warden"]["special_every"])
	expect("warden: closest to begin with (no opinion)", EnemyRoles.choose(warden, members, 300.0) == null)
	expect("warden: its telegraphed attack goes for the farthest member", EnemyRoles.choose(warden, members, 300.0 + every + 0.1) == cutter)
	expect("warden: and back to the closest once the window has passed", EnemyRoles.choose(warden, members, 300.0 + every + 0.1 + float(EnemyRoles.ROLES["warden"]["special_window"]) + 0.5) == player)
	# A champion keeps its kind's rule.
	var champ: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-3.0, 0.0, -4.0)), "ghoul", 1.0)
	champ.set_physics_process(false)
	Champion.attach(champ, "fast")
	expect("a champion ghoul follows the ghoul rule", champ.champion != null and EnemyRoles.choose(champ, members, 100.0) == cutter)
	champ.queue_free()

	# --- Flow: dash formation, the dive, Provoke -------------------------------------------------------------------------------------
	for e in [zombie, ghoul, thrower, brute, warden]:
		e.queue_free()
	await _frames(2)
	var anchor: Vector3 = Nav.snap(player, base + Vector3(16.0, 0.0, 2.0))
	var group: Array[Enemy] = []
	for kind in ["zombie", "zombie", "ghoul"]:
		var e: Enemy = _spawn_enemy(Nav.snap(player, anchor + Vector3(group.size() * 1.2, 0.0, 0.0)), kind, 1.0)
		e.group_id = 931
		e.aggro_range = 0.0
		e.max_health = 100000.0   # the party cannot kill the ghoul before it has dived
		e.health = e.max_health
		group.append(e)
	var diver: Enemy = group[2]
	var m := MapMode.new()
	game.add_child(m)
	m.setup(player, cutter, hud)
	await _frames(10)
	var group_centre: Vector3 = m.centre_of(group)
	m.overlay.selected.emit(931)
	var n: int = 0
	while m.state != MapMode.State.FIGHT and n < 200:
		await get_tree().physics_frame
		n += 1
	expect("the dash ended in a fight", m.state == MapMode.State.FIGHT)
	var behind: float = player.global_position.distance_to(cutter.global_position)
	var hero_far: float = player.global_position.distance_to(group_centre)
	var cutter_far: float = cutter.global_position.distance_to(group_centre)
	print("[mmroles] formation: Cutter %.1f m behind the warrior, %.1f m from the group (warrior %.1f m)" % [behind, cutter_far, hero_far])
	expect("formation: the Cutter lands %.1f m behind the warrior (8-10 m)" % behind, behind >= EnemyRoles.BACK_MIN - 0.6 and behind <= EnemyRoles.BACK_MAX + 0.6)
	expect("formation: the Cutter is on the side away from the group (%.1f m against the warrior's %.1f m)" % [cutter_far, hero_far], cutter_far > hero_far + 6.0)
	# The dive: the ghoul goes for the Cutter and reaches her.
	var reached: float = INF
	var targeted: bool = false
	for i in 480:
		await get_tree().physics_frame
		if is_instance_valid(diver) and not diver.dead:
			reached = minf(reached, diver.flat_distance_to(cutter))
			targeted = targeted or diver.target == cutter
		if reached < 2.6:
			break
	print("[mmroles] dive: ghoul closest to the Cutter %.1f m" % reached)
	expect("the ghoul targets the Cutter, not the nearest member", targeted)
	expect("the ghoul reaches the Cutter in the small arena (closest %.1f m)" % reached, reached < 2.6)
	var has_lines: bool = false
	for child in m.get_children():
		var script: Script = child.get_script() as Script
		has_lines = has_lines or (script != null and String(script.resource_path).contains("threat_lines"))
	expect("no red threat lines are drawn for a diver (the owner removed them)", not has_lines)
	# Provoke overrides the role for as long as it holds.
	player.global_position = diver.global_position + Vector3(2.0, 0.0, 0.0)
	player.powers._provoke()
	await _frames(6)
	expect("Provoke: the ghoul turns on the hero (its role says Cutter)", diver.target == player and Time.get_ticks_msec() < diver.provoked_until_ms)
	diver.provoked_until_ms = 0
	await _frames(4)
	expect("when Provoke ends the role takes over again", diver.target == cutter)
	# The route goes round the warrior standing on the line.
	player.global_position = Nav.snap(player, (diver.global_position + cutter.global_position) * 0.5)
	var goal: Vector3 = cutter.global_position
	var via: Vector3 = EnemyRoles.route_goal(diver, goal)
	expect("flank: with the warrior on its line the ghoul heads for a point beside him, not through him (%.1f m off him)" % via.distance_to(player.global_position), via != goal and via.distance_to(player.global_position) > 2.4)
	# Standing on the detour point, the ghoul is sent on to the real goal, not handed the same point again (it used to wait there, not moving).
	diver.global_position = via
	var steps: int = 0
	var onward: Vector3 = EnemyRoles.route_goal(diver, goal)
	while onward != goal and steps < 6:   # following the detour points it is handed, it must come to the real goal (never be handed the same point for ever)
		diver.global_position = onward
		onward = EnemyRoles.route_goal(diver, goal)
		steps += 1
	expect("flank: following its detour points the ghoul is sent on to the real goal within a few steps (%d), so it never waits beside the warrior" % steps, onward == goal)
	expect("and for a moment after, it keeps heading for the goal (no new detour at once)", EnemyRoles.route_goal(diver, goal) == goal)
	# An awake enemy stuck against a wall (pathing failing for seconds, a little off the navmesh) is set back on the navmesh with fresh path state.
	diver.wake()
	diver.behavior.on_interrupted()   # (not in the middle of a pounce: it stalks)
	var map: RID = Nav.map_of(diver)
	diver._nav_state["failed_time"] = 1.0
	expect("a ghoul whose pathing has only just started to fail is left alone", not m._unstick(diver))
	diver._nav_state["failed_time"] = 3.0
	diver._nav_state["path"] = PackedVector3Array([diver.global_position, diver.global_position])   # (some state to be cleared)
	var expected: Vector3 = NavigationServer3D.map_get_closest_point(map, diver.global_position)   # where it must be set: its closest navmesh point
	var recovered: bool = m._unstick(diver)
	var gap: float = Vector2(diver.global_position.x - expected.x, diver.global_position.z - expected.z).length()
	expect("a ghoul whose pathing has failed for 3 s is set on its closest navmesh point (%.2f m from it) and its path state is cleared" % gap,
		recovered and gap < 0.1 and float(diver._nav_state.get("failed_time", 0.0)) == 0.0 and (diver._nav_state.get("path", PackedVector3Array()) as PackedVector3Array).is_empty())
	# The fight log carries the Cutter's damage.
	m.log.note_damage_taken(7.0, "cutter")
	m.log.note_damage_taken(3.0, "hero")
	var row: Dictionary = m.log.end_fight(MapMode.now())
	expect("the fight log has a Cutter-damage field and prints it (%s)" % m.log.row_line(row), float(row.get("cutter_damage", -1.0)) >= 7.0 and m.log.row_line(row).contains("Cutter took"))
	# Tidy.
	for e in group:
		if is_instance_valid(e) and not e.dead:
			e.max_health = 10.0
			e.credit_hero()
			e._apply_damage(1000.0)
	m.overlay.queue_free()
	m.queue_free()
	await _frames(2)
	cutter.testing_disabled = cutter_was_disabled
	expect("map mode is off again afterwards", not MapMode.active)

## Before/after for the issue: the Cutter's damage in the same fight with the roles off (the old closest-member targeting) and on.
## Prints the numbers; asserts only that both fights ran and were logged. Run with `--only=mmrolesbench`.
func _test_map_mode_roles_bench() -> void:
	var cutter: Player = game.companion
	var cutter_was_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = false
	var base: Vector3 = player.global_position
	var m := MapMode.new()
	game.add_child(m)
	m.setup(player, cutter, hud)
	await _frames(10)
	var hero_hp: float = player.max_health
	var cutter_hp: float = cutter.max_health
	player.max_health = 100000.0   # nobody dies: the bench counts what each blow does
	cutter.max_health = 100000.0
	var totals: Dictionary = {false: 0.0, true: 0.0}
	var runs: int = 4
	var gid: int = 940
	for round in runs:
		for on in [false, true]:
			EnemyRoles.enabled = on
			player.global_position = Nav.snap(player, base)
			cutter.global_position = Nav.snap(cutter, base + Vector3(2.0, 0.0, 0.0))
			player.health = player.max_health
			cutter.health = cutter.max_health
			var anchor: Vector3 = Nav.snap(player, base + Vector3(16.0, 0.0, 2.0))
			var members: Array[Enemy] = []
			for kind in ["zombie", "zombie", "ghoul", "ghoul"]:
				var e: Enemy = _spawn_enemy(Nav.snap(player, anchor + Vector3(members.size() * 1.1, 0.0, 0.0)), kind, 4.0)
				e.group_id = gid
				e.aggro_range = 0.0
				members.append(e)
			var w: int = 0
			while m.state != MapMode.State.MAP and w < 900:
				await get_tree().physics_frame
				w += 1
			m.overlay.selected.emit(gid)
			gid += 1
			for e in members:
				e.max_health = 600.0   # a fixed 14 s fight: long enough for the ghouls to dive, then everything is cut down
				e.health = 600.0
			var n: int = 0
			while m.state != MapMode.State.FIGHT and n < 300:
				await get_tree().physics_frame
				n += 1
			for i in 840:
				await get_tree().physics_frame
				player.health = player.max_health   # (the hero is kept alive so the Cutter's share is what is measured)
			for e in members:
				if is_instance_valid(e) and not e.dead:
					e.credit_hero()
					e._apply_damage(e.max_health + 10.0)
			n = 0
			while m.state != MapMode.State.MAP and n < 900:
				await get_tree().physics_frame
				n += 1
			var row: Dictionary = m.log.fights.back() if not m.log.fights.is_empty() else {}
			totals[on] = float(totals[on]) + float(row.get("cutter_damage", 0.0))
			print("[mmroles] bench round %d roles %s: %s" % [round, "ON" if on else "OFF", m.log.row_line(row)])
	EnemyRoles.enabled = true
	player.max_health = hero_hp
	cutter.max_health = cutter_hp
	player.health = hero_hp
	cutter.health = cutter_hp
	print("[mmroles] bench: Cutter damage per fight, mean of %d: roles OFF %.1f, roles ON %.1f" % [runs, float(totals[false]) / runs, float(totals[true]) / runs])
	expect("the bench logged every fight", m.log.fights.size() == runs * 2)
	m.overlay.queue_free()
	m.queue_free()
	await _frames(2)
	cutter.testing_disabled = cutter_was_disabled
