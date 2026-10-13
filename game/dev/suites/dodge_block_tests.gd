extends DevSuite
## DS2 dodge and block from equipment: aggregation through the real equip path, resolution through Combat.resolve and Actor.receive, and the
## unchanged behaviour of everything around them (docs/DS2_DODGE_BLOCK.md).

const TRIALS := 20000
const TOLERANCE := 0.015

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
	body.ranged_dodge_chance = -1.0
	body.crit_chance = 0.0
	body.invulnerable_time = 0.0
	body.ward_time = 0.0
	body.forced_crits = 0

## Frequencies of each outcome over `TRIALS` blows of `kind` (a fixed seed makes the run repeatable).
func _rates(attacker: Actor, defender: Actor, kind: int = Combat.DamageType.PHYSICAL) -> Dictionary:
	seed(20260112)
	var counts: Dictionary = {Combat.Outcome.MISS: 0, Combat.Outcome.BLOCK: 0, Combat.Outcome.HIT: 0}
	for i in TRIALS:
		var r: Dictionary = Combat.resolve(attacker, defender, 10.0, kind, true, 1.0, false, false)
		counts[int(r["outcome"])] = int(counts.get(int(r["outcome"]), 0)) + 1
	return {"dodge": float(counts[Combat.Outcome.MISS]) / TRIALS, "block": float(counts[Combat.Outcome.BLOCK]) / TRIALS,
		"hit": float(counts[Combat.Outcome.HIT]) / TRIALS}

func _near(value: float, expected: float) -> bool:
	return absf(value - expected) <= TOLERANCE

func _worn(unique_id: String) -> Dictionary:
	return Items.unique(UniqueDb.get_unique(unique_id))

func _test_dodge_block() -> void:
	TownState.persist = false
	TownState.reset()
	var hero := player
	hero.set_physics_process(false)
	var stats: PlayerStats = hero.stats
	var enemy := _spawn_enemy(Vector3(28, 0, 28))
	enemy.set_physics_process(false)
	_plain(enemy)
	TownState.dev_set_hero_level(40)
	stats.equipment.clear()
	stats.bag.clear()
	stats.refresh()

	# --- Source data -------------------------------------------------------------------------------------------------------------------
	var dusk: UniqueDef = UniqueDb.get_unique("dusk")
	var grace: UniqueDef = UniqueDb.get_unique("grace_of_night")
	expect("Dusk is the DS2 Leather Jerkin (level 16): 6% melee dodge beside lightning and death resistance 13%, armour 8, magic find 18",
		dusk != null and dusk.base == "leather_jerkin" and dusk.level == 16 and dusk.mods == {"armor": 8.0, "lightning_resist": 13.0, "death_resist": 13.0, "dodge_melee": 6.0, "magic_find": 18.0})
	expect("Grace of Night is the DS2 Leather Boots (level 8): 8% ranged dodge, ice resistance 12%, life 12, armour 4",
		grace != null and grace.base == "leather_boots" and grace.level == 8 and grace.mods == {"life": 12.0, "armor": 4.0, "ice_resist": 12.0, "dodge_ranged": 8.0})
	expect("the three dodge stats and their card lines exist", AffixDb.describe_stat("dodge_melee", 6.0) == "+6% Chance to dodge melee"
		and AffixDb.describe_stat("dodge_ranged", 8.0) == "+8% Chance to dodge ranged" and AffixDb.describe_stat("dodge", 3.0) == "+3% Chance to dodge melee and ranged")

	# --- No equipment ------------------------------------------------------------------------------------------------------------------------
	_plain(hero)
	stats.refresh()
	expect("a hero with no gear has no dodge or block", is_zero_approx(hero.dodge_chance) and is_zero_approx(hero.ranged_dodge_chance)
		and is_zero_approx(hero.block_chance) and is_zero_approx(hero.ranged_block_chance))
	var none := _rates(enemy, hero)
	expect("and every one of %d blows lands" % TRIALS, is_equal_approx(none["hit"], 1.0))

	# --- Dodge gear: eligibility, aggregation, resolution -------------------------------------------------------------------------
	TownState.dev_set_hero_level(1)
	var jerkin := _worn("dusk")
	expect("a level-1 hero cannot wear Dusk (its requirement is unchanged): %s" % Items.requirement_text(jerkin, hero.member_id),
		stats.equip(jerkin, false) == null and is_zero_approx(hero.dodge_chance))
	stats.add_to_bag(jerkin)
	stats.refresh()
	expect("Dusk in the bag grants no dodge", is_zero_approx(hero.dodge_chance))
	stats.bag.clear()
	TownState.dev_set_hero_level(40)
	expect("a level-40 hero wears Dusk", stats.equip(jerkin, false) != null)
	expect("Dusk gives 6% melee dodge and no ranged dodge", is_equal_approx(hero.dodge_chance, 0.06) and is_zero_approx(hero.ranged_dodge_chance))
	expect("Dusk's other modifiers still apply (13% lightning and death resistance)", is_equal_approx(hero.lightning_resist, 0.13) and is_equal_approx(hero.death_resist, 0.13))
	_plain(enemy)
	hero.level = 1
	var melee := _rates(enemy, hero, Combat.DamageType.PHYSICAL)
	var arrows := _rates(enemy, hero, Combat.DamageType.RANGED)
	expect("melee blows are dodged about 6%% of the time (%.3f)" % melee["dodge"], _near(melee["dodge"], 0.06) and is_zero_approx(melee["block"]))
	expect("arrows are never dodged by melee-only gear", is_zero_approx(arrows["dodge"]) and is_equal_approx(arrows["hit"], 1.0))

	expect("Grace of Night is worn alongside", stats.equip(_worn("grace_of_night"), false) != null)
	expect("melee dodge stays 6% and ranged dodge is 8%", is_equal_approx(hero.dodge_chance, 0.06) and is_equal_approx(hero.ranged_dodge_chance, 0.08))
	hero.level = 1
	var arrows_both := _rates(enemy, hero, Combat.DamageType.RANGED)
	var melee_both := _rates(enemy, hero, Combat.DamageType.PHYSICAL)
	expect("arrows are dodged about 8%% (%.3f) and melee still about 6%% (%.3f)" % [arrows_both["dodge"], melee_both["dodge"]],
		_near(arrows_both["dodge"], 0.08) and _near(melee_both["dodge"], 0.06))
	expect("ice resistance from the boots stacks with the jerkin's other resistances", is_equal_approx(hero.ice_resist, 0.12) and is_equal_approx(hero.lightning_resist, 0.13))

	# --- Combination with the Dodge skill and general dodge gear -----------------------------------------------------------------------
	TownState.passive_ranks["dodge"] = 5
	stats.refresh()
	var skill := stats.passive("dodge")
	expect("the Dodge skill (rank 5: %.1f%%) adds to both kinds, gear is added on top" % skill, skill > 0.0
		and is_equal_approx(hero.dodge_chance, (skill + 6.0) / 100.0) and is_equal_approx(hero.ranged_dodge_chance, (skill + 8.0) / 100.0))
	var general := UniqueDef.new()
	general.id = "test_general_dodge"
	general.display_name = "Test Charm"
	general.base = "charm"
	general.level = 1
	general.mods = {"dodge": 3.0}
	UniqueDb.uniques()["test_general_dodge"] = general   # no catalogue item with general dodge fits a Curse base, so the stat is checked with this one
	var charm := Items.unique(general)
	expect("a general-dodge item equips", stats.equip(charm, false) != null)
	expect("general dodge (+3%) counts for melee and ranged: skill + gear", is_equal_approx(hero.dodge_chance, (skill + 6.0 + 3.0) / 100.0)
		and is_equal_approx(hero.ranged_dodge_chance, (skill + 8.0 + 3.0) / 100.0))
	TownState.passive_ranks.erase("dodge")
	stats.refresh()
	expect("without the skill only gear remains", is_equal_approx(hero.dodge_chance, 0.09) and is_equal_approx(hero.ranged_dodge_chance, 0.11))

	# --- Replacing, unequipping and repeating never stacks stale bonuses ------------------------------------------------------------------
	for i in 3:
		stats.equip(jerkin, false)
		stats.refresh()
	expect("re-equipping Dusk and refreshing repeatedly keeps 6% + 3% melee dodge", is_equal_approx(hero.dodge_chance, 0.09))
	var jerkin_two := _worn("dusk")
	stats.equip(jerkin_two, false)
	expect("replacing Dusk with a second Dusk does not double it", is_equal_approx(hero.dodge_chance, 0.09) and is_equal_approx(hero.lightning_resist, 0.13))
	stats.unequip(Items.Slot.ARMOR)
	expect("taking Dusk off removes its melee dodge (3% general remains) and its resistances", is_equal_approx(hero.dodge_chance, 0.03)
		and is_equal_approx(hero.ranged_dodge_chance, 0.11) and is_zero_approx(hero.lightning_resist))
	stats.unequip(Items.Slot.BOOTS)
	for place in Items.places(Items.Slot.RING):
		stats.unequip(place)
	for place in Items.places(Items.Slot.AMULET):
		stats.unequip(place)
	stats.refresh()
	expect("with every item removed the hero has no dodge again", is_zero_approx(hero.dodge_chance) and is_zero_approx(hero.ranged_dodge_chance) and stats.equipment.is_empty())
	UniqueDb.uniques().erase("test_general_dodge")

	# --- Saves keep the item and its dodge ----------------------------------------------------------------------------------------------
	var restored: Dictionary = Items.from_save(JSON.parse_string(JSON.stringify(Items.to_save(jerkin))))
	expect("Dusk survives a JSON save with its dodge", not restored.is_empty() and String(restored.get("unique", "")) == "dusk" and Items.mods_of(restored).get("dodge_melee") == 6.0)

	# --- Block: shield required, melee and ranged separate ---------------------------------------------------------------------------------
	TownState.passive_ranks["barricade"] = 1
	stats.refresh()
	expect("with no shield even the Barricade skill gives no block", is_zero_approx(hero.block_chance) and is_zero_approx(hero.ranged_block_chance))
	var ring_with_block := Items.build(ItemDb.of_slot(Items.Slot.RING)[0], 20, Items.Rarity.MAGIC, ["block_3"])
	stats.equip(ring_with_block, false)
	expect("a ring with a block modifier gives nothing without a shield (DS2: block needs a shield)", is_zero_approx(hero.block_chance))
	stats.unequip(Items.Slot.RING)
	var barricade := stats.passive("barricade")
	var shield := Items.build(ItemDb.get_def("buckler"), 6, Items.Rarity.MAGIC, ["block_4", "block_ranged_2"])
	var block_melee := AffixDb.get_def("block_4").value
	var block_ranged := AffixDb.get_def("block_ranged_2").value
	expect("a shield with block modifiers equips", stats.equip(shield, false) != null)
	expect("melee block = shield %.0f%% + Barricade %.0f%%, ranged block = shield %.0f%% + Barricade" % [block_melee, barricade, block_ranged],
		is_equal_approx(hero.block_chance, (block_melee + barricade) / 100.0) and is_equal_approx(hero.ranged_block_chance, (block_ranged + barricade) / 100.0))
	_plain(enemy)
	hero.level = 1
	var b_melee := _rates(enemy, hero, Combat.DamageType.PHYSICAL)
	var b_arrow := _rates(enemy, hero, Combat.DamageType.RANGED)
	expect("melee blows are blocked at the melee rate (%.3f), arrows at the ranged rate (%.3f)" % [b_melee["block"], b_arrow["block"]],
		_near(b_melee["block"], (block_melee + barricade) / 100.0) and _near(b_arrow["block"], (block_ranged + barricade) / 100.0) and is_zero_approx(b_melee["dodge"]))
	hero.level = 1
	stats.unequip(Items.Slot.SHIELD)
	expect("taking the shield off removes all block", is_zero_approx(hero.block_chance) and is_zero_approx(hero.ranged_block_chance))
	TownState.passive_ranks.erase("barricade")

	# --- Dodge and block together: dodge is rolled first, then block, and the outcomes are distinct ------------------------------------------
	_plain(hero)
	hero.dodge_chance = 0.30
	hero.block_chance = 0.50
	var both := _rates(enemy, hero)
	expect("dodge 30%% then block 50%% of the rest: dodged %.3f, blocked %.3f, hit %.3f" % [both["dodge"], both["block"], both["hit"]],
		_near(both["dodge"], 0.30) and _near(both["block"], 0.35) and _near(both["hit"], 0.35))
	var dodged := Combat.resolve(enemy, _certain(hero, 1.0, 0.0), 10.0, Combat.DamageType.PHYSICAL, true, 1.0, false, false)
	var blocked := Combat.resolve(enemy, _certain(hero, 0.0, 1.0), 10.0, Combat.DamageType.PHYSICAL, true, 1.0, false, false)
	expect("a dodge is a MISS and a block is a BLOCK, both deal no damage", int(dodged["outcome"]) == Combat.Outcome.MISS and int(blocked["outcome"]) == Combat.Outcome.BLOCK
		and is_zero_approx(float(dodged["damage"])) and is_zero_approx(float(blocked["damage"])))
	expect("the two have different floating text", Fx.OUTCOME_STYLE[Combat.Outcome.MISS][0] == "Dodge" and Fx.OUTCOME_STYLE[Combat.Outcome.BLOCK][0] == "Block")
	_plain(hero)

	# --- Everything else is untouched -----------------------------------------------------------------------------------------------------
	hero.dodge_chance = 1.0
	hero.ranged_dodge_chance = 1.0
	var fire := Combat.resolve(enemy, hero, 10.0, Combat.DamageType.FIRE, false, 1.0, false, false)
	expect("spells and powers (can_miss false) are never dodged, even by a certain dodge", int(fire["outcome"]) == Combat.Outcome.HIT and is_equal_approx(float(fire["damage"]), 10.0))
	expect("an enemy's own dodge still applies to every kind of blow", is_equal_approx(Combat.dodge_chance_against(enemy, Combat.DamageType.RANGED), enemy.dodge_chance))
	enemy.dodge_chance = 0.4
	expect("a monster with no separate ranged chance uses its one dodge for arrows too", is_equal_approx(Combat.dodge_chance_against(enemy, Combat.DamageType.RANGED), 0.4))
	_plain(enemy)
	_plain(hero)
	stats.refresh()
	stats.equip(_worn("dusk"), false)
	hero.level = 1
	hero.armor = 0.0   # typed hits meet armour too; Dusk carries some
	var ele := Combat.resolve(enemy, hero, 10.0, Combat.DamageType.LIGHTNING, false, 1.0, false, false)
	expect("Dusk's lightning resistance still reduces lightning damage by 13%", is_equal_approx(float(ele["damage"]), 10.0 * 0.87))

	# --- Real combat: Actor.receive with the equipped hero ------------------------------------------------------------------------------------
	stats.unequip(Items.Slot.ARMOR)
	stats.equip(_worn("dusk"), false)
	hero.max_health = 1.0e9
	hero.health = hero.max_health
	hero.level = 1
	_plain(enemy)
	seed(777)
	var landed := 0
	var dodged_count := 0
	var tally_before: int = int(Combat.tally.get(Combat.Outcome.MISS, 0))
	for i in 3000:
		var before := hero.health
		var blow := Combat.resolve(enemy, hero, 10.0, Combat.DamageType.PHYSICAL, true, 1.0, false, false)
		hero.receive(blow, enemy.global_position)
		if hero.health < before:
			landed += 1
		elif int(blow["outcome"]) == Combat.Outcome.MISS:
			dodged_count += 1
		hero.invulnerable_time = 0.0
	expect("through Actor.receive Dusk's wearer takes damage from ~94%% of melee blows (%d of 3000 dodged)" % dodged_count,
		landed + dodged_count == 3000 and absf(float(dodged_count) / 3000.0 - 0.06) < 0.025)
	expect("the live outcome tally counts the dodges", int(Combat.tally.get(Combat.Outcome.MISS, 0)) - tally_before >= dodged_count)
	hero.level = 1
	stats.unequip(Items.Slot.ARMOR)
	stats.refresh()
	enemy.queue_free()
	hero.set_physics_process(true)
	TownState.reset()
	await get_tree().process_frame
	await _test_dodge_block_lab()

## A copy of `base` with fixed dodge and block chances, for a single guaranteed outcome.
func _certain(base: Actor, dodge: float, block: float) -> Actor:
	var copy := Actor.new()
	copy.dodge_chance = dodge
	copy.block_chance = block
	copy.level = base.level
	return copy

## The Item Test Lab reports a dodge and a block as different outcomes.
func _test_dodge_block_lab() -> void:
	TownState.persist = false
	TownState.reset()
	var sfx_was_enabled: bool = Sfx.enabled
	Sfx.enabled = false
	var lab: ItemTestLab = (load("res://game/dev/item_lab/item_test_lab.tscn") as PackedScene).instantiate() as ItemTestLab
	game.add_child(lab)
	await get_tree().process_frame
	var hero: Player = lab.player
	var dummy: TrainingDummy = lab.dummy
	TownState.dev_set_hero_level(40)
	hero.stats.equipment.clear()
	hero.stats.refresh()
	lab.combat_log.clear_log()
	var dodge_hit := {"outcome": Combat.Outcome.MISS, "damage": 0.0, "type": Combat.DamageType.PHYSICAL, "skill_id": "basic"}
	var block_hit := {"outcome": Combat.Outcome.BLOCK, "damage": 0.0, "type": Combat.DamageType.PHYSICAL, "skill_id": "basic"}
	lab.combat_log.record_hit(dodge_hit, dummy, hero)
	lab.combat_log.record_hit(block_hit, dummy, hero)
	var text := ""
	for child in lab.combat_log._log_list.get_children():
		text += (child as Label).text + "\n"
	expect("the Lab log says DODGE for a dodge and BLOCK for a block", text.contains("[DODGE]") and text.contains("[BLOCK]") and not text.contains("[MISS]"))
	hero.stats.equip(Items.unique(UniqueDb.get_unique("dusk")), false)
	lab.stats_readout.refresh()
	var readout: String = lab.stats_readout._content_label.text
	expect("the Lab readout shows Dusk's 6% melee dodge and 0% ranged dodge", readout.contains("Dodge: 6.0% melee / 0.0% ranged"))
	hero.stats.equip(Items.unique(UniqueDb.get_unique("grace_of_night")), false)
	lab.stats_readout.refresh()
	expect("and Grace of Night's ranged dodge once worn", lab.stats_readout._content_label.text.contains("Dodge: 6.0% melee / 8.0% ranged"))
	lab._reset_lab_state()
	lab.queue_free()
	await get_tree().process_frame
	Sfx.enabled = sfx_was_enabled
	TownState.reset()
