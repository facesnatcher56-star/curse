extends DevSuite
## Map mode (owner rules): each member's powers fill only from his own damage; enemies follow MMO-style threat (issue #109: pulls, 110%/130%,
## healing threat, Provoke taunt, death wipe, the Cutter assisting the warrior, nothing assuming two members); a click on another enemy sends the
## controlled character after it at once.

func _test_map_mode_threat() -> void:
	var cutter: Player = game.companion
	var probe := MapMode.new()
	# --- own charge --------------------------------------------------------------------------------------------------------------
	player.stats.brutal_reload_required = player.stats.ult_cost("brutal_attack")
	player.stats.brutal_reload_remaining = player.stats.brutal_reload_required
	cutter.bow.reload_required = 1000.0
	cutter.bow.reload_remaining = 1000.0
	player.on_party_damage(100.0, "basic")
	expect("walking game: the warrior's damage charges only his own powers, not the Cutter's Take Aim", cutter.bow.reload_remaining == 1000.0)
	cutter.bow.reload_remaining = 1000.0
	player.stats.brutal_reload_remaining = player.stats.brutal_reload_required
	MapMode.current = probe
	player.on_party_damage(100.0, "basic")
	var cutter_untouched: bool = cutter.bow.reload_remaining == 1000.0
	var own_filled: bool = player.stats.brutal_reload_remaining < player.stats.brutal_reload_required
	MapMode.current = null
	expect("map mode: the warrior's damage charges only his own powers, not the Cutter's", cutter_untouched and own_filled)
	# --- threat (issue #109) -----------------------------------------------------------------------------------------------------
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().physics_frame
	player.global_position = Vector3.ZERO
	cutter.global_position = Vector3(0.0, 0.0, 9.0)
	var members: Array = [player, cutter]
	MapMode.current = probe
	# Pull: the first member to hit a group puts PULL_THREAT on every enemy of it; later hitters do not pull again.
	var pull_group: Array[Enemy] = [_threat_enemy("zombie", Vector3(2.0, 0.0, 2.0), 960), _threat_enemy("ghoul", Vector3(4.0, 0.0, 2.0), 960), _threat_enemy("zombie", Vector3(6.0, 0.0, 2.0), 960)]
	EnemyRoles.note_hit(pull_group[0], {"source": cutter, "damage": 5.0}, cutter.global_position)
	var pulled_all: bool = true
	for e in pull_group:
		pulled_all = pulled_all and EnemyRoles.threat_of(e, cutter) >= EnemyRoles.PULL_THREAT
	expect("the first member to hit a group pulls every enemy of it (PULL_THREAT on each)", pulled_all)
	EnemyRoles.note_hit(pull_group[1], {"source": player, "damage": 5.0}, player.global_position)
	expect("a later hitter does not pull again: the other enemies have no threat for him", EnemyRoles.threat_of(pull_group[2], player) == 0.0 and EnemyRoles.threat_of(pull_group[1], player) == 5.0 * EnemyRoles.WARRIOR_THREAT_MULT)
	# Pull at the start of a fight: the member closest to the group (the warrior in the dash) pulls it all, and a ghoul stays on him.
	var fight_group: Array[Enemy] = [_threat_enemy("ghoul", Vector3(3.0, 0.0, -2.0), 961), _threat_enemy("zombie", Vector3(5.0, 0.0, -2.0), 961)]
	fight_group[0].target = cutter
	EnemyRoles.pull_group(fight_group, members)
	expect("the member closest to the group pulls all of it when the fight starts", EnemyRoles.threat_of(fight_group[0], player) == EnemyRoles.PULL_THREAT and EnemyRoles.threat_of(fight_group[1], player) == EnemyRoles.PULL_THREAT and EnemyRoles.threat_of(fight_group[0], cutter) == 0.0)
	expect("a ghoul goes for the warrior at the start of a fight, not the Cutter", EnemyRoles.choose(fight_group[0], members, 10.0) == player)
	fight_group[0].target = player
	expect("and keeps him against a Cutter shot (no dive)", _hit_then_choose(fight_group[0], cutter, 3.0, members) == player)
	# The archer pulls an enemy the warrior has not touched.
	var lone: Enemy = _threat_enemy("zombie", Vector3(-3.0, 0.0, 0.0))
	lone.target = player
	EnemyRoles.note_hit(lone, {"source": cutter, "damage": 5.0}, cutter.global_position)
	expect("the archer pulls an enemy the warrior has not touched", EnemyRoles.choose(lone, members, 10.0) == cutter)
	# 110% in melee, 130% at range.
	var held: Enemy = _threat_enemy("brute", Vector3(2.0, 0.0, 2.0))
	EnemyRoles.state_of(held).threat[player] = 100.0
	held.target = player
	cutter.global_position = Vector3(0.0, 0.0, 9.0)
	EnemyRoles.state_of(held).threat[cutter] = 125.0
	expect("at range the Cutter at 125% of the holder does not take him", EnemyRoles.choose(held, members, 10.0) == player)
	EnemyRoles.state_of(held).threat[cutter] = 131.0
	expect("at range the Cutter above 130% takes him", EnemyRoles.choose(held, members, 10.0) == cutter)
	cutter.global_position = Vector3(2.0, 0.0, 4.0)
	held.target = player
	EnemyRoles.state_of(held).threat[cutter] = 109.0
	expect("in melee range (%.1f m) 109%% is not enough" % held.flat_distance_to(cutter), EnemyRoles.choose(held, members, 10.0) == player)
	EnemyRoles.state_of(held).threat[cutter] = 111.0
	expect("in melee range 111%% takes him", EnemyRoles.choose(held, members, 10.0) == cutter)
	cutter.global_position = Vector3(0.0, 0.0, 9.0)
	# Warrior x2 on damage.
	var mult: Enemy = _threat_enemy("zombie", Vector3(-4.0, 0.0, 4.0))
	EnemyRoles.note_hit(mult, {"source": player, "damage": 10.0}, player.global_position)
	var after_warrior: float = EnemyRoles.threat_of(mult, player)
	EnemyRoles.note_hit(mult, {"source": cutter, "damage": 10.0}, cutter.global_position)
	expect("the warrior's threat is doubled (pull 10 + 2 x 10), the Cutter's is not (%.0f, %.0f)" % [after_warrior, EnemyRoles.threat_of(mult, cutter)], after_warrior == EnemyRoles.PULL_THREAT + 10.0 * EnemyRoles.WARRIOR_THREAT_MULT and EnemyRoles.threat_of(mult, cutter) == 10.0)
	# Healing threat goes to the healer, split across the enemies that already have a party member in their threat table.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().physics_frame
	var fighters: Array[Enemy] = []
	for i in 3:
		var f: Enemy = _threat_enemy("zombie", Vector3(3.0 + i, 0.0, -4.0))
		f.wake()
		EnemyRoles.pull(f, player)   # in combat with the party: the warrior is in its table
		fighters.append(f)
	var sleeper: Enemy = _threat_enemy("zombie", Vector3(-8.0, 0.0, -8.0))
	var awake_elsewhere: Enemy = _threat_enemy("zombie", Vector3(-12.0, 0.0, 8.0))
	awake_elsewhere.wake()   # awake, but nobody in the party has pulled it
	var hurt: float = player.health
	player.health = player.max_health - 50.0
	player.stats.heal(30.0, cutter)
	var each: float = 30.0 * EnemyRoles.HEAL_THREAT / 3.0
	var split_ok: bool = true
	for f in fighters:
		split_ok = split_ok and is_equal_approx(EnemyRoles.threat_of(f, cutter), each) and EnemyRoles.threat_of(f, player) == EnemyRoles.PULL_THREAT
	expect("healing threat goes to the healer (the Cutter), not to the one healed, split evenly across the 3 enemies in combat (%.1f each)" % each, split_ok)
	expect("an enemy that is not in combat gets none", EnemyRoles.threat_of(sleeper, cutter) == 0.0)
	expect("an awake enemy with no party member in its threat table gets none", EnemyRoles.threat_of(awake_elsewhere, cutter) == 0.0)
	player.health = player.max_health - 50.0
	player.stats.heal(30.0)
	expect("a tank's own healing is doubled: 30 healed = %.0f each" % (each * EnemyRoles.WARRIOR_THREAT_MULT), is_equal_approx(EnemyRoles.threat_of(fighters[0], player), EnemyRoles.PULL_THREAT + each * EnemyRoles.WARRIOR_THREAT_MULT))
	var potions_before: int = player.stats.potions
	player.stats.potions = 1
	player.stats.cooldowns.erase("potion")
	player.health = player.max_health - 100.0
	var before_potion: float = EnemyRoles.threat_of(fighters[1], player)
	player.stats.use_potion()
	expect("a potion counts for the member who drank it", EnemyRoles.threat_of(fighters[1], player) > before_potion)
	player.stats.potions = potions_before
	player.health = hurt
	# Provoke: everything in its radius is taken and locked for its duration; what is out of range is not.
	var radius: float = player.powers.value("provoke", "radius")
	var duration: float = player.powers.value("provoke", "duration")
	var near_a: Enemy = _threat_enemy("zombie", Vector3(radius * 0.4, 0.0, 0.0))
	var near_b: Enemy = _threat_enemy("ghoul", Vector3(0.0, 0.0, -radius * 0.7))
	var far: Enemy = _threat_enemy("zombie", Vector3(radius * 3.0, 0.0, 0.0))
	for e in [near_a, near_b, far]:
		EnemyRoles.state_of(e).threat[cutter] = 40.0
		e.target = cutter
	player.global_position = Vector3.ZERO
	var t0: int = Time.get_ticks_msec()
	player.powers._provoke()
	var locked_ok: bool = true
	for e in [near_a, near_b]:
		locked_ok = locked_ok and e.target == player and EnemyRoles.threat_of(e, player) >= 40.0 * EnemyRoles.TAUNT_BONUS - 0.001 and absi(e.provoked_until_ms - (t0 + int(duration * 1000.0))) < 400
	expect("Provoke takes every enemy in its radius: threat top + 10%%, locked on the warrior for %.0f s" % duration, locked_ok)
	expect("an enemy beyond its radius is not taken", far.target == cutter and EnemyRoles.threat_of(far, player) == 0.0 and far.provoked_until_ms == 0)
	EnemyRoles.state_of(near_a).threat[cutter] = 1000.0
	EnemyRoles.retarget(near_a)
	expect("while the lock holds the table is ignored", near_a.target == player)
	near_a.provoked_until_ms = 0
	EnemyRoles.retarget(near_a)
	expect("when it ends the table decides again", near_a.target == cutter)
	# Death wipes threat.
	var mortal: Enemy = _threat_enemy("zombie", Vector3(-4.0, 0.0, -4.0))
	EnemyRoles.state_of(mortal).threat[cutter] = 50.0
	EnemyRoles.state_of(mortal).threat[player] = 20.0
	mortal.target = cutter
	cutter.dead = true
	var after_death: Actor = EnemyRoles.choose(mortal, members, 10.0)
	cutter.dead = false
	expect("a dead member is no longer chosen (the warrior is) and his threat is gone, even if he rises again", after_death == player and EnemyRoles.threat_of(mortal, cutter) == 0.0)
	EnemyRoles.state_of(mortal).threat[cutter] = 50.0
	EnemyRoles.wipe(cutter)
	expect("wipe() clears him from every table", EnemyRoles.threat_of(mortal, cutter) == 0.0 and EnemyRoles.threat_of(near_b, cutter) == 0.0)
	# The Warden's special still overrides the table for its window.
	var warden: Enemy = _threat_enemy("warden", Vector3(-6.0, 0.0, 2.0))
	EnemyRoles.state_of(warden).threat[player] = 30.0
	warden.target = player
	var every: float = float(EnemyRoles.ROLES["warden"]["special_every"])
	var window: float = float(EnemyRoles.ROLES["warden"]["special_window"])
	expect("warden: the table to begin with", EnemyRoles.choose(warden, members, 300.0) == player)
	expect("warden: its special goes for the farthest member", EnemyRoles.choose(warden, members, 300.0 + every + 0.1) == cutter)
	expect("warden: and back to the table once the window has passed", EnemyRoles.choose(warden, members, 300.0 + every + 0.1 + window + 0.5) == player)
	# The Cutter assists the warrior's target (a click-focus overrides).
	var a: Enemy = _threat_enemy("zombie", Vector3(3.0, 0.0, 0.0))
	var b: Enemy = _threat_enemy("zombie", Vector3(-3.0, 0.0, 0.0))
	for e in [a, b]:
		e.max_health = 5000.0
		e.health = 5000.0
	cutter.global_position = Vector3(-6.0, 0.0, 0.0)   # b is her nearest
	probe.hero = player
	probe.companion = cutter
	probe.state = MapMode.State.FIGHT
	player.attack_target = a
	expect("the Cutter's automatic target is the warrior's target, though another is nearer to her", probe.target_for(cutter) == a)
	probe.focus = b
	expect("a click-focus overrides it", probe.target_for(cutter) == b)
	probe.focus = null
	# A third member: nothing assumes two.
	var third := Player.new()
	third.member_id = "threat_standin"
	add_child(third)
	third.set_physics_process(false)
	third.global_position = Vector3(-5.0, 0.0, 3.0)
	PartyManager.current().bodies[third.member_id] = third
	var trio: Array = [player, cutter, third]
	var squad: Array[Enemy] = [_threat_enemy("zombie", Vector3(-9.0, 0.0, 9.0), 962), _threat_enemy("ghoul", Vector3(-10.0, 0.0, 9.0), 962)]
	EnemyRoles.note_hit(squad[0], {"source": third, "damage": 3.0}, third.global_position)
	expect("a third member pulls the whole group like any other", EnemyRoles.threat_of(squad[0], third) >= EnemyRoles.PULL_THREAT and EnemyRoles.threat_of(squad[1], third) == EnemyRoles.PULL_THREAT)
	squad[1].target = cutter
	expect("the third member holds the enemy he pulled", EnemyRoles.choose(squad[1], trio, 10.0) == third)
	expect("a non-tank third member assists the tank's target too", probe.target_for(third) == a and not EnemyRoles.is_tank(third))
	EnemyRoles.state_of(squad[1]).threat[third] = 15.0
	third.dead = true
	var survivor: Actor = EnemyRoles.choose(squad[1], trio, 11.0)
	third.dead = false
	expect("the third member's threat is wiped when he dies", EnemyRoles.threat_of(squad[1], third) == 0.0 and survivor != third)
	PartyManager.current().bodies.erase(third.member_id)
	third.queue_free()
	player.attack_target = null
	# Map mode off: the normal game uses threat too (#109 comment, owner 2026-10-21).
	MapMode.current = null
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().physics_frame
	player.global_position = Vector3.ZERO
	cutter.global_position = Vector3(5.0, 0.0, 9.0)
	var plain: Enemy = _threat_enemy("zombie", Vector3(5.0, 0.0, 5.0))
	plain.wake()
	EnemyRoles.note_heal(cutter, 40.0)
	expect("normal game: an awake enemy nobody has pulled gets no healing threat", EnemyRoles.threat_of(plain, cutter) == 0.0)
	EnemyRoles.taunt(plain, player)
	expect("normal game: a taunt sets the taunter's threat (at least a pull)", EnemyRoles.threat_of(plain, player) == EnemyRoles.PULL_THREAT)
	EnemyRoles.note_heal(cutter, 40.0)
	expect("normal game: healing threat reaches an enemy in combat with the party", is_equal_approx(EnemyRoles.threat_of(plain, cutter), 40.0 * EnemyRoles.HEAL_THREAT))
	plain.set_physics_process(true)
	plain.target = null
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("normal game: an enemy goes for the top threat (the healer, above 130% of the taunter)", plain.target == cutter)
	plain.queue_free()
	await get_tree().physics_frame
	# --- a click on another enemy ------------------------------------------------------------------------------------------------
	a = _threat_enemy("zombie", Vector3(3.0, 0.0, 0.0))
	b = _threat_enemy("zombie", Vector3(-3.0, 0.0, 0.0))
	player.global_position = Vector3.ZERO
	for e in [a, b]:
		e.set_physics_process(true)
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
	for e in [a, b]:
		e.queue_free()
	probe.free()
	await get_tree().physics_frame

func _threat_enemy(kind: String, pos: Vector3, group: int = -1) -> Enemy:
	var e: Enemy = _spawn_enemy(pos, kind, 1.0)
	e.group_id = group
	e.aggro_range = 0.0
	e.set_physics_process(false)   # the rules are driven by hand here
	return e

func _hit_then_choose(e: Enemy, source: Player, damage: float, members: Array) -> Actor:
	EnemyRoles.note_hit(e, {"source": source, "damage": damage}, source.global_position)
	return EnemyRoles.choose(e, members, 20.0)
