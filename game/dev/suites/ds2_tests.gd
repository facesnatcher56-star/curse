extends DevSuite
## Self-test: the Dungeon Siege II character and combat model (class skills, attributes, life and mana, the level-up, the save step;
## combat's armour, level gap, crits, avoidance and resistance; monsters by level; the hero's weapon and spell numbers).

## Class skills, attributes, life and mana; XP split over the class skills; the level-up; saving and the version 6 step.
func _test_class_skills() -> void:
	TownState.persist = false
	TownState.reset()
	expect("the extracted XP table includes exact intermediate levels", HeroProgression.xp_for_level(3) == 900 and HeroProgression.xp_for_level(4) == 2000 and HeroProgression.xp_for_level(6) == 7600)
	var old_table: PackedInt64Array = HeroProgression.legacy_table()
	var old_mid: int = old_table[2] + (old_table[3] - old_table[2]) / 2
	var v9: Dictionary = TownState.migrate({"save_version": 9, "hero_xp": old_mid, "cutter_xp": old_mid, "class_xp": {"melee": old_mid, "ranged": 0}})
	expect("version 9 XP migration preserves level and half-level progress for hero, class and Cutter",
		HeroProgression.level_for_xp(int(v9["hero_xp"])) == 3 and absf(HeroProgression.level_fraction(int(v9["hero_xp"])) - 0.5) < 0.002
		and int(v9["hero_xp"]) == int(v9["cutter_xp"]) and int(v9["class_xp"]["melee"]) == int(v9["hero_xp"]) and int(v9["class_xp"]["ranged"]) == 0)
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
	expect("the human's DS2 racial magic find is added to gear in actual loot rolls",
		is_equal_approx(player.stats.magic_find(), 10.0 + player.stats.gear_stat("magic_find"))
		and is_equal_approx(game.director.magic_find(), player.stats.magic_find()))
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
	player.stats.cooldowns["fireball"] = 3.0
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
	# The opening ramps from DS2's tutorial fighters that attack (level 2) into its first real region (jnglight), skipping the attack-less
	# Bracken Defender target dummies: levels 2 to 6, Haku Slayers are trivial level 3.
	expect("the road opens at level 2 and deepens to 6 (zones), and a level converts to its threat and back",
		WorldThreat.monster_level(TownDb.zone_at(10.0).base_threat) == 2 and WorldThreat.monster_level(TownDb.zone_at(300.0).base_threat) == 6
		and WorldThreat.monster_level(WorldThreat.threat_for_level(1)) == 1 and WorldThreat.monster_level(WorldThreat.threat_for_level(7)) == 7)
	var intro: Enemy = game.director.spawn_enemy(Vector3(28, 0, 30), "zombie", WorldThreat.threat_for_level(3), "trivial")
	intro.set_physics_process(false)
	target.set_physics_process(false)
	expect("an opening slayer-grade zombie is DS2 trivial melee at level 3: 15.3 life and its own damage and armour",
		intro.level == 3 and is_equal_approx(intro.max_health, MonsterScaling.life(3, "trivial")) and absf(intro.max_health - 15.3) < 0.01
		and is_equal_approx(intro.damage_min, 0.75 * MonsterScaling.damage(3, "trivial")) and is_equal_approx(intro.armor, MonsterScaling.armor(3))
		and intro.def.tier == "trivial" and is_equal_approx(intro.move_speed, 2.7))
	var hunter: Enemy = game.director.spawn_enemy(Vector3(26, 0, 30), "spitter", WorldThreat.threat_for_level(4), "weak")
	hunter.set_physics_process(false)
	expect("an opening spitter is a DS2 hunter: weak ranged at level 4, a thug-grade ghoul weak melee",
		hunter.level == 4 and hunter.def.tier == "weak" and is_equal_approx(hunter.max_health, MonsterScaling.life(4, "weak", "ranged")))
	expect("tier is local to the spawn, never mutating the shared zombie definition",
		EnemyDb.get_def("zombie").tier == "normal" and target.def.tier == "normal")
	var gate: Enemy = game.director.spawn_enemy(Vector3(24, 0, 30), "zombie", WorldThreat.threat_for_level(2))
	gate.set_physics_process(false)
	gate.use_tutorial_fighter_stats()
	gate.set_threat(WorldThreat.threat_for_level(2))
	expect("tutorial fighter overrides survive stat refresh without changing other zombies",
		gate.level == 0 and is_equal_approx(gate.max_health, 12.0) and is_equal_approx(gate.damage_min, 2.0)
		and is_equal_approx(gate.damage_max, 3.0) and is_equal_approx(gate.armor, 8.0)
		and EnemyDb.get_def("zombie").tier == "normal" and target.level == 1)
	gate.queue_free()
	intro.target = target
	intro.damage_min = 5.2
	intro.damage_max = 5.2
	intro.crit_chance = 0.0
	target.armor = 0.0
	target.dodge_chance = 0.0
	target.block_chance = 0.0
	var melee: MeleeBehavior = intro.behavior as MeleeBehavior
	for heavy in [false, true]:
		melee._begin()
		melee._heavy = heavy
		var before: float = target.health
		melee._tick_attack(intro.attack_time * melee._scale * (melee._hit_frac() + 0.01), 1.0)
		expect("%s melee contact uses the DS2 per-hit stat without an extra multiplier" % ("heavy" if heavy else "ordinary"),
			is_equal_approx(before - target.health, 5.2))
	intro.queue_free()
	target.health = target.max_health
	target.armor = MonsterScaling.armor(1)
	expect("DS2's level 30 normal monster: about 1325 life, 157 a hit, 101 armour", absf(MonsterScaling.life(30, "normal") - 1324.8) < 0.1
		and absf(MonsterScaling.damage(30, "normal") - 157.52) < 0.1 and absf(MonsterScaling.armor(30) - 101.54) < 0.1)
	expect("tier life uses the original GAS coefficients rather than rounded multipliers",
		is_equal_approx(MonsterScaling.life(1, "weak"), 20.16) and is_equal_approx(MonsterScaling.life(1, "strong"), 50.4)
		and is_equal_approx(MonsterScaling.life(1, "miniboss"), 110.88))
	expect("ranged, magic, rogue and tank hits use their own literal DS2 coefficients",
		is_equal_approx(MonsterScaling.damage(1, "trivial", "ranged"), 4.212)
		and is_equal_approx(MonsterScaling.damage(1, "normal", "ranged"), 8.424)
		and is_equal_approx(MonsterScaling.damage(1, "normal", "magic"), 10.504)
		and is_equal_approx(MonsterScaling.damage(1, "normal", "rogue"), 8.8088)
		and is_equal_approx(MonsterScaling.damage(1, "strong", "tank"), 17.992))
	expect("tiers and roles: a miniboss outlives a strong one, a tank a normal one, a mage is frail", MonsterScaling.life(5, "miniboss") > MonsterScaling.life(5, "strong")
		and MonsterScaling.life(5, "normal", "tank") > MonsterScaling.life(5, "normal") and MonsterScaling.life(5, "normal", "magic") < MonsterScaling.life(5, "normal"))
	expect("levels follow threat (1.25 -> 1, 1.5 -> 4)", WorldThreat.monster_level(1.25) == 1 and WorldThreat.monster_level(1.5) == 4)
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
	target.level = player.level
	target.armor = 20.0
	var fire_hit: Dictionary = Combat.resolve(player, target, 100.0, Combat.DamageType.FIRE, false, 1.0, false, false)
	expect("fire spells and powers pass through armour", is_equal_approx(float(fire_hit["damage"]), 50.0))
	target.fire_resist = 1.0
	expect("full fire immunity is zero, not the minimum damage floor", is_zero_approx(float(Combat.resolve(player, target, 100.0, Combat.DamageType.FIRE, false)["damage"])))
	target.fire_resist = 1.5
	var before_heal: float = target.max_health * 0.5
	target.health = before_heal
	target.receive(Combat.resolve(player, target, 10.0, Combat.DamageType.FIRE, false, 1.0, false, false), player.global_position)
	expect("fire absorption heals without hit recoil", target.health > before_heal and target.health <= target.max_health)
	target.fire_resist = 0.0
	target.armor = 0.0
	player.added_fire = 10.0
	player.added_fire_max = 10.0
	expect("power damage includes amplified added fire, without criticals", is_equal_approx(float(Combat.resolve(player, target, 20.0, Combat.DamageType.PHYSICAL, false, 1.0, true, false, 15.0)["damage"]), 450.0))
	player.added_fire = 0.0
	player.added_fire_max = 0.0
	player.powers.reload_remaining = {"whirling_strike": 100.0, "detonation": 100.0}
	player.stats.brutal_reload_remaining = 100.0
	player.on_party_damage(25.0, "detonation")
	expect("party damage recharges other powers but cannot recharge itself", is_equal_approx(float(player.powers.reload_remaining["whirling_strike"]), 75.0)
		and is_equal_approx(float(player.powers.reload_remaining["detonation"]), 100.0) and is_equal_approx(player.stats.brutal_reload_remaining, 75.0))
	target.apply_burn(10.0, 2.0, true, player, "detonation")
	target._tick_burn(0.5)
	expect("power burns recharge other powers, not their source", is_equal_approx(float(player.powers.reload_remaining["whirling_strike"]), 70.0)
		and is_equal_approx(float(player.powers.reload_remaining["detonation"]), 100.0))
	target.stop_burning()
	player.powers.reset()
	player.stats.brutal_reload_remaining = 0.0
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

## Dungeon Siege II's items: the weapon and armour curves, the modifier tiers, how many a magic or rare item carries, the equip
## requirement, the drop windows and magic find, and what the gear does to the hero (attributes, life, armour, block, rings, two hands,
## sets, added fire, life steal).
func _test_ds2_items() -> void:
	TownState.persist = false
	TownState.reset()
	await get_tree().process_frame
	# Curves.
	var longsword: Dictionary = Items.build(ItemDb.get_def("longsword"), 30, Items.Rarity.NORMAL)
	expect("a level 30 one-handed sword hits 19.2-32.0 (DS2: 3.4 + 0.74L, x0.75 / x1.25)", absf(float(longsword["stats"]["min"]) - 19.2) < 0.01
		and absf(float(longsword["stats"]["max"]) - 32.0) < 0.01)
	var great: Dictionary = Items.build(ItemDb.get_def("greatsword"), 30, Items.Rarity.NORMAL)
	expect("a two-handed sword follows the two-handed curve (5.2 + 1.2L)", absf((float(great["stats"]["min"]) + float(great["stats"]["max"])) * 0.5 - 41.2) < 0.01)
	var falchion: Dictionary = Items.build(ItemDb.get_def("falchion"), 30, Items.Rarity.NORMAL)
	expect("a faster blade hits for less (its swing time, as DS2)", float(falchion["stats"]["max"]) < float(longsword["stats"]["max"]))
	var fighter_set: float = 0.0
	for id in ["mail_hauberk", "iron_helm", "iron_gauntlets", "iron_greaves"]:
		fighter_set += float(Items.build(ItemDb.get_def(id), 30, Items.Rarity.NORMAL)["stats"]["armor"])
	expect("a full level 30 fighter set (no shield) is exactly 16 + 4L = 136 armour (%.1f)" % fighter_set, absf(fighter_set - 136.0) < 0.01)
	expect("ranger leather is 0.8 of it, a shield 0.2", is_equal_approx(float(Items.build(ItemDb.get_def("leather_jerkin"), 30, 0)["stats"]["armor"]), 0.8 * 0.5 * 136.0)
		and is_equal_approx(float(Items.build(ItemDb.get_def("buckler"), 30, 0)["stats"]["armor"]), 0.2 * 136.0))
	var levels_ok: bool = true
	for d in ItemDb.all().values():
		var sorted_levels: Array[int] = (d as ItemDef).levels.duplicate()
		sorted_levels.sort()
		levels_ok = levels_ok and (d as ItemDef).levels.size() == 5 and (d as ItemDef).levels == sorted_levels
	expect("every base has five item levels, lowest first", levels_ok)
	# Modifier tiers (the reference's first and last of a family).
	var first: AffixDef = AffixDb.get_def("strength_1")
	var fortunate: Dictionary = Items.build(ItemDb.get_def("signet"), 20, Items.Rarity.MAGIC, ["magic_find_1"])
	var found: float = float(Items.mods_of(fortunate)["magic_find"])
	expect("Fortunate rolls DS2's 4–6 range and retains its roll through save/load", found >= 4.0 and found <= 6.0
		and is_equal_approx(float(Items.mods_of(Items.from_save(Items.to_save(fortunate)))["magic_find"]), found))
	expect("source affix middle tiers are not interpolated", AffixDb.get_def("strength_2").level == 10 and is_equal_approx(AffixDb.get_def("strength_2").value, 3.0))
	expect("Scorching is the original +2–4 fire damage range at level 15", AffixDb.get_def("fire_added_1").title == "Scorching" and AffixDb.get_def("fire_added_1").level == 15
		and is_equal_approx(AffixDb.get_def("fire_added_1").value, 2.0) and is_equal_approx(AffixDb.get_def("fire_added_1").max_value, 4.0))
	expect("DS2 mana affixes have their original tiers and weapon-only restriction",
		AffixDb.get_def("mana_steal_1").level == 6 and is_equal_approx(AffixDb.get_def("mana_steal_1").value, 3.0)
		and AffixDb.get_def("mana_per_hit_1").level == 12 and is_equal_approx(AffixDb.get_def("mana_per_hit_1").value, 2.0)
		and AffixDb.get_def("mana_steal_1").slots == ["weapon"] and AffixDb.is_percent("mana_steal") and not AffixDb.is_percent("mana_per_hit"))
	var mana_weapon: Dictionary = Items.build(ItemDb.get_def("longsword"), 30, Items.Rarity.MAGIC, ["mana_steal_1", "mana_per_hit_1"])
	expect("mana modifiers survive an item save/load", Items.mods_of(Items.from_save(Items.to_save(mana_weapon))) == {"mana_steal": 3.0, "mana_per_hit": 2.0})
	var last: AffixDef = AffixDb.get_def("strength_9")
	expect("of Hardiness is +1 STR at modifier level 2, of the Colossus +72 at 82", first.title == "of Hardiness" and first.level == 2 and is_equal_approx(first.value, 1.0)
		and last.title == "of Colossus" and last.level == 82 and is_equal_approx(last.value, 72.0))
	expect("of the Lion is +237 life at 75; Excruciating +56% melee damage at 53", is_equal_approx(AffixDb.get_def("life_12").value, 237.0) and AffixDb.get_def("life_12").level == 75
		and AffixDb.get_def("melee_pct_8").title == "Excrutiating" and is_equal_approx(AffixDb.get_def("melee_pct_8").value, 56.0))
	var counts_ok: bool = true
	var families_ok: bool = true
	var names_ok: bool = true
	for i in 150:
		var magic: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.MAGIC, 40)
		var rare: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 40)
		counts_ok = counts_ok and (magic["mods"] as Array).size() >= 1 and (magic["mods"] as Array).size() <= 2 \
			and (rare["mods"] as Array).size() >= 3 and (rare["mods"] as Array).size() <= 4
		for item in [magic, rare]:
			var seen: Dictionary = {}
			for id in item["mods"]:
				var family: String = AffixDb.get_def(String(id)).family
				families_ok = families_ok and not seen.has(family) and AffixDb.get_def(String(id)).slots.has(Items.KINDS[int(item["slot"])])
				seen[family] = true
		if (magic["mods"] as Array).size() == 2:
			names_ok = names_ok and AffixDb.get_def(String(magic["mods"][0])).position != AffixDb.get_def(String(magic["mods"][1])).position
	expect("a magic item has 1 or 2 modifiers, a rare 3 or 4", counts_ok)
	expect("never two of one family, and only kinds the item may carry", families_ok)
	expect("a two-modifier magic item has a prefix and a suffix", names_ok)
	expect("jewellery is never plain", int(Items.make(Items.Slot.RING, Items.Rarity.NORMAL, 10)["rarity"]) == Items.Rarity.MAGIC)
	# Requirement: class skill >= item level - 2.
	var heavy: Dictionary = Items.build(ItemDb.get_def("longsword"), 17, Items.Rarity.NORMAL)
	expect("a level 17 sword needs Melee 15", Items.requirement(heavy) == {"class": "melee", "level": 15, "passive": ""}
		and not Items.meets_requirement(heavy, {"melee": 14}) and Items.meets_requirement(heavy, {"melee": 15}))
	var ranger_cap: Dictionary = Items.build(ItemDb.get_def("leather_cap"), 20, 0)
	expect("armour needs its own class's skill (a ranger cap Ranged, a fighter helm Melee)", Items.meets_requirement(ranger_cap, {"melee": 40, "ranged": 18})
		and not Items.meets_requirement(ranger_cap, {"melee": 40, "ranged": 17}) and not Items.meets_requirement(Items.build(ItemDb.get_def("iron_helm"), 20, 0), {"melee": 17, "ranged": 40}))
	expect("jewellery needs the character level", Items.meets_requirement(Items.build(ItemDb.get_def("signet"), 34, 1), {"uber": 32})
		and not Items.meets_requirement(Items.build(ItemDb.get_def("signet"), 34, 1), {"uber": 31, "melee": 60}))
	expect("a new hero cannot wear it: it stays off and he says why", player.stats.equip(heavy) == null and player.stats.equipment.get(Items.Slot.WEAPON) != heavy)
	expect("and the card says so, as a worse line", Items.compare(heavy, player.stats.equipment.get(Items.Slot.WEAPON))[0]["sign"] == -1)
	# Drops.
	var windows_ok: bool = true
	for i in 300:
		var drop: Dictionary = Items.item_of_kind("item", 30, Items.DROPS["normal"]["window"])
		windows_ok = windows_ok and int(drop["level"]) >= 25 and int(drop["level"]) <= 31
	expect("a normal monster's drop is a base variant within its level -5 ... +1", windows_ok)
	var plain_rare: int = 0
	var lucky_rare: int = 0
	var nothing: int = 0
	for i in 3000:
		var a: Dictionary = Items.roll_drop(30, "strong", 0.0)
		var b: Dictionary = Items.roll_drop(30, "strong", 300.0)
		nothing += 1 if a.is_empty() else 0
		plain_rare += 1 if not a.is_empty() and int(a["rarity"]) >= Items.Rarity.RARE else 0
		lucky_rare += 1 if not b.is_empty() and int(b["rarity"]) >= Items.Rarity.RARE else 0
	expect("a strong monster drops no item about 83%% of the time (DS2's item columns: %d of 3000)" % nothing, nothing > 2380 and nothing < 2580)
	expect("magic find makes rares, uniques and sets more likely (%d vs %d)" % [lucky_rare, plain_rare], lucky_rare > plain_rare * 2)
	# The gear on the hero.
	TownState.dev_set_hero_level(40)
	TownState.passive_ranks = {"overbear": 1, "barricade": 1}   # (DS2: a two-handed weapon needs Overbear, a shield Barricade)
	await get_tree().process_frame
	var stats: PlayerStats = player.stats
	var saved_equipment: Dictionary = stats.equipment.duplicate()
	var saved_bag: Array[Dictionary] = stats.bag.duplicate()
	stats.equipment = {}
	stats.refresh()
	var str_before: float = stats.strength
	var life_before: float = player.max_health
	var ring: Dictionary = Items.build(ItemDb.get_def("signet"), 34, Items.Rarity.MAGIC, ["strength_9", "life_12"])
	stats.equip(ring, false)
	expect("a ring of +72 STR and +237 life adds them (life from its STR too)", is_equal_approx(stats.strength, str_before + 72.0)
		and player.max_health > life_before + 237.0 + 100.0)
	var second: Dictionary = Items.build(ItemDb.get_def("band"), 25, Items.Rarity.MAGIC, ["dexterity_1"])
	stats.equip(second, false)
	expect("a second ring goes on the other hand", stats.equipment.get(Items.Slot.RING) == ring and stats.equipment.get(Items.Slot.RING2) == second)
	var shield: Dictionary = Items.build(ItemDb.get_def("buckler"), 28, Items.Rarity.MAGIC, ["block_4"])
	stats.equip(shield, false)
	expect("a shield's block (and Barricade's) is the hero's chance to block (%.2f)" % player.block_chance, is_equal_approx(player.block_chance, (AffixDb.get_def("block_4").value + 2.0) / 100.0))
	var off: Variant = stats.equip(Items.build(ItemDb.get_def("greatsword"), 26, Items.Rarity.NORMAL), false)
	expect("a two-handed weapon takes the shield off (and blocking with it)", off != null and (off as Array).has(shield) and not stats.equipment.has(Items.Slot.SHIELD)
		and is_equal_approx(player.block_chance, 0.0))
	var body: Dictionary = Items.build(ItemDb.get_def("mail_hauberk"), 30, Items.Rarity.MAGIC, ["armor_pct_8"])
	stats.equip(body, false)
	expect("armour is the pieces' armour x (1 + armour %%) (%.1f)" % player.armor, is_equal_approx(player.armor, 68.0 * (1.0 + AffixDb.get_def("armor_pct_8").value / 100.0)))
	stats.equipment = {}
	for id in ["roadwarden_helm", "roadwarden_gauntlets"]:
		stats.equip(Items.unique(UniqueDb.get_unique(id)), false)
	expect("two pieces of a set give its two-piece bonus", is_equal_approx(stats.gear_stat("armor"), 10.0 + 20.0))
	stats.equipment = {}
	stats.refresh()
	# Added fire and life steal.
	var target: Enemy = _spawn_enemy(Vector3(30, 0, 30))
	target.aggro_range = 0.0
	target.armor = 0.0
	target.dodge_chance = 0.0
	target.block_chance = 0.0
	target.level = player.level
	await get_tree().process_frame
	player.added_fire = 10.0
	expect("added fire lands on a physical blow (DS2: before armour)", is_equal_approx(float(Combat.resolve(player, target, 20.0)["damage"]), 30.0))
	player.added_fire = 0.0
	stats.gear = {"life_steal": 5.0, "life_per_hit": 2.0, "mana_steal": 3.0, "mana_per_hit": 2.0}
	player.health = 10.0
	stats.mana = 0.0
	player._steal_resources({"type": Combat.DamageType.PHYSICAL, "damage": 100.0})
	expect("life steal and life per hit heal on a blow (10 + 2 + 5% of 100)", is_equal_approx(player.health, 17.0))
	expect("mana steal and mana per hit restore mana (2 + 3% of 100)", is_equal_approx(stats.mana, 5.0))
	for invalid_hit in [{"type": Combat.DamageType.FIRE, "damage": 100.0},
			{"type": Combat.DamageType.PHYSICAL, "damage": 0.0},
			{"type": Combat.DamageType.PHYSICAL, "damage": 100.0, "skill_id": "reflect"},
			{"type": Combat.DamageType.PHYSICAL, "damage": 100.0, "outcome": Combat.Outcome.BLOCK}]:
		player._steal_resources(invalid_hit)
	expect("spells, zero-damage hits, reflection and blocks do not steal resources", is_equal_approx(stats.mana, 5.0) and is_equal_approx(player.health, 17.0))
	player._steal_resources({"type": Combat.DamageType.RANGED, "damage": 100.0})
	expect("ranged weapon hits also return resources", is_equal_approx(stats.mana, 10.0) and is_equal_approx(player.health, 24.0))
	stats.mana = stats.max_mana - 1.0
	player._steal_resources({"type": Combat.DamageType.PHYSICAL, "damage": 100.0})
	expect("mana steal cannot exceed maximum mana", is_equal_approx(stats.mana, stats.max_mana))
	target.queue_free()
	stats.equipment = saved_equipment
	stats.bag = saved_bag
	TownState.reset()
	stats.refresh()
	await get_tree().process_frame

## DS2's skill points and passive trees: a point a level (and a human's two), the tiers and prerequisites, the rank cap, buying for good,
## a save, the stance requirements (Overbear for two hands, Barricade for a shield), and what the passives do to the hero.
func _test_skill_tree() -> void:
	TownState.persist = false
	TownState.reset()
	await get_tree().process_frame
	expect("a new hero has a human's two skill points", TownState.skill_points_total() == 2 and TownState.skill_points_left() == 2)
	TownState.dev_set_hero_level(10)
	expect("one point a level after that (11 at level 10)", TownState.skill_points_left() == 11)
	expect("a passive opens at its tree's class level (Toughness at Melee 12; a level 10 fighter is Melee 9)",
		TownState.passive_blocker("toughness") == "Needs Melee 12" and TownState.passive_blocker("fortitude") == "")
	expect("and may need another first (Barricade needs Fortitude 1)", TownState.passive_blocker("barricade") == "Needs Fortitude 1")
	TownState.dev_set_hero_level(30)
	expect("Smite needs Overbear and Toughness first (DS2)", TownState.passive_blocker("smite") == "Needs Overbear 1"
		and TownState.passive_blocker("smite", {"overbear": 1}) == "Needs Toughness 1")
	expect("a staged rank counts for what comes after it", TownState.passive_blocker("barricade", {"fortitude": 1}) == "")
	var life_before: float = player.max_health
	expect("buying ranks spends points and keeps them", TownState.buy_passives({"fortitude": 20, "barricade": 1}) and TownState.passive_rank("fortitude") == 20
		and TownState.skill_points_left() == 31 - 21)
	await get_tree().process_frame
	expect("Fortitude 20 is +45%% life (%.0f -> %.0f)" % [life_before, player.max_health], absf(player.max_health - life_before * 1.45) < 1.0)
	expect("no rank past 20", TownState.passive_blocker("fortitude") == "At its highest rank")
	expect("ranks follow DS2's own tables, not a straight line (Fortitude 10 is +32%, Deadly Strike 2 is 242%, Smite 6 stuns 1.25 s)",
		is_equal_approx(PassiveDb.get_def("fortitude").value(10), 32.0) and is_equal_approx(PassiveDb.get_def("deadly_strike").value(2), 242.0)
		and is_equal_approx(PassiveDb.get_def("smite").extra_value("stun", 6), 1.25)
		and is_equal_approx(PassiveDb.get_def("barricade").extra_value("shield_armor", 2), 35.0))
	expect("a purchase that breaks a rule buys nothing", not TownState.buy_passives({"rebuke": 1}) and TownState.passive_rank("rebuke") == 0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.reset()
	TownState.from_dict(TownState.migrate(saved))
	expect("ranks survive a save", TownState.passive_rank("fortitude") == 20 and TownState.passive_rank("barricade") == 1)
	expect("a version 8 save starts with nothing bought", (TownState.migrate({"save_version": 8})["passive_ranks"] as Dictionary).is_empty())
	# Stances.
	var great: Dictionary = Items.build(ItemDb.get_def("greatsword"), 6, Items.Rarity.NORMAL)
	var shield: Dictionary = Items.build(ItemDb.get_def("buckler"), 6, Items.Rarity.NORMAL)
	var bare: Dictionary = TownState.passive_ranks.duplicate()
	TownState.passive_ranks = {}
	expect("a two-handed weapon needs Overbear and a shield Barricade (DS2)", not Items.hero_can_wear(great) and not Items.hero_can_wear(shield)
		and Items.requirement_text(great).contains("Overbear") and Items.requirement_text(shield).contains("Barricade"))
	TownState.passive_ranks = bare
	TownState.buy_passives({"critical_strike": 1, "overbear": 1})
	expect("with Overbear the greatsword can be wielded, with Barricade the buckler", Items.hero_can_wear(great) and Items.hero_can_wear(shield))
	# Effects.
	var stats: PlayerStats = player.stats
	TownState.passive_ranks["critical_strike"] = 20
	TownState.passive_ranks["deadly_strike"] = 20
	TownState.passive_ranks["toughness"] = 20
	TownState.passive_ranks["dodge"] = 20
	TownState.passive_ranks["survival"] = 20
	TownState.passive_ranks["brilliance"] = 20
	var mana_plain: float = player.stats.max_mana
	stats.refresh()
	expect("Critical Strike 20 is a 50% crit, Deadly Strike 20 a 350% one", is_equal_approx(player.crit_chance, 0.5) and is_equal_approx(player.crit_mult, 3.5))
	expect("Toughness 20 takes 26% off physical blows, Dodge 20 is 40%, Survival 20 +60% fire resistance", is_equal_approx(player.toughness, 0.26)
		and is_equal_approx(player.dodge_chance, 0.4) and is_equal_approx(player.fire_resist, 0.6))
	expect("Brilliance 20 is +150% mana", absf(stats.max_mana - mana_plain * 2.5) < 1.0)
	var spell_before: Vector2 = stats.spell_range()
	TownState.passive_ranks["devastation"] = 20
	expect("Devastation 20 is +60% combat magic damage", absf(stats.spell_range().y - spell_before.y * 1.6) < 0.01)
	var target: Enemy = _spawn_enemy(Vector3(30, 0, 30))
	target.aggro_range = 0.0
	await get_tree().process_frame
	target.armor = 0.0
	target.level = player.level
	player.dodge_chance = 0.0
	var hit: Dictionary = Combat.resolve(target, player, 100.0, Combat.DamageType.PHYSICAL, false)
	expect("the toughened hero takes 74 of a 100 blow", is_equal_approx(float(hit["damage"]), 74.0))
	target.queue_free()
	TownState.reset()
	stats.refresh()
	await get_tree().process_frame

## DS2's powers as data: all of them load and every number evaluates; a power's rank comes from passive ranks (nothing spent); Brutal
## Attack needs Critical Strike and grows with its rank and Melee; Cutter's Take Aim grows with his Ranged.
func _test_powers() -> void:
	TownState.persist = false
	TownState.reset()
	await get_tree().process_frame
	expect("all 27 of DS2's hero powers are data (%d)" % PowerDb.all().size(), PowerDb.all().size() == 27)
	var numbers_ok: bool = true
	var shaped: bool = true
	for def in PowerDb.all().values():
		var power := def as PowerDef
		shaped = shaped and power.ranks.size() == 3 and power.recharge in [12.0, 21.0, 35.0, 60.0]
		for key in power.values:
			for rank in [1, 2, 3]:
				var v: float = power.value(String(key), rank, {"melee": 20, "ranged": 20, "combat": 20, "nature": 20})
				numbers_ok = numbers_ok and v > 0.0 and is_finite(v)
	expect("each has three ranks and DS2's 12 / 21 / 35 / 60 second recharge", shaped)
	expect("every value of every rank evaluates", numbers_ok)
	expect("the ones Curse cannot do yet say what they need", PowerDb.get_def("waves_of_force").needs == "dual wielding"
		and PowerDb.get_def("brutal_attack").needs == "")
	expect("no rank without its passives: Brutal Attack needs Critical Strike 1", PowerDb.hero_rank("brutal_attack") == 0
		and not player.stats.can_use("brutal_attack"))
	var paths_present: bool = true
	for id in PowerController.LIVE:
		for rank in PowerDb.get_def(id).ranks:
			for required_passive in rank:
				paths_present = paths_present and PassiveDb.get_def(String(required_passive)) != null
	expect("every implemented power rank has its prerequisite passives available", paths_present)
	var recharge: float = player.stats.power_recharge_damage(21.0)
	TownState.passive_ranks["fierce_renewal"] = 20
	TownState.passive_ranks["cunning_renewal"] = 20
	expect("renewal affects every power of its own tree", is_equal_approx(player.stats.power_recharge_damage(21.0, "melee"), recharge / 1.3)
		and is_equal_approx(player.stats.power_recharge_damage(21.0, "ranged"), recharge / 1.3) and is_equal_approx(player.stats.power_recharge_damage(21.0, "combat"), recharge))
	TownState.passive_ranks.erase("fierce_renewal")
	TownState.passive_ranks.erase("cunning_renewal")
	TownState.dev_set_hero_level(20)
	TownState.passive_ranks["critical_strike"] = 1
	var melee: float = float(HeroAttributes.levels_from_xp(TownState.class_xp)["melee"])
	expect("with Critical Strike 1 it is rank 1: 1500 + 25 x Melee %% (%.1fx)" % player.stats.brutal_mult(), PowerDb.hero_rank("brutal_attack") == 1
		and is_equal_approx(player.stats.brutal_mult(), (1500.0 + 25.0 * melee) / 100.0))
	TownState.passive_ranks["critical_strike"] = 8
	expect("Critical Strike 8 opens rank 3: 2000 + 60 x Melee %", PowerDb.hero_rank("brutal_attack") == 3
		and is_equal_approx(player.stats.brutal_mult(), (2000.0 + 60.0 * melee) / 100.0))
	TownState.cutter_xp = HeroProgression.xp_for_level(11)
	expect("Cutter's Take Aim grows with his Ranged level (rank 1)", is_equal_approx(ArcherCompanion.take_aim_mult(), (1500.0 + 25.0 * 10.0) / 100.0))
	expect("Provoke's ranks need Barricade (DS2's aegis)", PowerDb.get_def("provoke").ranks[0].has("barricade"))
	TownState.reset()
	await get_tree().process_frame

## The DS2 powers that play: each opens with its passives and the right weapon, does what DS2's does, and recharges from damage dealt.
func _test_live_powers() -> void:
	TownState.persist = false
	TownState.reset()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	TownState.dev_set_hero_level(30)
	var powers: PowerController = player.powers
	powers.reset()
	player.global_position = Vector3(30, 0, 30)
	player.reset_physics_interpolation()
	expect("a power that is not open says so and does nothing", powers.blocker("whirling_strike") == "Whirling Strike is not open yet"
		and not powers.activate("whirling_strike", player.global_position))
	TownState.passive_ranks = {"critical_strike": 8, "fortitude": 8, "smite": 1, "overbear": 1, "barricade": 1, "dodge": 5, "survival": 3,
		"devastation": 2, "searing_flames": 8, "ignite": 1}
	player.stats.refresh()
	var spawn: Callable = func(offset: Vector3) -> Enemy:
		var e: Enemy = _spawn_enemy(player.global_position + offset)
		e.aggro_range = 0.0
		e.max_health = 50000.0
		e.health = e.max_health
		e.dodge_chance = 0.0
		e.block_chance = 0.0
		return e
	# Whirling Strike.
	var ring: Array[Enemy] = [spawn.call(Vector3(1.5, 0, 0)), spawn.call(Vector3(-1.5, 0, 0)), spawn.call(Vector3(0, 0, 1.8))]
	var far: Enemy = spawn.call(Vector3(0, 0, 9))
	await get_tree().process_frame
	expect("Whirling Strike goes off with a melee weapon", powers.activate("whirling_strike", player.global_position))
	expect("it hits and stuns everything within reach, nothing beyond", ring.all(func(e: Enemy) -> bool: return e.health < e.max_health and e.stun_time > 0.0)
		and is_equal_approx(far.health, far.max_health))
	expect("then it must recharge from damage dealt", not powers.ready("whirling_strike") and powers.fraction("whirling_strike") < 0.05)
	powers.gain(powers.required("whirling_strike"))
	expect("dealing its recharge's worth of damage readies it again", powers.ready("whirling_strike"))
	# War Cry.
	for e in ring:
		e.stun_time = 0.0
	var ahead: Enemy = ring[2]
	var behind: Enemy = spawn.call(Vector3(0, 0, -2.0))
	expect("War Cry goes off", powers.activate("war_cry", player.global_position + Vector3(0, 0, 5)))
	expect("enemies in front lose 35% armour and run, those behind do not", is_equal_approx(ahead.armor_shred, 0.35) and ahead.fear_time > 0.0
		and is_equal_approx(behind.armor_shred, 0.0) and is_equal_approx(behind.fear_time, 0.0))
	expect("and the hero's next 8 blows are critical", player.forced_crits == 8
		and int(Combat.resolve(player, ahead, 10.0)["outcome"]) == Combat.Outcome.CRITICAL and player.forced_crits == 7)
	player.forced_crits = 0
	# Provoke needs a shield.
	expect("Provoke needs a shield", powers.blocker("provoke") == "Provoke needs a shield")
	player.stats.wear(Items.Slot.SHIELD, Items.build(ItemDb.get_def("buckler"), 6, Items.Rarity.NORMAL))
	var armor_before: float = player.armor
	expect("with one it goes off and his armour rises 25%%", powers.activate("provoke", player.global_position) and absf(player.armor - armor_before * 1.25) < 0.5)
	player.stats.unequip(Items.Slot.SHIELD)
	# Staggering Blow needs two hands and rides the next blow.
	expect("Staggering Blow needs a two-handed weapon", powers.blocker("staggering_blow") == "Staggering Blow needs a two-handed weapon")
	var saved_weapon: Variant = player.stats.equipment.get(Items.Slot.WEAPON)
	player.stats.wear(Items.Slot.WEAPON, Items.build(ItemDb.get_def("greatsword"), 6, Items.Rarity.NORMAL))
	expect("it arms, and is not spent until a blow lands", powers.activate("staggering_blow", player.global_position) and powers.staggering_armed and powers.ready("staggering_blow"))
	for e in ring:
		e.stun_time = 0.0
	powers.release_staggering(ring[0])
	expect("the blow's shockwave stuns those around for 6 s", ring[0].stun_time >= 5.5 and not powers.staggering_armed and not powers.ready("staggering_blow"))
	if saved_weapon != null:
		player.stats.wear(Items.Slot.WEAPON, saved_weapon)
	# Repulse.
	expect("Repulse goes off", powers.activate("repulse", player.global_position))
	var intruder: Enemy = spawn.call(Vector3(1.0, 0, -1.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("an enemy that comes close is thrown back and stunned", intruder.knock.length() > 3.0 and intruder.stun_time > 0.0)
	# Silence.
	expect("Silence goes off on the area under the cursor", powers.activate("silence", far.global_position) and far.silence_time >= 15.0)
	# Fire.
	for e in [ring[0], ring[1]]:
		e.stop_burning()
	var hp: float = ring[0].health
	expect("Flame Nexus burns everything around", powers.activate("flame_nexus", player.global_position) and ring[0].health < hp and ring[0].burn_time > 0.0)
	hp = far.health
	expect("Detonation blasts the target area", powers.activate("detonation", far.global_position) and far.health < hp and far.burn_time > 0.0)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	TownState.reset()
	powers.reset()
	player.stats.refresh()
	await get_tree().process_frame
