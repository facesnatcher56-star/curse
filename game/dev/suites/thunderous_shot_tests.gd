extends DevSuite
## Thunderous Shot (Cutter's bow power): it needs its passive and a bow, draws for one long draw, then one bolt goes through every enemy on
## the line within the bow's reach, each taking the power's share of the bow's damage and a stun; it is spent at the release (a draw cut short
## spends nothing), kills are ordinary deaths (no gibbing), and what is off the line or beyond the reach is untouched.

const DELTA := 1.0 / 60.0

func _foe(at: Vector3, health: float) -> Enemy:
	var foe := _spawn_enemy(at)
	foe.set_physics_process(false)
	foe.aggro_range = 0.0
	foe.max_health = health
	foe.health = health
	foe.armor = 0.0
	foe.toughness = 0.0
	foe.dodge_chance = 0.0
	foe.block_chance = 0.0
	foe.ranged_block_chance = 0.0
	foe.stun_resist = 0.0
	return foe

func _draw_through(archer: ArcherCompanion, frames: int) -> void:
	for i in frames:
		if not archer.skills.busy:
			break
		archer.skills.tick_busy(DELTA)
		await get_tree().process_frame

func _test_thunderous_shot() -> void:
	TownState.persist = false
	TownState.reset()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	_prepare_archer(archer)
	archer.testing_disabled = true
	var lane: Vector3 = await _own_lane(26.0, 8.0)
	archer.global_position = lane
	archer.reset_physics_interpolation()
	player.global_position = lane + Vector3(-6.0, 0.0, 3.0)
	player.reset_physics_interpolation()
	archer.powers.reset()

	# Gates: the passive, then the bow.
	expect("Thunderous Shot is a live power, on the hotbar picker and with a skill entry", PowerController.LIVE.has("thunderous_shot")
		and HotbarLayout.ASSIGNABLE.has("thunderous_shot") and SkillDb.all().has("thunderous_shot"))
	expect("it is Cutter's starting power: open at rank 1 without Biting Arrow (Lane P), and the passive alone still opens nothing", PowerDb.hero_rank("thunderous_shot", "cutter") == 1 and PowerDb.get_def("thunderous_shot").rank_for({}) == 0)
	TownState.add_member_xp("cutter", HeroProgression.xp_for_level(11), false, {"ranged": 1.0})
	expect("Cutter opens it through the common purchase rule (Critical Shot, then Biting Arrow)", TownState.buy_passives({"critical_shot": 1}, "cutter") and TownState.buy_passives({"biting_arrow": 1}, "cutter"))
	archer.stats.refresh()
	expect("with the passive and his bow it is ready", PowerDb.hero_rank("thunderous_shot", "cutter") == 1 and archer.powers.stance_ok("bow") and archer.powers.ready("thunderous_shot"))
	expect("a sword is not a bow: the hero's stance check fails", not player.powers.stance_ok("bow"))

	# The line: three on it (8, 11.5, 15 m), one off to the side, one beyond the 17 m reach, one a wall's width behind.
	var first := _foe(lane + Vector3(8.0, 0.0, 0.0), 100000.0)
	var second := _foe(lane + Vector3(11.5, 0.0, 0.0), 100000.0)
	var third := _foe(lane + Vector3(15.0, 0.0, 0.0), 1.0)    # low life: dies of it
	var aside := _foe(lane + Vector3(11.5, 0.0, 4.0), 100000.0)
	var beyond := _foe(lane + Vector3(19.5, 0.0, 0.0), 100000.0)
	await get_tree().physics_frame
	var gibs_before: int = get_tree().get_nodes_in_group("gibs").size()
	var mult: float = PowerDb.hero_value("thunderous_shot", "damage_pct", "cutter") / 100.0 * archer.stats.power_damage_mult()
	var range: Vector2 = archer.stats.ranged_range()

	# The casting area: it follows the cursor, shows how far the bolt goes, and outlines exactly the enemies the bolt will go through.
	archer.skills.aiming_id = "thunderous_shot"
	archer.skills.update_aim(first.global_position)
	var area: ThunderousAimFx = archer.skills._thunder_aim
	var outlined: Array = archer.skills._highlighted
	expect("holding the key shows the casting area", area != null and area.visible)
	expect("it outlines exactly the three on the line, in the power's own colour", outlined.size() == 3 and first in outlined and second in outlined and third in outlined
		and not (aside in outlined) and not (beyond in outlined) and first.highlight_override == ThunderousAimFx.highlight_material())
	var line: Dictionary = archer.powers.thunderous_line(archer.global_position + Vector3(0, 1.4, 0) + Vector3.RIGHT * 0.6, Vector3.RIGHT)
	expect("the area is the line the release will use (the bow's reach, three on it)", is_equal_approx(float(line["length"]), ThunderousShotFx.REACH) and (line["victims"] as Array).size() == 3)
	archer.skills.clear_aim()
	expect("letting go or cancelling clears the area and the outlines", not area.visible and not first.highlighted and first.highlight_override == null)

	# A draw cut short does nothing and is not spent.
	expect("using it draws the bow", archer.powers.activate("thunderous_shot", first.global_position) and archer.skills.busy and archer.bow.thunder_power)
	expect("the draw is the long one", is_equal_approx(archer.skills.busy_time, BowAttack.THUNDER_DRAW / archer.stats.attack_speed()))
	await _draw_through(archer, 40)
	archer.bow.cancel()
	archer.skills.busy = false
	expect("a draw cut short spends nothing and hurts no one", archer.powers.ready("thunderous_shot") and first.health == first.max_health
		and not archer.bow.thunder_power and not archer.bow.thunder_visual)

	# The shot.
	expect("it can be used again", archer.powers.activate("thunderous_shot", first.global_position))
	await _draw_through(archer, 220)
	var lost_first: float = first.max_health - first.health
	var lost_second: float = second.max_health - second.health
	expect("the bolt goes through the first and the second enemy", lost_first > 0.0 and lost_second > 0.0)
	expect("each takes the power's share of the bow's damage (never a crit, never a miss)", lost_first >= range.x * mult * 0.5 and lost_first <= range.y * mult + 1.0
		and lost_second >= range.x * mult * 0.5 and lost_second <= range.y * mult + 1.0)
	expect("the third, on the line with one life, dies of it", third.dead)
	expect("and dies an ordinary death: this power does not gib", get_tree().get_nodes_in_group("gibs").size() == gibs_before)
	expect("the ones it went through are stunned for the rank's time", first.stun_time > 0.0 and second.stun_time > 0.0
		and first.stun_time <= PowerDb.hero_value("thunderous_shot", "stun", "cutter") + 0.01)
	expect("what stood to the side is untouched", aside.health == aside.max_health and aside.stun_time <= 0.0)
	expect("and so is what stood beyond the bow's reach", beyond.health == beyond.max_health and beyond.stun_time <= 0.0)
	expect("it is spent at the release and recharges from damage dealt", not archer.powers.ready("thunderous_shot")
		and archer.powers.fraction("thunderous_shot") < 1.0)
	expect("the draw state is cleared", not archer.bow.thunder_power and not archer.bow.thunder_visual and archer.bow.thunder_fx == null)
	await get_tree().create_timer(1.2).timeout   # the lightning lingers for a second after the release
	expect("the bolt's visuals clean up", get_tree().get_nodes_in_group(ThunderousShotFx.GROUP).is_empty())

	# Nothing to spend while it recharges.
	expect("it will not draw again until recharged", not archer.powers.activate("thunderous_shot", first.global_position) and not archer.skills.busy)
	for foe in [first, second, aside, beyond]:
		if is_instance_valid(foe): foe.queue_free()
	archer.testing_disabled = false
	TownState.reset()
	await get_tree().process_frame
