extends DevSuite
## Champions in map mode (game/map_mode/map_mode_rules.gd, map_auto_powers.gd): with map mode off the shield is exactly as before; in map mode a
## regenerating shield beats auto-attacks alone, a power hit pauses the regeneration, regeneration stops after the safety limit so a fight
## always ends, and the autoplay's MapAutoPowers fires the real hotbar powers that damage a shielded champion. The regeneration checks step the
## rules with explicit times (no waiting); only the power check plays real frames.

const AUTO_HIT := 4.0       # a basic blow's damage after armour on a Lv 3 zombie in the arena (about one per second per fighter)
const REGEN := 0.10         # shield fraction per second used by the checks (about 5 shield/s on a Lv 3 zombie): out-paces a lone fighter's blows

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _champion(offset: Vector3) -> Enemy:
	var z: Enemy = game.director.spawn_enemy(Nav.snap(player, player.global_position + offset), "zombie", WorldThreat.threat_for_level(3), "normal")
	z.alert_delay = 999.0
	z.aggro_range = 0.0
	z.armor = 0.0
	z.toughness = 0.0
	z.dodge_chance = 0.0
	z.block_chance = 0.0
	Champion.attach(z, "shielded")
	return z

func _blow(champ: Enemy, skill: String, damage: float) -> void:
	champ.receive({"outcome": Combat.Outcome.HIT, "damage": damage, "weight": 1.0, "source": player, "type": Combat.DamageType.PHYSICAL, "skill_id": skill}, player.global_position)

## A basic blow straight through the champion's filter; what the shield does not soak reaches the life.
func _basic(champ: Enemy, damage: float) -> void:
	var out: Dictionary = champ.champion.filter_incoming(champ, {"outcome": Combat.Outcome.HIT, "damage": damage, "skill_id": "basic"})
	champ.health -= float(out["damage"])

func _test_champion_map_mode() -> void:
	TownState.persist = false
	TownState.reset()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await _frames(2)
	var rate_before: float = MapModeRules.SHIELD_REGEN_FRACTION
	var cutter: Player = game.companion
	var cutter_was_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = true

	# --- Map mode off: nothing changes (the hooks are gated on MapMode.active) --------------------------------------------------------------
	MapModeRules.SHIELD_REGEN_FRACTION = REGEN
	var off: Enemy = _champion(Vector3(12, 0, 0))
	off.set_physics_process(false)
	var c0: Champion = off.champion
	expect("map mode is off for the first checks", not MapMode.active)
	_blow(off, "whirling_strike", 10.0)
	var after_hit: float = c0.shield
	c0.tick(off, 5.0)
	expect("with map mode off a power hit stamps nothing and the shield does not regenerate", c0.last_power_hit < -999.0 and is_equal_approx(c0.shield, after_hit) and after_hit < c0.shield_max)

	# --- Map mode on ---------------------------------------------------------------------------------------------------------------------------
	var m := MapMode.new()
	game.add_child(m)
	expect("map mode is active once its node runs", MapMode.active)
	var champ: Enemy = _champion(Vector3(12, 3, 0))
	champ.set_physics_process(false)
	var c: Champion = champ.champion
	var max_shield: float = c.shield_max
	var t: float = 100.0
	MapModeRules.note_fight_start(t)
	print("CHAMPMM shield_max=%.1f life=%.1f regen=%.2f/s (%.0f%%) auto_hit=%.1f/s pause=%.1fs limit=%.0fs" % [max_shield, champ.max_health, max_shield * REGEN, REGEN * 100.0, AUTO_HIT, MapModeRules.SHIELD_REGEN_PAUSE_ON_POWER_HIT, MapModeRules.FIGHT_SAFETY_LIMIT])
	expect("a Lv 3 champion's regeneration (%.1f/s) is above one fighter's auto-attack damage (%.1f/s)" % [max_shield * REGEN, AUTO_HIT], max_shield * REGEN > AUTO_HIT)

	# Auto-attacks alone (one blow a second for 30 s) cannot wear the shield down.
	for i in 30:
		t += 1.0
		_basic(champ, AUTO_HIT)
		MapModeRules.regen_step(c, 1.0, t)
	expect("auto-attacks alone do not beat the shield in 30 s (%.1f of %.1f left)" % [c.shield, max_shield], c.shield > max_shield * 0.5 and champ.health == champ.max_health)

	# A power hit pauses the regeneration for the pause time, then it resumes.
	c.shield = max_shield
	var power_hit := {"outcome": Combat.Outcome.HIT, "damage": 10.0, "weight": 1.0, "source": player, "type": Combat.DamageType.PHYSICAL, "skill_id": "whirling_strike"}
	champ.receive(power_hit.duplicate(), player.global_position)
	var stamp: float = c.last_power_hit
	expect("a power hit is recognised and stamps the champion", MapModeRules.is_power_hit(power_hit) and not MapModeRules.is_power_hit(power_hit.merged({"skill_id": "basic"}, true)) and stamp > 0.0)
	var held: float = c.shield
	var held_ok: bool = true
	for i in 3:   # inside the 4 s pause
		held_ok = held_ok and MapModeRules.regen_step(c, 1.0, stamp + 0.5 + i) == 0.0
	expect("after a power hit the shield does not regenerate during the pause", held_ok and is_equal_approx(c.shield, held))
	var restored: float = MapModeRules.regen_step(c, 1.0, stamp + MapModeRules.SHIELD_REGEN_PAUSE_ON_POWER_HIT + 0.1)
	expect("and it regenerates again once the pause is over (%.1f)" % restored, restored > 0.0)

	# The safety limit: past it nothing regenerates, so auto-attacks alone eventually kill the champion within a bounded time.
	MapModeRules.note_fight_start(1000.0)
	c.last_power_hit = -1000.0
	c.shield = max_shield
	expect("regeneration is allowed inside the safety limit", MapModeRules.shield_regen_allowed(c, 1000.0 + MapModeRules.FIGHT_SAFETY_LIMIT - 1.0))
	expect("regeneration stops once the fight passes the safety limit", not MapModeRules.shield_regen_allowed(c, 1000.0 + MapModeRules.FIGHT_SAFETY_LIMIT + 0.1))
	var now: float = 1000.0
	var seconds: int = 0
	while champ.health > 0.0 and seconds < 400:
		now += 1.0
		seconds += 1
		_basic(champ, AUTO_HIT)
		MapModeRules.regen_step(c, 1.0, now)
	var cap: float = MapModeRules.FIGHT_SAFETY_LIMIT + (max_shield + champ.max_health) / AUTO_HIT + 2.0
	expect("a fight of auto-attacks alone always ends: the champion falls after %d s (cap %.0f s)" % [seconds, cap], champ.health <= 0.0 and float(seconds) <= cap)
	MapModeRules.note_fight_end()
	expect("note_fight_end clears the fight clock", is_equal_approx(MapModeRules.fight_time(5000.0), 0.0))

	# --- Real powers through the hotbar damage a shielded champion (MapAutoPowers) --------------------------------------------------------------
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await _frames(2)
	var hero_weapon: Variant = player.stats.equipment.get(Items.Slot.WEAPON)
	var cutter_weapon: Variant = cutter.stats.equipment.get(Items.Slot.WEAPON)
	player.stats.equipment[Items.Slot.WEAPON] = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Longsword")
	cutter.stats.equipment[Items.Slot.WEAPON] = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow")
	player.stats.refresh()
	cutter.stats.refresh()
	player.powers.reset()
	cutter.powers.reset()
	player.stats.brutal_reload_remaining = 0.0
	cutter.bow.reload_remaining = 0.0
	var lane: Vector3 = await _own_lane(20.0, 6.0)
	player.global_position = lane
	player.reset_physics_interpolation()
	cutter.global_position = lane + Vector3(-4.0, 0.0, 2.0)
	cutter.reset_physics_interpolation()
	var target: Enemy = _champion(Vector3.ZERO)
	target.global_position = lane + Vector3(2.0, 0.0, 0.0)
	target.set_physics_process(false)
	target.max_health = 1.0e6
	target.health = 1.0e6
	var tc: Champion = target.champion
	tc.shield_max = 400.0
	tc.shield = 400.0
	MapModeRules.SHIELD_REGEN_FRACTION = 0.0   # isolate what the powers do
	await _frames(2)
	var fired: int = MapAutoPowers.fire(player, cutter, target)
	await _frames(150)
	expect("MapAutoPowers fires the four ready powers (both members) at the target (%d)" % fired, fired == 4)
	expect("the powers damaged the shielded champion through the real hotbar path (shield %.0f of 400)" % tc.shield, tc.shield < 400.0 and tc.last_power_hit > 0.0)
	await _frames(30)
	for action in ["skill_1", "skill_2", "skill_3", "skill_4"]:
		Input.action_release(action)

	# Tidy
	for pair in [[player, hero_weapon], [cutter, cutter_weapon]]:
		if pair[1] == null:
			pair[0].stats.equipment.erase(Items.Slot.WEAPON)
		else:
			pair[0].stats.equipment[Items.Slot.WEAPON] = pair[1]
		pair[0].stats.refresh()
	MapModeRules.SHIELD_REGEN_FRACTION = rate_before
	MapModeRules.note_fight_end()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	m.queue_free()
	await _frames(2)
	cutter.testing_disabled = cutter_was_disabled
	expect("removing the node turns map mode off again", not MapMode.active)
