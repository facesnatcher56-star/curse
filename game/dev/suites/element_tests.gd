extends DevSuite
## DS2 ice / lightning / death added damage and resistance equipment: source tiers, aggregation through real equipment, resolution
## through Combat.resolve and Actor.receive, and unchanged fire / physical behaviour (docs/ELEMENTAL_EQUIPMENT_VERIFICATION.md).

const NEW_ELEMENTS: Array[String] = ["ice", "lightning", "death"]
const BASE := 10.0

func _plain(body: Actor) -> void:
	body.level = 1
	body.armor = 0.0
	body.toughness = 0.0
	for element in Combat.ELEMENTS:
		body.set(element + "_resist", 0.0)
		body.set("added_" + element, 0.0)
		body.set("added_" + element + "_max", 0.0)
	body.block_chance = 0.0
	body.ranged_block_chance = 0.0
	body.dodge_chance = 0.0
	body.crit_chance = 0.0
	body.invulnerable_time = 0.0
	body.ward_time = 0.0
	body.forced_crits = 0

## The affix whose title and stat match (tier ids depend on the source ordering, not on this test).
func _affix(title: String, stat: String) -> AffixDef:
	for def in AffixDb.all().values():
		if (def as AffixDef).title == title and (def as AffixDef).stat == stat:
			return def
	return null

## A hit that cannot be dodged or blocked and cannot crit unless asked.
func _resolve(attacker: Actor, defender: Actor, kind: int = Combat.DamageType.PHYSICAL, crit: bool = false) -> Dictionary:
	return Combat.resolve(attacker, defender, BASE, kind, false, 1.0, crit, crit)

func _pin_rolls(body: Actor) -> void:
	for element in Combat.ELEMENTS:
		body.set("added_%s_max" % element, body.get("added_%s" % element))

func _test_elements() -> void:
	TownState.persist = false
	var hero := player
	var saved_hero := hero.character.to_dict()
	hero.set_physics_process(false)
	_plain(hero)
	var enemy := _spawn_enemy(Vector3(28, 0, 28))
	enemy.set_physics_process(false)
	_plain(enemy)
	enemy.max_health = 100000.0
	enemy.health = enemy.max_health

	var sword_def := ItemDb.get_def("longsword")
	var bow_def := ItemDb.get_def("short_bow")
	var ring_def := ItemDb.of_slot(Items.Slot.RING)[0]
	var amulet_def := ItemDb.of_slot(Items.Slot.AMULET)[0]

	# --- Source tiers: exact values from the DS2 catalog, melee / ranged discipline, armour-only resistances ------------------------
	var arctic := _affix("Arctic", "ice_added")
	var frozen := _affix("Frozen", "ice_added")
	var incandescent := _affix("Incandescent", "lightning_added")
	var necromantic := _affix("Necromantic", "death_added")
	var azure := _affix("Azure", "ice_resist")
	var amethyst := _affix("Amethyst", "death_resist")
	var pearl := _affix("Pearl", "lightning_resist")
	expect("all six alteration families are loaded as affixes", NEW_ELEMENTS.all(func(e: String) -> bool:
		return _count_family(e + "_added") == 12 and _count_family(e + "_resist") == 5))
	expect("Arctic is melee ice 13-22 at level 49", arctic != null and arctic.level == 49 and arctic.value == 13.0 and arctic.max_value == 22.0
		and arctic.classes == ["fighter"] and arctic.slots == ["weapon"] and arctic.position == "prefix")
	expect("Frozen is the ranged ice 13-22 twin", frozen != null and frozen.value == 13.0 and frozen.max_value == 22.0 and frozen.classes == ["ranger"])
	expect("Incandescent is ranged lightning 24-70 at level 85", incandescent != null and incandescent.level == 85
		and incandescent.value == 24.0 and incandescent.max_value == 70.0)
	expect("Necromantic is melee death 35-58 at level 85", necromantic != null and necromantic.level == 85
		and necromantic.value == 35.0 and necromantic.max_value == 58.0)
	expect("Azure / Amethyst / Pearl resistances are 10 / 25 / 25 percent on armour and jewellery only",
		azure != null and azure.value == 10.0 and azure.percent and amethyst != null and amethyst.value == 25.0
		and pearl != null and pearl.value == 25.0 and not azure.slots.has("weapon") and azure.slots.has("ring") and azure.slots.has("body"))

	# --- Aggregation through equipment, per element -----------------------------------------------------------------------------------
	for element in NEW_ELEMENTS:
		var added: AffixDef = AffixDb.get_def("%s_added_5" % element)   # a mid tier: a real range, minimum < maximum
		var sword := Items.build(sword_def, 60, Items.Rarity.MAGIC, [added.id])
		hero.stats.equipment = {Items.Slot.WEAPON: sword}
		hero.stats.refresh()
		expect("%s damage from the equipped weapon reaches the actor as %.0f-%.0f" % [element, added.value, added.max_value],
			is_equal_approx(Combat.added_damage(hero, element), added.value) and is_equal_approx(Combat.added_damage_max(hero, element), added.max_value))
		for other in Combat.ELEMENTS:
			if other != element:
				expect("%s damage does not leak into %s" % [element, other], is_zero_approx(Combat.added_damage(hero, other))
					and is_zero_approx(Combat.added_damage_max(hero, other)))
		expect("%s damage is not a resistance" % element, is_zero_approx(Combat.resistance_of(hero, element)))
		var card := Items.lines(sword)
		expect("%s weapon card reads the damage range" % element, card.has("+%d–%d %s damage" % [int(added.value), int(added.max_value), element.capitalize()]))
		hero.stats.unequip(Items.Slot.WEAPON)
		expect("unequipping the %s weapon removes the damage" % element, is_zero_approx(Combat.added_damage(hero, element))
			and is_zero_approx(Combat.added_damage_max(hero, element)))

		var res: AffixDef = AffixDb.get_def("%s_resist_2" % element)
		var charm := Items.build(ring_def, 40, Items.Rarity.MAGIC, [res.id])
		hero.stats.equipment = {Items.Slot.RING: charm}
		hero.stats.refresh()
		expect("%s resistance from a ring is %.0f%% for %s only" % [element, res.value, element],
			is_equal_approx(Combat.resistance_of(hero, element), res.value / 100.0)
			and Combat.ELEMENTS.all(func(e: String) -> bool: return e == element or is_zero_approx(Combat.resistance_of(hero, e))))
		expect("%s ring card reads the resistance" % element, Items.lines(charm).has("+%d%% %s resistance" % [int(res.value), element.capitalize()]))
		hero.stats.unequip(Items.Slot.RING)
		expect("unequipping the %s ring restores zero resistance" % element, is_zero_approx(Combat.resistance_of(hero, element)))

	# --- Outgoing added damage through Combat.resolve: exactly one roll per element, only on weapon hits -------------------------------
	for element in NEW_ELEMENTS:
		_plain(hero)
		hero.stats.equipment = {Items.Slot.WEAPON: Items.build(sword_def, 60, Items.Rarity.MAGIC, ["%s_added_5" % element])}
		hero.stats.refresh()
		var low := Combat.added_damage(hero, element)
		var high := Combat.added_damage_max(hero, element)
		var seen_low := INF
		var seen_high := -INF
		var inside := true
		for i in 300:
			var r := _resolve(hero, enemy)
			var rolled := float(r["added_elements"][element])
			seen_low = minf(seen_low, rolled)
			seen_high = maxf(seen_high, rolled)
			inside = inside and rolled >= low - 0.0001 and rolled <= high + 0.0001 and is_equal_approx(float(r["damage"]), BASE + rolled) \
				and (r["added_elements"] as Dictionary).size() == 1
		expect("%s added damage rolls inside its %.0f-%.0f range and is counted once" % [element, low, high], inside)
		expect("%s added damage is a real range, not a constant" % element, seen_high - seen_low > (high - low) * 0.5)
		_pin_rolls(hero)
		hero.armor = 0.0
		var pinned := _resolve(hero, enemy)
		expect("%s pinned roll adds its minimum on top of the physical blow" % element, is_equal_approx(float(pinned["damage"]), BASE + low))
		var spell := _resolve(hero, enemy, Combat.DamageType.FIRE)
		expect("%s added damage does not ride on a spell or power" % element, not spell.has("added_elements") and is_equal_approx(float(spell["damage"]), BASE))
		# Ranged weapon hits (arrows) are weapon hits too.
		var arrow := _resolve(hero, enemy, Combat.DamageType.RANGED)
		expect("%s added damage rides on a ranged weapon hit" % element, is_equal_approx(float(arrow["damage"]), BASE + low))

		# --- Matching resistance mitigates only its own element -----------------------------------------------------------------------
		enemy.set(element + "_resist", 0.5)
		var half := _resolve(hero, enemy)
		expect("%s: 50%% matching resistance halves the added damage only" % element, is_equal_approx(float(half["damage"]), BASE + low * 0.5)
			and is_equal_approx(float(half["added_elements"][element]), low * 0.5))
		enemy.set(element + "_resist", 0.0)
		for other in Combat.ELEMENTS:
			if other != element:
				enemy.set(other + "_resist", 0.9)
		var unrelated := _resolve(hero, enemy)
		expect("%s: 90%% resistance to every other element mitigates nothing" % element, is_equal_approx(float(unrelated["damage"]), BASE + low))
		_plain(enemy)
		enemy.max_health = 100000.0
		var zero := _resolve(hero, enemy)
		expect("%s: zero resistance is full damage" % element, is_equal_approx(float(zero["damage"]), BASE + low))
		# Boundaries on a monster: -100% doubles, -30% is x1.3, 100% negates, 200% heals (negative added), clamped beyond.
		for case in [[-0.3, 1.3], [-1.0, 2.0], [-2.5, 2.0], [1.0, 0.0], [0.8, 0.2]]:
			enemy.set(element + "_resist", case[0])
			var edge := _resolve(hero, enemy)
			expect("%s: monster resistance %.0f%% scales added damage x%.1f" % [element, case[0] * 100.0, case[1]],
				is_equal_approx(float(edge["added_elements"][element]) if edge.has("added_elements") else 0.0, low * case[1]))
		enemy.set(element + "_resist", 5.0)
		expect("%s: a monster resistance is capped at 200%%" % element, is_equal_approx(Combat.element_multiplier(enemy, element), -1.0))
		_plain(enemy)
		enemy.max_health = 100000.0

		# --- Armour, crit and level gap still shape the blow; the element is in it before armour (DS2 step 4) ---------------------------
		enemy.armor = 40.0
		var armoured := _resolve(hero, enemy)
		expect("%s: armour mitigates physical and added damage together" % element,
			is_equal_approx(float(armoured["damage"]), (BASE + low) * Combat.armor_factor(hero.level, 40.0)))
		enemy.armor = 0.0
		var crit := _resolve(hero, enemy, Combat.DamageType.PHYSICAL, true)
		expect("%s: a critical doubles the combined blow, element included" % element, int(crit["outcome"]) == Combat.Outcome.CRITICAL
			and is_equal_approx(float(crit["damage"]), (BASE + low) * hero.crit_mult))

		# --- Directly typed damage meets the matching resistance only ---------------------------------------------------------------------
		var typed: int = {"ice": Combat.DamageType.ICE, "lightning": Combat.DamageType.LIGHTNING, "death": Combat.DamageType.DEATH}[element]
		enemy.set(element + "_resist", 0.25)
		var typed_hit := _resolve(hero, enemy, typed)
		expect("%s: typed damage is cut by the matching 25%% resistance" % element, is_equal_approx(float(typed_hit["damage"]), BASE * 0.75)
			and not typed_hit.has("added_elements") and not Combat.weapon_hit_eligible(typed_hit))
		enemy.set(element + "_resist", 0.0)
		enemy.fire_resist = 0.9
		for other in NEW_ELEMENTS:
			if other != element:
				enemy.set(other + "_resist", 0.9)
		expect("%s: typed damage ignores fire and the other elements' resistance" % element, is_equal_approx(float(_resolve(hero, enemy, typed)["damage"]), BASE))
		_plain(enemy)
		enemy.max_health = 100000.0

	# --- Stacking across items, no double counting, mixed elements ---------------------------------------------------------------------
	_plain(hero)
	var multi_sword := Items.build(sword_def, 90, Items.Rarity.RARE, ["ice_added_5", "lightning_added_5", "death_added_5", "fire_added_3"])
	var multi_ring := Items.build(ring_def, 40, Items.Rarity.MAGIC, ["ice_added_2"])
	hero.stats.equipment = {Items.Slot.WEAPON: multi_sword, Items.Slot.RING: multi_ring}
	hero.stats.refresh()
	var ice5 := AffixDb.get_def("ice_added_5")
	var ice2 := AffixDb.get_def("ice_added_2")
	expect("ice damage from two equipped items stacks once", is_equal_approx(hero.stats.gear_stat("ice_added"), ice5.value + ice2.value)
		and is_equal_approx(hero.stats.gear_stat("ice_added_max"), ice5.max_value + ice2.max_value)
		and is_equal_approx(hero.added_ice, ice5.value + ice2.value) and is_equal_approx(hero.added_ice_max, ice5.max_value + ice2.max_value))
	var again_ice := hero.added_ice
	hero.stats.refresh()
	hero.stats.refresh()
	expect("repeated refresh never re-adds elemental damage", is_equal_approx(hero.added_ice, again_ice))
	_pin_rolls(hero)
	var all_four := _resolve(hero, enemy)
	var parts: Dictionary = all_four["added_elements"]
	var expected_total := BASE
	for element in Combat.ELEMENTS:
		expected_total += Combat.added_damage(hero, element)
	expect("physical, fire, ice, lightning and death are four independent entries summed once", parts.size() == 4
		and is_equal_approx(float(all_four["damage"]), expected_total)
		and is_equal_approx(float(parts["fire"]), AffixDb.get_def("fire_added_3").value))
	enemy.ice_resist = 1.0
	enemy.death_resist = -0.3
	var mixed := _resolve(hero, enemy)
	var mixed_total := BASE + float(parts["fire"]) + float(parts["lightning"]) + float(parts["death"]) * 1.3
	expect("mixed resistances (ice 100%, death -30%) each apply to their own element", is_equal_approx(float(mixed["damage"]), mixed_total)
		and is_zero_approx(float(mixed["added_elements"]["ice"])))
	_plain(enemy)
	enemy.max_health = 100000.0
	hero.stats.unequip(Items.Slot.RING)
	expect("removing one source leaves only the other's elemental damage", is_equal_approx(hero.added_ice, ice5.value))
	hero.stats.unequip(Items.Slot.WEAPON)
	expect("unequipping everything restores every element to zero", Combat.ELEMENTS.all(func(e: String) -> bool:
		return is_zero_approx(Combat.added_damage(hero, e)) and is_zero_approx(Combat.added_damage_max(hero, e))))

	# --- Fire compatibility: unchanged formula and resistance ---------------------------------------------------------------------------
	_plain(hero)
	hero.stats.equipment = {Items.Slot.WEAPON: Items.build(sword_def, 60, Items.Rarity.MAGIC, ["fire_added_3"])}
	hero.stats.refresh()
	_pin_rolls(hero)
	enemy.fire_resist = 0.5
	enemy.ice_resist = 1.0
	var fire_hit := _resolve(hero, enemy)
	expect("fire added damage still meets fire resistance only", is_equal_approx(float(fire_hit["damage"]), BASE + AffixDb.get_def("fire_added_3").value * 0.5))
	enemy.fire_resist = 0.0
	var typed_fire := _resolve(hero, enemy, Combat.DamageType.FIRE)
	enemy.fire_resist = 0.4
	expect("typed fire damage is still cut by fire resistance", is_equal_approx(float(_resolve(hero, enemy, Combat.DamageType.FIRE)["damage"]), BASE * 0.6)
		and is_equal_approx(float(typed_fire["damage"]), BASE) and is_equal_approx(Combat.fire_multiplier(enemy), 0.6))
	_plain(enemy)
	enemy.max_health = 100000.0
	hero.stats.unequip(Items.Slot.WEAPON)
	var plain_hit := _resolve(hero, enemy)
	expect("a hero with no elemental gear deals exactly the physical blow", is_equal_approx(float(plain_hit["damage"]), BASE) and not plain_hit.has("added_elements"))

	# --- Incoming damage on the hero: armour pieces give resistance; hero cap and floor --------------------------------------------------
	_plain(hero)
	var ring_ice := Items.build(ring_def, 40, Items.Rarity.MAGIC, ["ice_resist_1"])
	var amulet_ice := Items.build(amulet_def, 40, Items.Rarity.MAGIC, ["ice_resist_2"])
	hero.stats.equipment = {Items.Slot.RING: ring_ice, Items.Slot.AMULET: amulet_ice}
	hero.stats.refresh()
	hero.armor = 0.0
	var survival := hero.fire_resist
	expect("two ice-resistance items stack to 24% ice and touch nothing else", is_equal_approx(hero.ice_resist, 0.24)
		and is_zero_approx(hero.lightning_resist) and is_zero_approx(hero.death_resist) and is_equal_approx(hero.fire_resist, survival))
	enemy.added_ice = 10.0
	enemy.added_ice_max = 10.0
	enemy.added_lightning = 10.0
	enemy.added_lightning_max = 10.0
	var incoming := _resolve(enemy, hero)
	expect("incoming enemy ice is cut 24% while its lightning is not", is_equal_approx(float(incoming["added_elements"]["ice"]), 7.6)
		and is_equal_approx(float(incoming["added_elements"]["lightning"]), 10.0) and is_equal_approx(float(incoming["damage"]), BASE + 17.6))
	var health := hero.health
	var live := _resolve(enemy, hero)
	live["calm"] = true
	hero.receive(live, enemy.global_position)
	expect("Actor.receive applies the element-bearing result to life once", is_equal_approx(health - hero.health, float(live["damage"]))
		and (hero.last_result.get("added_elements", {}) as Dictionary).has("ice"))
	hero.health = hero.max_health
	hero.death_resist = 0.95
	expect("hero resistance is capped at 80%", is_equal_approx(Combat.element_multiplier(hero, "death"), 0.2))
	hero.death_resist = -0.3
	expect("hero vulnerability applies (death -30% is x1.3)", is_equal_approx(Combat.element_multiplier(hero, "death"), 1.3))
	hero.death_resist = 0.0
	expect("a hero with no death resistance takes the full typed blow", is_equal_approx(float(_resolve(enemy, hero, Combat.DamageType.DEATH)["damage"]), BASE))
	_plain(enemy)
	enemy.max_health = 100000.0

	# --- A negative source value flows through the real equipment path (the catalog has death -25% / -30% on items) ---------------------------
	_plain(hero)
	var cursed := Items.build(ring_def, 40, Items.Rarity.MAGIC, ["death_resist_1"])
	cursed["mod_values"]["death_resist_1"] = -30.0
	hero.stats.equipment = {Items.Slot.RING: cursed, Items.Slot.AMULET: Items.build(amulet_def, 40, Items.Rarity.MAGIC, ["death_resist_2"])}
	hero.stats.refresh()
	expect("a -30% death item and a +14% death item sum to -16%", is_equal_approx(hero.death_resist, -0.16))
	expect("net negative death resistance amplifies incoming death damage", is_equal_approx(Combat.element_multiplier(hero, "death"), 1.16))
	hero.stats.equipment = {}
	hero.stats.refresh()

	# --- Save / load of supported modifiers -----------------------------------------------------------------------------------------------------
	var saved_sword := Items.from_save(JSON.parse_string(JSON.stringify(Items.to_save(multi_sword))))
	var saved_ring := Items.from_save(JSON.parse_string(JSON.stringify(Items.to_save(ring_ice))))
	expect("elemental weapon modifiers survive an item save/load", Items.mods_of(saved_sword) == Items.mods_of(multi_sword)
		and Items.mods_of(saved_ring) == Items.mods_of(ring_ice))
	hero.character.equipment = {Items.Slot.WEAPON: multi_sword, Items.Slot.RING: ring_ice}
	var reloaded := CharacterState.from_dict("hero", JSON.parse_string(JSON.stringify(hero.character.to_dict())))
	hero.character.equipment = reloaded.equipment
	hero.stats.equipment = reloaded.equipment
	hero.stats.refresh()
	expect("a reloaded character re-derives the same elemental stats", is_equal_approx(hero.added_ice, ice5.value) and is_equal_approx(hero.added_death_max, AffixDb.get_def("death_added_5").max_value)
		and is_equal_approx(hero.ice_resist, 0.10))

	# --- Loot rolling honours the melee / ranged / armour source rules -------------------------------------------------------------------------
	seed(20261012)
	var melee_ok := true
	var ranged_ok := true
	var armour_ok := true
	var reached: Dictionary = {}
	var body_def := ItemDb.of_slot(Items.Slot.ARMOR)[0]
	for i in 400:
		for id in Items.roll_mods(sword_def, 90, Items.Rarity.RARE, 4):
			var a := AffixDb.get_def(String(id))
			reached[a.family] = true
			melee_ok = melee_ok and not (a.stat.ends_with("_resist") and a.stat != "fire_resist") and (a.classes.is_empty() or a.classes.has("fighter"))
		for id in Items.roll_mods(bow_def, 90, Items.Rarity.RARE, 4):
			var a := AffixDb.get_def(String(id))
			ranged_ok = ranged_ok and (a.classes.is_empty() or a.classes.has("ranger")) and not (a.stat.ends_with("_resist") and a.stat != "fire_resist")
		for id in Items.roll_mods(body_def, 90, Items.Rarity.RARE, 4):
			armour_ok = armour_ok and not AffixDb.get_def(String(id)).stat.ends_with("_added")
	expect("sword loot rolls ice, lightning and death damage, only fighter tiers", melee_ok
		and reached.has("ice_added") and reached.has("lightning_added") and reached.has("death_added"))
	expect("bow loot rolls only ranger elemental tiers", ranged_ok)
	expect("armour never rolls added elemental damage", armour_ok)

	# --- Cleanup ---------------------------------------------------------------------------------------------------------------------------------------
	PartyManager.current().members["hero"] = CharacterState.from_dict("hero", saved_hero)
	hero.stats.refresh()
	hero.health = hero.max_health
	hero.set_physics_process(true)
	enemy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _count_family(family: String) -> int:
	var n := 0
	for def in AffixDb.all().values():
		if (def as AffixDef).family == family:
			n += 1
	return n
