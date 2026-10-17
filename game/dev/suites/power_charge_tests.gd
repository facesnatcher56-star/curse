extends DevSuite
## Curse's pacing of the charged powers (departs from DS2; PowerDb.CHARGE_SECONDS, PlayerStats.*_REFILL): a new party starts with its two
## powers learned, on the bar and full; each power's bar fills in its own number of seconds of combat; kills and Openings refill every
## power; the charge carries over the gap between fights with no top-up.

const HERO_POWERS: Array[String] = ["brutal_attack", "whirling_strike"]
const CUTTER_POWERS: Array[String] = ["take_aim", "thunderous_shot"]

func _spend(body: Player, id: String) -> void:
	match id:
		"brutal_attack":
			body.stats.spend_brutal_attack()
		"take_aim":
			body.bow.reload_required = body.stats.power_recharge_damage(PowerDb.charge_seconds("take_aim"), "ranged")
			body.bow.reload_remaining = body.bow.reload_required
		_:
			body.powers._spend(id)

func _spend_all() -> void:
	for id in HERO_POWERS:
		_spend(player, id)
	for id in CUTTER_POWERS:
		_spend(game.companion, id)

func _fractions(body: Player, ids: Array[String]) -> Array[float]:
	var out: Array[float] = []
	for id in ids:
		out.append(body.stats.ult_fraction(id))
	return out

func _all_near(values: Array[float], expected: float) -> bool:
	for value in values:
		if absf(value - expected) > 0.001:
			return false
	return true

func _test_power_charge() -> void:
	TownState.persist = false
	TownState.reset()
	var hero: Player = player
	var cutter: ArcherCompanion = game.companion
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	hero.powers.reset()
	cutter.powers.reset()
	hero.stats.brutal_reload_remaining = 0.0
	cutter.bow.reload_remaining = 0.0

	# --- A new party's starting powers: learned, slotted, full -----------------------------------------------------------------------------
	expect("a new party has Brutal Attack and Whirling Strike learned for the hero, Take Aim and Thunderous Shot for Cutter",
		PowerDb.hero_rank("brutal_attack", "hero") >= 1 and PowerDb.hero_rank("whirling_strike", "hero") >= 1
		and PowerDb.hero_rank("take_aim", "cutter") >= 1 and PowerDb.hero_rank("thunderous_shot", "cutter") >= 1)
	expect("a starting power is not learned by the other member (no free Take Aim for the hero)",
		PowerDb.hero_rank("take_aim", "hero") == 0 and PowerDb.hero_rank("brutal_attack", "cutter") == 0)
	expect("the default bar holds the four powers, two per member, cast by their owners",
		HotbarLayout.DEFAULT_SLOTS.slice(0, 4) == ["brutal_attack", "whirling_strike", "take_aim", "thunderous_shot"]
		and HotbarLayout.DEFAULT_CASTERS.slice(0, 4) == ["hero", "hero", "cutter", "cutter"] and HotbarLayout.SLOTS_PER_MEMBER == 2
		and HotbarLayout.is_valid(HotbarLayout.DEFAULT_SLOTS, HotbarLayout.DEFAULT_ALT))
	var learned_ok: bool = true
	for id in HERO_POWERS + CUTTER_POWERS:
		learned_ok = learned_ok and HotbarLayout.learned(id)
	expect("every starting power counts as learned for the bar (pruning keeps it)", learned_ok)
	expect("both hero powers start full", _all_near(_fractions(hero, HERO_POWERS), 1.0))
	expect("both Cutter powers start full", _all_near(_fractions(cutter, CUTTER_POWERS), 1.0))
	expect("Brutal Attack is usable at once", hero.stats.can_use("brutal_attack"))
	expect("Whirling Strike is not blocked by its rank or its charge", not hero.powers.blocker("whirling_strike").contains("not open") and not hero.powers.blocker("whirling_strike").contains("charged"))

	# --- Each power's recharge time matches its constant --------------------------------------------------------------------------------------
	expect("the constants: Brutal Attack and Take Aim 11 s, Whirling Strike and Thunderous Shot 7 s",
		is_equal_approx(PowerDb.charge_seconds("brutal_attack"), 11.0) and is_equal_approx(PowerDb.charge_seconds("take_aim"), 11.0)
		and is_equal_approx(PowerDb.charge_seconds("whirling_strike"), 7.0) and is_equal_approx(PowerDb.charge_seconds("thunderous_shot"), 7.0))
	for entry in [["brutal_attack", hero, "melee"], ["whirling_strike", hero, "melee"], ["take_aim", cutter, "ranged"], ["thunderous_shot", cutter, "ranged"]]:
		var id: String = entry[0]
		var body: Player = entry[1]
		_spend(body, id)
		var seconds: float = PowerDb.charge_seconds(id)
		# The damage one second of combat is worth to this member; another power's blow feeds it (a power is never fed by its own).
		var per_second: float = body.stats.power_recharge_damage(1.0, String(entry[2]))
		body.on_party_damage(per_second * (seconds - 1.0), "other")
		var short: float = body.stats.ult_fraction(id)
		body.on_party_damage(per_second, "other")
		expect("%s recharges in %.0f s of combat (%.0f%% after %.0f s, full after %.0f s)" % [id, seconds, short * 100.0, seconds - 1.0, seconds],
			absf(short - (seconds - 1.0) / seconds) < 0.02 and body.stats.ult_fraction(id) >= 1.0)

	# --- A kill refills every power: 10%, a champion 25% -----------------------------------------------------------------------------------------
	_spend_all()
	var foe: Enemy = _spawn_enemy(hero.global_position + Vector3(6, 0, 0))
	foe.set_physics_process(false)
	hero.on_enemy_killed(foe)
	expect("a party kill adds 10%% to every power of every member",
		_all_near(_fractions(hero, HERO_POWERS), PlayerStats.KILL_REFILL) and _all_near(_fractions(cutter, CUTTER_POWERS), PlayerStats.KILL_REFILL)
		and is_equal_approx(PlayerStats.KILL_REFILL, 0.10))
	var elite: Enemy = _spawn_enemy(hero.global_position + Vector3(7, 0, 0))
	elite.set_physics_process(false)
	elite.champion = Champion.new()
	hero.on_enemy_killed(elite)
	expect("a champion kill adds 25%% (0.10 -> 0.35)", _all_near(_fractions(hero, HERO_POWERS), 0.35) and _all_near(_fractions(cutter, CUTTER_POWERS), 0.35)
		and is_equal_approx(PlayerStats.CHAMPION_KILL_REFILL, 0.25))
	elite.champion = null
	foe.queue_free()
	elite.queue_free()

	# --- An Opening refills that hero's powers by 25%, once ----------------------------------------------------------------------------------
	_spend_all()
	var target: Enemy = _spawn_enemy(hero.global_position + Vector3(2, 0, 0))
	target.set_physics_process(false)
	target.max_health = 5000.0
	target.health = 5000.0
	hero.openings.on_executed(target, {"outcome": Combat.Outcome.CRITICAL}, {})
	expect("a landed Opening adds exactly 25%% to each of the hero's powers (the one rule; the old rank-scaled refund is folded into it)",
		_all_near(_fractions(hero, HERO_POWERS), 0.25) and is_equal_approx(hero.openings.charge_refund(), 25.0))
	target.queue_free()

	# --- Charge carries over the gap between fights: no out-of-combat top-up ------------------------------------------------------------------
	_spend_all()
	hero.on_party_damage(hero.stats.power_recharge_damage(2.0, "melee"), "other")
	cutter.on_party_damage(cutter.stats.power_recharge_damage(2.0, "ranged"), "other")
	var before: Array[float] = _fractions(hero, HERO_POWERS) + _fractions(cutter, CUTTER_POWERS)
	for i in 300:   # five seconds of the real game loop in an empty arena
		await get_tree().physics_frame
	var after: Array[float] = _fractions(hero, HERO_POWERS) + _fractions(cutter, CUTTER_POWERS)
	expect("with no enemies the charge is exactly what the last fight left, five seconds later", before[0] > 0.0 and before[0] < 1.0 and before == after)

	# --- A level-up still refills the levelling member's powers (DS2); see the report ---------------------------------------------------------
	_spend_all()
	hero._on_leveled(1, 2, 0)
	expect("a level-up refills the levelling member's powers (kept from DS2)", _all_near(_fractions(hero, HERO_POWERS), 1.0)
		and cutter.stats.ult_fraction("take_aim") < 0.001)

	# Leave a normal start behind for the checks that follow: TownState.reset() emptied the worn gear.
	_restore_start(hero, cutter)

## The starting kit worn again (hero) and Cutter's short bow, every bar full.
func _restore_start(hero: Player, cutter: ArcherCompanion) -> void:
	for item in Items.starting_gear():
		hero.stats.equip(item, false)
	cutter.stats.equipment[Items.Slot.WEAPON] = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow")
	hero.stats.refresh()
	cutter.stats.refresh()
	hero.powers.reset()
	cutter.powers.reset()
	hero.stats.brutal_reload_remaining = 0.0
	cutter.bow.reload_remaining = 0.0

## `-- --startbarcapture`: the HUD of a brand-new party at 1080p (windowed, screen 1): the four starting powers full, then partly charged by
## damage, then after a kill. Saves PNGs of the whole window to `res://.dev_output/startbar/`. Never saves the game.
func _start_bar_capture() -> void:
	TownState.persist = false
	TownState.reset()
	GameSettings.reset_hotbar()
	GameSettings.ui_size = 1.0
	GameSettings.apply_ui_scale()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	_restore_start(player, game.companion)   # TownState.reset() empties the worn gear; a real start equips the kit
	var out_dir := ProjectSettings.globalize_path("res://.dev_output/startbar")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(1.0).timeout
	await _shot(out_dir, "1_start_full")
	_spend_all()
	for body in [player, game.companion]:
		body.on_party_damage(body.stats.power_recharge_damage(5.0, "melee"), "other")
	await get_tree().create_timer(0.5).timeout
	await _shot(out_dir, "2_after_5s_of_combat")
	var foe: Enemy = _spawn_enemy(player.global_position + Vector3(8, 0, 8))
	foe.set_physics_process(false)
	player.on_enemy_killed(foe)
	await get_tree().create_timer(0.5).timeout
	await _shot(out_dir, "3_after_a_kill")
	print("STARTBAR_CAPTURE ", out_dir, " window=", DisplayServer.window_get_size(), " screen=", DisplayServer.window_get_current_screen())
	get_tree().quit()

func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
