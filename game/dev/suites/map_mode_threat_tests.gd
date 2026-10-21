extends DevSuite
## Map mode (owner rules): each member's powers fill only from his own damage; a melee blow forces the enemy onto the attacker (a ghoul diving
## the Cutter turns on the warrior who cuts it); a click on another enemy sends the controlled character after it at once.

func _test_map_mode_threat() -> void:
	var cutter: Player = game.companion
	var probe := MapMode.new()
	# --- own charge --------------------------------------------------------------------------------------------------------------
	player.stats.brutal_reload_required = player.stats.ult_cost("brutal_attack")
	player.stats.brutal_reload_remaining = player.stats.brutal_reload_required
	cutter.bow.reload_required = 1000.0
	cutter.bow.reload_remaining = 1000.0
	player.on_party_damage(100.0, "basic")
	expect("default game: the warrior's damage also charges the Cutter's Take Aim", cutter.bow.reload_remaining < 1000.0)
	cutter.bow.reload_remaining = 1000.0
	player.stats.brutal_reload_remaining = player.stats.brutal_reload_required
	MapMode.current = probe
	player.on_party_damage(100.0, "basic")
	var cutter_untouched: bool = cutter.bow.reload_remaining == 1000.0
	var own_filled: bool = player.stats.brutal_reload_remaining < player.stats.brutal_reload_required
	MapMode.current = null
	expect("map mode: the warrior's damage charges only his own powers, not the Cutter's", cutter_untouched and own_filled)
	# --- threat ------------------------------------------------------------------------------------------------------------------
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().physics_frame
	player.global_position = Vector3.ZERO
	cutter.global_position = Vector3(0.0, 0.0, 9.0)
	var ghoul: Enemy = _spawn_enemy(Vector3(2.0, 0.0, 2.0), "ghoul", 1.0)
	ghoul.aggro_range = 0.0
	var members: Array = [player, cutter]
	var now: float = Time.get_ticks_msec() / 1000.0
	expect("a ghoul dives the Cutter by its role", EnemyRoles.choose(ghoul, members, now) == cutter)
	EnemyRoles.note_hit(ghoul, {"source": cutter, "damage": 5.0}, Vector3(0.0, 0.0, 9.0), now)
	expect("a shot from range does not force it", EnemyRoles.choose(ghoul, members, now) == cutter)
	EnemyRoles.note_hit(ghoul, {"source": player, "damage": 5.0}, Vector3(1.0, 0.0, 1.0), now)
	expect("a melee blow from the warrior forces it onto him, whatever its role", EnemyRoles.choose(ghoul, members, now + 1.0) == player)
	expect("and it holds for a few seconds", EnemyRoles.choose(ghoul, members, now + EnemyRoles.FORCE_SECONDS - 0.5) == player)
	expect("then the role takes over again", EnemyRoles.choose(ghoul, members, now + EnemyRoles.FORCE_SECONDS + 0.5) == cutter)
	# --- a click on another enemy ------------------------------------------------------------------------------------------------
	var a: Enemy = _spawn_enemy(Vector3(3.0, 0.0, 0.0), "zombie", 1.0)
	var b: Enemy = _spawn_enemy(Vector3(-3.0, 0.0, 0.0), "zombie", 1.0)
	for e in [a, b]:
		e.aggro_range = 0.0
		e.max_health = 5000.0
		e.health = 5000.0
	probe.hero = player
	probe.companion = cutter
	probe.state = MapMode.State.FIGHT
	MapMode.current = probe
	player.attack_target = a
	player.skills.start_skill("basic", a)
	expect("he is mid-swing on the first enemy", player.skills.busy)
	probe.set_focus(b)
	var dropped: bool = not player.skills.busy and player.attack_target == b
	MapMode.current = null
	expect("clicking another enemy drops the swing in progress and targets it at once", dropped)
	player.skills.cancel_action()
	player.attack_target = null
	for e in [ghoul, a, b]:
		e.queue_free()
	probe.free()
	await get_tree().physics_frame
