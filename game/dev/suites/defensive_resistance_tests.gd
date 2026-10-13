extends DevSuite
## Approved resistance layering through equipped items and the real resolve/receive path.

func _test_defensive_resistances() -> void:
	TownState.persist = false
	var hero := player
	hero.set_physics_process(false)
	var saved_character_data: Dictionary = hero.character.to_dict()
	var saved_health: float = hero.health
	var saved_max_health: float = hero.max_health
	var saved_mana: float = hero.stats.mana
	var enemy := _spawn_enemy(Vector3(28, 0, 28))
	enemy.set_physics_process(false)
	_plain(hero)
	_plain(enemy)
	hero.stats.equipment.clear()
	hero.stats.refresh()
	hero.health = 1000.0
	hero.max_health = 1000.0
	enemy.max_health = 10000.0
	enemy.health = 10000.0

	# Source catalog imports use the actual resistance values and authored requirements.
	var traveler := Items.unique(UniqueDb.get_unique("traveler_robe"))
	var oakcase := Items.unique(UniqueDb.get_unique("oakcase_carved_tunic"))
	var forest := Items.unique(UniqueDb.get_unique("forest_shroud"))
	var amulet := Items.unique(UniqueDb.get_unique("heros_amulet"))
	expect("four representative catalog resistance items are available", not traveler.is_empty() and not oakcase.is_empty()
		and not forest.is_empty() and not amulet.is_empty())
	expect("catalog resistance item retains source requirement", Items.requirement_expression(traveler) == "combat magic:#item_level-2.0")

	# Independent physical/attack-type overlaps, additive and capped only once.
	hero.stats.wear(Items.Slot.ARMOR, traveler)
	var melee_piece := Items.build(ItemDb.get_def("iron_helm"), 20, Items.Rarity.MAGIC, ["melee_resist_1"])
	var melee_piece_2 := Items.build(ItemDb.get_def("iron_gauntlets"), 20, Items.Rarity.MAGIC, ["melee_resist_1"])
	hero.stats.wear(Items.Slot.HELM, melee_piece)
	hero.stats.wear(Items.Slot.GLOVES, melee_piece_2)
	hero.armor = 0.0
	hero.max_health = 1000.0
	hero.health = 1000.0
	expect("equipment aggregation refreshes physical plus two melee sources", is_equal_approx(hero.physical_resist, 0.03)
		and is_equal_approx(hero.melee_resist, 0.10)
		and is_equal_approx(Combat.effective_resistance(hero, Combat.DamageType.PHYSICAL), 0.13))
	var old_hp: float = hero.health
	var melee := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	hero.receive(melee, enemy.global_position)
	expect("melee physical overlap mitigates through resolve and receive", is_equal_approx(old_hp - hero.health, 87.0))

	hero.stats.wear(Items.Slot.HELM, forest)
	hero.armor = 0.0
	expect("replacement removes one melee source and adds ranged resistance immediately", is_equal_approx(hero.melee_resist, 0.05)
		and is_equal_approx(hero.ranged_resist, 0.10))
	var ranged := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.RANGED, false, 1.0, false, false)
	expect("ranged hit uses physical plus ranged and excludes melee resistance", is_equal_approx(float(ranged.damage), 87.0))
	var melee_after_swap := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	expect("melee hit excludes ranged resistance and keeps its remaining melee source", is_equal_approx(float(melee_after_swap.damage), 92.0))

	# Elemental weapon bonus is reduced first; the attack resistance then applies to the combined hit.
	hero.fire_resist = 0.20
	hero.physical_resist = 0.10
	hero.melee_resist = 0.30
	enemy.added_fire = 10.0
	enemy.added_fire_max = 10.0
	var mixed := Combat.resolve(enemy, hero, 10.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	expect("added fire is cut by fire resistance before combined melee resistance", is_equal_approx(float(mixed.damage), 10.8)
		and is_equal_approx(float((mixed.added_elements as Dictionary).fire), 8.0))
	enemy.added_fire = 0.0
	enemy.added_fire_max = 0.0

	# Magical and elemental protection combine in one effective cap; weapon resistance does not leak into magic.
	hero.stats.equipment.clear()
	hero.stats.wear(Items.Slot.AMULET, amulet)
	hero.stats.refresh()
	hero.armor = 0.0
	hero.max_health = 1000.0
	hero.health = 1000.0
	hero.fire_resist = 0.20
	hero.physical_resist = 0.50
	hero.melee_resist = 0.20
	expect("magic resistance sums with matching fire resistance and is capped once",
		is_equal_approx(Combat.effective_resistance(hero, Combat.DamageType.FIRE), 0.24))
	var fire := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.FIRE, false, 1.0, false, false)
	var hp_before_fire: float = hero.health
	hero.receive(fire, enemy.global_position)
	expect("magical plus elemental mitigation applies once through resolve and receive", is_equal_approx(float(fire.damage), 76.0)
		and is_equal_approx(hp_before_fire - hero.health, 76.0))
	var physical := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	expect("physical mitigation does not affect magical damage and magic does not affect physical", is_equal_approx(float(physical.damage), 30.0))

	# Armor remains its existing stage and precedes resistance. Dodge and block remain avoidance outcomes.
	hero.armor = 20.0
	var armored := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.FIRE, false, 1.0, false, false)
	expect("armor remains before combined magical resistance", is_equal_approx(float(armored.damage), 38.0))
	hero.armor = 0.0
	hero.physical_resist = 0.65
	hero.melee_resist = 0.40
	expect("effective player resistance caps at 80 percent", is_equal_approx(Combat.effective_resistance(hero, Combat.DamageType.PHYSICAL), 0.80))
	var capped := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	expect("capped physical hit leaves 20 percent damage", is_equal_approx(float(capped.damage), 20.0))
	hero.dodge_chance = 1.0
	var dodged := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.PHYSICAL, true, 1.0, false, false)
	expect("dodge remains a miss before resistance resolution", int(dodged.outcome) == Combat.Outcome.MISS and is_zero_approx(float(dodged.damage)))
	hero.dodge_chance = 0.0
	hero.block_chance = 1.0
	var blocked := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.PHYSICAL, true, 1.0, false, false)
	expect("shield block remains a block before resistance resolution", int(blocked.outcome) == Combat.Outcome.BLOCK and is_zero_approx(float(blocked.damage)))
	hero.block_chance = 0.0

	# Replacing/unequipping clears effective resistance; persisted item IDs rebuild modifiers on load.
	hero.stats.wear(Items.Slot.AMULET, Items.from_save(Items.to_save(amulet)))
	expect("resistance item save/load preserves modifiers and effective combat value",
		is_equal_approx(Items.mods_of(Items.from_save(Items.to_save(amulet))).get("magical_resist", 0.0), 4.0)
		and is_equal_approx(hero.stats.gear_stat("magical_resist"), 4.0))
	hero.stats.unequip(Items.Slot.AMULET)
	expect("unequipping removes magical resistance immediately", is_zero_approx(hero.magical_resist))
	hero.stats.wear(Items.Slot.ARMOR, oakcase)
	expect("replacing armor removes prior resistance and adds the new item stat", is_zero_approx(hero.physical_resist)
		and is_equal_approx(hero.melee_resist, 0.06))
	var saved_character := CharacterState.from_dict("hero", JSON.parse_string(JSON.stringify(hero.character.to_dict())))
	expect("character save/load retains equipped resistance unique identity", saved_character.equipment.values().any(
		func(entry: Dictionary) -> bool: return String(entry.get("unique", "")) == "oakcase_carved_tunic"))

	PartyManager.current().members[hero.member_id] = CharacterState.from_dict(hero.member_id, saved_character_data)
	hero.stats.refresh()
	hero.health = saved_health
	hero.stats.mana = saved_mana
	hero.set_physics_process(true)
	enemy.queue_free()

func _plain(actor: Actor) -> void:
	actor.level = 1
	actor.armor = 0.0
	actor.toughness = 0.0
	actor.fire_resist = 0.0
	actor.ice_resist = 0.0
	actor.lightning_resist = 0.0
	actor.death_resist = 0.0
	actor.physical_resist = 0.0
	actor.melee_resist = 0.0
	actor.ranged_resist = 0.0
	actor.magical_resist = 0.0
	actor.block_chance = 0.0
	actor.ranged_block_chance = 0.0
	actor.dodge_chance = 0.0
	actor.ranged_dodge_chance = 0.0
	actor.crit_chance = 0.0
	actor.invulnerable_time = 0.0
	actor.ward_time = 0.0
