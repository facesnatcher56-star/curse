extends DevSuite
## Dedicated automated gameplay tests for implemented Dungeon Siege II equipment alterations and passive rank payloads:
## alter_intelligence, alter_max_mana, alter_melee_damage_min, alter_melee_damage_max,
## alter_melee_damage_source_percent, alter_custom_damage_fire, alter_cmagic_damage_percent,
## alter_fire_resistance, alter_life_recovery_unit, alter_mana_recovery_unit, alter_power_reload.
##
## Validates real equip, unequip, stacking, boundary conditions, and displayed card lines.

func _plain(body: Actor) -> void:
	body.level = 1
	body.armor = 0.0
	body.toughness = 0.0
	body.fire_resist = 0.0
	body.block_chance = 0.0
	body.ranged_block_chance = 0.0
	body.dodge_chance = 0.0
	body.crit_chance = 0.0
	body.added_fire = 0.0
	body.added_fire_max = 0.0
	body.invulnerable_time = 0.0
	body.ward_time = 0.0
	body.forced_crits = 0

func _test_equipment_effects() -> void:
	TownState.persist = false
	var hero := player
	expect("equipment effects fixture has player", hero != null)
	if hero == null:
		return

	var saved_hero := hero.character.to_dict()
	var party := PartyManager.current()
	var saved_active := party.active_id

	hero.set_physics_process(false)
	_plain(hero)
	hero.character.class_xp = {"melee": 0, "ranged": 0, "combat": 0, "nature": 0}
	hero.character.passive_ranks = {}
	hero.character.equipment = {}
	hero.stats.refresh()

	var sword_def := ItemDb.get_def("longsword")
	var bow_def := ItemDb.get_def("short_bow")
	var ring_def := ItemDb.get_def("band")
	var amulet_def := ItemDb.get_def("talisman")
	var armor_def := ItemDb.get_def("leather_jerkin")

	var plain_sword := Items.build(sword_def, 10, Items.Rarity.NORMAL)
	var plain_bow := Items.build(bow_def, 10, Items.Rarity.NORMAL)

	var enemy := _spawn_enemy(Vector3(26, 0, 26))
	enemy.set_physics_process(false)
	_plain(enemy)
	enemy.max_health = 10000.0
	enemy.health = 10000.0

	# -------------------------------------------------------------------------------------------------
	# 1. alter_intelligence (runtime_key: "int")
	# -------------------------------------------------------------------------------------------------
	var int_ring_1 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["intelligence_1"]) # +1 INT
	var int_ring_2 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["intelligence_2"]) # +3 INT
	var base_int := hero.stats.intelligence
	var base_mana_pool := hero.stats.max_mana
	var base_spell_window := hero.stats.spell_range()
	var base_spell_cost := hero.stats.mana_cost("fireball")

	var int_lines := Items.lines(int_ring_2)
	expect("alter_intelligence displays '+3 Intelligence' on item card", int_lines.has("+3 Intelligence"))

	hero.character.equipment = {Items.Slot.RING: int_ring_2}
	hero.stats.refresh()
	expect("alter_intelligence raises character intelligence", is_equal_approx(hero.stats.intelligence, base_int + 3.0))
	expect("alter_intelligence expands maximum mana via HeroAttributes curve", hero.stats.max_mana > base_mana_pool)
	var int_spell_window := hero.stats.spell_range()
	expect("alter_intelligence scales Fireball damage window", int_spell_window.x > base_spell_window.x and int_spell_window.y > base_spell_window.y)
	expect("alter_intelligence scales Fireball mana cost", hero.stats.mana_cost("fireball") > base_spell_cost)

	# Stacking
	hero.character.equipment[Items.Slot.RING2] = int_ring_1
	hero.stats.refresh()
	expect("alter_intelligence stacks additively across multiple equipped pieces", is_equal_approx(hero.stats.intelligence, base_int + 4.0))

	# Unequip
	hero.character.equipment.clear()
	hero.stats.refresh()
	expect("alter_intelligence reverts to baseline when unequipped", is_equal_approx(hero.stats.intelligence, base_int)
		and is_equal_approx(hero.stats.max_mana, base_mana_pool) and hero.stats.spell_range().is_equal_approx(base_spell_window)
		and is_equal_approx(hero.stats.mana_cost("fireball"), base_spell_cost))

	# -------------------------------------------------------------------------------------------------
	# 2. alter_max_mana (runtime_key: "mana")
	# -------------------------------------------------------------------------------------------------
	var mana_ring_1 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["mana_1"]) # +4 Mana
	var mana_ring_2 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["mana_2"]) # +13 Mana
	base_mana_pool = hero.stats.max_mana

	var mana_lines := Items.lines(mana_ring_2)
	expect("alter_max_mana displays '+13 Mana' on item card", mana_lines.has("+13 Mana"))

	hero.character.equipment = {Items.Slot.RING: mana_ring_2}
	hero.stats.refresh()
	expect("alter_max_mana expands maximum mana by exact item value", is_equal_approx(hero.stats.max_mana, base_mana_pool + 13.0))

	# Stacking
	hero.character.equipment[Items.Slot.RING2] = mana_ring_1
	hero.stats.refresh()
	expect("alter_max_mana stacks additively across rings", is_equal_approx(hero.stats.max_mana, base_mana_pool + 17.0))

	# Boundary & unequip clamping
	hero.stats.mana = hero.stats.max_mana
	hero.character.equipment.clear()
	hero.stats.refresh()
	expect("alter_max_mana reverts maximum mana pool on unequip", is_equal_approx(hero.stats.max_mana, base_mana_pool))
	expect("alter_max_mana clamps current mana to baseline max_mana", hero.stats.mana <= hero.stats.max_mana + 0.001)

	# Baseline bow ranged window
	hero.character.equipment = {Items.Slot.WEAPON: plain_bow}
	hero.stats.refresh()
	var base_bow_range := hero.stats.ranged_range()

	# -------------------------------------------------------------------------------------------------
	# 3. alter_melee_damage_min (runtime_key: "melee_min")
	# -------------------------------------------------------------------------------------------------
	var min_sword := Items.build(sword_def, 10, Items.Rarity.MAGIC, ["melee_min_1"]) # +3 Min
	var min_ring := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["melee_min_2"]) # +4 Min

	hero.character.equipment = {Items.Slot.WEAPON: plain_sword}
	hero.stats.refresh()
	var base_melee_window := hero.stats.weapon_range(1.0)

	var min_sword_lines := Items.lines(min_sword)
	expect("alter_melee_damage_min displays on item card", min_sword_lines.has("+3 Minimum melee damage"))

	hero.character.equipment = {Items.Slot.WEAPON: min_sword}
	hero.stats.refresh()
	var elevated_min_window := hero.stats.weapon_range(1.0)
	expect("alter_melee_damage_min increases melee minimum damage", elevated_min_window.x > base_melee_window.x)
	expect("alter_melee_damage_min preserves maximum damage ceiling", is_equal_approx(elevated_min_window.y, base_melee_window.y))

	# Boundary: ring with melee_min equipped with bow does not affect ranged damage
	hero.character.equipment = {Items.Slot.WEAPON: plain_bow, Items.Slot.RING: min_ring}
	hero.stats.refresh()
	expect("alter_melee_damage_min never alters bow ranged calculation", hero.stats.ranged_range().is_equal_approx(base_bow_range))

	# Stacking
	hero.character.equipment = {Items.Slot.WEAPON: min_sword, Items.Slot.RING: min_ring}
	hero.stats.refresh()
	var stacked_min_window := hero.stats.weapon_range(1.0)
	expect("alter_melee_damage_min stacks additively from armor/jewelry", stacked_min_window.x > elevated_min_window.x)

	# Unequip
	hero.character.equipment = {Items.Slot.WEAPON: plain_sword}
	hero.stats.refresh()
	expect("alter_melee_damage_min reverts on unequip", hero.stats.weapon_range(1.0).is_equal_approx(base_melee_window))

	# -------------------------------------------------------------------------------------------------
	# 4. alter_melee_damage_max (runtime_key: "melee_max")
	# -------------------------------------------------------------------------------------------------
	var max_sword := Items.build(sword_def, 10, Items.Rarity.MAGIC, ["melee_max_1"]) # +1 Max
	var max_ring := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["melee_max_2"]) # +4 Max

	var max_sword_lines := Items.lines(max_sword)
	expect("alter_melee_damage_max displays on item card", max_sword_lines.has("+1 Maximum melee damage"))

	hero.character.equipment = {Items.Slot.WEAPON: max_sword}
	hero.stats.refresh()
	var elevated_max_window := hero.stats.weapon_range(1.0)
	expect("alter_melee_damage_max elevates melee damage ceiling", elevated_max_window.y > base_melee_window.y)
	expect("alter_melee_damage_max preserves minimum damage floor", is_equal_approx(elevated_max_window.x, base_melee_window.x))

	# Stacking
	hero.character.equipment[Items.Slot.RING] = max_ring
	hero.stats.refresh()
	expect("alter_melee_damage_max stacks additively from jewelry", hero.stats.weapon_range(1.0).y > elevated_max_window.y)

	# Unequip
	hero.character.equipment = {Items.Slot.WEAPON: plain_sword}
	hero.stats.refresh()
	expect("alter_melee_damage_max reverts on unequip", hero.stats.weapon_range(1.0).is_equal_approx(base_melee_window))

	# -------------------------------------------------------------------------------------------------
	# 5. alter_melee_damage_source_percent (runtime_key: "melee_pct")
	# -------------------------------------------------------------------------------------------------
	var pct_sword := Items.build(sword_def, 10, Items.Rarity.MAGIC, ["melee_pct_1"]) # +10% Melee
	var pct_ring := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["melee_pct_2"]) # +15% Melee

	var pct_sword_lines := Items.lines(pct_sword)
	expect("alter_melee_damage_source_percent displays on item card", pct_sword_lines.has("+10% Melee damage"))

	hero.character.equipment = {Items.Slot.WEAPON: pct_sword}
	hero.stats.refresh()
	var pct_window := hero.stats.weapon_range(1.0)
	expect("alter_melee_damage_source_percent scales entire melee window by percentage",
		is_equal_approx(pct_window.x, base_melee_window.x * 1.10) and is_equal_approx(pct_window.y, base_melee_window.y * 1.10))

	# Stacking
	hero.character.equipment[Items.Slot.RING] = pct_ring
	hero.stats.refresh()
	var stacked_pct_window := hero.stats.weapon_range(1.0)
	expect("alter_melee_damage_source_percent stacks additively with worn gear",
		is_equal_approx(stacked_pct_window.x, base_melee_window.x * 1.25) and is_equal_approx(stacked_pct_window.y, base_melee_window.y * 1.25))

	# Boundary: never alters ranged damage
	hero.character.equipment = {Items.Slot.WEAPON: plain_bow, Items.Slot.RING: pct_ring}
	hero.stats.refresh()
	expect("alter_melee_damage_source_percent does not scale bow ranged damage", hero.stats.ranged_range().is_equal_approx(base_bow_range))

	# Unequip
	hero.character.equipment = {Items.Slot.WEAPON: plain_sword}
	hero.stats.refresh()
	expect("alter_melee_damage_source_percent reverts on unequip", hero.stats.weapon_range(1.0).is_equal_approx(base_melee_window))

	# -------------------------------------------------------------------------------------------------
	# 6. alter_custom_damage_fire (runtime_key: "fire_added, fire_added_max")
	# -------------------------------------------------------------------------------------------------
	var fire_sword := Items.build(sword_def, 10, Items.Rarity.MAGIC, ["fire_added_1"]) # Adds 2 to 4 Fire damage
	var fire_ring := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["fire_added_2"]) # Adds 4 to 6 Fire damage

	var fire_sword_lines := Items.lines(fire_sword)
	expect("alter_custom_damage_fire displays damage span on item card", fire_sword_lines.has("+2–4 Fire damage"))

	hero.character.equipment = {Items.Slot.WEAPON: fire_sword}
	hero.stats.refresh()
	expect("alter_custom_damage_fire sets added_fire floor and ceiling on actor",
		is_equal_approx(hero.added_fire, 2.0) and is_equal_approx(hero.added_fire_max, 4.0))

	# Actual hit resolution with added fire
	_plain(enemy)
	enemy.fire_resist = 0.0
	var hit_with_fire := Combat.resolve(hero, enemy, 10.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	_plain(hero)
	hero.added_fire = 0.0
	hero.added_fire_max = 0.0
	var hit_without_fire := Combat.resolve(hero, enemy, 10.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	expect("alter_custom_damage_fire adds fire damage to physical blows", hit_with_fire.damage >= hit_without_fire.damage + 2.0)

	# Elemental resistance interaction
	enemy.fire_resist = 0.8 # capped in Combat.RESIST_CAP
	var hit_resisted := Combat.resolve(hero, enemy, 10.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	expect("alter_custom_damage_fire respects target fire resistance", hit_resisted.damage < hit_with_fire.damage)

	# Stacking
	hero.character.equipment[Items.Slot.RING] = fire_ring
	hero.stats.refresh()
	expect("alter_custom_damage_fire stacks additively across equipment",
		is_equal_approx(hero.added_fire, 6.0) and is_equal_approx(hero.added_fire_max, 10.0))

	# Unequip
	hero.character.equipment.clear()
	hero.stats.refresh()
	expect("alter_custom_damage_fire clears from actor on unequip", is_equal_approx(hero.added_fire, 0.0) and is_equal_approx(hero.added_fire_max, 0.0))

	# -------------------------------------------------------------------------------------------------
	# 7. alter_cmagic_damage_percent (runtime_key: "spell_pct")
	# -------------------------------------------------------------------------------------------------
	var spell_ring_1 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["spell_pct_1"]) # +4%
	var spell_ring_2 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["spell_pct_2"]) # +8%

	var spell_lines := Items.lines(spell_ring_2)
	expect("alter_cmagic_damage_percent displays on item card", spell_lines.has("+8% Combat magic damage"))

	base_spell_window = hero.stats.spell_range()
	hero.character.equipment = {Items.Slot.RING: spell_ring_2}
	hero.stats.refresh()
	var boosted_spell := hero.stats.spell_range()
	expect("alter_cmagic_damage_percent scales Fireball spell damage window",
		is_equal_approx(boosted_spell.x, base_spell_window.x * 1.08) and is_equal_approx(boosted_spell.y, base_spell_window.y * 1.08))

	# Stacking
	hero.character.equipment[Items.Slot.RING2] = spell_ring_1
	hero.stats.refresh()
	var stacked_spell := hero.stats.spell_range()
	expect("alter_cmagic_damage_percent stacks additively from jewelry",
		is_equal_approx(stacked_spell.x, base_spell_window.x * 1.12) and is_equal_approx(stacked_spell.y, base_spell_window.y * 1.12))

	# Unequip
	hero.character.equipment.clear()
	hero.stats.refresh()
	expect("alter_cmagic_damage_percent reverts on unequip", hero.stats.spell_range().is_equal_approx(base_spell_window))

	# -------------------------------------------------------------------------------------------------
	# 8. alter_fire_resistance (runtime_key: "fire_resist")
	# -------------------------------------------------------------------------------------------------
	var resist_ring_1 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["fire_resist_1"]) # +10%
	var resist_ring_2 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["fire_resist_2"]) # +14%

	var resist_lines := Items.lines(resist_ring_2)
	expect("alter_fire_resistance displays on item card", resist_lines.has("+14% Fire resistance"))

	expect("baseline hero has zero fire resistance", is_equal_approx(hero.fire_resist, 0.0))
	var incoming_unresisted := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.FIRE, false, 1.0, false, false)

	hero.character.equipment = {Items.Slot.RING: resist_ring_2}
	hero.stats.refresh()
	expect("alter_fire_resistance applies to actor fire_resist", is_equal_approx(hero.fire_resist, 0.14))
	var incoming_resisted := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.FIRE, false, 1.0, false, false)
	expect("alter_fire_resistance mitigates incoming fire damage proportionally",
		is_equal_approx(incoming_resisted.damage, incoming_unresisted.damage * 0.86))

	# Stacking
	hero.character.equipment[Items.Slot.RING2] = resist_ring_1
	hero.stats.refresh()
	expect("alter_fire_resistance stacks additively", is_equal_approx(hero.fire_resist, 0.24))

	# Resistance Cap Boundary (Combat.RESIST_CAP = 0.80)
	hero.stats.gear["fire_resist"] = 99.0
	hero.fire_resist = 0.99
	var incoming_capped := Combat.resolve(enemy, hero, 100.0, Combat.DamageType.FIRE, false, 1.0, false, false)
	expect("alter_fire_resistance enforces DS2 80% maximum resistance cap",
		is_equal_approx(incoming_capped.damage, incoming_unresisted.damage * (1.0 - Combat.RESIST_CAP)))

	# Unequip
	hero.character.equipment.clear()
	hero.stats.refresh()
	expect("alter_fire_resistance clears on unequip", is_equal_approx(hero.fire_resist, 0.0))

	# -------------------------------------------------------------------------------------------------
	# 9. alter_life_recovery_unit (runtime_key: "life_regen")
	# -------------------------------------------------------------------------------------------------
	var life_regen_ring_1 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["life_regen_1"]) # +4%
	var life_regen_ring_2 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["life_regen_2"]) # +6%

	var life_regen_lines := Items.lines(life_regen_ring_2)
	expect("alter_life_recovery_unit displays on item card", life_regen_lines.has("+6% Life recovery"))

	hero.health = 50.0
	hero.stats.regen(1.0)
	var baseline_life_recovered := hero.health - 50.0

	hero.character.equipment = {Items.Slot.RING: life_regen_ring_2}
	hero.stats.refresh()
	hero.health = 50.0
	hero.stats.regen(1.0)
	var boosted_life_recovered := hero.health - 50.0
	expect("alter_life_recovery_unit accelerates passive health regeneration",
		is_equal_approx(boosted_life_recovered, baseline_life_recovered * 1.06))

	# Stacking
	hero.character.equipment[Items.Slot.RING2] = life_regen_ring_1
	hero.stats.refresh()
	hero.health = 50.0
	hero.stats.regen(1.0)
	expect("alter_life_recovery_unit stacks additively", is_equal_approx(hero.health - 50.0, baseline_life_recovered * 1.10))

	# Boundary: clamp at max_health
	hero.health = hero.max_health - 0.01
	hero.stats.regen(1.0)
	expect("alter_life_recovery_unit clamps regeneration at max_health", is_equal_approx(hero.health, hero.max_health))

	# Unequip
	hero.character.equipment.clear()
	hero.stats.refresh()
	hero.health = 50.0
	hero.stats.regen(1.0)
	expect("alter_life_recovery_unit returns to baseline on unequip", is_equal_approx(hero.health - 50.0, baseline_life_recovered))

	# -------------------------------------------------------------------------------------------------
	# 10. alter_mana_recovery_unit (runtime_key: "mana_regen")
	# -------------------------------------------------------------------------------------------------
	var mana_regen_ring_1 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["mana_regen_1"]) # +4%
	var mana_regen_ring_2 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["mana_regen_2"]) # +6%

	var mana_regen_lines := Items.lines(mana_regen_ring_2)
	expect("alter_mana_recovery_unit displays on item card", mana_regen_lines.has("+6% Mana recovery"))

	hero.stats.mana = 10.0
	hero.stats.regen(1.0)
	var baseline_mana_recovered := hero.stats.mana - 10.0

	hero.character.equipment = {Items.Slot.RING: mana_regen_ring_2}
	hero.stats.refresh()
	hero.stats.mana = 10.0
	hero.stats.regen(1.0)
	var boosted_mana_recovered := hero.stats.mana - 10.0
	expect("alter_mana_recovery_unit accelerates passive mana regeneration",
		is_equal_approx(boosted_mana_recovered, baseline_mana_recovered * 1.06))

	# Stacking
	hero.character.equipment[Items.Slot.RING2] = mana_regen_ring_1
	hero.stats.refresh()
	hero.stats.mana = 10.0
	hero.stats.regen(1.0)
	expect("alter_mana_recovery_unit stacks additively", is_equal_approx(hero.stats.mana - 10.0, baseline_mana_recovered * 1.10))

	# Boundary: clamp at max_mana
	hero.stats.mana = hero.stats.max_mana - 0.01
	hero.stats.regen(1.0)
	expect("alter_mana_recovery_unit clamps regeneration at max_mana", is_equal_approx(hero.stats.mana, hero.stats.max_mana))

	# Unequip
	hero.character.equipment.clear()
	hero.stats.refresh()
	hero.stats.mana = 10.0
	hero.stats.regen(1.0)
	expect("alter_mana_recovery_unit returns to baseline on unequip", is_equal_approx(hero.stats.mana - 10.0, baseline_mana_recovered))

	# -------------------------------------------------------------------------------------------------
	# 11. alter_power_reload (runtime_key: "recharge")
	# -------------------------------------------------------------------------------------------------
	var recharge_ring_1 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["recharge_1"]) # +5%
	var recharge_ring_2 := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["recharge_2"]) # +7%

	var recharge_lines := Items.lines(recharge_ring_2)
	expect("alter_power_reload displays on item card", recharge_lines.has("+7% Power recharge"))

	var baseline_recharge_required := hero.stats.power_recharge_damage(21.0, "melee")
	hero.character.equipment = {Items.Slot.RING: recharge_ring_2}
	hero.stats.refresh()
	var accelerated_recharge := hero.stats.power_recharge_damage(21.0, "melee")
	expect("alter_power_reload reduces damage required to recharge power",
		is_equal_approx(accelerated_recharge, baseline_recharge_required / 1.07))

	# Stacking
	hero.character.equipment[Items.Slot.RING2] = recharge_ring_1
	hero.stats.refresh()
	var double_recharge := hero.stats.power_recharge_damage(21.0, "melee")
	expect("alter_power_reload stacks additively across equipment",
		is_equal_approx(double_recharge, baseline_recharge_required / 1.12))

	# Unequip
	hero.character.equipment.clear()
	hero.stats.refresh()
	expect("alter_power_reload returns to unaccelerated baseline on unequip",
		is_equal_approx(hero.stats.power_recharge_damage(21.0, "melee"), baseline_recharge_required))

	# -------------------------------------------------------------------------------------------------
	# Equipment passive ranks: source-accurate payload fixtures, independent of the absent source uniques.
	# -------------------------------------------------------------------------------------------------
	var invested := {"barricade": 2, "toughness": 19}
	hero.character.passive_ranks = invested.duplicate()
	hero.character.class_xp["melee"] = HeroProgression.xp_for_level(6)
	var passive_ring := Items.build(ring_def, 10, Items.Rarity.NORMAL)
	passive_ring["effects"] = [
		{"alteration": "alter_skill_suite", "suite": "MELEE_SUITE_1", "value": 2},
		{"alteration": "ALTER_MELEE_PASSIVE_SKILLS", "value": 1},
		{"alteration": "alter_skill_suite", "suite": "ranged_suite_1", "value": 1},
		{"alteration": "alter_skill_suite", "suite": "cmagic_suite_3", "value": 1},
		{"alteration": "alter_skill_suite", "suite": "special_suite_2", "value": 1},
		{"alteration": "alter_skill_suite", "suite": "ranged_suite_3", "value": 5},
	]
	hero.character.equipment = {Items.Slot.RING: passive_ring}
	expect("suite and discipline payloads grant only verified passive ranks",
		TownState.gear_passive_bonus("barricade") == 3 and TownState.gear_passive_bonus("toughness") == 4
		and TownState.gear_passive_bonus("critical_shot") == 2 and TownState.gear_passive_bonus("survival") == 1
		and TownState.gear_passive_bonus("searing_flames") == 1 and TownState.gear_passive_bonus("fortitude") == 2
		and TownState.gear_passive_bonus("quick_draw") == 0)
	expect("equipment ranks change effective rank without changing invested ranks",
		TownState.passive_rank("barricade") == 2 and TownState.effective_passive_rank("barricade") == 5
		and TownState.passive_rank("toughness") == 19 and TownState.effective_passive_rank("toughness") == PassiveDef.MAX_RANK)
	expect("gear ranks do not satisfy purchase prerequisites", TownState.passive_blocker("overbear") == "Needs Critical Strike")
	expect("equipment passive payload is visible on item card", Items.lines(passive_ring).has("+2 to Barricade, Toughness, and Reinforced Armor"))
	hero.character.equipment.clear()
	expect("passive ranks disappear immediately when unequipped",
		TownState.effective_passive_rank("barricade") == 2 and TownState.effective_passive_rank("critical_shot") == 0)
	var affix_id := "fixture_passive_rank"
	var unique_id := "fixture_passive_unique"
	var affix_def := AffixDef.new()
	affix_def.id = affix_id
	affix_def.passive_effects = [{"alteration": "alter_skill_suite", "suite": "melee_suite_2", "value": 1}]
	AffixDb.all()[affix_id] = affix_def
	var unique_def := UniqueDef.new()
	unique_def.id = unique_id
	unique_def.base = ring_def.id
	unique_def.passive_effects = [{"alteration": "Alter_Combat_Magic_Passive_Skills", "value": 1}]
	UniqueDb.uniques()[unique_id] = unique_def
	var affix_ring := Items.build(ring_def, 10, Items.Rarity.MAGIC, [affix_id])
	var unique_ring := Items.build(ring_def, 10, Items.Rarity.UNIQUE, [], unique_id)
	hero.character.equipment = {Items.Slot.RING: affix_ring, Items.Slot.RING2: unique_ring}
	expect("affix and unique definition payloads are aggregated", TownState.gear_passive_bonus("smite") == 1
		and TownState.gear_passive_bonus("devastation") == 1 and TownState.gear_passive_bonus("ignite") == 1)
	hero.character.equipment = {Items.Slot.RING: Items.from_save(Items.to_save(affix_ring)),
		Items.Slot.RING2: Items.from_save(Items.to_save(unique_ring))}
	expect("passive affix and unique effects rebuild from saved item identifiers", TownState.gear_passive_bonus("smite") == 1
		and TownState.gear_passive_bonus("devastation") == 1)
	var set_id := "fixture_passive_set"
	var set_unique_a := UniqueDef.new()
	set_unique_a.id = "fixture_set_piece_a"
	set_unique_a.base = ring_def.id
	set_unique_a.set_id = set_id
	var set_unique_b := UniqueDef.new()
	set_unique_b.id = "fixture_set_piece_b"
	set_unique_b.base = ring_def.id
	set_unique_b.set_id = set_id
	UniqueDb.uniques()[set_unique_a.id] = set_unique_a
	UniqueDb.uniques()[set_unique_b.id] = set_unique_b
	var set_def := SetDef.new()
	set_def.id = set_id
	set_def.passive_effect_tiers = {"2": [{"alteration": "alter_skill_suite", "suite": "special_suite_2", "value": 1}]}
	UniqueDb.sets()[set_id] = set_def
	var set_ring_a := Items.build(ring_def, 10, Items.Rarity.UNIQUE, [], set_unique_a.id)
	var set_ring_b := Items.build(ring_def, 10, Items.Rarity.UNIQUE, [], set_unique_b.id)
	hero.character.equipment = {Items.Slot.RING: set_ring_a, Items.Slot.RING2: set_ring_b}
	expect("set passive tiers activate at their worn-piece threshold", TownState.gear_passive_bonus("fortitude") == 1
		and TownState.gear_passive_bonus("toughness") == 1)
	expect("set passive tier is described on its item card", Items.lines(set_ring_a).has("  2 worn: +1 to Fortitude, Toughness"))
	hero.character.equipment.erase(Items.Slot.RING2)
	expect("set passive tiers deactivate as soon as a piece is removed", TownState.gear_passive_bonus("fortitude") == 0)
	AffixDb.all().erase(affix_id)
	UniqueDb.uniques().erase(unique_id)
	UniqueDb.uniques().erase(set_unique_a.id)
	UniqueDb.uniques().erase(set_unique_b.id)
	UniqueDb.sets().erase(set_id)
	hero.character.passive_ranks = {}

	# Cleanup
	party.members["hero"] = CharacterState.from_dict("hero", saved_hero)
	hero.character = party.members["hero"]
	hero.stats.refresh()
	hero.health = hero.max_health
	hero.stats.mana = hero.stats.max_mana
	hero.set_physics_process(true)
	party.select(saved_active)
	enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
