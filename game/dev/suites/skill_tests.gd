extends DevSuite
## Self-test: hotkeys, hotbar, the skill queue and data integrity.

## Hotkeys pressed mid-animation: the potion drinks immediately, usable skills cancel the swing, unusable ones do not.
func _test_hotkeys() -> void:
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.stats.potions = 3
	var previous_hotbar := player.skills.hotbar.duplicate()
	player.skills.assign_slot(3, "fireball")
	expect("hotkey fixture configures this character's slot", player.skills.hotbar[3] == "fireball")
	var dummy: Enemy = _spawn_enemy(Vector3(1.8, 0, 0))
	dummy.aggro_range = 0.0
	dummy.max_health = 900.0
	dummy.health = 900.0
	await get_tree().physics_frame
	# 1. Potion during a swing.
	player.health = player.max_health * 0.3
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.15).timeout
	var was_busy: bool = player.skills.busy
	Input.action_press("use_potion")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("use_potion")
	var potion_ok: bool = player.stats.potions == 2 and player.health > player.max_health * 0.3 + 20.0 and not player.skills.busy
	# 2. Potion while stunned.
	player.health = 30.0
	player.stats.cooldowns.clear()
	player.stun_time = 1.0
	await get_tree().physics_frame
	Input.action_press("use_potion")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("use_potion")
	var stunned_ok: bool = player.stats.potions == 1 and player.health > 60.0
	player.stun_time = 0.0
	# 3. A usable skill cancels the current swing and starts.
	player.stats.cooldowns.clear()
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.1).timeout
	Input.action_press("skill_4")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_4")
	await get_tree().physics_frame   # Fireball is aimed: it is cast when the key is let go
	await get_tree().physics_frame
	var skill_ok: bool = player.skills.busy_skill == "fireball"
	player.skills.cancel_action()
	# 4. A skill on cooldown must NOT cancel the swing.
	player.stats.cooldowns["fireball"] = 5.0
	player.skills.start_skill("basic", dummy)
	await get_tree().create_timer(0.1).timeout
	Input.action_press("skill_4")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("skill_4")
	var no_cancel_ok: bool = player.skills.busy and player.skills.busy_skill == "basic"
	player.skills.cancel_action()
	expect("potion works mid-swing", potion_ok)
	expect("potion works while stunned", stunned_ok)
	expect("a usable skill cancels a swing", skill_ok)
	expect("an unusable skill leaves the swing alone", no_cancel_ok)
	print("  hotkeys: potion mid-swing=", potion_ok, " (was busy=", was_busy, "), potion while stunned=", stunned_ok,
		", skill cancels swing=", skill_ok, ", skill on cooldown leaves swing alone=", no_cancel_ok)
	dummy.queue_free()
	player.stats.cooldowns.clear()
	player.stats.potions = 3
	player.skills.hotbar = previous_hotbar
	await get_tree().process_frame

## Skills on keys can be changed freely: the layout is always the same seven skills (a change is a swap), it is shared by the hero, the
## settings and the save, and clicking a hotbar slot opens a picker whose icons put a skill on that key.
func _test_hotbar() -> void:
	GameSettings.reset_hotbar()
	var full_layout: Array[String] = ["whirling_strike", "fireball", "war_cry", "provoke", "repulse", "silence"]
	var slots: Array[String] = full_layout.duplicate()
	var alt: String = HotbarLayout.assign(slots, HotbarLayout.DEFAULT_ALT, 0, "fireball")
	expect("putting a skill that is elsewhere on a key swaps the two", slots[0] == "fireball" and slots[1] == "whirling_strike" and alt == "basic")
	alt = HotbarLayout.assign(slots, alt, HotbarLayout.ALT, "war_cry")
	expect("the mouse button swaps like any other slot", alt == "war_cry" and slots[2] == "basic" and HotbarLayout.is_valid(slots, alt))
	var benched: Array[String] = full_layout.duplicate()
	var bench_alt: String = HotbarLayout.assign(benched, HotbarLayout.DEFAULT_ALT, 3, "brutal_attack")
	expect("a skill from the bench takes a key and the one it replaces goes to the bench", benched[3] == "brutal_attack" and not benched.has("provoke") and bench_alt == "basic" and HotbarLayout.is_valid(benched, bench_alt))
	expect("a layout has six slots, permits empty keys, excludes potions, and never duplicates assigned skills", not HotbarLayout.is_valid(["whirling_strike", "whirling_strike", "war_cry", "provoke", "repulse", "silence"], "basic")
		and not HotbarLayout.is_valid(["whirling_strike", "fireball", "potion", "provoke", "repulse", "silence"], "basic")
		and not HotbarLayout.is_valid(["whirling_strike", "fireball", "war_cry", "provoke", "repulse"], "basic") and HotbarLayout.is_valid(HotbarLayout.DEFAULT_SLOTS, "basic"))
	expect("the dodge cannot be put on a key", HotbarLayout.assign(slots, alt, 3, "dodge") == alt and slots[3] == "provoke")
	# The hero's bar IS the settings' layout, so one change shows everywhere.
	GameSettings.reset_hotbar()
	var skills: SkillController = player.skills
	expect("the hero's hotbar is the settings' layout", is_same(skills.hotbar, GameSettings.hotbar_slots) and skills.right_click_skill == "basic")
	# The real click path: open the picker on slot 2, choose Repulse.
	await get_tree().process_frame
	await get_tree().process_frame
	var size_px: Vector2 = hud.get_viewport_rect().size
	var second: Dictionary = {}
	var mouse_slot: Dictionary = {}
	for hit in hud._slot_hits:
		if hit["action"] == "skill_2":
			second = {"slot": 1, "rect": hit["rect"]}
		if hit["action"] == "alt_skill":
			mouse_slot = {"slot": HotbarLayout.ALT, "rect": hit["rect"]}
	expect("the hotbar slots are known to the HUD", not second.is_empty() and not mouse_slot.is_empty())
	var press := func(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> bool:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = true
		e.position = at
		return hud.picker.handle_click(e)
	expect("clicking a slot opens the picker for it", press.call((second["rect"] as Rect2).get_center()) and hud.picker.is_open() and hud.picker.open_slot == 1)
	expect("the open picker keeps the world from taking clicks", hud.covers(hud.picker.panel_rect(size_px).get_center()))
	var repulse_at: Vector2 = Vector2.ZERO
	for cell in hud.picker.cells(size_px):
		if cell["id"] == "repulse":
			repulse_at = (cell["rect"] as Rect2).get_center()
	press.call(repulse_at)
	expect("choosing a skill asks for its caster before changing the slot", hud.picker.pending_skill_id == "repulse" and hud.picker.is_open())
	for cell in hud.picker.caster_cells(size_px):
		if cell["id"] == "hero": press.call((cell["rect"] as Rect2).get_center())
	expect("choosing Repulse puts it on the empty key 2", skills.hotbar[1] == "repulse" and not hud.picker.is_open()
		and GameSettings.hotbar_caster(1) == "hero" and HotbarLayout.is_valid(skills.hotbar, skills.right_click_skill))
	# The mouse button, and closing without choosing.
	await get_tree().process_frame
	press.call((mouse_slot["rect"] as Rect2).get_center())
	expect("the mouse button's slot opens a picker too", hud.picker.is_open() and hud.picker.open_slot == HotbarLayout.ALT)
	press.call(Vector2(5, 5), MOUSE_BUTTON_RIGHT)
	expect("a right click closes it with nothing changed", not hud.picker.is_open() and skills.right_click_skill == "basic")
	press.call((mouse_slot["rect"] as Rect2).get_center())
	expect("the dedicated potion is absent from the skill picker", not HotbarLayout.ASSIGNABLE.has("potion"))
	hud.picker.close() # An open picker consumes an outside click to close; test the dodge from the normal closed state.
	var dodge_rect: Rect2 = Rect2()
	for hit in hud._slot_hits:
		if hit["action"] == "dodge":
			dodge_rect = hit["rect"]
	expect("the dodge slot cannot be changed", not press.call(dodge_rect.get_center()) and not hud.picker.is_open())
	# Take Aim can be assigned from the bench, shows in the picker, and commands Cutter.
	press.call((second["rect"] as Rect2).get_center())
	var take_aim_at: Vector2 = Vector2.ZERO
	for cell in hud.picker.cells(size_px):
		if cell["id"] == "take_aim":
			take_aim_at = (cell["rect"] as Rect2).get_center()
	expect("the picker presents Take Aim as an assignable power", take_aim_at != Vector2.ZERO)
	press.call(take_aim_at)
	for cell in hud.picker.caster_cells(size_px):
		if cell["id"] == "cutter": press.call((cell["rect"] as Rect2).get_center())
	expect("Take Aim can be assigned to hotbar slot 2", skills.hotbar[1] == "take_aim" and HotbarLayout.is_valid(skills.hotbar, skills.right_click_skill))
	var cutter: ArcherCompanion = game.companion
	if cutter != null:
		_prepare_archer(cutter)
		var saved_ranks := cutter.character.passive_ranks.duplicate()
		cutter.character.passive_ranks["critical_shot"] = 1
		cutter.take_aim_armed = false
		cutter.take_aim_reload_remaining = 0.0
		expect("Take Aim is usable by the slot's assigned Cutter when ready", cutter.stats.can_use("take_aim") and is_equal_approx(cutter.stats.ult_fraction("take_aim"), 1.0))
		Input.action_press("skill_2")
		skills._route_hotbar_action("skill_2", "take_aim", 1, player.global_position)
		Input.action_release("skill_2")
		expect("the shared Take Aim hotkey commands Cutter", cutter.skills.take_aim_targeting or cutter.take_aim_armed)
		expect("the controlled melee hero does not take over Cutter's targeting", not player.skills.take_aim_targeting)
		cutter.skills.cancel_take_aim_targeting()
		cutter.character.passive_ranks = saved_ranks
	GameSettings.reset_hotbar()

## Drive cancellation synchronously so regeneration and input timing cannot mask a spend or refund.
func _test_action_queue() -> void:
	player.set_physics_process(false)
	var s: SkillController = player.skills
	var aim: Vector3 = player.global_position + Vector3(0, 0, -2)
	var target: Enemy = _spawn_enemy(aim)
	target.set_physics_process(false)
	s.reset()
	player.stats.cooldowns.clear()
	player.stats.mana = player.stats.max_mana
	s.queue_skill("basic", aim)
	s.cancel_action()
	expect("idle cancellation drops queued order", s.queued_skill == "" and s.queued_target == null)
	s.reset()
	s.queue_skill("basic", aim)
	s.start_skill("fireball", null, aim)
	expect("immediate skill supersedes queued order", s.queued_skill == "" and s.queued_target == null)
	s.cancel_action()
	s.reset()
	s.queue_skill("basic", aim)
	s.start_skill("basic", target)
	expect("consuming queue clears target ownership", s.queued_skill == "" and s.queued_target == null)
	s.cancel_action()
	s.queue_skill("basic", aim)
	expect("fixture queued target before deletion", s.queued_target == target)
	target.free()
	player._act(0.0, aim)
	expect("freed queue target is dropped", s.queued_skill == "" and s.queued_target == null)
	var next: Enemy = _spawn_enemy(aim)
	next.set_physics_process(false)
	s.queue_skill("basic", aim)
	player.stats.cooldowns.clear()
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(aim)
	expect("idle dodge clears queued target ownership", s.queued_skill == "" and s.queued_target == null)
	player.movement.tick_roll(2.0)
	# Presses on either side of completion retain only the latest intended order.
	for elapsed in [0.0, 0.25, 0.8]:
		s.reset()
		player.stats.cooldowns.clear()
		player.stats.mana = player.stats.max_mana
		s.start_skill("fireball", null, aim)
		s.tick_busy(elapsed)
		s.queue_skill("basic", aim)
		s.queue_skill("basic", aim)
		expect("repeated queue holds one next order", s.queued_skill == "basic" and s.queued_target == next)
		s.tick_busy(s.busy_time)
		var mana: float = player.stats.mana
		var children: int = get_tree().current_scene.get_child_count()
		s.tick_busy(10.0)
		expect("completion cannot replay or spend", is_equal_approx(player.stats.mana, mana) and get_tree().current_scene.get_child_count() == children)
		player._act(0.0, aim)
		expect("completion consumes queued action once", s.busy and s.busy_skill == "basic" and s.queued_skill == "" and s.queued_target == null)
		s.cancel_action()
	# A power going off supersedes the queued order too.
	s.reset()
	TownState.passive_ranks["critical_strike"] = 8
	TownState.passive_ranks["smite"] = 1
	player.powers.reset()
	s.queue_skill("basic", aim)
	expect("a power starts whatever was queued", player.powers.activate("war_cry", aim) and s.busy and s.queued_skill == "")
	_settle_cast(player)
	expect("and is spent at its impact", not player.powers.ready("war_cry"))
	player.forced_crits = 0
	player.powers.reset()
	TownState.passive_ranks.clear()
	s.queue_skill("basic", aim)
	player.stats.cooldowns.clear()
	player.stats.potions = 1
	player.health = player.max_health * 0.5
	s.drink_potion()
	expect("idle potion cancels queued action", s.queued_skill == "" and s.queued_target == null and player.stats.potions == 0)
	# Unusable replacement preserves the intended next action without spending.
	s.queue_skill("basic", aim)
	player.stats.cooldowns["fireball"] = 5.0
	s.start_skill("fireball", null, aim)
	expect("rejected replacement preserves queue", s.queued_skill == "basic" and not s.busy)
	player.stats.cooldowns["basic"] = 5.0
	player._act(0.0, aim)
	expect("unusable queued action is dropped without blocking", not s.busy and s.queued_skill == "" and s.queued_target == null)
	player.stats.cooldowns.clear()
	s.queue_skill("basic", aim)
	player.dead = true
	player._on_death()
	s.queue_skill("basic", aim)
	expect("dead input cannot acquire queue ownership", s.queued_skill == "" and s.queued_target == null)
	player.revive_at(player.global_position)
	player.set_physics_process(false)
	player.stats.cooldowns.clear()
	s.start_skill("basic", next)
	expect("revive accepts immediate action", s.busy and s.busy_skill == "basic")
	s.cancel_action()
	next.free()
	s.reset()
	player.set_physics_process(true)

func _test_skill_integrity() -> void:
	player.set_physics_process(false)
	var s: SkillController = player.skills
	var aim: Vector3 = player.global_position + Vector3(0, 0, -6)
	for elapsed in [0.0, 0.25, 0.8]:
		player.stats.mana = player.stats.max_mana
		player.stats.cooldowns.clear()
		s.start_skill("fireball", null, aim)
		s.tick_busy(elapsed)
		var spent: float = player.stats.mana
		s.start_skill("fireball", null, aim)
		expect("repeated start does not spend again", is_equal_approx(player.stats.mana, spent))
		s.cancel_action()
		expect("generic pre-release cancellation refunds Fireball", is_equal_approx(player.stats.mana, player.stats.max_mana) and float(player.stats.cooldowns.get("fireball", 0.0)) == 0.0)
		s.cancel_action()
		expect("repeat cancellation cannot mint mana", is_equal_approx(player.stats.mana, player.stats.max_mana))
	player.stats.cooldowns.clear()
	s.start_skill("fireball", null, aim)
	s.tick_busy(s.busy_time)
	var committed_mana: float = player.stats.mana
	var balls: int = get_tree().current_scene.get_child_count()
	s.tick_busy(10.0)
	expect("finished tick cannot replay Fireball", get_tree().current_scene.get_child_count() == balls)
	s.cancel_action()
	expect("released Fireball keeps its cost", is_equal_approx(player.stats.mana, committed_mana) and float(player.stats.cooldowns.get("fireball", 0.0)) > 0.0)
	# The potion and legal switch both use the generic cancellation path.
	player.stats.mana = player.stats.max_mana
	player.stats.cooldowns.clear()
	player.stats.potions = 1
	player.health = player.max_health * 0.5
	s.start_skill("fireball", null, aim)
	s.drink_potion()
	expect("potion abort refunds unreleased cast", not s.busy and player.stats.potions == 0 and is_equal_approx(player.stats.mana, player.stats.max_mana))
	player.stats.cooldowns.clear()
	s.start_skill("fireball", null, aim)
	s.cancel_action()
	s.start_skill("basic", _spawn_enemy(aim))
	expect("legal switch spends only the replacement skill", s.busy and s.busy_skill == "basic" and is_equal_approx(player.stats.mana, player.stats.max_mana))
	s.cancel_action()
	player.stats.cooldowns.clear()
	s.aiming_id = "fireball"
	s.aiming_action = "skill_2"
	s.aim_blocked = "skill_1"
	s.swallow_alt = true
	s.queued_skill = "basic"
	s.start_skill("fireball", null, aim)
	player._on_death()
	expect("death clears action and aim state", not s.busy and s.aiming_id == "" and s.aiming_action == "" and s.queued_skill == "" and s.fire_orb == null)
	player.dead = true
	s.start_skill("fireball", null, aim)
	expect("dead actor cannot restart a skill (busy %s %s)" % [s.busy_skill, s.busy_def.get("kind", "")], not s.busy)
	player.revive_at(player.global_position)
	expect("revive clears blocked input state", s.aim_blocked == "" and not s.swallow_alt and s.busy_def.is_empty() and s.busy_target == null and s.queued_target == null)
	player.set_physics_process(true)
