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
	var last: AffixDef = AffixDb.get_def("strength_9")
	expect("of Hardiness is +1 STR at modifier level 2, of the Colossus +72 at 82", first.title == "of Hardiness" and first.level == 2 and is_equal_approx(first.value, 1.0)
		and last.title == "of the Colossus" and last.level == 82 and is_equal_approx(last.value, 72.0))
	expect("of the Lion is +237 life at 75; Excruciating +56% melee damage at 53", is_equal_approx(AffixDb.get_def("life_12").value, 237.0) and AffixDb.get_def("life_12").level == 75
		and AffixDb.get_def("melee_pct_8").title == "Excruciating" and is_equal_approx(AffixDb.get_def("melee_pct_8").value, 56.0))
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
	expect("a level 17 sword needs Melee 15", Items.requirement(heavy) == {"class": "melee", "level": 15}
		and not Items.meets_requirement(heavy, {"melee": 14}) and Items.meets_requirement(heavy, {"melee": 15}))
	expect("armour needs any class skill at that level", Items.meets_requirement(Items.build(ItemDb.get_def("iron_helm"), 20, 0), {"melee": 0, "ranged": 18}))
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
	expect("a shield's block is the hero's chance to block (%.2f)" % player.block_chance, is_equal_approx(player.block_chance, AffixDb.get_def("block_4").value / 100.0))
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
	stats.gear = {"life_steal": 5.0, "life_per_hit": 2.0}
	player.health = 10.0
	player._steal_life({"type": Combat.DamageType.PHYSICAL, "damage": 100.0})
	expect("life steal and life per hit heal on a blow (10 + 2 + 5% of 100)", is_equal_approx(player.health, 17.0))
	target.queue_free()
	stats.equipment = saved_equipment
	stats.bag = saved_bag
	TownState.reset()
	stats.refresh()
	await get_tree().process_frame
