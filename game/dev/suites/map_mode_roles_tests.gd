extends DevSuite
## Map mode enemy targeting + dash formation (issues #81, #109): threat picks each target, Provoke overrides it, the Cutter lands 8-10 m behind the warrior,
## a ghoul stays on the warrior, and with the flag off targeting is exactly the default game's (closest, sticky).

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
	ghoul_off.target = cutter
	await _frames(4)
	expect("flag off: a sticky target is never swapped (the hand-off Provoke uses)", ghoul_off.target == cutter)
	var threat_before: int = EnemyRoles.state_of(brute_off).threat.size()
	brute_off.receive({"source": player, "damage": 5.0, "outcome": Combat.Outcome.HIT, "weight": 1.0}, base)
	expect("flag off: no threat is kept", EnemyRoles.state_of(brute_off).threat.size() == threat_before)
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
	expect("the role table names only the kinds with a special (the Warden); everything else follows threat", EnemyRoles.ROLES.keys() == ["warden"])
	expect("zombie: no opinion while nobody has threat on it, so the sticky closest target stays", EnemyRoles.choose(zombie, members, 100.0) == null)
	expect("ghoul: no opinion without threat (it no longer dives the Cutter)", EnemyRoles.choose(ghoul, members, 100.0) == null)
	EnemyRoles.pull_group([ghoul], members)   # the warrior pulls it
	ghoul.target = cutter
	expect("ghoul: the warrior who pulled it, though the Cutter is farther back", EnemyRoles.choose(ghoul, members, 100.0) == player)
	expect("ghoul: the hero when the Cutter is down", EnemyRoles.choose(ghoul, [player], 100.0) == player)
	expect("rock thrower: no opinion before anyone hit it", EnemyRoles.choose(thrower, members, 100.0) == null)
	EnemyRoles.note_hit(thrower, _hit(cutter, 5.0), thrower.global_position + Vector3(12.0, 0.0, 0.0), 110.0)   # an arrow from range
	expect("rock thrower: a ranged hit pulls it onto the archer (it no longer chases ranged hits as a role)", EnemyRoles.choose(thrower, members, 112.0) == cutter)
	thrower.target = cutter
	EnemyRoles.note_hit(thrower, _hit(player, 20.0), thrower.global_position + Vector3(1.0, 0.0, 0.0), 113.0)   # a melee blow, x2 threat
	expect("rock thrower: the warrior's melee blow (x2) takes it from the archer", EnemyRoles.choose(thrower, members, 113.5) == player)
	EnemyRoles.note_hit(brute, _hit(player, 40.0), brute.global_position + Vector3(5.0, 0.0, 0.0), 200.0)
	EnemyRoles.note_hit(brute, _hit(cutter, 15.0), brute.global_position + Vector3(5.0, 0.0, 0.0), 200.5)
	EnemyRoles.note_hit(brute, _hit(cutter, 15.0), brute.global_position + Vector3(5.0, 0.0, 0.0), 201.0)
	expect("brute: the biggest threat (the hero: pull 10 + 2 x 40 against the Cutter's 30)", EnemyRoles.choose(brute, members, 201.5) == player)
	EnemyRoles.note_hit(brute, _hit(cutter, 30.0), brute.global_position + Vector3(5.0, 0.0, 0.0), 202.0)
	brute.target = player
	expect("brute: the Cutter (60 against 90) does not take it from the warrior, there is no re-check clock", EnemyRoles.choose(brute, members, 202.0) == player)
	var every: float = float(EnemyRoles.ROLES["warden"]["special_every"])
	expect("warden: closest to begin with (no opinion)", EnemyRoles.choose(warden, members, 300.0) == null)
	expect("warden: its telegraphed attack goes for the farthest member", EnemyRoles.choose(warden, members, 300.0 + every + 0.1) == cutter)
	expect("warden: and back to the closest once the window has passed", EnemyRoles.choose(warden, members, 300.0 + every + 0.1 + float(EnemyRoles.ROLES["warden"]["special_window"]) + 0.5) == player)
	# A champion follows threat like its kind.
	var champ: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-3.0, 0.0, -4.0)), "ghoul", 1.0)
	champ.set_physics_process(false)
	Champion.attach(champ, "fast")
	EnemyRoles.pull_group([champ], members)
	champ.target = cutter
	expect("a champion ghoul follows threat too (the warrior who pulled it)", champ.champion != null and EnemyRoles.choose(champ, members, 100.0) == player)
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
	MapModeScreen.enabled = false   # this checks the role table's own 8-10 m formation; the on-screen clamp (issue #87) has its own suite, mmcutterscreen
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
	await _frames(20)
	var tank_target := player.attack_target as Enemy
	expect("in the real fight the Cutter's automatic target is the warrior's target", tank_target != null and m.target_for(cutter) == tank_target)
	# The ghoul stays on the warrior from the start of the fight and reaches him in the small arena.
	var reached: float = INF
	var started_on_hero: bool = false
	for i in 480:
		await get_tree().physics_frame
		if i == 10:
			started_on_hero = is_instance_valid(diver) and diver.target == player
		if is_instance_valid(diver) and not diver.dead:
			reached = minf(reached, diver.flat_distance_to(player))
		if reached < 2.6 and i > 10:
			break
	print("[mmroles] ghoul closest to the warrior %.1f m" % reached)
	expect("the ghoul is on the warrior at the start of the fight, not the Cutter", started_on_hero)
	expect("the ghoul reaches the warrior in the small arena (closest %.1f m)" % reached, reached < 2.6)
	var has_lines: bool = false
	for child in m.get_children():
		var script: Script = child.get_script() as Script
		has_lines = has_lines or (script != null and String(script.resource_path).contains("threat_lines"))
	expect("no red threat lines are drawn for a diver (the owner removed them)", not has_lines)
	# Provoke overrides the table for as long as it holds.
	player.global_position = diver.global_position + Vector3(2.0, 0.0, 0.0)
	diver.target = cutter
	player.powers._provoke()
	await _frames(6)
	expect("Provoke: the ghoul turns on the hero", diver.target == player and Time.get_ticks_msec() < diver.provoked_until_ms)
	diver.provoked_until_ms = 0
	await _frames(4)
	expect("when Provoke ends the table still says the hero (his threat is on top)", diver.target == player)
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
	# A party member whose path to its target has been blocked for seconds gives that target up for a while and takes another.
	player.attack_target = diver
	player.movement._nav_state["failed_time"] = 5.0
	var gave_up: int = m._keep_party_moving()
	expect("a party member blocked on its target for 5 s gives it up (%d), skips it and starts its path afresh" % gave_up,
		gave_up >= 1 and m._is_skipped(diver) and float(player.movement._nav_state.get("failed_time", 0.0)) == 0.0 and player.attack_target == null)
	# The fight watchdog: no kill for a long time brings whatever still stands up to the party.
	diver.global_position = Nav.snap(diver, player.global_position + Vector3(30.0, 0.0, 0.0))
	var brought: int = m._gather_enemies()
	var near_gap: float = diver.flat_distance_to(player)
	expect("after a long fight with no kill the enemies still standing are brought to within a few metres of the party (%d moved, ghoul %.1f m away)" % [brought, near_gap],
		brought >= 1 and near_gap <= MapMode.GATHER_DISTANCE + 3.0)
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
	MapModeScreen.enabled = true
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

