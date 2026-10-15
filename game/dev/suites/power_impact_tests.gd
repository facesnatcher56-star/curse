extends DevSuite
## Impact timing and feel for Whirling Strike, Staggering Blow and War Cry: damage, stun and throw-back land at the strike frame (never on
## the key press); a wind-up cut short by death, a knockdown or a move does nothing and is not spent; the cues play through Sfx.power; the
## hit-pause and shake are bounded and only follow a hit; and no floating name text is left over the hero.

func _test_power_impact() -> void:
	TownState.persist = false
	TownState.reset()
	await get_tree().process_frame
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	for item in Items.starting_gear(): player.stats.equip(item, false)
	TownState.passive_ranks = {"critical_strike": 8, "fortitude": 8, "smite": 1, "overbear": 1, "barricade": 1, "dodge": 5, "survival": 3,
		"devastation": 2, "searing_flames": 8, "ignite": 1}
	player.stats.refresh()
	player.set_physics_process(false)
	var powers: PowerController = player.powers
	var s: SkillController = player.skills
	var was_enabled: bool = Sfx.enabled
	Sfx.enabled = true
	powers.reset()
	s.reset()
	player.global_position = Vector3(40, 0, 40)
	player.reset_physics_interpolation()
	var spawn: Callable = func(offset: Vector3) -> Enemy:
		var e: Enemy = _spawn_enemy(player.global_position + offset)
		e.set_physics_process(false)
		e.aggro_range = 0.0
		e.max_health = 50000.0
		e.health = e.max_health
		e.dodge_chance = 0.0
		e.block_chance = 0.0
		e.stun_time = 0.0
		return e
	var near: Array[Enemy] = [spawn.call(Vector3(1.4, 0, 0)), spawn.call(Vector3(-1.4, 0, 0))]
	var untouched: Callable = func() -> bool: return near.all(func(e: Enemy) -> bool: return is_equal_approx(e.health, e.max_health))

	# --- Whirling Strike: the key press does nothing; the strike does everything --------------------------------------------------------
	Sfx.played_log.clear()
	Sfx._last_played.clear()
	expect("Whirling Strike is ready to use (%s)" % powers.blocker("whirling_strike"), powers.blocker("whirling_strike") == "")
	expect("Whirling Strike starts its wind-up", powers.activate("whirling_strike", player.global_position) and s.busy)
	expect("the key press deals no damage and stuns nothing", untouched.call() and near.all(func(e: Enemy) -> bool: return e.stun_time <= 0.0))
	expect("the power is not spent while it winds up", not powers.reload_remaining.has("whirling_strike") and powers.ready("whirling_strike"))
	expect("a second power cannot start over a wind-up in progress", not powers.activate("war_cry", player.global_position) and s.busy_skill == "whirling_strike")
	expect("the cast cue plays on the key press", Sfx.played_log.has("whirling_strike_cast") and not Sfx.played_log.has("whirling_strike_hit"))
	s.tick_busy(0.05)
	expect("still before the strike, nothing has landed", untouched.call() and not powers.reload_remaining.has("whirling_strike"))
	_settle_cast(player)
	expect("at the strike every enemy in reach is hit and stunned", near.all(func(e: Enemy) -> bool: return e.health < e.max_health and e.stun_time > 0.0))
	expect("and thrown back from the hero", near.all(func(e: Enemy) -> bool: return e.knock.length() > 0.5))
	expect("the power is spent at the strike", powers.reload_remaining.has("whirling_strike") and not powers.ready("whirling_strike"))
	expect("the impact cue plays with the hit", Sfx.played_log.has("whirling_strike_hit"))
	powers.gain(powers.required("whirling_strike"))

	# --- A wind-up cut short by a knockdown does nothing and is not spent ----------------------------------------------------------------
	for e in near:
		e.health = e.max_health
		e.stun_time = 0.0
		e.knock = Vector3.ZERO
	powers.reset()
	s.reset()
	expect("Whirling Strike starts again", powers.activate("whirling_strike", player.global_position) and s.busy)
	s.tick_busy(0.1)
	player.knockdown.begin()
	expect("a knockdown before the strike ends the wind-up", not s.busy)
	expect("and it does nothing and is not spent", untouched.call() and not powers.reload_remaining.has("whirling_strike"))
	_settle_cast(player)
	expect("the wind-up never resumes after the fall", untouched.call() and not powers.reload_remaining.has("whirling_strike"))
	player.knockdown.phase = Knockdown.Phase.NONE
	player.stun_time = 0.0

	# --- A wind-up cut short by death does nothing and is not spent ----------------------------------------------------------------------
	powers.reset()
	s.reset()
	expect("War Cry starts", powers.activate("war_cry", near[0].global_position) and s.busy)
	s.tick_busy(0.2)
	player.dead = true
	_settle_cast(player)
	expect("death before the shout's impact does nothing and does not spend War Cry", not powers.reload_remaining.has("war_cry")
		and is_equal_approx(near[0].armor_shred, 0.0) and near[0].fear_time <= 0.0)
	player.dead = false
	s.cancel_action()

	# --- War Cry: no floating name, impact hits what is in front, and the shout's cue plays on the key press -------------------------------
	powers.reset()
	s.reset()
	for e in near:
		e.fear_time = 0.0
		e.armor_shred = 0.0
	var labels_before: int = _label_count("War Cry")
	Sfx.played_log.clear()
	Sfx._last_played.clear()
	powers.activate("war_cry", player.global_position + Vector3(5, 0, 0))   # the enemies sit at +X and -X: +X is in front
	expect("War Cry shows no floating name text", _label_count("War Cry") == labels_before)
	expect("the shout's cue plays on the key press", Sfx.played_log.has("war_cry_cast"))
	_settle_cast(player)
	expect("at its impact the enemies in front are frightened", near[0].fear_time > 0.0 and near[0].armor_shred > 0.0)
	expect("and the impact cue plays", Sfx.played_log.has("war_cry_hit"))
	player.forced_crits = 0

	# --- Staggering Blow: arms, the armed swing is its own clip, and the shockwave lands on the blow's impact ----------------------------
	powers.reset()
	s.reset()
	var saved_weapon: Variant = player.stats.equipment.get(Items.Slot.WEAPON)
	player.stats.wear(Items.Slot.WEAPON, Items.build(ItemDb.get_def("greatsword"), 6, Items.Rarity.NORMAL))
	for e in near:
		e.stun_time = 0.0
		e.health = e.max_health
	Sfx.played_log.clear()
	Sfx._last_played.clear()
	player.stats.cooldowns.clear()
	player.attack_target = near[0]   # the armed blow goes at the nearest enemy, as a basic attack would
	expect("Staggering Blow arms", powers.activate("staggering_blow", player.global_position) and powers.staggering_armed)
	expect("arming plays the arm cue and spends nothing", Sfx.played_log.has("staggering_cast") and not powers.reload_remaining.has("staggering_blow"))
	expect("the armed swing uses Staggering Blow's own clip", s.busy and bool(s.busy_def.get("staggering_animation", false)))
	s.tick_busy(0.02)
	player.dead = true
	for i in 200:
		s.tick_busy(0.01)   # a dead hero's swing never reaches its blow
	player.dead = false
	s.cancel_action()
	expect("a blow cut short leaves Staggering Blow armed and unspent", powers.staggering_armed and not powers.reload_remaining.has("staggering_blow")
		and near.all(func(e: Enemy) -> bool: return e.stun_time <= 0.0))
	player.stats.cooldowns.clear()
	player.attack_target = near[0]
	s.start_skill("basic", near[0])   # still armed: the next blow that lands is the release
	var guard: int = 0
	while s.busy and guard < 300:
		s.tick_busy(0.01)   # the swing runs to its blow; the shockwave is released by that impact
		guard += 1
	expect("the blow's shockwave stuns those around the target and is spent", near.all(func(e: Enemy) -> bool: return e.stun_time > 0.0)
		and not powers.staggering_armed and powers.reload_remaining.has("staggering_blow"))
	expect("its impact cue plays", Sfx.played_log.has("staggering_hit"))
	player.attack_target = null
	if saved_weapon != null:
		player.stats.wear(Items.Slot.WEAPON, saved_weapon)

	# --- Hit-pause and shake: bounded, and only after a hit --------------------------------------------------------------------------------
	expect("the hit-pause is bounded", PowerController.IMPACT_PAUSE_MAX <= 0.07 and PowerController.IMPACT_SHAKE_MAX <= 0.3)
	powers.reset()
	s.reset()
	for e in near:
		e.stun_time = 0.0
		e.health = e.max_health
	Fx.reset_time()
	for e in near:
		e.global_position += Vector3(0, 0, 40)   # out of reach: the whirl hits nothing
	var far: Enemy = near[0]
	powers.activate("whirling_strike", player.global_position)
	_settle_cast(player)
	expect("a whirl that hits nothing adds no hit-pause or shake", not Fx._stopped and is_equal_approx(Engine.time_scale, 1.0)
		and is_equal_approx(far.health, far.max_health))
	Fx.reset_time()

	# --- Tidy up ------------------------------------------------------------------------------------------------------------------------
	player.knockdown.phase = Knockdown.Phase.NONE
	player.dead = false
	s.reset()
	powers.reset()
	TownState.passive_ranks.clear()
	player.stats.refresh()
	Sfx.enabled = was_enabled
	for e in near:
		if is_instance_valid(e):
			e.queue_free()
	player.set_physics_process(true)

## Labels in the world reading `text` (a floating name is a Label3D that Fx.text_at adds to the scene).
func _label_count(text: String) -> int:
	var count: int = 0
	for node in get_tree().current_scene.get_children():
		var label := node as Label3D
		if label != null and label.text == text:
			count += 1
	return count
