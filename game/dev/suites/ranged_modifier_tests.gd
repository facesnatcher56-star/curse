extends DevSuite
## Source-backed ranged equipment modifiers, their shared-character ownership, and real projectile resolution.

const RANGED_FAMILIES: Array[String] = ["ranged_min", "ranged_max", "ranged_pct"]
const MELEE_FAMILIES: Array[String] = ["melee_min", "melee_max", "melee_pct"]

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

func _families(mods: Array) -> Array[String]:
	var out: Array[String] = []
	for id in mods:
		var affix := AffixDb.get_def(String(id))
		if affix != null:
			out.append(affix.family)
	return out

func _arrow_hit(shooter: Player, enemy: Enemy, damage: float, empowered: bool = false) -> Dictionary:
	var arrow := CompanionArrow.fire(self, shooter, shooter.global_position + Vector3.UP, enemy.global_position + Vector3.UP, damage, empowered)
	arrow.set_physics_process(false)
	arrow._hit_enemy(enemy, shooter.global_position)
	var result := enemy.last_result.duplicate(true)
	arrow.queue_free()
	return result

func _expected_range(body: Player, item: Dictionary, min_bonus: float, max_bonus: float, pct: float, biting: float) -> Vector2:
	var low := float(item.stats.min) + min_bonus
	var high := maxf(float(item.stats.max) + max_bonus, low)
	var dex_bonus := 0.2 * maxf(body.stats.dexterity, 10.0)
	return Vector2(low + dex_bonus * 0.75, high + dex_bonus * 1.25) * (1.0 + biting / 100.0) * (1.0 + pct / 100.0)

func _test_ranged_modifiers() -> void:
	TownState.persist = false
	var party := PartyManager.current()
	var hero := player
	var cutter := party.bodies.get("cutter") as Player
	expect("ranged modifier fixture has both common-character bodies", cutter != null)
	if cutter == null:
		return
	var saved_hero := hero.character.to_dict()
	var saved_cutter := cutter.character.to_dict()
	var saved_active := party.active_id
	for body in [hero, cutter]:
		body.set_physics_process(false)
		_plain(body)
		body.character.class_xp = {"melee": 0, "ranged": 0, "combat": 0, "nature": 0}
		body.character.passive_ranks = {}

	var bow_def := ItemDb.get_def("short_bow")
	var sword_def := ItemDb.get_def("longsword")
	var plain_bow := Items.build(bow_def, 10, Items.Rarity.NORMAL)
	var min_bow := Items.build(bow_def, 10, Items.Rarity.MAGIC, ["ranged_min_1"])
	var max_bow := Items.build(bow_def, 10, Items.Rarity.MAGIC, ["ranged_max_1"])
	var pct_bow := Items.build(bow_def, 10, Items.Rarity.MAGIC, ["ranged_pct_1"])
	var rare_bow := Items.build(bow_def, 10, Items.Rarity.RARE, ["ranged_pct_1", "ranged_min_1", "ranged_max_1"])
	var normal_speed := float(plain_bow.stats.speed)

	for fixture in [
		{"item": plain_bow, "min": 0.0, "max": 0.0, "pct": 0.0, "label": "base bow"},
		{"item": min_bow, "min": 3.0, "max": 0.0, "pct": 0.0, "label": "minimum ranged damage"},
		{"item": max_bow, "min": 0.0, "max": 1.0, "pct": 0.0, "label": "maximum ranged damage"},
		{"item": pct_bow, "min": 0.0, "max": 0.0, "pct": 10.0, "label": "percent ranged damage"},
		{"item": rare_bow, "min": 3.0, "max": 1.0, "pct": 10.0, "label": "combined ranged modifiers"},
	]:
		hero.character.equipment = {Items.Slot.WEAPON: fixture.item}
		hero.stats.refresh()
		var expected := _expected_range(hero, fixture.item, fixture.min, fixture.max, fixture.pct, 0.0)
		expect("%s follows DS2 ranged calculation order" % fixture.label, hero.stats.ranged_range().is_equal_approx(expected))

	expect("ranged damage modifiers do not alter bow attack speed", is_equal_approx(hero.stats.attack_speed(), normal_speed))
	var sword := Items.build(sword_def, 10, Items.Rarity.NORMAL)
	hero.character.equipment = {Items.Slot.WEAPON: sword}
	hero.stats.refresh()
	var melee_without_ranged := hero.stats.weapon_range(1.0)
	hero.stats.gear["ranged_min"] = 100.0
	hero.stats.gear["ranged_max"] = 100.0
	hero.stats.gear["ranged_pct"] = 100.0
	expect("ranged modifiers never alter a melee weapon calculation", hero.stats.weapon_range(1.0).is_equal_approx(melee_without_ranged))
	hero.character.equipment = {Items.Slot.WEAPON: rare_bow}
	hero.stats.refresh()
	var card_lines := Items.lines(rare_bow)
	expect("item card exposes all three ranged modifier values", card_lines.has("+3 Minimum ranged damage")
		and card_lines.has("+1 Maximum ranged damage") and card_lines.has("+10% Ranged damage"))
	var comparisons := Items.compare(rare_bow, plain_bow)
	expect("equipment comparison exposes ranged modifier gains", comparisons.any(func(line: Dictionary) -> bool: return String(line.text).begins_with("Minimum ranged damage") and int(line.sign) > 0)
		and comparisons.any(func(line: Dictionary) -> bool: return String(line.text).begins_with("Maximum ranged damage") and int(line.sign) > 0)
		and comparisons.any(func(line: Dictionary) -> bool: return String(line.text).begins_with("Ranged damage") and int(line.sign) > 0))
	var tile := ItemTile.create(rare_bow, plain_bow)
	add_child(tile)
	tile.mouse_entered.emit()
	expect("hovered ranged weapon card renders modifier text", _label_text(tile).contains("Minimum ranged damage")
		and _label_text(tile).contains("Maximum ranged damage") and _label_text(tile).contains("Ranged damage"))
	tile.mouse_exited.emit()
	tile.queue_free()

	# The exact tiers, values, positions and ranger-only eligibility are extracted from pcontent.gas.
	var tiers_ok := true
	for expected in [
		["ranged_max_1", 1, 1.0, "of Accuracy", "suffix"], ["ranged_max_6", 74, 72.0, "of Mastery", "suffix"],
		["ranged_min_1", 3, 3.0, "of Piercing", "suffix"], ["ranged_min_6", 48, 18.0, "of Penetrating", "suffix"],
		["ranged_pct_1", 1, 10.0, "Sharp", "prefix"], ["ranged_pct_8", 55, 56.0, "Razor", "prefix"],
	]:
		var affix := AffixDb.get_def(expected[0])
		tiers_ok = tiers_ok and affix != null and affix.level == expected[1] and is_equal_approx(affix.value, expected[2]) \
			and affix.title == expected[3] and affix.position == expected[4] and affix.classes == ["ranger"] and affix.slots == ["weapon"]
	expect("ranged affix endpoints exactly match DS2 source tiers", tiers_ok)
	expect("Razor enters the eligible pool only at modifier level 55",
		not AffixDb.eligible("weapon", 1, 54).any(func(a: AffixDef) -> bool: return a.id == "ranged_pct_8")
		and AffixDb.eligible("weapon", 55, 55).any(func(a: AffixDef) -> bool: return a.id == "ranged_pct_8"))
	seed(31032006)
	var bow_families: Array[String] = []
	var sword_clean := true
	var bow_clean := true
	for i in 300:
		var rolled_bow := _families(Items.roll_mods(bow_def, 60, Items.Rarity.RARE, 4))
		var rolled_sword := _families(Items.roll_mods(sword_def, 60, Items.Rarity.RARE, 4))
		for family in rolled_bow:
			if family in RANGED_FAMILIES and family not in bow_families: bow_families.append(family)
			if family in MELEE_FAMILIES: bow_clean = false
		for family in rolled_sword:
			if family in RANGED_FAMILIES: sword_clean = false
	expect("normal rare-bow generation reaches every ranged modifier family", RANGED_FAMILIES.all(func(family: String) -> bool: return family in bow_families))
	expect("weapon affix generation respects ranged versus melee discipline", bow_clean and sword_clean)
	# Generated DS2 ranged affixes are weapon-only. This synthetic second equipped source exercises the shared accumulator used by
	# authored pieces and future content without changing the source eligibility or the normal loot pool.
	var ring_def := ItemDb.of_slot(Items.Slot.RING)[0]
	var authored_fixture := Items.build(ring_def, 10, Items.Rarity.MAGIC, ["ranged_max_1"])
	hero.character.equipment = {Items.Slot.WEAPON: rare_bow, Items.Slot.RING: authored_fixture}
	hero.stats.refresh()
	expect("ranged bonuses from multiple equipped sources stack once", is_equal_approx(hero.stats.gear_stat("ranged_max"), 2.0))

	# The shared character records own equipment independently, including serialization.
	hero.character.equipment = {Items.Slot.WEAPON: rare_bow}
	cutter.character.equipment = {Items.Slot.WEAPON: pct_bow}
	hero.stats.refresh()
	cutter.stats.refresh()
	var hero_range := hero.stats.ranged_range()
	var cutter_range := cutter.stats.ranged_range()
	expect("Hero and Cutter calculate their own equipped ranged modifiers", not hero_range.is_equal_approx(cutter_range)
		and is_equal_approx(hero.stats.gear_stat("ranged_min"), 3.0) and is_zero_approx(cutter.stats.gear_stat("ranged_min")))
	if party.active_id != "cutter": party.select("cutter")
	expect("active-member switching never transfers ranged equipment stats", cutter.stats.ranged_range().is_equal_approx(cutter_range)
		and hero.stats.ranged_range().is_equal_approx(hero_range))
	var reloaded_hero := CharacterState.from_dict("hero", JSON.parse_string(JSON.stringify(hero.character.to_dict())))
	var reloaded_cutter := CharacterState.from_dict("cutter", JSON.parse_string(JSON.stringify(cutter.character.to_dict())))
	expect("ranged modifier equipment serializes independently for both members",
		(reloaded_hero.equipment[Items.Slot.WEAPON].mods as Array) == rare_bow.mods
		and (reloaded_cutter.equipment[Items.Slot.WEAPON].mods as Array) == pct_bow.mods)

	# Passives multiply after flat bonuses and Dexterity; the tooltip uses the finished ranged range.
	hero.character.passive_ranks = {"critical_shot": 1, "biting_arrow": 1, "mortal_wound": 1}
	hero.stats.refresh()
	var biting := PassiveDb.get_def("biting_arrow").value(1)
	var passive_expected := _expected_range(hero, rare_bow, 3.0, 1.0, 10.0, biting)
	expect("Biting Arrow stacks before ranged percentage damage", hero.stats.ranged_range().is_equal_approx(passive_expected))
	expect("Critical Shot and Mortal Wound still drive ranged combat stats", is_equal_approx(hero.crit_chance, 0.08)
		and is_equal_approx(hero.crit_mult, 2.24))
	expect("basic and Take Aim tooltip summaries use the completed ranged range",
		hero.stats.skill_damage_text("basic") == "Damage %d-%d per hit" % [int(passive_expected.x), int(passive_expected.y)]
		and hero.stats.skill_damage_text("take_aim").begins_with("Empowered arrow "))

	var enemy := _spawn_enemy(Vector3(28, 0, 28))
	enemy.set_physics_process(false)
	_plain(enemy)
	enemy.max_health = 100000.0
	enemy.health = enemy.max_health
	var rolled := (passive_expected.x + passive_expected.y) * 0.5
	var before := enemy.health
	hero.forced_crits = 1
	var crit_result := _arrow_hit(hero, enemy, rolled)
	expect("real ranged modifier arrow retains Critical Shot and Mortal Wound resolution",
		int(crit_result.outcome) == Combat.Outcome.CRITICAL and is_equal_approx(before - enemy.health, rolled * hero.crit_mult))

	enemy.health = enemy.max_health
	enemy.ranged_block_chance = 1.0
	before = enemy.health
	var blocks_before := int(Combat.tally.get(Combat.Outcome.BLOCK, 0))
	_arrow_hit(hero, enemy, rolled)
	expect("ranged modifiers preserve ranged block behavior", int(Combat.tally.get(Combat.Outcome.BLOCK, 0)) == blocks_before + 1
		and is_equal_approx(enemy.health, before))
	enemy.ranged_block_chance = 0.0
	enemy.armor = 40.0
	enemy.health = enemy.max_health
	hero.crit_chance = 0.0
	before = enemy.health
	_arrow_hit(hero, enemy, rolled)
	expect("ranged modifiers preserve shared armour mitigation", is_equal_approx(before - enemy.health, rolled * Combat.armor_factor(hero.level, enemy.armor)))

	# Damage is fixed when the arrow is released; later equipment/control changes cannot rewrite it.
	enemy.armor = 0.0
	enemy.health = enemy.max_health
	hero.character.passive_ranks = {}
	hero.stats.refresh()
	hero.crit_chance = 0.0
	var snap_damage := (hero.stats.ranged_range().x + hero.stats.ranged_range().y) * 0.5
	var snapshot := CompanionArrow.fire(self, hero, hero.global_position + Vector3.UP, enemy.global_position + Vector3.UP, snap_damage)
	snapshot.set_physics_process(false)
	hero.character.equipment = {Items.Slot.WEAPON: plain_bow}
	hero.stats.refresh()
	if party.active_id != "hero": party.select("hero")
	if party.active_id != "cutter": party.select("cutter")
	before = enemy.health
	snapshot._hit_enemy(enemy, hero.global_position)
	expect("arrow snapshots ranged equipment damage across switching and re-equipping", is_equal_approx(before - enemy.health, snap_damage)
		and String(enemy.last_result.get("origin", {}).get("character_id", "")) == "hero")
	snapshot.queue_free()

	# Take Aim multiplies the completed weapon range and remains unable to critical.
	hero.character.equipment = {Items.Slot.WEAPON: rare_bow}
	hero.character.passive_ranks = {"critical_shot": 1, "biting_arrow": 1}
	hero.stats.refresh()
	hero.forced_crits = 1
	var take_aim_base := (hero.stats.ranged_range().x + hero.stats.ranged_range().y) * 0.5
	var take_aim_mult := PowerDb.hero_value("take_aim", "damage_pct", "hero") / 100.0
	enemy.health = enemy.max_health
	before = enemy.health
	var aimed := _arrow_hit(hero, enemy, take_aim_base * take_aim_mult, true)
	expect("Take Aim multiplies the modifier-complete range and never criticals", int(aimed.outcome) == Combat.Outcome.HIT
		and is_equal_approx(before - enemy.health, take_aim_base * take_aim_mult) and hero.forced_crits == 1)

	# When flat minimum exceeds maximum, DS2 repairs the upper bound before Dexterity and percentage multipliers.
	hero.stats.gear = {"ranged_min": 100.0, "ranged_pct": 10.0}
	var repaired := hero.stats.ranged_range()
	expect("ranged flat bonuses always produce a valid ordered range", repaired.y > repaired.x and repaired.x > 100.0)

	party.members["hero"] = CharacterState.from_dict("hero", saved_hero)
	party.members["cutter"] = CharacterState.from_dict("cutter", saved_cutter)
	for body in [hero, cutter]:
		body.stats.refresh()
		body.health = body.max_health
		body.stats.mana = body.stats.max_mana
		body.set_physics_process(true)
	if party.active_id != saved_active: party.select(saved_active)
	enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
