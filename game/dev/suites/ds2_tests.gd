extends DevSuite
## Self-test: the Dungeon Siege II character and combat model (class skills, attributes, life and mana, the level-up, the save step;
## combat's armour, level gap, crits, avoidance and resistance; monsters by level; the hero's weapon and spell numbers).

## Class skills, attributes, life and mana; XP split over the class skills; the level-up; saving and the version 6 step.
func _test_class_skills() -> void:
	TownState.persist = false
	TownState.reset()
	expect("a class skill is 0 untrained and 1 at the XP of character level 2", HeroAttributes.class_level(0) == 0
		and HeroAttributes.class_level(299) == 0 and HeroAttributes.class_level(300) == 1 and HeroAttributes.class_level(HeroProgression.xp_for_level(30)) == 29)
	var fighter: Vector3 = HeroAttributes.attributes({"melee": 29})
	expect("a pure fighter at Melee 29 has 99 / 40 / 40 (DS2's design note: about 100 / 40 / 40 at level 30)", fighter == Vector3(99, 40, 40))
	var life: float = HeroAttributes.max_life(fighter)
	expect("and about DS2's 374 life (%.1f)" % life, absf(life - 374.0) < 5.0)
	expect("Ranged raises DEX most, magic INT most", HeroAttributes.attributes({"ranged": 10}).y > HeroAttributes.attributes({"ranged": 10}).x
		and HeroAttributes.attributes({"combat": 10}).z > HeroAttributes.attributes({"combat": 10}).x)
	var fresh: Vector3 = HeroAttributes.START
	expect("a new hero starts as DS2's human: 12 / 11 / 11, about 64 life and 55 mana", fresh == Vector3(12, 11, 11)
		and absf(HeroAttributes.max_life(fresh) - 64.1) < 0.05 and absf(HeroAttributes.max_mana(fresh) - 55.05) < 0.5)
	# The split.
	TownState.add_hero_xp(1000, false, {"melee": 300.0, "combat": 100.0})
	expect("XP is split over the class skills by the damage each did (750 Melee, 250 Combat Magic)", int(TownState.class_xp["melee"]) == 750
		and int(TownState.class_xp["combat"]) == 250 and TownState.hero_xp == 1000)
	TownState.add_hero_xp(400, false)
	expect("XP that no hit earned (a quest) goes to the class skill used most", int(TownState.class_xp["melee"]) == 1150 and int(TownState.class_xp["combat"]) == 250)
	var dummy: Enemy = _spawn_enemy(Vector3(30, 0, 30))
	dummy.aggro_range = 0.0
	dummy.max_health = 5000.0
	dummy.health = 5000.0
	await get_tree().process_frame
	var swing: Dictionary = Combat.resolve(player, dummy, 40.0, Combat.DamageType.PHYSICAL, false)
	swing["skill_id"] = "basic"
	dummy.receive(swing, player.global_position)
	var spell: Dictionary = Combat.resolve(player, dummy, 40.0, Combat.DamageType.FIRE, false)
	spell["skill_id"] = "fireball"
	dummy.receive(spell, player.global_position)
	expect("a monster remembers the hero's damage by class skill (a sword is Melee, Fireball Combat Magic)", float(dummy.hero_damage.get("melee", 0.0)) > 0.0
		and float(dummy.hero_damage.get("combat", 0.0)) > 0.0)
	dummy.queue_free()
	# The hero follows his class skills; the level-up restores him.
	TownState.dev_set_hero_level(30)
	await get_tree().process_frame
	expect("a level 30 pure fighter has about 374 life and fights at level 30 (%.0f)" % player.max_health, absf(player.max_health - 371.5) < 1.0
		and player.level == 30 and is_equal_approx(player.stats.strength, 99.0))
	player.health = 5.0
	player.stats.mana = 0.0
	player.stats.cooldowns["power"] = 3.0
	player.stats.brutal_reload_remaining = 100.0
	TownState.add_hero_xp(HeroProgression.xp_for_level(31) - TownState.hero_xp, false)
	expect("a level-up restores life and mana and recharges every power (DS2)", TownState.hero_level == 31 and is_equal_approx(player.health, player.max_health)
		and is_equal_approx(player.stats.mana, player.stats.max_mana) and player.stats.cooldowns.is_empty() and player.stats.brutal_reload_remaining <= 0.0)
	# Saving and the version 6 step.
	TownState.add_cutter_xp(777)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	var classes: Dictionary = TownState.class_xp.duplicate()
	TownState.reset()
	TownState.from_dict(TownState.migrate(saved))
	expect("class XP and Cutter's XP survive a save", TownState.cutter_xp == 777 and int(TownState.class_xp["melee"]) == int(classes["melee"]))
	var v6: Dictionary = TownState.migrate({"save_version": 6, "hero_xp": 2700, "hero_level": 10, "board": [{"name": "Cleanse", "xp": 120}]})
	expect("a version 6 level 10 hero is level 10 on DS2's table, all of it Melee, with Cutter level with him", int(v6["hero_level"]) == 10
		and int(v6["hero_xp"]) == HeroProgression.xp_for_level(10) and int(v6["class_xp"]["melee"]) == HeroProgression.xp_for_level(10)
		and int(v6["cutter_xp"]) == HeroProgression.xp_for_level(10) and int(v6["board"][0]["xp"]) == HeroProgression.STANDING_QUEST_XP)
	TownState.reset()
	await get_tree().process_frame

## DS2's combat rules and monster numbers, and the hero's weapon and spell.
func _test_ds2_combat() -> void:
	TownState.persist = false
	TownState.reset()
	await get_tree().process_frame
	expect("armour at or under 8 + 2L stops nothing; above it, the blow is cut in proportion", is_equal_approx(Combat.armor_factor(1, 10.0), 1.0)
		and is_equal_approx(Combat.armor_factor(1, 20.0), 0.5) and is_equal_approx(Combat.armor_factor(30, 136.0), 0.5))
	expect("the level gap: x0.75 at 5-6 below, x0.5 at 7-8, x0.25 beyond; nothing for the stronger side", is_equal_approx(Combat.level_gap_factor(1, 6), 0.75)
		and is_equal_approx(Combat.level_gap_factor(1, 8), 0.5) and is_equal_approx(Combat.level_gap_factor(1, 10), 0.25) and is_equal_approx(Combat.level_gap_factor(10, 1), 1.0))
	var target: Enemy = _spawn_enemy(Vector3(30, 0, 30))
	target.aggro_range = 0.0
	await get_tree().process_frame
	expect("a level 1 zombie has DS2's life, damage and armour (%.1f life, %.1f armour)" % [target.max_health, target.armor], target.level == 1
		and absf(target.max_health - 30.24) < 0.01 and absf(target.armor - MonsterScaling.armor(1)) < 0.01 and absf(target.average_hit() - 10.5248) < 0.01)
	expect("DS2's level 30 normal monster: about 1325 life, 157 a hit, 101 armour", absf(MonsterScaling.life(30, "normal") - 1324.8) < 0.1
		and absf(MonsterScaling.damage(30, "normal") - 157.52) < 0.1 and absf(MonsterScaling.armor(30) - 101.54) < 0.1)
	expect("tiers and roles: a miniboss outlives a strong one, a tank a normal one, a mage is frail", MonsterScaling.life(5, "miniboss") > MonsterScaling.life(5, "strong")
		and MonsterScaling.life(5, "normal", "tank") > MonsterScaling.life(5, "normal") and MonsterScaling.life(5, "normal", "magic") < MonsterScaling.life(5, "normal"))
	expect("the road opens at level 1 and deepens (threat 1.25 -> 1, 1.5 -> 4)", WorldThreat.monster_level(1.25) == 1 and WorldThreat.monster_level(1.5) == 4)
	# No accuracy roll; blocks need a chance to block; crits double.
	target.armor = 0.0
	target.dodge_chance = 0.0
	target.block_chance = 0.0
	var outcomes: Dictionary = {}
	for i in 200:
		var r: Dictionary = Combat.resolve(player, target, 10.0)
		outcomes[int(r["outcome"])] = true
	expect("with no dodge and no shield every blow lands (no accuracy roll)", not outcomes.has(Combat.Outcome.MISS) and not outcomes.has(Combat.Outcome.BLOCK))
	target.dodge_chance = 1.0
	expect("a dodge avoids the blow", int(Combat.resolve(player, target, 10.0)["outcome"]) == Combat.Outcome.MISS)
	expect("a blast cannot be dodged", int(Combat.resolve(player, target, 10.0, Combat.DamageType.PHYSICAL, false)["outcome"]) != Combat.Outcome.MISS)
	target.dodge_chance = 0.0
	var crit: Dictionary = Combat.resolve(player, target, 10.0, Combat.DamageType.PHYSICAL, true, 1.0, true)
	expect("a critical is 200%", int(crit["outcome"]) == Combat.Outcome.CRITICAL and is_equal_approx(float(crit["damage"]), 20.0))
	player.crit_chance = 1.0
	expect("a power never crits", int(Combat.resolve(player, target, 10.0, Combat.DamageType.PHYSICAL, true, 1.0, false, false)["outcome"]) == Combat.Outcome.HIT)
	player.crit_chance = 0.0
	player.fire_resist = 0.95
	var burned: Dictionary = Combat.resolve(target, player, 100.0, Combat.DamageType.FIRE, false)
	expect("a hero's resistance is capped at 80%", absf(float(burned["damage"]) - 20.0) < 0.01)
	player.fire_resist = 0.0
	# The hero's numbers.
	var base: Vector2 = player.stats.weapon_base_range()
	var longsword: Vector2 = player.stats.weapon_range(1.0)
	var bonus: float = 0.2 * maxf(player.stats.strength, 10.0)
	expect("a sword blow is the weapon plus DS2's 0.2 x STR (0.75 of it low, 1.25 high)", absf(longsword.x - (base.x + 0.75 * bonus)) < 0.01
		and absf(longsword.y - (base.y + 1.25 * bonus)) < 0.01)
	expect("a thrown weapon uses DEX instead", absf(player.stats.weapon_range(1.0, true).y - (base.y + 1.25 * 0.2 * maxf(player.stats.dexterity, 10.0))) < 0.01)
	var spell: Vector2 = player.stats.spell_range()
	expect("Fireball grows with INT, and so does its mana (DS2: 53 damage, 82 mana at INT 100)", absf((spell.x + spell.y) * 0.5 - (1.0 + 0.52 * player.stats.intelligence)) < 0.01
		and is_equal_approx(player.stats.mana_cost("fireball"), roundf(0.82 * player.stats.intelligence)))
	expect("the hero's armour is his gear's alone, and he regenerates 1% a second", is_equal_approx(player.stats.base_armor, 0.0)
		and is_equal_approx(HeroAttributes.REGEN_PER_SECOND, 0.01))
	target.queue_free()
	await get_tree().process_frame
