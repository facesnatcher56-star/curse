extends DevSuite
## Map-mode item traits (game/items/map_mode_traits.gd, issue #82): each of the 20 level 1-5 bases does what its trait says (asserted numerically),
## since #112 the traits, the item generation, the tooltips, the drop gaps (Battle Axe and Buckler from item level 3) and the extra modifiers are
## the same with map mode off (the walking game) as on, and work.

## Digest of 600 generated items in the default game before map-mode traits existed (seed 777, see _digest). Since #112 generation differs from it.
const GOLDEN_DIGEST := "356797020"

var _hero: Player
var _cutter: Player
var _m: MapMode
var _saved: Dictionary = {}

func _digest() -> String:
	seed(777)
	var parts: PackedStringArray = []
	for i in 150:
		parts.append(str(Items.roll_drop(1 + i % 8, ["weak", "normal", "strong", "miniboss"][i % 4])))
		parts.append(str(Items.item_of_kind(["item", "magic1", "magic2", "rare", "normal"][i % 5], 1 + i % 9, Vector2i(-5, 1))))
		parts.append(str(Items.make(i % 8, 1 + i % 3, 1 + i % 9)))
		parts.append(str(Items.shop_item(1 + i % 9, 0.3)))
	var result: String = str(" ".join(parts).hash())
	randomize()
	return result

func _near(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance

func _on() -> void:
	if _m == null:
		_m = MapMode.new()
		_m.hero = _hero
		_m.companion = _cutter
		game.add_child(_m)

func _off() -> void:
	if _m != null:
		_m.free()
		_m = null

func _wear(body: Player, def_id: String, level: int = 3, mods: Array = [], values: Dictionary = {}) -> Dictionary:
	var def: ItemDef = ItemDb.get_def(def_id)
	var item: Dictionary = Items.build(def, level, Items.Rarity.MAGIC if not mods.is_empty() else Items.Rarity.NORMAL, mods, "", values)
	body.stats.equipment[def.slot] = item
	body.stats.refresh()
	return item

func _strip(body: Player) -> void:
	body.stats.equipment.clear()
	body.stats.refresh()

func _foe(offset: Vector3) -> Enemy:
	var e: Enemy = _spawn_enemy(_hero.global_position + offset)
	e.set_physics_process(false)
	e.alert_delay = 999.0
	e.max_health = 100000.0
	e.health = 100000.0
	e.level = 1
	e.armor = 0.0
	e.toughness = 0.0
	e.block_chance = 0.0
	e.dodge_chance = 0.0
	e.ranged_dodge_chance = -1.0
	e.crit_chance = 0.0
	e.invulnerable_time = 0.0
	return e

func _auto(damage: float = 20.0, skill: String = "basic") -> Dictionary:
	return {"outcome": Combat.Outcome.HIT, "damage": damage, "weight": 1.0, "source": _hero, "type": Combat.DamageType.PHYSICAL, "skill_id": skill}

func _charge(body: Player, required: float = 100000.0) -> void:
	body.powers.reload_required = {"whirling_strike": required}
	body.powers.reload_remaining = {"whirling_strike": required}

func _left(body: Player) -> float:
	return float(body.powers.reload_remaining["whirling_strike"])

func _test_map_traits() -> void:
	TownState.persist = false
	var town_before: Dictionary = TownState.to_dict()   # the town and party this suite finds: put back at the end, so later suites start from what they always did
	TownState.reset()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().physics_frame
	_hero = player
	_cutter = game.companion
	_hero.set_physics_process(false)
	var cutter_disabled: bool = _cutter.testing_disabled
	_cutter.testing_disabled = true
	_cutter.set_physics_process(false)
	_saved = {"hero": _hero.stats.equipment.duplicate(true), "cutter": _cutter.stats.equipment.duplicate(true)}
	_hero.stats.equipment.clear()
	_cutter.stats.equipment.clear()
	_hero.stats.refresh()
	_cutter.stats.refresh()
	MapModeTraits.reset()

	# --- The table: 20 bases, all existing level 1-5 bases, every line renders ---------------------------------------------------------------
	var expected_bases: Array[String] = ["club", "dagger", "falchion", "longsword", "axe_1h", "mace", "short_bow", "leather_jerkin", "apprentice_robe",
		"mail_hauberk", "leather_cap", "iron_helm", "woven_hood", "leather_gloves", "iron_gauntlets", "studded_gloves", "leather_boots", "iron_greaves",
		"signet", "charm"]
	var table_ok: bool = MapModeTraits.TABLE.size() == 20
	var lines_ok: bool = true
	var unique_ids: Dictionary = {}
	for id in expected_bases:
		var def: ItemDef = ItemDb.get_def(id)
		table_ok = table_ok and MapModeTraits.TABLE.has(id) and def != null and def.levels[0] <= 5
		var line: String = MapModeTraits.line_for(id)
		lines_ok = lines_ok and line != "" and not line.contains("{") and not line.contains("}")
		unique_ids[String(MapModeTraits.TABLE[id]["id"])] = true
	expect("the table has the 20 trait bases of the issue, all existing bases with a level 1-5 variant", table_ok)
	expect("every trait has a distinct id and a finished tooltip line (no unfilled {number})", lines_ok and unique_ids.size() == 20)

	# --- Map mode off (the walking game, #112): every trait is worn and shown the same ------------------------------------------------------
	var traits_off: bool = true
	for id in expected_bases:
		var item: Dictionary = _wear(_hero, id, 5)
		var tid: String = String(MapModeTraits.TABLE[id]["id"])
		traits_off = traits_off and not MapMode.active and MapModeTraits.has(_hero, tid) and MapModeTraits.rows_for(item).size() == 1
	expect("with map mode off every trait is active on its wearer and shown on its card", traits_off)
	_strip(_hero)

	# --- One item generation for both modes (#112): drops and tooltips are map mode's with it off too ------------------------------------
	var off_digest: String = _digest()
	_on()
	var map_digest: String = _digest()
	_off()
	expect("item generation is the same with map mode on and off, and no longer the pre-trait default (digest %s, was %s)" % [off_digest, GOLDEN_DIGEST], map_digest == off_digest and off_digest != GOLDEN_DIGEST)
	var trait_rows_ok: bool = true
	for id in expected_bases:
		var sample: Dictionary = Items.build(ItemDb.get_def(id), 5, Items.Rarity.NORMAL)
		var coloured: bool = false
		for row in Items.rows(sample):
			coloured = coloured or row.get("color", Color.BLACK) == MapModeTraits.LINE_COLOR
		trait_rows_ok = trait_rows_ok and coloured
	expect("with map mode off each trait base's card carries its trait line", trait_rows_ok)
	var shield_pick_off: Dictionary = Items.pick_base(3, 3, Items.Slot.SHIELD)
	expect("with map mode off the Buckler is offered at item level 3 too", (shield_pick_off["def"] as ItemDef).id == "buckler" and int(shield_pick_off["level"]) == 3)
	var new_affixes: bool = false
	for a in AffixDb.eligible("weapon", 0, 50, ""):
		new_affixes = new_affixes or (a.id as String).begins_with("mm_")
	expect("with map mode off the modifier pool has the new modifiers too", new_affixes and not MapModeTraits.extra_affixes("weapon", 0, 50, "").is_empty())

	# --- Tooltips in map mode ---------------------------------------------------------------------------------------------------------------
	_on()
	var tip_ok: bool = true
	var colour_ok: bool = true
	for id in expected_bases:
		var sample: Dictionary = Items.build(ItemDb.get_def(id), 5, Items.Rarity.NORMAL)
		var texts: Array = Items.lines(sample)
		tip_ok = tip_ok and texts.has(MapModeTraits.line_for(id)) and (texts.find(MapModeTraits.line_for(id)) == texts.size() - 1 or (texts.find(MapModeTraits.line_for(id)) == texts.size() - 2 and String(texts[-1]).begins_with("Requires")))   # last, or just above the requirement line (the item level is in the card header)
		var shown := false
		for row in ItemTile.display_rows(sample, [], "hero"):
			if row["text"] == MapModeTraits.line_for(id):
				shown = row["color"] == MapModeTraits.LINE_COLOR
		colour_ok = colour_ok and shown
	expect("in map mode each of the 20 cards shows its trait line (above the requirement) through the shared tooltip code", tip_ok)
	expect("the shared card builder draws the trait line in its own colour", colour_ok)
	var no_trait: Dictionary = Items.build(ItemDb.get_def("band"), 8, Items.Rarity.NORMAL)
	expect("a base without a trait has no extra line in map mode", MapModeTraits.rows_for(no_trait).is_empty())

	# --- The drop gaps in map mode ----------------------------------------------------------------------------------------------------------
	var shield_pick: Dictionary = Items.pick_base(3, 3, Items.Slot.SHIELD)
	expect("map mode offers the Buckler at item level 3", (shield_pick["def"] as ItemDef).id == "buckler" and int(shield_pick["level"]) == 3)
	var seen_axe: bool = false
	var early_gap: bool = true
	for i in 400:
		var pick: Dictionary = Items.pick_base(3, 3, Items.Slot.WEAPON)
		seen_axe = seen_axe or ((pick["def"] as ItemDef).id == "axe_2h" and int(pick["level"]) == 3)
		var below: Dictionary = Items.pick_base(1, 2, Items.Slot.WEAPON)
		early_gap = early_gap and not ((below["def"] as ItemDef).id == "axe_2h" and int(below["level"]) <= 2)
	expect("map mode offers the Battle Axe (two-hander) at item level 3, but not below it", seen_axe and early_gap)
	var gap_item: Dictionary = Items.build(ItemDb.get_def("axe_2h"), 3, Items.Rarity.NORMAL)
	expect("a level 3 Battle Axe is a normal item with its DS2 curve at level 3", _near(float(gap_item["stats"]["min"]), (5.2 + 1.2 * 3.0) * 0.75 * float(ItemDb.get_def("axe_2h").stats.get("damage", 1.0)), 0.01))

	# --- The map-mode modifiers --------------------------------------------------------------------------------------------------------------
	var pool_ok: bool = true
	for stat in ["opening", "charge_on_kill", "marked_damage", "room_heal", "auto_speed"]:
		var found: bool = false
		for kind in ["weapon", "body", "ring", "helm", "gloves", "boots", "amulet"]:
			for a in AffixDb.eligible(kind, 0, 50, ""):
				found = found or (a.stat == stat and (a.id as String).begins_with("mm_"))
		pool_ok = pool_ok and found
	expect("map mode adds +Opening chance, +charge on kill, +damage to marked, +heal on room clear and +auto-attack speed to the modifier pool", pool_ok)
	_off()
	var pool_off: Array = []
	for kind in ["body", "boots"]:
		for a in AffixDb.eligible(kind, 0, 50, ""):
			pool_off.append(a.id)
	_on()
	var pool_on: Array = []
	for kind in ["body", "boots"]:
		for a in AffixDb.eligible(kind, 0, 50, ""):
			pool_on.append(a.id)
	expect("the modifier pool is the same with map mode off and on", pool_off == pool_on)
	var rolled: Dictionary = {}
	var kinds: Array = [Items.Slot.WEAPON, Items.Slot.GLOVES, Items.Slot.BOOTS, Items.Slot.RING, Items.Slot.AMULET, Items.Slot.HELM, Items.Slot.ARMOR]
	for i in 1500:
		var def_pick: ItemDef = ItemDb.of_slot(kinds[i % 7])[0]
		for id in Items.roll_mods(def_pick, 12, Items.Rarity.RARE):
			if (id as String).begins_with("mm_"):
				rolled[AffixDb.get_def(id).stat] = true
	expect("rare rolls in map mode actually pick the new modifiers (%s)" % ", ".join(PackedStringArray(rolled.keys())), rolled.size() == 5)
	var sample_mod: Dictionary = Items.build(ItemDb.get_def("leather_gloves"), 5, Items.Rarity.MAGIC, ["mm_auto_1"], "", {"mm_auto_1": 6.0})
	expect("a new modifier reads on the card as a percentage", Items.lines(sample_mod).has("+6% Auto-attack speed"))
	var saved_back: Dictionary = Items.from_save(Items.to_save(sample_mod))
	expect("an item with a map-mode modifier survives a save round trip", (saved_back["mods"] as Array) == ["mm_auto_1"] and _near(float(saved_back["mod_values"]["mm_auto_1"]), 6.0))

	var foe := _foe(Vector3(2, 0, 0))
	var foe2 := _foe(Vector3(3.6, 0, 0))

	# --- Club ---------------------------------------------------------------------------------------------------------------------------------
	TownState.passive_ranks["opening"] = 20
	_wear(_hero, "club", 3)
	var with_club: float = _hero.openings.spot_chance()
	_off()
	var club_off: float = _hero.openings.spot_chance()
	_on()
	expect("Club: +8 Opening chance on top of the passive's 12 (20 with map mode on and off)", _near(with_club, 20.0) and _near(club_off, 20.0))
	_strip(_hero)

	# --- Dagger -------------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "dagger", 3)
	var base_speed: float = _hero.stats.weapon_stat("speed", 1.0)
	expect("Dagger: +20%% attack speed (x%.2f from x%.2f)" % [_hero.stats.attack_speed(), base_speed], _near(_hero.stats.attack_speed(), base_speed * 1.2))
	_hero.openings.cooldown = 0.0
	_hero.openings.clear_mark(false)
	var plain_hit: Dictionary = MapModeTraits.modify_hit(foe, _auto(20.0))
	expect("Dagger: an auto on an enemy with no Opening is an ordinary hit", plain_hit["outcome"] == Combat.Outcome.HIT and _near(float(plain_hit["damage"]), 20.0))
	_hero.openings._mark(foe, "melee")
	var hp0: float = foe.health
	foe.receive(_auto(20.0), _hero.global_position)
	expect("Dagger: an auto on an enemy with an open Opening crits (x%.1f damage landed: %.1f)" % [_hero.crit_mult, hp0 - foe.health],
		_near(hp0 - foe.health, 20.0 * _hero.crit_mult, 0.05) and foe.last_result.get("outcome") == Combat.Outcome.CRITICAL)
	_hero.openings.clear_mark(false)
	_strip(_hero)

	# --- Falchion -----------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "falchion", 3)
	foe2.health = foe2.max_health
	_hero.on_dealt_hit(foe, _auto())
	_hero.on_dealt_hit(foe, _auto())
	var before_third: float = foe2.health
	_hero.on_dealt_hit(foe, _auto())
	var cleave_dealt: float = before_third - foe2.health
	var range_max: float = _hero.stats.weapon_range(1.0).y * 0.75
	expect("Falchion: the 3rd auto cleaves to one extra enemy (%.1f damage), the 1st and 2nd do not" % cleave_dealt, before_third == foe2.max_health and cleave_dealt > 0.0 and cleave_dealt <= range_max + 0.01)
	var again: float = foe2.health
	_hero.on_dealt_hit(foe, _auto())
	_hero.on_dealt_hit(foe, _auto())
	expect("Falchion: the count starts over after a cleave", foe2.health == again)
	_hero.on_dealt_hit(foe, _auto())
	expect("Falchion: and the 6th auto cleaves again", foe2.health < again)
	_strip(_hero)

	# --- Longsword ----------------------------------------------------------------------------------------------------------------------------
	_charge(_hero)
	_hero.on_dealt_hit(foe, _auto(100.0))
	var without_ls: float = 100000.0 - _left(_hero)
	_wear(_hero, "longsword", 3)
	_charge(_hero)
	_hero.on_dealt_hit(foe, _auto(100.0))
	var with_ls: float = 100000.0 - _left(_hero)
	expect("Longsword: 100 auto damage charges %.0f instead of %.0f (+10%%)" % [with_ls, without_ls], _near(without_ls, 100.0, 0.01) and _near(with_ls, 110.0, 0.01))
	_strip(_hero)

	# --- War Axe ------------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "axe_1h", 3)
	foe.bleed_time = 0.0
	foe.bleed_dps = 0.0
	_hero.on_dealt_hit(foe, _auto(20.0))
	expect("War Axe: an auto makes the enemy bleed 25%% of the hit a second for 3 s (%.1f/s, %.1f s)" % [foe.bleed_dps, foe.bleed_time], _near(foe.bleed_dps, 5.0) and _near(foe.bleed_time, 3.0))
	var hp_bleed: float = foe.health
	foe._actor_tick(1.0)
	expect("War Axe: the existing bleed ticks its damage (5 in a second)", _near(hp_bleed - foe.health, 5.0, 0.01))
	foe.bleed_time = 0.0
	foe.bleed_dps = 0.0
	_strip(_hero)

	# --- Mace ---------------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "mace", 4)
	foe.armor_shred = 0.0
	foe.armor_shred_time = 0.0
	_hero.on_dealt_hit(foe, _auto())
	var one_stack: float = foe.armor_shred
	_hero.on_dealt_hit(foe, _auto())
	var two_stacks: float = foe.armor_shred
	for i in 12:
		_hero.on_dealt_hit(foe, _auto())
	expect("Mace: each auto strips 3%% armour, stacking (%.2f, %.2f) to the 15%% cap (%.2f) for 4 s" % [one_stack, two_stacks, foe.armor_shred],
		_near(one_stack, 0.03) and _near(two_stacks, 0.06) and _near(foe.armor_shred, 0.15) and _near(foe.armor_shred_time, 4.0))
	foe.armor_shred = 0.0
	foe.armor_shred_time = 0.0
	_strip(_hero)

	# --- Short Bow ----------------------------------------------------------------------------------------------------------------------------
	_wear(_cutter, "short_bow", 3)
	MapModeTraits.time_override = 100.0
	var arrow: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": 10.0, "weight": 1.0, "source": _cutter, "type": Combat.DamageType.RANGED, "skill_id": "companion_arrow"}
	var hp_a: float = foe.health
	foe.receive(arrow.duplicate(), _cutter.global_position)
	var arrow_dealt: float = hp_a - foe.health
	var marked: bool = foe.has_meta(MapModeTraits.MARK_META)
	var hp_b: float = foe.health
	foe.receive(_auto(20.0), _hero.global_position)
	var warrior_dealt: float = hp_b - foe.health
	var hp_c: float = foe.health
	foe.receive(arrow.duplicate(), _cutter.global_position)
	var arrow_again: float = hp_c - foe.health
	MapModeTraits.time_override = 107.0
	var hp_d: float = foe.health
	foe.receive(_auto(20.0), _hero.global_position)
	var after_expiry: float = hp_d - foe.health
	expect("Short Bow: the Cutter's auto marks the target (%s) and the warrior then deals +15%% (%.1f of 20 -> 23), the archer's own arrows do not (%.1f)" % [marked, warrior_dealt, arrow_again],
		_near(arrow_dealt, 10.0, 0.01) and marked and _near(warrior_dealt, 23.0, 0.01) and _near(arrow_again, 10.0, 0.01))
	expect("Short Bow: the mark runs out after 6 s (%.1f)" % after_expiry, _near(after_expiry, 20.0, 0.01))
	foe.remove_meta(MapModeTraits.MARK_META)
	MapModeTraits.time_override = -1.0
	_strip(_cutter)

	# --- Leather Jerkin: first-hit shield ----------------------------------------------------------------------------------------------------
	_hero.health = _hero.max_health
	_wear(_hero, "leather_jerkin", 3)
	var pool: float = _hero.max_health * 0.2
	expect("Leather Jerkin tooltip reads the first-hit shield", MapModeTraits.line_for("leather_jerkin") == "A shield absorbs the first 20% of your max life in damage each fight")
	var hit := func(dmg: float, extra: Dictionary = {}) -> Dictionary:
		var r: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": dmg, "weight": 1.0}
		r.merge(extra, true)
		return _hero._filter_incoming(r)
	expect("Jerkin shield is empty before a fight starts", _near(float(hit.call(10.0)["damage"]), 10.0))
	MapModeTraits.on_fight_start(_m)
	var h1: Dictionary = hit.call(pool * 0.5)
	var h2: Dictionary = hit.call(pool * 0.4, {"aoe": true})   # AoE is absorbed too
	var h3: Dictionary = hit.call(pool * 0.3)                  # 0.1 of the pool is left: 0.2 gets through
	var h4: Dictionary = hit.call(25.0)
	expect("Jerkin shield soaks 20%% of max life (%.1f) over several hits (%.1f, %.1f, %.1f taken) and then stops (%.1f)" % [pool, h1["damage"], h2["damage"], h3["damage"], h4["damage"]],
		_near(float(h1["damage"]), 0.0) and _near(float(h2["damage"]), 0.0) and _near(float(h3["damage"]), pool * 0.2, 0.01) and _near(float(h4["damage"]), 25.0)
		and _near(float(h1["shield_absorbed"]) + float(h2["shield_absorbed"]) + float(h3["shield_absorbed"]), pool, 0.01))
	var zero: Dictionary = hit.call(0.0)
	expect("the shield never heals or goes below the pool on a zero hit", _near(float(zero["damage"]), 0.0))
	MapModeTraits.on_fight_start(_m)
	var fresh: float = float(hit.call(1.0)["damage"])
	expect("the shield is fresh at the next fight (1.0 hit -> %.1f taken)" % fresh, _near(fresh, 0.0))
	MapModeTraits.on_fight_start(_m)
	MapModeTraits.on_room_clear(_m)
	expect("the shield is gone when the fight ends", _near(float(hit.call(30.0)["damage"]), 30.0))
	MapModeTraits.on_fight_start(_m)
	_off()
	var shield_off: Dictionary = hit.call(30.0)
	_on()
	expect("with map mode off (the walking game) the shield soaks too", shield_off.has("shield_absorbed") and float(shield_off["damage"]) < 30.0)
	_strip(_hero)
	MapModeTraits.on_fight_start(_m)
	expect("without the Jerkin there is no shield", _near(float(hit.call(30.0)["damage"]), 30.0))

	# --- "of Mending": heal on room clear -------------------------------------------------------------------------------------------------------
	var mending: Dictionary = Items.build(ItemDb.get_def("leather_boots"), 5, Items.Rarity.MAGIC, ["mm_heal_1"], "", {"mm_heal_1": 8.0})
	_hero.stats.equipment[Items.Slot.BOOTS] = mending
	_hero.stats.refresh()
	_hero.health = _hero.max_health * 0.5
	MapModeTraits.on_room_clear(_m)
	expect("Heal on room clear: +8%% of max life (%.1f of %.1f)" % [_hero.health, _hero.max_health], _near(_hero.health, _hero.max_health * 0.58, 0.01))
	_hero.health = _hero.max_health * 0.95
	MapModeTraits.on_room_clear(_m)
	expect("Heal on room clear stops at max life", _near(_hero.health, _hero.max_health, 0.01))
	_hero.health = _hero.max_health * 0.5
	_off()
	MapModeTraits.on_room_clear(_m)
	_on()
	expect("Heal on room clear is inert with map mode off", _near(_hero.health, _hero.max_health * 0.5, 0.01))
	_hero.dead = true
	_hero.health = 0.0
	MapModeTraits.on_room_clear(_m)
	expect("Heal on room clear does not raise the dead", _hero.health == 0.0)
	_hero.dead = false
	_hero.health = _hero.max_health
	_strip(_hero)

	# --- Apprentice Robe ----------------------------------------------------------------------------------------------------------------------
	var plain_recharge: float = _hero.stats.power_recharge_damage(10.0, "melee")
	_wear(_hero, "apprentice_robe", 3)
	var robe_recharge: float = _hero.stats.power_recharge_damage(10.0, "melee")
	expect("Apprentice Robe: powers need 1/1.10 of the damage to charge (%.1f from %.1f)" % [robe_recharge, plain_recharge], _near(robe_recharge, plain_recharge / 1.1, 0.01))
	_strip(_hero)

	# --- Mail Hauberk -------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "mail_hauberk", 5)
	_charge(_hero)
	_hero._on_hurt({"damage": 40.0, "outcome": Combat.Outcome.HIT}, Vector3.ZERO)
	expect("Mail Hauberk: 40 damage taken charges the wearer's powers by 20 (%.1f)" % (100000.0 - _left(_hero)), _near(100000.0 - _left(_hero), 20.0, 0.01))
	_strip(_hero)
	_charge(_hero)
	_hero._on_hurt({"damage": 40.0, "outcome": Combat.Outcome.HIT}, Vector3.ZERO)
	expect("Mail Hauberk: without it, taking damage charges nothing", _left(_hero) == 100000.0)

	# --- Leather Cap --------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "leather_cap", 3)
	var shambler := _foe(Vector3(9, 0, 0))
	var early: bool = MapModeTraits.pre_telegraph(shambler, 0.4, shambler.attack_range)
	var shows: bool = shambler.is_telegraphing()
	shambler._tele_hold = 0.0
	var too_early: bool = MapModeTraits.pre_telegraph(shambler, 0.9, shambler.attack_range)
	var far_away: bool = MapModeTraits.pre_telegraph(shambler, 0.4, shambler.attack_range * 5.0)
	expect("Leather Cap: a swing 0.4 s away already shows its telegraph (lead 0.5 s); 0.9 s away or out of reach does not", early and shows and not too_early and not far_away)
	_strip(_hero)
	shambler._tele_hold = 0.0
	expect("without the cap the same moment shows nothing", not MapModeTraits.pre_telegraph(shambler, 0.4, shambler.attack_range))
	shambler.queue_free()

	# --- Iron Helm ----------------------------------------------------------------------------------------------------------------------------
	_hero.stun_time = 0.0
	_hero._gain_stun(1.0)
	var plain_stun: float = _hero.stun_time
	_hero.stun_time = 0.0
	_wear(_hero, "iron_helm", 5)
	_hero._gain_stun(1.0)
	expect("Iron Helm: a 1.0 s stun lasts 0.75 s (%.2f, %.2f without)" % [_hero.stun_time, plain_stun], _near(_hero.stun_time, 0.75) and _near(plain_stun, 1.0))
	_hero.stun_time = 0.0
	_strip(_hero)

	# --- Woven Hood ---------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "woven_hood", 5)
	MapModeTraits.time_override = 200.0
	var no_dash: float = _hero.stats.power_damage_mult()
	MapModeTraits.on_dash_arrived(_m)
	var just_after: float = _hero.stats.power_damage_mult()
	MapModeTraits.time_override = 202.5
	var inside: float = _hero.stats.power_damage_mult()
	MapModeTraits.time_override = 203.5
	var later: float = _hero.stats.power_damage_mult()
	expect("Woven Hood: power damage x1.15 for 3 s after a dash (x%.2f before, x%.2f, x%.2f at 2.5 s, x%.2f at 3.5 s)" % [no_dash, just_after, inside, later],
		_near(no_dash, 1.0) and _near(just_after, 1.15) and _near(inside, 1.15) and _near(later, 1.0))
	MapModeTraits.reset()
	_strip(_hero)

	# --- Leather Gloves -----------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "longsword", 3)
	var sword_speed: float = _hero.stats.attack_speed()
	_wear(_hero, "leather_gloves", 3)
	expect("Leather Gloves: +10%% auto-attack speed (x%.3f from x%.3f)" % [_hero.stats.attack_speed(), sword_speed], _near(_hero.stats.attack_speed(), sword_speed * 1.1, 0.0005))
	_strip(_hero)

	# --- Iron Gauntlets -----------------------------------------------------------------------------------------------------------------------
	TownState.passive_ranks["opening"] = 20
	var base_bonus: float = _hero.openings.damage_bonus()
	_wear(_hero, "iron_gauntlets", 5)
	expect("Iron Gauntlets: Opening executions hit 25 percentage points harder (%.0f from %.0f)" % [_hero.openings.damage_bonus(), base_bonus], _near(_hero.openings.damage_bonus(), base_bonus + 25.0))
	_strip(_hero)

	# --- Studded Gloves -----------------------------------------------------------------------------------------------------------------------
	var champion := _foe(Vector3(4, 0, 4))
	Champion.attach(champion, "shielded")
	_wear(_hero, "studded_gloves", 5)
	expect("Studded Gloves: +15 Opening chance against a champion, none against an ordinary enemy",
		_near(MapModeTraits.opening_bonus_vs(_hero, champion), 15.0) and is_zero_approx(MapModeTraits.opening_bonus_vs(_hero, foe)) and is_zero_approx(MapModeTraits.opening_bonus(_hero)))
	_strip(_hero)
	champion.queue_free()

	# --- Leather Boots ------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "longsword", 3)
	var sword_speed_2: float = _hero.stats.attack_speed()
	_wear(_hero, "leather_boots", 3)
	MapModeTraits.time_override = 300.0
	var boots_before: float = _hero.stats.attack_speed()
	MapModeTraits.on_dash_arrived(_m)
	var boots_burst: float = _hero.stats.attack_speed()
	MapModeTraits.time_override = 303.5
	var boots_after: float = _hero.stats.attack_speed()
	expect("Leather Boots: +30%% attack speed for 3 s after a dash (x%.2f before, x%.2f during, x%.2f after)" % [boots_before, boots_burst, boots_after],
		_near(boots_before, sword_speed_2) and _near(boots_burst, sword_speed_2 * 1.3) and _near(boots_after, sword_speed_2))
	MapModeTraits.reset()
	_strip(_hero)

	# --- Iron Greaves -------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "iron_greaves", 5)
	var near_foe := _foe(Vector3(5, 0, 0))
	var far_foe := _foe(Vector3(20, 0, 0))
	near_foe.knock = Vector3.ZERO
	far_foe.knock = Vector3.ZERO
	near_foe.stun_time = 0.0
	MapModeTraits.on_dash_arrived(_m)
	var thrown: Vector3 = near_foe.knock
	expect("Iron Greaves: landing knocks an enemy 5 m away back (%.1f m/s outward) and stuns it; one 20 m away is left alone" % thrown.x,
		thrown.x > 5.0 and near_foe.stun_time >= 0.5 and far_foe.knock == Vector3.ZERO)
	near_foe.queue_free()
	far_foe.queue_free()
	_strip(_hero)

	# --- Signet -------------------------------------------------------------------------------------------------------------------------------
	_wear(_hero, "signet", 3)
	_charge(_hero)
	_charge(_cutter)
	_hero.power_activated.emit("hero", "whirling_strike")
	expect("Signet: when the hero uses a power the Cutter gains 10%% charge (%.0f of 100000) and the user gains nothing" % (100000.0 - _left(_cutter)),
		_near(_left(_cutter), 90000.0, 0.5) and _left(_hero) == 100000.0)
	_cutter.power_activated.emit("cutter", "take_aim")
	expect("Signet: it works from the wearer only: the Cutter using a power shares nothing with the hero (owner decision)", _left(_hero) == 100000.0)
	_strip(_hero)
	_charge(_cutter)
	_hero.power_activated.emit("hero", "whirling_strike")
	expect("Signet: with no signet worn nothing is shared", _left(_cutter) == 100000.0)

	# --- Charm and the charge-on-kill modifier ------------------------------------------------------------------------------------------------
	_charge(_hero)
	_hero.on_enemy_killed(foe)
	var plain_kill: float = 100000.0 - _left(_hero)
	_wear(_hero, "charm", 3)
	_charge(_hero)
	_hero.on_enemy_killed(foe)
	var charm_kill: float = 100000.0 - _left(_hero)
	expect("Charm: a kill refills 5%% more of the power bar (%.0f instead of %.0f of 100000)" % [charm_kill, plain_kill], _near(plain_kill, 10000.0, 1.0) and _near(charm_kill, 15000.0, 1.0))
	_strip(_hero)
	_hero.stats.equipment[Items.Slot.RING] = Items.build(ItemDb.get_def("band"), 8, Items.Rarity.MAGIC, ["mm_charge_kill_1"], "", {"mm_charge_kill_1": 3.0})
	_hero.stats.refresh()
	_charge(_hero)
	_hero.on_enemy_killed(foe)
	expect("modifier +charge on kill: +3%% more per kill (%.0f)" % (100000.0 - _left(_hero)), _near(100000.0 - _left(_hero), 13000.0, 1.0))
	_strip(_hero)

	# --- The other new modifiers --------------------------------------------------------------------------------------------------------------
	_wear(_hero, "longsword", 3)
	var sword_speed_3: float = _hero.stats.attack_speed()
	_hero.stats.equipment[Items.Slot.GLOVES] = Items.build(ItemDb.get_def("iron_gauntlets"), 5, Items.Rarity.MAGIC, ["mm_auto_1"], "", {"mm_auto_1": 6.0})
	_hero.stats.refresh()
	expect("modifier +auto-attack speed: +6%% (x%.3f from x%.3f)" % [_hero.stats.attack_speed(), sword_speed_3], _near(_hero.stats.attack_speed(), sword_speed_3 * 1.06, 0.0005))
	_strip(_hero)
	TownState.passive_ranks["opening"] = 20
	var spot_base: float = _hero.openings.spot_chance()
	_hero.stats.equipment[Items.Slot.GLOVES] = Items.build(ItemDb.get_def("iron_gauntlets"), 5, Items.Rarity.MAGIC, ["mm_opening_1"], "", {"mm_opening_1": 5.0})
	_hero.stats.refresh()
	expect("modifier +Opening chance: +5 on the existing Opening roll (%.0f from %.0f)" % [_hero.openings.spot_chance(), spot_base], _near(_hero.openings.spot_chance(), spot_base + 5.0))
	_strip(_hero)
	_hero.stats.equipment[Items.Slot.RING] = Items.build(ItemDb.get_def("band"), 8, Items.Rarity.MAGIC, ["mm_marked_1"], "", {"mm_marked_1": 10.0})
	_hero.stats.refresh()
	MapModeTraits.time_override = 400.0
	foe.set_meta(MapModeTraits.MARK_META, {"until": 410.0, "by": "cutter", "pct": 0.0})
	var marked_hit: Dictionary = MapModeTraits.modify_hit(foe, _auto(20.0))
	expect("modifier +damage to marked enemies: +10%% on a marked enemy (%.1f of 20 -> 22)" % float(marked_hit["damage"]), _near(float(marked_hit["damage"]), 22.0, 0.01))
	foe.remove_meta(MapModeTraits.MARK_META)
	var unmarked_hit: Dictionary = MapModeTraits.modify_hit(foe, _auto(20.0))
	expect("and nothing on an unmarked one", _near(float(unmarked_hit["damage"]), 20.0, 0.01))
	MapModeTraits.reset()
	_strip(_hero)

	# --- Map mode off again: the effects stay while the gear is worn (#112) ------------------------------------------------------------------------
	_wear(_hero, "leather_gloves", 3)
	_hero.stats.equipment[Items.Slot.BOOTS] = Items.build(ItemDb.get_def("leather_boots"), 5, Items.Rarity.MAGIC, ["mm_auto_1"], "", {"mm_auto_1": 6.0})
	_hero.stats.refresh()
	var worn_on: float = _hero.stats.attack_speed()
	_off()
	var worn_off: float = _hero.stats.attack_speed()
	expect("worn trait and modifier speed (x%.3f) stay when map mode ends (x%.3f)" % [worn_on, worn_off], _near(worn_on, worn_off) and worn_off > _hero.stats.weapon_stat("speed", 1.0))
	expect("the item generation digest still matches after all of it", _digest() == off_digest)

	# --- Clean up -----------------------------------------------------------------------------------------------------------------------------
	for e in [foe, foe2]:
		if is_instance_valid(e):
			e.queue_free()
	TownState.passive_ranks.erase("opening")
	_hero.stats.equipment.clear()
	for place in _saved["hero"]:
		_hero.stats.equipment[place] = _saved["hero"][place]
	_cutter.stats.equipment.clear()
	for place in _saved["cutter"]:
		_cutter.stats.equipment[place] = _saved["cutter"][place]
	_hero.stats.refresh()
	_cutter.stats.refresh()
	_cutter.testing_disabled = cutter_disabled
	_cutter.set_physics_process(true)
	_hero.set_physics_process(true)
	MapModeTraits.reset()
	TownState.from_dict(town_before)
