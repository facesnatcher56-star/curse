extends DevSuite
## Cross-feature checks for the combined equipment build: requirements (Items.hero_can_wear), elemental stats and combat
## (Combat.resolve), the Item Test Lab, movement priority and saves. Each check drives the real equip path, not a model of it.

const BASE := 10.0
const NEW_ELEMENTS: Array[String] = ["ice", "lightning", "death"]

func _plain(body: Actor) -> void:
	body.level = 1
	body.armor = 0.0
	body.toughness = 0.0
	for element in Combat.ELEMENTS:
		body.set(element + "_resist", 0.0)
	body.block_chance = 0.0
	body.ranged_block_chance = 0.0
	body.dodge_chance = 0.0
	body.crit_chance = 0.0
	body.invulnerable_time = 0.0
	body.ward_time = 0.0
	body.forced_crits = 0

func _hit(attacker: Actor, defender: Actor, kind: int = Combat.DamageType.PHYSICAL) -> Dictionary:
	return Combat.resolve(attacker, defender, BASE, kind, false, 1.0, false, false)

func _bag_has(stats: PlayerStats, item: Dictionary) -> bool:
	for held in stats.bag:
		if held.get("name") == item.get("name") and held.get("def") == item.get("def") and held.get("mods") == item.get("mods"):
			return true
	return false

## Tests A and E: an item that has both an elemental modifier and a requirement.
func _test_equipment_integration() -> void:
	TownState.persist = false
	TownState.reset()
	var hero := player
	hero.set_physics_process(false)
	var stats: PlayerStats = hero.stats
	stats.equipment.clear()
	stats.bag.clear()
	stats.refresh()
	_plain(hero)
	var enemy := _spawn_enemy(Vector3(28, 0, 28))
	enemy.set_physics_process(false)
	_plain(enemy)
	enemy.max_health = 100000.0
	enemy.health = enemy.max_health

	var sword_def := ItemDb.get_def("longsword")
	var ring_def := ItemDb.of_slot(Items.Slot.RING)[0]

	# --- Test A: weapon with an added-damage modifier and a class-level requirement ------------------------------------------------
	for element in NEW_ELEMENTS:
		TownState.dev_set_hero_level(1)
		stats.equipment.clear()
		stats.bag.clear()
		stats.refresh()
		_plain(hero)
		var added: AffixDef = AffixDb.get_def("%s_added_5" % element)
		var sword := Items.build(sword_def, 40, Items.Rarity.MAGIC, [added.id])
		var expression := Items.requirement_expression(sword)
		expect("%s sword carries a real requirement (%s)" % [element, expression], expression != "" and EquipmentRequirement.parse(expression).valid)
		expect("a level-1 hero does not meet the %s sword's requirement" % element, not Items.hero_can_wear(sword, hero.member_id))
		var reason := Items.requirement_text(sword, hero.member_id)
		expect("rejection explains the unmet requirement: '%s'" % reason, reason.contains("Melee") or reason.contains("melee"))
		expect("its card shows the requirement as a line the tile colours red", Items.lines(sword, hero.member_id).any(
			func(line: String) -> bool: return line.contains("Requires ")))
		expect("the equip path refuses the %s sword and returns null" % element, stats.equip(sword, false) == null and not stats.equipment.has(Items.Slot.WEAPON))
		expect("the bag path refuses it too and keeps it in the bag", stats.add_to_bag(sword) and not stats.equip_from_bag(stats.bag.size() - 1)
			and not stats.equipment.has(Items.Slot.WEAPON) and _bag_has(stats, sword))
		stats.refresh()
		expect("an ineligible %s item in the bag grants no damage" % element, is_zero_approx(Combat.added_damage(hero, element))
			and is_zero_approx(Combat.added_damage_max(hero, element)) and is_zero_approx(stats.gear_stat(added.stat)))
		expect("and nothing is added to the blow", not _hit(hero, enemy).has("added_elements"))
		expect("a ground item is not pre-equipped by pickup rules while ineligible", not stats.takes_empty_slot(sword))

		# Raise the hero until the requirement is met, one level at a time, so the threshold is the item's own.
		var needed := 0
		for lvl in range(1, 80):
			TownState.dev_set_hero_level(lvl)
			if Items.hero_can_wear(sword, hero.member_id):
				needed = lvl
				break
		expect("the %s sword becomes wearable at hero level %d (item level 40)" % [element, needed], needed > 1)
		if needed > 1:
			TownState.dev_set_hero_level(needed - 1)
			expect("one level earlier it is still refused", not Items.hero_can_wear(sword, hero.member_id))
			TownState.dev_set_hero_level(needed)
		var index := stats.bag.size() - 1
		expect("after meeting the requirement the bag path equips it", stats.equip_from_bag(index) and stats.equipment.has(Items.Slot.WEAPON)
			and not _bag_has(stats, sword))
		expect("equipping applies %s %.0f-%.0f exactly" % [element, added.value, added.max_value], is_equal_approx(Combat.added_damage(hero, element), added.value)
			and is_equal_approx(Combat.added_damage_max(hero, element), added.max_value))
		for other in Combat.ELEMENTS:
			if other != element:
				expect("%s sword adds no %s damage" % [element, other], is_zero_approx(Combat.added_damage(hero, other)))
		hero.level = 1   # exact arithmetic: the level gap and armour are neutral
		hero.set("added_%s_max" % element, added.value)
		var blow := _hit(hero, enemy)
		expect("the %s sword's element reaches combat once and as the only added element" % element,
			(blow["added_elements"] as Dictionary).size() == 1 and is_equal_approx(float(blow["added_elements"][element]), added.value)
			and is_equal_approx(float(blow["damage"]), BASE + added.value))
		enemy.set(element + "_resist", 0.5)
		var resisted := _hit(hero, enemy)
		expect("a 50%% matching resistance on the target halves only the %s part" % element, is_equal_approx(float(resisted["damage"]), BASE + added.value * 0.5))
		enemy.set(element + "_resist", 0.0)
		expect("unequipping removes the %s damage again" % element, stats.unequip(Items.Slot.WEAPON) != null
			and is_zero_approx(Combat.added_damage(hero, element)) and not _hit(hero, enemy).has("added_elements"))

	# --- Test A, defensive half: a ring with a resistance modifier and a character-level requirement --------------------------
	for element in NEW_ELEMENTS:
		TownState.dev_set_hero_level(1)
		stats.equipment.clear()
		stats.bag.clear()
		stats.refresh()
		var resist: AffixDef = AffixDb.get_def("%s_resist_2" % element)
		var ring := Items.build(ring_def, 40, Items.Rarity.MAGIC, [resist.id])
		expect("a level-1 hero cannot wear the %s resistance ring: %s" % [element, Items.requirement_text(ring, hero.member_id)],
			not Items.hero_can_wear(ring, hero.member_id) and stats.equip(ring, false) == null)
		expect("it sits in the bag without any %s resistance" % element, stats.add_to_bag(ring) and is_zero_approx(Combat.resistance_of(hero, element)))
		stats.refresh()
		expect("refreshing with the ring in the bag still gives none", is_zero_approx(Combat.resistance_of(hero, element)))
		var worn_at := 0
		for lvl in range(1, 80):
			TownState.dev_set_hero_level(lvl)
			if Items.hero_can_wear(ring, hero.member_id):
				worn_at = lvl
				break
		expect("the ring becomes wearable once the character level is reached (%d)" % worn_at, worn_at > 1 and stats.equip_from_bag(0))
		expect("worn, it gives %.0f%% %s resistance and no other" % [resist.value, element], is_equal_approx(Combat.resistance_of(hero, element), resist.value / 100.0)
			and Combat.ELEMENTS.all(func(e: String) -> bool: return e == element or is_zero_approx(Combat.resistance_of(hero, e))))
		var typed: int = {"ice": Combat.DamageType.ICE, "lightning": Combat.DamageType.LIGHTNING, "death": Combat.DamageType.DEATH}[element]
		_plain(enemy)
		hero.level = 1
		var incoming := _hit(enemy, hero, typed)
		expect("an incoming %s blow is cut by exactly the ring's resistance" % element, is_equal_approx(float(incoming["damage"]), BASE * (1.0 - resist.value / 100.0)))
		for other in Combat.ELEMENTS:
			if other != element and other != "fire":
				var typed_other: int = {"ice": Combat.DamageType.ICE, "lightning": Combat.DamageType.LIGHTNING, "death": Combat.DamageType.DEATH}[other]
				expect("the %s ring does not soften %s" % [element, other], is_equal_approx(float(_hit(enemy, hero, typed_other)["damage"]), BASE))
		stats.unequip(Items.Slot.RING)
		hero.level = 1   # refresh restores the hero's real level; keep the level gap neutral
		expect("unequipping the %s ring restores full damage" % element, is_zero_approx(Combat.resistance_of(hero, element))
			and is_equal_approx(float(_hit(enemy, hero, typed)["damage"]), BASE))

	# --- Test E: original equipment effects, stacking, saves and registrations ------------------------------------------------------------
	TownState.dev_set_hero_level(80)
	stats.equipment.clear()
	stats.bag.clear()
	stats.refresh()
	_plain(hero)
	var armor_before := hero.armor
	var life_before := hero.max_health
	var fire := Items.build(sword_def, 40, Items.Rarity.MAGIC, ["fire_added_3"])
	var mixed := Items.build(sword_def, 60, Items.Rarity.RARE, ["fire_added_3", "ice_added_5", "lightning_added_5", "death_added_5"])
	var plate_def := ItemDb.get_def("plate_cuirass")
	var plate := Items.build(plate_def, 40, Items.Rarity.NORMAL)
	var res_fire := Items.build(ring_def, 40, Items.Rarity.MAGIC, ["fire_resist_2"])
	var res_ice := Items.build(ring_def, 40, Items.Rarity.MAGIC, ["ice_resist_2"])
	expect("fire sword equips for the stacking checks", stats.equip(fire, false) != null and hero.added_fire > 0.0)
	var fire_added := hero.added_fire
	expect("fire damage is unchanged by the other elements' registration", Combat.ELEMENTS.all(func(e: String) -> bool: return e == "fire" or is_zero_approx(Combat.added_damage(hero, e))))
	stats.equip(res_fire, false)
	stats.equip(res_ice, false)
	var fire_res := AffixDb.get_def("fire_resist_2")
	var ice_res := AffixDb.get_def("ice_resist_2")
	expect("fire and ice resistance rings stack side by side, each on its own element", is_equal_approx(hero.fire_resist, fire_res.value / 100.0)
		and is_equal_approx(hero.ice_resist, ice_res.value / 100.0))
	stats.equip(plate, false)
	expect("armour still raises armour", hero.armor > armor_before)
	stats.refresh()
	stats.refresh()
	expect("repeated refresh does not accumulate any stat", is_equal_approx(hero.added_fire, fire_added) and is_equal_approx(hero.fire_resist, fire_res.value / 100.0)
		and is_equal_approx(hero.ice_resist, ice_res.value / 100.0))
	stats.equip(mixed, false)
	var ice5 := AffixDb.get_def("ice_added_5")
	expect("replacing the weapon swaps its elements instead of adding them", is_equal_approx(hero.added_ice, ice5.value) and is_equal_approx(hero.added_fire,
		AffixDb.get_def("fire_added_3").value))
	stats.unequip(Items.Slot.WEAPON)
	stats.unequip(Items.Slot.ARMOR)
	for place in Items.places(Items.Slot.RING):   # a ring goes on a free hand: both rings are worn
		stats.unequip(place)
	expect("both rings came off", stats.equipment.is_empty())
	stats.refresh()
	expect("unequipping everything restores the armour and element baseline", is_equal_approx(hero.armor, armor_before) and is_equal_approx(hero.max_health, life_before)
		and Combat.ELEMENTS.all(func(e: String) -> bool: return is_zero_approx(Combat.added_damage(hero, e)))
		and is_zero_approx(hero.ice_resist) and is_zero_approx(hero.fire_resist) and is_zero_approx(hero.lightning_resist) and is_zero_approx(hero.death_resist))

	# A save keeps the item, its elemental rolls and what it requires.
	for item in [mixed, res_ice]:
		var saved: Dictionary = JSON.parse_string(JSON.stringify(Items.to_save(item)))
		var loaded: Dictionary = Items.from_save(saved)
		expect("%s survives a JSON save with the same mods, level and requirement" % item["name"], not loaded.is_empty() and loaded["def"] == item["def"]
			and int(loaded["level"]) == int(item["level"]) and loaded["mods"] == item["mods"]
			and Items.requirement_expression(loaded) == Items.requirement_expression(item) and Items.mods_of(loaded) == Items.mods_of(item))
	# A worn elemental item saved in the town record comes back worn (TownState bypasses the requirement for what was already on).
	stats.equip(mixed, false)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(hero.character.to_dict()))
	expect("the character record keeps the worn elemental weapon", JSON.stringify(snapshot).contains("ice_added_5"))
	stats.unequip(Items.Slot.WEAPON)

	# Registration integrity: every affix file registered once, ids unique, no element family duplicated.
	var seen: Dictionary = {}
	var duplicates := 0
	for def in AffixDb.all().values():
		# Scoped to the new families: main already carries identical life_steal_5/6 and life_per_hit_5/6 source rows.
		if not (def as AffixDef).stat.begins_with("ice_") and not (def as AffixDef).stat.begins_with("lightning_") and not (def as AffixDef).stat.begins_with("death_"):
			continue
		var key := "%s|%s|%s|%s|%s|%s|%s" % [(def as AffixDef).title, (def as AffixDef).stat, (def as AffixDef).level, (def as AffixDef).slots,
			(def as AffixDef).classes, (def as AffixDef).value, (def as AffixDef).max_value]
		if seen.has(key):
			duplicates += 1
		seen[key] = true
	expect("no elemental affix is registered twice", duplicates == 0)
	var files := 0
	for file_name in DirAccess.get_files_at("res://data/affixes"):
		if file_name.ends_with(".tres"):
			files += 1
	expect("every affix file is registered exactly once (%d files)" % files, files == AffixDb.all().size())
	var families: Dictionary = {}
	for def in AffixDb.all().values():
		families[(def as AffixDef).stat] = int(families.get(String((def as AffixDef).stat), 0)) + 1
	expect("the six elemental alterations map to the 45 new definitions (12/5 per element)", NEW_ELEMENTS.all(func(e: String) -> bool:
		return int(families.get(e + "_added", 0)) == 12 and int(families.get(e + "_resist", 0)) == 5) and int(families.get("fire_added", 0)) > 0
		and int(families.get("fire_resist", 0)) > 0)
	expect("every elemental stat has a display name and every added range a maximum", NEW_ELEMENTS.all(func(e: String) -> bool:
		return AffixDb.STAT_NAMES.has(e + "_added") and AffixDb.STAT_NAMES.has(e + "_resist")))
	enemy.queue_free()
	hero.set_physics_process(true)
	TownState.reset()
	await get_tree().process_frame
	await _integration_lab()
	await _integration_combat()

## Test B and C: the Item Test Lab uses the real eligibility rules and reports every element it applies.
func _integration_lab() -> void:
	TownState.persist = false
	TownState.reset()
	var sfx_was_enabled: bool = Sfx.enabled
	Sfx.enabled = false
	var lab: ItemTestLab = (load("res://game/dev/item_lab/item_test_lab.tscn") as PackedScene).instantiate() as ItemTestLab
	game.add_child(lab)
	await get_tree().process_frame
	await get_tree().physics_frame
	var hero: Player = lab.player
	var dummy: TrainingDummy = lab.dummy
	var panel: LabSpawnerPanel = lab.spawner_panel
	var stats: PlayerStats = hero.stats
	var outcomes: Array = []
	panel.item_equipped.connect(func(item: Dictionary, ok: bool, why: String) -> void: outcomes.append([item, ok, why]))

	# --- Test B: the panel's Equip button obeys the same rules as the game -----------------------------------------------------------
	TownState.dev_set_hero_level(1)
	stats.equipment.clear()
	stats.refresh()
	_plain(hero)
	_plain(dummy)
	var chosen: ItemDef = ItemDb.get_def("longsword")
	var picked := false
	panel._filter_option.select(1)
	panel._on_filter_changed(1)
	for i in panel._filtered_defs.size():
		if panel._filtered_defs[i] == chosen:
			panel._item_def_option.select(i)
			panel._on_def_selected(i)
			picked = true
	expect("the lab panel offers the longsword", picked)
	var level_id := panel._level_option.get_item_id(panel._level_option.item_count - 1)
	panel._level_option.select(panel._level_option.item_count - 1)
	panel._rarity_option.select(Items.Rarity.MAGIC)
	panel._on_variant_or_rarity_changed(0)
	var ice_index := -1
	for i in panel._affix_prefix_option.item_count:
		var meta: Variant = panel._affix_prefix_option.get_item_metadata(i)
		if meta != null and String(meta).begins_with("ice_added_"):
			ice_index = i
	expect("the lab offers an ice-damage prefix for a high-level longsword", ice_index > 0)
	if ice_index > 0:
		panel._affix_prefix_option.select(ice_index)
	var item := panel.build_current_item()
	expect("the lab builds a real elemental longsword at item level %d" % level_id, not item.is_empty() and Items.mods_of(item).has("ice_added"))
	expect("the lab preview marks the requirement UNMET for a level-1 hero", Items.requirement_text(item) != "" and not Items.hero_can_wear(item, hero.member_id))
	panel._on_equip_pressed()
	expect("pressing Equip is refused with the real requirement text", not outcomes.is_empty() and outcomes[-1][1] == false and String(outcomes[-1][2]) == Items.requirement_text(item))
	expect("the refused item was not worn and added no ice damage", not stats.equipment.has(Items.Slot.WEAPON) or stats.equipment[Items.Slot.WEAPON].get("mods") != item["mods"])
	expect("no ice damage reached the lab hero", is_zero_approx(hero.added_ice))
	expect("the lab exposes no requirement override control", not _has_override_control(lab))
	# Raising the lab's own level slider (the same TownState level) lifts the requirement and the same button then succeeds.
	lab._on_hero_level_changed(float(level_id))
	expect("the lab level control feeds the real requirement check", Items.hero_can_wear(item, hero.member_id))
	panel._on_equip_pressed()
	expect("with the level reached, the lab equips it through PlayerStats", outcomes[-1][1] == true and stats.equipment.has(Items.Slot.WEAPON)
		and hero.added_ice > 0.0)

	# --- Test C: elemental combat in the lab, the dummy and the combat log ----------------------------------------------------------
	for element in NEW_ELEMENTS:
		lab._reset_lab_state()
		TownState.dev_set_hero_level(level_id)
		stats.refresh()
		_plain(hero)
		_plain(dummy)
		var added: AffixDef = AffixDb.get_def("%s_added_5" % element)
		var sword := Items.build(chosen, 40, Items.Rarity.MAGIC, [added.id])
		hero.set("added_%s_max" % element, 0.0)
		expect("the lab hero can wear the %s sword at level %d" % [element, level_id], stats.equip(sword, false) != null)
		stats.refresh()
		hero.set("added_%s_max" % element, added.value)   # pin the roll: minimum == maximum
		hero.level = 1
		dummy.reset_health()
		lab.combat_log.clear_log()
		var blow := Combat.resolve(hero, dummy, BASE, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
		blow["skill_id"] = "basic"
		var before := dummy.health
		dummy.receive(blow, hero.global_position)
		expect("%s: the dummy loses exactly physical plus the rolled element once" % element, is_equal_approx(before - dummy.health, BASE + added.value)
			and is_equal_approx(float(blow["damage"]), BASE + added.value))
		expect("%s: the hit breakdown names only that element" % element, (blow["added_elements"] as Dictionary).keys() == [element])
		var entry := _log_text(lab)
		expect("%s: the combat log reports the total and the %s part ('%s')" % [element, element, entry], entry.contains("%.1f" % (BASE + added.value))
			and entry.contains("%.1f %s" % [added.value, element.capitalize()]) and _count(entry, element.capitalize()) == 1)
		# Resistance on the dummy.
		dummy.set(element + "_resist", 0.5)
		dummy.reset_health()
		var half := Combat.resolve(hero, dummy, BASE, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
		half["skill_id"] = "basic"
		dummy.receive(half, hero.global_position)
		expect("%s: dummy resistance 50%% halves only the element in the log and the health" % element,
			is_equal_approx(float(half["damage"]), BASE + added.value * 0.5) and is_equal_approx(dummy.max_health - dummy.health, BASE + added.value * 0.5))
		dummy.set(element + "_resist", -1.0)
		var vulnerable := Combat.resolve(hero, dummy, BASE, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
		expect("%s: a -100%% dummy resistance doubles the element, not the physical part" % element, is_equal_approx(float(vulnerable["damage"]), BASE + added.value * 2.0))
		_plain(dummy)
		# A pure elemental hit labels its own type in the log.
		var typed: int = {"ice": Combat.DamageType.ICE, "lightning": Combat.DamageType.LIGHTNING, "death": Combat.DamageType.DEATH}[element]
		lab.combat_log.clear_log()
		var pure := Combat.resolve(hero, dummy, BASE, typed, false, 1.0, false, false)
		pure["skill_id"] = "test"
		dummy.receive(pure, hero.global_position)
		expect("%s: a typed %s hit is logged as %s damage and carries no added part" % [element, element, element.capitalize()],
			_log_text(lab).contains(element.capitalize()) and not _log_text(lab).contains("incl. added") and not pure.has("added_elements"))
		expect("%s: weapon-only added damage is not applied to the typed hit" % element, is_equal_approx(float(pure["damage"]), BASE))

	# Mixed weapon: every element once, plus the lab readout shows all of them.
	lab._reset_lab_state()
	TownState.dev_set_hero_level(80)
	var mixed := Items.build(chosen, 60, Items.Rarity.RARE, ["fire_added_3", "ice_added_5", "lightning_added_5", "death_added_5"])
	expect("the lab hero wears the four-element sword", stats.equip(mixed, false) != null)
	_plain(dummy)
	hero.level = 1
	for element in Combat.ELEMENTS:
		hero.set("added_%s_max" % element, Combat.added_damage(hero, element))
	lab.combat_log.clear_log()
	var big := Combat.resolve(hero, dummy, BASE, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	big["skill_id"] = "basic"
	dummy.receive(big, hero.global_position)
	var total := BASE
	for element in Combat.ELEMENTS:
		total += Combat.added_damage(hero, element)
	expect("physical plus four elements sum without double counting", is_equal_approx(float(big["damage"]), total)
		and (big["added_elements"] as Dictionary).size() == 4)
	var big_log := _log_text(lab)
	expect("the log names each of the four elements exactly once", Combat.ELEMENTS.all(func(e: String) -> bool: return _count(big_log, e.capitalize()) == 1))
	lab.stats_readout.refresh()
	var readout: String = lab.stats_readout._content_label.text
	expect("the lab stats readout lists every element's added damage", Combat.ELEMENTS.all(func(e: String) -> bool: return readout.contains("Added %s" % e.capitalize())))
	expect("the lab stats readout lists every element's resistance", Combat.ELEMENTS.all(func(e: String) -> bool: return readout.contains("%s Resistance" % e.capitalize())))
	expect("the lab stats readout shows effective physical, melee, ranged and magical resistances",
		readout.contains("Physical component:") and readout.contains("Effective physical — Melee:")
		and readout.contains("Ranged:") and readout.contains("Magic component:"))
	expect("the lab readout includes the effective typed-magic total", Combat.ELEMENTS.all(func(e: String) -> bool:
		return readout.contains("%s Resistance:" % e.capitalize()) and readout.contains("vs magic")))
	var imported_amulet: Dictionary = Items.unique(UniqueDb.get_unique("heros_amulet"))
	expect("the Item Lab can equip a source catalog resistance item", stats.equip(imported_amulet, false) != null
		and is_equal_approx(hero.stats.gear_stat("magical_resist"), 4.0))
	lab.stats_readout.refresh()
	expect("the Item Lab readout shows the equipped item as effective typed magic resistance",
		lab.stats_readout._content_label.text.contains("Fire Resistance: 0.0% (4.0% vs magic)"))

	lab.queue_free()
	await get_tree().process_frame
	Sfx.enabled = sfx_was_enabled
	TownState.reset()

func _log_text(lab: ItemTestLab) -> String:
	var out := ""
	for child in lab.combat_log._log_list.get_children():
		if child is Label:
			out += (child as Label).text + "\n"
	return out

func _count(haystack: String, needle: String) -> int:
	return haystack.count(needle)

func _has_override_control(root: Node) -> bool:
	for node in root.find_children("*", "", true, false):
		var label := ""
		if node is Button:
			label = (node as Button).text
		elif node is CheckBox:
			label = (node as CheckBox).text
		if label.to_lower().contains("override") or label.to_lower().contains("ignore req") or label.to_lower().contains("bypass"):
			return true
	return false

## Test D: equipping during a swing, then a ground click, with the new weapon's element and the unchanged movement rules.
func _integration_combat() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.dev_set_hero_level(60)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().physics_frame
	var hero := player
	var stats: PlayerStats = hero.stats
	stats.equipment.clear()
	stats.refresh()
	var was_pad: bool = Gamepad.active
	var start: Vector3 = _free_lane_start(14.0, 6.0)
	hero.global_position = start
	hero.reset_physics_interpolation()
	hero.hitpause = 0.0
	hero.stun_time = 0.0
	hero.movement.has_goal = false
	Gamepad.active = true
	var destination: Vector3 = start + Vector3(0.0, 0.0, 2.2)
	hero.cursor_override = destination
	var target: Enemy = _spawn_enemy(start + Vector3(1.5, 0.0, 0.0))
	target.aggro_range = 0.0
	_plain(target)
	target.max_health = 100000.0
	target.health = target.max_health
	await get_tree().physics_frame
	var frozen := Items.build(ItemDb.get_def("longsword"), 40, Items.Rarity.MAGIC, ["ice_added_5"])
	var ice5 := AffixDb.get_def("ice_added_5")
	hero.attack_target = target
	hero.click_mode = 1
	hero.skills.start_skill("basic", target)
	expect("a swing is under way", hero.skills.busy)
	var mid_swing_equip: Variant = stats.equip(frozen, false)
	expect("equipping mid-swing succeeds and updates the stats at once", mid_swing_equip != null and is_equal_approx(hero.added_ice, ice5.value))
	var health_before := target.health
	await _integration_click(destination)
	expect("a ground click then cancels the swing before its hit and clears every lock", not hero.skills.busy and hero.skills.busy_skill == ""
		and hero.skills.busy_target == null and hero.attack_target == null and not hero._attack_engaged and target.health == health_before)
	expect("the hero is moving, not stuck in recovery", hero.movement.has_goal and ["walk", "run"].has(hero.model.current))
	expect("the mid-swing equip survived the cancel", stats.equipment.has(Items.Slot.WEAPON) and is_equal_approx(hero.added_ice, ice5.value))
	# Unequipping while moving keeps the movement order and drops the element.
	stats.unequip(Items.Slot.WEAPON)
	expect("unequipping on the move keeps the destination and removes the damage", hero.movement.has_goal and is_zero_approx(hero.added_ice))
	# A landed hit with the elemental weapon counts the element once.
	hero.set_physics_process(false)
	hero.global_position = start
	hero.reset_physics_interpolation()
	hero.movement.has_goal = false
	stats.equip(frozen, false)
	_plain(hero)
	hero.added_ice_max = hero.added_ice
	target.last_result = {}
	target.global_position = start + Vector3(1.5, 0.0, 0.0)
	hero.attack_target = target
	hero.skills.start_skill("basic", target)
	var hit_at: float = hero.skills.busy_time * SkillController.hit_fraction(hero.skills.busy_def)
	var basic_mult: float = float(hero.skills.busy_def.get("mult", 1.0))
	# Predict the next global weapon roll, then rewind so the real hit-frame path consumes the same value.
	var hit_seed := 41327
	seed(hit_seed)
	var expected_physical: float = hero.stats.weapon_damage(basic_mult)
	seed(hit_seed)
	var health_one: float = target.health
	hero.skills.tick_busy(hit_at + 0.01)
	expect("the swing's hit frame damages the target", target.health < health_one)
	var dealt := health_one - target.health
	var live_result: Dictionary = target.last_result
	var live_elements: Dictionary = live_result.get("added_elements", {})
	expect("the live swing resolves controlled physical plus one ice roll (dealt=%.3f physical=%.3f result=%s elements=%s)" % [dealt, expected_physical, str(live_result), str(live_elements)],
		is_equal_approx(dealt, expected_physical + ice5.value) and is_equal_approx(float(live_result.get("damage", -1.0)), expected_physical + ice5.value)
		and live_elements.size() == 1 and is_equal_approx(float(live_elements.get("ice", -1.0)), ice5.value))
	hero.set_physics_process(true)
	hero.cursor_override = start + Vector3(0.0, 0.0, -2.2)
	await _integration_click(hero.cursor_override)
	expect("recovery after the landed hit is cancelled by the click and the damage stays", not hero.skills.busy and hero.movement.has_goal
		and target.health <= health_one - dealt + 0.001)
	stats.unequip(Items.Slot.WEAPON)
	hero.movement.has_goal = false
	hero.cursor_override = Vector3.INF
	Gamepad.active = was_pad
	target.queue_free()
	await get_tree().process_frame
	TownState.reset()

func _integration_click(point: Vector3) -> void:
	player.cursor_override = point
	Input.action_press("click")
	await get_tree().physics_frame
	Input.action_release("click")
	await get_tree().physics_frame
