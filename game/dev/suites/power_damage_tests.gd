extends DevSuite
## DS2 `ALTER_POWER_DAMAGE_PERCENT` (rules.skrit `DamageGoPower$`): equipment that multiplies the damage of activated powers, and nothing else
## (docs/DS2_POWER_DAMAGE.md). Every ratio below compares two real runs of the same power under the same random seed, so the only difference is the gear.

const RATIO_TOLERANCE := 0.0005

var _ring: Array[Enemy] = []

func _plain(body: Actor) -> void:
	body.armor = 0.0
	body.toughness = 0.0
	body.block_chance = 0.0
	body.ranged_block_chance = 0.0
	body.dodge_chance = 0.0
	body.ranged_dodge_chance = -1.0
	body.crit_chance = 0.0
	for element in Combat.ELEMENTS:
		body.set(element + "_resist", 0.0)

func _register(id: String, base: String, power: float) -> Dictionary:
	var def := UniqueDef.new()
	def.id = id
	def.display_name = id
	def.base = base
	def.level = 1
	def.mods = {"power_damage": power}
	UniqueDb.uniques()[id] = def   # test-only items carrying nothing but the bonus, so a changed weapon roll cannot blur the ratios
	return Items.unique(def)

const RING_AT := [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.6)]

func _heal_all() -> void:
	player.crit_chance = 0.0   # every refresh restores the Critical Strike skill's chance; a blow here must not crit
	for i in _ring.size():
		var e: Enemy = _ring[i]
		e.global_position = player.global_position + RING_AT[i]
		e.velocity = Vector3.ZERO
		e.knock = Vector3.ZERO
		e.max_health = 1.0e7
		e.health = e.max_health
		e.stun_time = 0.0
		e.stop_burning()

func _loss() -> float:
	var total := 0.0
	for e in _ring:
		total += e.max_health - e.health
	return total

## Whirling Strike (a physical power). One enemy stays in reach: with several, the effects of each hit draw random numbers between the damage
## rolls, so the rolls of two runs would differ; a single hit is exact.
func _whirling() -> float:
	_heal_all()
	_ring[1].global_position += Vector3(0, 0, 40)
	_ring[2].global_position += Vector3(0, 0, 40)
	player.powers.reset()
	player.powers.activate("whirling_strike", player.global_position)
	seed(1101)   # the rolls are drawn at the strike, so the seed is set once the wind-up is under way
	_settle_cast(player)
	return _loss()

## Flame Nexus (a fire power).
func _nexus() -> float:
	_heal_all()
	player.powers.reset()
	seed(1202)
	player.powers.activate("flame_nexus", player.global_position)
	return _loss()

## One basic swing, armed with Brutal Attack or not (a landed blow, read at the hit frame).
func _swing(brutal: bool) -> float:
	_heal_all()
	var target: Enemy = _ring[0]
	player.skills.cancel_action()
	player.skills.combo_step = 0   # every swing is the same first blow of the combo
	player.skills.combo_timer = 0.0
	player.skills.brutal_armed = brutal
	player.stats.brutal_reload_remaining = 0.0
	player.attack_target = target
	seed(1303 if brutal else 1404)
	player.skills.start_skill("basic", target)
	var hit_at: float = player.skills.busy_time * SkillController.hit_fraction(player.skills.busy_def)
	player.skills.tick_busy(hit_at + 0.01)
	var loss: float = target.max_health - target.health
	player.skills.cancel_action()
	player.skills.brutal_armed = false
	player.attack_target = null
	return loss

func _ratio(bonus: float, base: float) -> float:
	return bonus / maxf(base, 0.0001)

func _test_power_damage() -> void:
	TownState.persist = false
	TownState.reset()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var hero := player
	hero.set_physics_process(false)
	var stats: PlayerStats = hero.stats
	TownState.dev_set_hero_level(30)
	TownState.passive_ranks = {"critical_strike": 8, "fortitude": 8, "smite": 1, "overbear": 1, "barricade": 1, "dodge": 5, "survival": 3,
		"devastation": 2, "searing_flames": 8, "ignite": 1}
	hero.global_position = Vector3(30, 0, 30)
	hero.reset_physics_interpolation()
	stats.equipment.clear()
	for item in Items.starting_gear():
		stats.equip(item, false)
	stats.refresh()
	_plain(hero)
	hero.level = 30
	_ring.clear()
	for offset in RING_AT:
		var e: Enemy = _spawn_enemy(hero.global_position + offset)
		e.aggro_range = 0.0
		e.set_physics_process(false)
		_plain(e)
		_ring.append(e)
	await get_tree().process_frame
	hero.stats.refresh()
	hero.crit_chance = 0.0

	# --- Source data -----------------------------------------------------------------------------------------------------------------------
	var talisman: UniqueDef = UniqueDb.get_unique("assailing_talisman")
	expect("Assailing Talisman is DS2's crafted Talisman (level 75): +18 max melee and ranged, +7%% power recharge, +3%% power damage, 30%% reflect",
		talisman != null and talisman.base == "talisman" and talisman.level == 75
		and talisman.mods == {"melee_max": 18.0, "ranged_max": 18.0, "recharge": 7.0, "power_damage": 3.0, "reflect": 30.0})
	expect("it keeps its source requirement (melee or ranged level - 8)", talisman.requirements == "melee:#item_level-8|ranged:#item_level-8")
	expect("the stat reads on a card", AffixDb.describe_stat("power_damage", 3.0) == "+3% Power damage")

	# --- No bonus equipment ---------------------------------------------------------------------------------------------------------------------
	expect("without bonus gear the multiplier is exactly 1", is_equal_approx(stats.power_damage_mult(), 1.0))
	var base_whirl := _whirling()
	var base_nexus := _nexus()
	var base_brutal := _swing(true)
	var base_basic := _swing(false)
	var base_spell := stats.spell_range()
	expect("every power and the ordinary swing do damage (%.0f / %.0f / %.0f / %.0f)" % [base_whirl, base_nexus, base_brutal, base_basic],
		base_whirl > 0.0 and base_nexus > 0.0 and base_brutal > base_basic and base_basic > 0.0)
	expect("Brutal Attack is far stronger than a plain swing (its own multiplier is untouched)", base_brutal / base_basic > 10.0)
	expect("the same seed repeats the same damage (the ratios below are exact)", is_equal_approx(_whirling(), base_whirl) and is_equal_approx(_swing(true), base_brutal))

	# --- One +3% source ----------------------------------------------------------------------------------------------------------------------------
	var ring3 := _register("test_pd3", "signet", 3.0)
	var ring5 := _register("test_pd5", "signet", 5.0)
	var charm2 := _register("test_pd2", "charm", 2.0)
	expect("a +3%% ring equips", stats.equip(ring3, false) != null)
	expect("the multiplier is 1.03", is_equal_approx(stats.power_damage_mult(), 1.03))
	expect("Whirling Strike deals 3%% more (%.5f)" % _ratio(_whirling(), base_whirl), absf(_ratio(_whirling(), base_whirl) - 1.03) < RATIO_TOLERANCE)
	expect("Flame Nexus (fire) deals 3%% more (%.5f)" % _ratio(_nexus(), base_nexus), absf(_ratio(_nexus(), base_nexus) - 1.03) < RATIO_TOLERANCE)
	expect("an armed Brutal Attack deals 3%% more (%.5f)" % _ratio(_swing(true), base_brutal), absf(_ratio(_swing(true), base_brutal) - 1.03) < RATIO_TOLERANCE)
	expect("an ordinary swing is unchanged (%.5f)" % _ratio(_swing(false), base_basic), absf(_ratio(_swing(false), base_basic) - 1.0) < RATIO_TOLERANCE)
	var plain_hit := Combat.resolve(hero, _ring[0], 10.0, Combat.DamageType.PHYSICAL, false, 1.0, false, false)
	var no_gear_hit_damage := float(plain_hit["damage"])
	expect("Combat.resolve itself knows nothing of power damage (a plain blow of 10 stays 10 before added damage)", is_equal_approx(no_gear_hit_damage, 10.0))
	expect("Fireball's ordinary spell range is unchanged by power damage", stats.spell_range().is_equal_approx(base_spell))

	# --- Stacking: sources add, they do not multiply -------------------------------------------------------------------------------------------------
	expect("a second ring (+5%%) and an amulet (+2%%) equip", stats.equip(ring5, false) != null and stats.equip(charm2, false) != null)
	expect("the sources add to +10%% (not 1.03 x 1.05 x 1.02 = 1.1033 ... 1.1)", is_equal_approx(stats.power_damage_mult(), 1.10) and stats.gear_stat("power_damage") == 10.0)
	expect("Whirling Strike deals 10%% more once (%.5f)" % _ratio(_whirling(), base_whirl), absf(_ratio(_whirling(), base_whirl) - 1.10) < RATIO_TOLERANCE)
	expect("Brutal Attack deals 10%% more once (%.5f)" % _ratio(_swing(true), base_brutal), absf(_ratio(_swing(true), base_brutal) - 1.10) < RATIO_TOLERANCE)
	expect("Flame Nexus deals 10%% more once (%.5f)" % _ratio(_nexus(), base_nexus), absf(_ratio(_nexus(), base_nexus) - 1.10) < RATIO_TOLERANCE)
	expect("the ordinary swing is still unchanged", absf(_ratio(_swing(false), base_basic) - 1.0) < RATIO_TOLERANCE)

	# --- Replace, repeat, unequip ----------------------------------------------------------------------------------------------------------------------
	var ring3_again := _register("test_pd3", "signet", 3.0)
	stats.equip(ring3_again, false, Items.Slot.RING2)   # replaces the +5% ring
	expect("replacing the +5%% ring with a +3%% ring gives +8%% at once", is_equal_approx(stats.power_damage_mult(), 1.08))
	expect("and the next Whirling Strike already uses it (%.5f)" % _ratio(_whirling(), base_whirl), absf(_ratio(_whirling(), base_whirl) - 1.08) < RATIO_TOLERANCE)
	for i in 3:
		stats.equip(charm2, false)
		stats.refresh()
	expect("equipping the same amulet again and refreshing never stacks it", is_equal_approx(stats.power_damage_mult(), 1.08))
	stats.unequip(Items.Slot.AMULET)
	expect("taking the amulet off removes exactly its 2%%", is_equal_approx(stats.power_damage_mult(), 1.06))
	for place in Items.places(Items.Slot.RING):
		stats.unequip(place)
	expect("with all three gone the multiplier is 1 again", is_equal_approx(stats.power_damage_mult(), 1.0) and stats.equipment.has(Items.Slot.WEAPON))
	expect("and every power is back to its base damage (%.5f / %.5f / %.5f)" % [_ratio(_whirling(), base_whirl), _ratio(_nexus(), base_nexus), _ratio(_swing(true), base_brutal)],
		absf(_ratio(_whirling(), base_whirl) - 1.0) < RATIO_TOLERANCE and absf(_ratio(_nexus(), base_nexus) - 1.0) < RATIO_TOLERANCE
		and absf(_ratio(_swing(true), base_brutal) - 1.0) < RATIO_TOLERANCE)
	stats.bag.clear()
	stats.add_to_bag(ring3)
	stats.refresh()
	expect("an ineligible or unworn item in the bag adds nothing", is_equal_approx(stats.power_damage_mult(), 1.0))
	stats.bag.clear()

	# --- The real item: requirement, stats, saves ---------------------------------------------------------------------------------------------------
	var real := Items.unique(talisman)
	expect("the level-30 hero cannot wear the Assailing Talisman: %s" % Items.requirement_text(real, hero.member_id),
		not Items.hero_can_wear(real, hero.member_id) and stats.equip(real, false) == null and is_equal_approx(stats.power_damage_mult(), 1.0))
	TownState.dev_set_hero_level(80)
	hero.stats.refresh()
	hero.level = 30
	expect("a level-80 hero wears it", stats.equip(real, false) != null)
	expect("it gives +3%% power damage, +7%% recharge, +30%% reflect and the damage", is_equal_approx(stats.power_damage_mult(), 1.03)
		and stats.gear_stat("recharge") == 7.0 and stats.gear_stat("reflect") == 30.0 and stats.gear_stat("melee_max") == 18.0 and stats.gear_stat("ranged_max") == 18.0)
	expect("its card lists the power damage", Items.lines(real, hero.member_id).has("+3% Power damage"))
	var restored: Dictionary = Items.from_save(JSON.parse_string(JSON.stringify(Items.to_save(real))))
	expect("it survives a JSON save with its power damage and its source requirement", not restored.is_empty() and String(restored.get("unique", "")) == "assailing_talisman"
		and Items.mods_of(restored).get("power_damage") == 3.0 and Items.requirement_expression(restored) == "melee:#item_level-8|ranged:#item_level-8")
	var record: String = JSON.stringify(hero.character.to_dict())
	expect("the character record keeps the worn talisman", record.contains("assailing_talisman"))
	hero.character.to_dict()
	stats.unequip(Items.Slot.AMULET)
	expect("taking it off removes the bonus", is_equal_approx(stats.power_damage_mult(), 1.0))

	# --- Take Aim: the arrow carries the multiplier -------------------------------------------------------------------------------------------------
	stats.equip(ring3, false)
	var weapon_was: Variant = stats.equipment.get(Items.Slot.WEAPON)
	stats.wear(Items.Slot.WEAPON, Items.build(ItemDb.get_def("short_bow"), 6, Items.Rarity.NORMAL))
	hero.refresh_weapon_model()
	await get_tree().process_frame
	TownState.passive_ranks["critical_shot"] = 1
	var armed_damage := _arrow_damage(true)
	var plain_damage := _arrow_damage(false)
	stats.unequip(Items.Slot.RING)
	var armed_base := _arrow_damage(true)
	var plain_base := _arrow_damage(false)
	if armed_base > 0.0:
		expect("Take Aim's arrow deals 3%% more with the ring (%.5f)" % (armed_damage / armed_base), absf(armed_damage / armed_base - 1.03) < RATIO_TOLERANCE)
		expect("an ordinary arrow does not (%.5f)" % (plain_damage / plain_base), plain_base > 0.0 and absf(plain_damage / plain_base - 1.0) < RATIO_TOLERANCE)
	else:
		expect("Take Aim could be armed with the test bow", false)
	if weapon_was != null:
		stats.wear(Items.Slot.WEAPON, weapon_was)
	hero.refresh_weapon_model()

	# --- Dodge and block untouched, readout --------------------------------------------------------------------------------------------------------------
	stats.equip(Items.unique(UniqueDb.get_unique("dusk")), false)
	stats.equip(ring3, false)
	expect("dodge gear still works beside power damage", is_equal_approx(hero.dodge_chance, (stats.passive("dodge") + 6.0) / 100.0) and is_equal_approx(stats.power_damage_mult(), 1.03))
	for id in ["test_pd3", "test_pd5", "test_pd2"]:
		UniqueDb.uniques().erase(id)
	for e in _ring:
		e.queue_free()
	hero.set_physics_process(true)
	TownState.reset()
	await get_tree().process_frame
	await _power_damage_lab()

## The damage of the arrow Take Aim (armed) or an ordinary shot fires, read off the arrow itself (the hero's real firing code).
func _arrow_damage(armed: bool) -> float:
	var hero := player
	if hero.bow == null:
		return 0.0
	for node in get_tree().current_scene.get_children():
		if node is CompanionArrow:
			node.queue_free()
	hero.bow.armed = armed
	hero.attack_target = _ring[0]
	seed(1505)
	hero.bow.start(_ring[0])
	seed(1505)   # the charge effect draws random numbers; the arrow's own roll is the next draw
	hero.bow.loose()   # the arrow leaves exactly as it does at the end of the draw
	var found := 0.0
	for node in get_tree().current_scene.get_children():
		if node is CompanionArrow:
			found = float((node as CompanionArrow).damage)
	hero.skills.cancel_action()
	hero.bow.armed = false
	hero.attack_target = null
	return found

## The Item Test Lab shows the power damage bonus in the existing stats readout.
func _power_damage_lab() -> void:
	TownState.persist = false
	TownState.reset()
	var sfx_was_enabled: bool = Sfx.enabled
	Sfx.enabled = false
	var lab: ItemTestLab = (load("res://game/dev/item_lab/item_test_lab.tscn") as PackedScene).instantiate() as ItemTestLab
	game.add_child(lab)
	await get_tree().process_frame
	TownState.dev_set_hero_level(80)
	lab.player.stats.refresh()
	lab.stats_readout.refresh()
	expect("the Lab readout shows no power damage bonus by default", lab.stats_readout._content_label.text.contains("Power damage: +0%"))
	lab.player.stats.equip(Items.unique(UniqueDb.get_unique("assailing_talisman")), false)
	lab.stats_readout.refresh()
	expect("and +3%% with the Assailing Talisman", lab.stats_readout._content_label.text.contains("Power damage: +3%"))
	lab._reset_lab_state()
	lab.queue_free()
	await get_tree().process_frame
	Sfx.enabled = sfx_was_enabled
	TownState.reset()
