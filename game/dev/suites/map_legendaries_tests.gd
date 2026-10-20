extends DevSuite
## The first map-mode legendaries (game/items/map_mode_legendaries.gd, issue #82): each rewrites one power, only while MapMode.active and only for the
## member who wears it (Hero's Amulet: either member). Every effect is compared with the same power and the same item with map mode off, and with
## the plain base in map mode. Also: the first champion of a run always drops one (the second does not guarantee one), the drop gets a beam,
## the tooltip line shows in map mode only, and the default unique pool is untouched.

const DELTA := 1.0 / 60.0

var _mm: MapMode

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _plain(body: Actor) -> void:
	body.level = 1
	body.armor = 0.0
	body.toughness = 0.0
	body.block_chance = 0.0
	body.ranged_block_chance = 0.0
	body.dodge_chance = 0.0
	body.ranged_dodge_chance = -1.0
	body.crit_chance = 0.0
	body.stun_resist = 0.0
	body.knock_resist = 0.0

func _foe(at: Vector3, health: float = 1.0e7) -> Enemy:
	var foe: Enemy = _spawn_enemy(at)
	foe.set_physics_process(false)
	foe.aggro_range = 0.0
	foe.alert_delay = 999.0
	_plain(foe)
	foe.max_health = health
	foe.health = health
	return foe

func _map_mode(on: bool) -> void:
	if on and _mm == null:
		_mm = MapMode.new()
		game.add_child(_mm)
	elif not on and _mm != null:
		_mm.queue_free()
		_mm = null
		await get_tree().process_frame

func _wear(body: Player, slot: int, item: Dictionary) -> void:
	body.stats.equipment[slot] = item
	body.stats.refresh()

func _lost(e: Enemy) -> float:
	return e.max_health - e.health

func _count_legendaries() -> int:
	var n := 0
	for drop in get_tree().get_nodes_in_group("loot"):
		if MapModeLegendaries.id_of((drop as LootDrop).item) != "":
			n += 1
	return n

func _clear_loot() -> void:
	for drop in get_tree().get_nodes_in_group("loot"):
		drop.queue_free()

func _test_map_legendaries() -> void:
	TownState.persist = false
	TownState.reset()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var hero: Player = player
	var archer: ArcherCompanion = game.companion
	var archer_was_disabled: bool = archer.testing_disabled
	hero.set_physics_process(false)
	archer.testing_disabled = true
	TownState.dev_set_hero_level(30)
	TownState.passive_ranks = {"critical_strike": 8, "fortitude": 8, "smite": 1, "overbear": 1, "barricade": 1, "dodge": 5, "survival": 3}
	hero.global_position = Vector3(30, 0, 30)
	hero.reset_physics_interpolation()
	hero.stats.equipment.clear()
	for item in Items.starting_gear():
		hero.stats.equip(item, false)
	hero.stats.refresh()
	hero.level = 30
	_plain(hero)
	hero.crit_chance = 0.0
	await _frames(2)

	# --- The data: one table, outside the default unique pool, saves and names itself ---------------------------------------------------
	for id in ["gravecaller_maul", "headsmans_due", "executioners_sight", "splitbow"]:
		expect("%s is in the legendary table and not in the default unique drop pool" % id, MapModeLegendaries.DEFS.has(id) and not UniqueDb.uniques().has(id))
		var built: Dictionary = MapModeLegendaries.item(id)
		expect("%s builds on %s as a unique and names itself" % [id, MapModeLegendaries.DEFS[id]["base"]], built["def"] == MapModeLegendaries.DEFS[id]["base"]
			and built["rarity"] == Items.Rarity.UNIQUE and built["name"] == MapModeLegendaries.DEFS[id]["name"] and UniqueDb.get_unique(id) != null)
		var loaded: Dictionary = Items.from_save(Items.to_save(built))
		expect("%s survives a save and load" % id, not loaded.is_empty() and loaded["unique"] == id and loaded["name"] == built["name"])
	expect("Hero's Amulet is the existing level-5 charm unique", UniqueDb.get_unique("heros_amulet").base == "charm" and UniqueDb.get_unique("heros_amulet").level == 5
		and MapModeLegendaries.DEFS.has("heros_amulet"))
	expect("no legendary line on any card with map mode off", MapModeLegendaries.tooltip_line(MapModeLegendaries.item("splitbow")) == ""
		and not Items.lines(MapModeLegendaries.item("splitbow")).any(func(l: String) -> bool: return l.begins_with("Legendary")))

	var maul: Dictionary = MapModeLegendaries.item("gravecaller_maul")
	var plain_axe: Dictionary = Items.build(ItemDb.get_def("axe_2h"), 6, Items.Rarity.NORMAL, [])

	# --- Gravecaller Maul: Whirling Strike pulls enemies in first ---------------------------------------------------------------------------
	hero.stats.equipment.erase(Items.Slot.SHIELD)
	_wear(hero, Items.Slot.WEAPON, maul)
	hero.powers.reset()
	var radius: float = hero.powers.value("whirling_strike", "radius")
	var far_d: float = radius + 2.0
	var reach: float = MapModeLegendaries.number("gravecaller_maul", "pull_reach")
	expect("Whirling Strike is open for the hero, and the pull reaches past its radius (%.1f > %.1f)" % [reach, radius], radius > 0.0 and reach > far_d)
	var results := {}
	for mode in ["off", "on", "plain_axe", "beyond_reach"]:
		await _map_mode(mode != "off")
		_wear(hero, Items.Slot.WEAPON, plain_axe if mode == "plain_axe" else maul)
		var near := _foe(hero.global_position + Vector3(radius * 0.5, 0, 0))
		var far := _foe(hero.global_position + Vector3(0, 0, far_d if mode != "beyond_reach" else reach + 2.0))
		var far_before: float = far.global_position.distance_to(hero.global_position)
		hero.powers.reset()
		hero.powers.impact("whirling_strike", hero.global_position)
		var gap: float = Vector2(far.global_position.x - hero.global_position.x, far.global_position.z - hero.global_position.z).length()
		results[mode] = {"near": _lost(near), "far": _lost(far), "gap": gap, "before": far_before}
		near.queue_free()
		far.queue_free()
		await get_tree().process_frame
	expect("map mode off: the maul changes nothing (the far enemy is not hit and does not move)", results["off"]["near"] > 0.0 and results["off"]["far"] == 0.0
		and is_equal_approx(results["off"]["gap"], results["off"]["before"]))
	expect("map mode on: the enemy %.1f m away is pulled in (to %.2f m) and then hit" % [far_d, results["on"]["gap"]], results["on"]["far"] > 0.0
		and results["on"]["gap"] <= radius + 0.2 and results["on"]["gap"] < results["on"]["before"])
	expect("the pulled enemy takes the same hit as the one already in reach (pull comes before the damage)", absf(results["on"]["far"] - results["on"]["near"]) < results["on"]["near"] * 0.6 + 1.0
		and results["on"]["near"] > 0.0)
	expect("a plain Battle Axe in map mode pulls nothing", results["plain_axe"]["far"] == 0.0 and is_equal_approx(results["plain_axe"]["gap"], results["plain_axe"]["before"]))
	expect("an enemy beyond the pull's reach is left alone", results["beyond_reach"]["far"] == 0.0 and is_equal_approx(results["beyond_reach"]["gap"], results["beyond_reach"]["before"]))

	# --- Headsman's Due: a Brutal Attack kill jumps to the nearest enemy, up to 3 times ----------------------------------------------------
	var due: Dictionary = MapModeLegendaries.item("headsmans_due")
	var chain := {}
	for mode in ["off", "on", "plain_sword", "tough"]:
		await _map_mode(mode != "off")
		_wear(hero, Items.Slot.WEAPON, Items.build(ItemDb.get_def("longsword"), 5, Items.Rarity.NORMAL, []) if mode == "plain_sword" else due)
		hero.global_position = Vector3(30, 0, 30)
		var line: Array[Enemy] = []
		for i in 5:
			line.append(_foe(hero.global_position + Vector3(1.6, 0, 3.0 * i), 1.0))
		if mode == "tough":
			line[2].max_health = 1.0e7   # the chain stops at an enemy the blow does not kill
			line[2].health = 1.0e7
		hero.skills.cancel_action()
		hero.skills.combo_step = 0
		hero.skills.combo_timer = 0.0
		hero.skills.brutal_armed = true
		hero.stats.brutal_reload_remaining = 0.0
		hero.attack_target = line[0]
		hero.skills.start_skill("basic", line[0])
		hero.skills.tick_busy(hero.skills.busy_time * SkillController.hit_fraction(hero.skills.busy_def) + 0.01)
		var dead_count := 0
		for e in line:
			if not is_instance_valid(e) or e.dead:
				dead_count += 1
		chain[mode] = {"dead": dead_count, "fourth": not is_instance_valid(line[3]) or line[3].dead, "fifth": not is_instance_valid(line[4]) or line[4].dead,
			"third_hurt": is_instance_valid(line[2]) and line[2].health < line[2].max_health}
		hero.skills.cancel_action()
		hero.skills.brutal_armed = false
		hero.attack_target = null
		for e in line:
			if is_instance_valid(e):
				e.queue_free()
		await get_tree().process_frame
	expect("map mode off: the Brutal Attack kills only its target (%d dead)" % chain["off"]["dead"], chain["off"]["dead"] == 1)
	expect("map mode on: the kill jumps three times (target + 3 = %d dead) and no further" % chain["on"]["dead"], chain["on"]["dead"] == 4 and chain["on"]["fourth"] and not chain["on"]["fifth"])
	expect("a plain Longsword in map mode does not chain", chain["plain_sword"]["dead"] == 1)
	expect("the chain stops when a hit does not kill (the tough enemy is hurt, nothing after it dies)", chain["tough"]["dead"] == 2 and chain["tough"]["third_hurt"] and not chain["tough"]["fourth"])

	# --- Executioner's Sight: Take Aim on an Opening always crits and refunds half its charge --------------------------------------------------
	var sight: Dictionary = MapModeLegendaries.item("executioners_sight")
	var short_bow: Dictionary = Items.build(ItemDb.get_def("short_bow"), 5, Items.Rarity.NORMAL, [])
	var lane: Vector3 = await _own_lane(26.0, 8.0)
	archer.global_position = lane
	archer.reset_physics_interpolation()
	hero.global_position = lane + Vector3(-6.0, 0.0, 3.0)
	hero.reset_physics_interpolation()
	var shots := {}
	for mode in ["off", "on_open", "on_closed", "plain_bow"]:
		await _map_mode(mode != "off")
		_prepare_archer(archer)
		_wear(archer, Items.Slot.WEAPON, short_bow if mode == "plain_bow" else sight)
		archer.openings.clear_mark(false)
		var target := _foe(lane + Vector3(8, 0, 0))
		await get_tree().physics_frame
		if mode != "on_closed":
			archer.openings.mark_target = target
			archer.openings.mark_left = 1.0
		for node in get_tree().current_scene.get_children():
			if node is CompanionArrow:
				node.queue_free()
		archer.bow.armed = true
		archer.bow.start(target)
		archer.bow.loose()
		var arrow: CompanionArrow
		for node in get_tree().current_scene.get_children():
			if node is CompanionArrow:
				arrow = node
		shots[mode] = {"crit": arrow != null and arrow.always_crit, "take_aim": arrow != null and arrow.take_aim,
			"left": archer.bow.reload_remaining / maxf(archer.bow.reload_required, 0.001), "required": archer.bow.reload_required}
		archer.skills.cancel_action()
		archer.bow.cancel()
		archer.bow.armed = false
		archer.bow.reload_remaining = 0.0
		if arrow != null:
			arrow.queue_free()
		target.queue_free()
		await get_tree().process_frame
	expect("map mode on, target open: the Take Aim shot always crits and %.0f%% of its charge is still to earn" % (shots["on_open"]["left"] * 100.0),
		shots["on_open"]["take_aim"] and shots["on_open"]["crit"] and is_equal_approx(shots["on_open"]["left"], 0.5) and shots["on_open"]["required"] > 0.0)
	expect("on a target without an Opening it is an ordinary Take Aim (no forced crit, full charge to earn)", shots["on_closed"]["take_aim"] and not shots["on_closed"]["crit"]
		and is_equal_approx(shots["on_closed"]["left"], 1.0))
	expect("map mode off: the same bow and the same Opening change nothing", shots["off"]["take_aim"] and not shots["off"]["crit"] and is_equal_approx(shots["off"]["left"], 1.0))
	expect("a plain Short Bow in map mode changes nothing", not shots["plain_bow"]["crit"] and is_equal_approx(shots["plain_bow"]["left"], 1.0))
	# The forced crit itself: a fixed-damage arrow, with and without it, lands for exactly the critical multiplier.
	var damage_of := {}
	for forced in [false, true]:
		var victim := _foe(lane + Vector3(8, 0, 0))
		await get_tree().physics_frame
		var from: Vector3 = lane + Vector3(0.5, 1.2, 0)
		var arrow: CompanionArrow = CompanionArrow.fire(get_tree().current_scene, archer, from, victim.global_position + Vector3(0, victim.body_height * 0.6, 0), 100.0, true, forced)
		await _frames(40)
		damage_of[forced] = _lost(victim)
		arrow.queue_free()
		victim.queue_free()
		await get_tree().process_frame
	expect("a forced-crit Take Aim arrow deals the critical multiplier (x%.2f) of an unforced one (%.1f vs %.1f)" % [archer.crit_mult, damage_of[true], damage_of[false]],
		damage_of[false] > 0.0 and absf(damage_of[true] / damage_of[false] - archer.crit_mult) < 0.02)

	# --- Splitbow: Thunderous Shot fires 3 bolts in a cone -------------------------------------------------------------------------------------
	var split: Dictionary = MapModeLegendaries.item("splitbow")
	TownState.add_member_xp("cutter", HeroProgression.xp_for_level(11), false, {"ranged": 1.0})
	TownState.buy_passives({"critical_shot": 1}, "cutter")
	TownState.buy_passives({"biting_arrow": 1}, "cutter")
	archer.stats.refresh()
	var bolts := {}
	var muzzle: Vector3 = lane + Vector3(0, 1.4, 0) + Vector3.RIGHT * 0.6
	for mode in ["off", "on", "plain_bow"]:
		await _map_mode(mode != "off")
		_prepare_archer(archer)
		_wear(archer, Items.Slot.WEAPON, short_bow if mode == "plain_bow" else split)
		archer.powers.reset()
		var dirs: Array[Vector3] = archer.powers.thunderous_directions(Vector3.RIGHT)
		var foes: Array[Enemy] = []
		for angle in [0.0, 15.0, -15.0, 40.0]:
			foes.append(_foe(muzzle + Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(angle)) * 8.0 - Vector3(0, 1.4 - 0.0, 0) * 0.0 + Vector3(0, -1.4, 0) * 0.0))
		await get_tree().physics_frame
		for f in foes:
			f.global_position.y = lane.y
		var count: int = archer.powers.thunderous_release(muzzle, Vector3.RIGHT)
		bolts[mode] = {"dirs": dirs.size(), "count": count, "factor": MapModeLegendaries.bolt_damage_factor(archer), "lost": [_lost(foes[0]), _lost(foes[1]), _lost(foes[2]), _lost(foes[3])],
			"angle": rad_to_deg(Vector3.RIGHT.angle_to(dirs[dirs.size() - 1])) if dirs.size() > 1 else 0.0}
		for f in foes:
			f.queue_free()
		await get_tree().process_frame
	expect("map mode on: three bolts fly, 15 degrees either side of the aim (%.1f)" % bolts["on"]["angle"], bolts["on"]["dirs"] == 3 and absf(bolts["on"]["angle"] - 15.0) < 0.01)
	expect("they hit the centre and both flank enemies, and not the one outside the cone", bolts["on"]["count"] == 3 and bolts["on"]["lost"][0] > 0.0
		and bolts["on"]["lost"][1] > 0.0 and bolts["on"]["lost"][2] > 0.0 and bolts["on"]["lost"][3] == 0.0)
	expect("the flank bolts hit about as hard as the centre one (each at the same 60%% share)", bolts["on"]["lost"][1] > bolts["on"]["lost"][0] * 0.5 and bolts["on"]["lost"][1] < bolts["on"]["lost"][0] * 2.0)
	expect("the damage factor is 0.6 with the Splitbow and 1.0 without", is_equal_approx(bolts["on"]["factor"], 0.6) and is_equal_approx(bolts["off"]["factor"], 1.0)
		and is_equal_approx(bolts["plain_bow"]["factor"], 1.0))
	expect("map mode off: one bolt, centre only", bolts["off"]["dirs"] == 1 and bolts["off"]["count"] == 1 and bolts["off"]["lost"][0] > 0.0
		and bolts["off"]["lost"][1] == 0.0 and bolts["off"]["lost"][2] == 0.0)
	expect("a plain Short Bow in map mode fires one bolt", bolts["plain_bow"]["dirs"] == 1 and bolts["plain_bow"]["count"] == 1)

	# --- Hero's Amulet: when one member uses a power, the other gains 25% charge --------------------------------------------------------------------
	var amulet: Dictionary = MapModeLegendaries.item("heros_amulet")
	var gains := {}
	for mode in ["off", "hero_wears", "cutter_wears", "nobody"]:
		await _map_mode(mode != "off")
		MapModeLegendaries.reset_run()
		hero.stats.unequip(Items.Slot.AMULET)
		archer.stats.unequip(Items.Slot.AMULET)
		if mode == "hero_wears" or mode == "off":
			_wear(hero, Items.Slot.AMULET, amulet)
		elif mode == "cutter_wears":
			_wear(archer, Items.Slot.AMULET, amulet)
		archer.powers.reset()
		hero.powers.reset()
		archer.powers.reload_required["thunderous_shot"] = 1000.0
		archer.powers.reload_remaining["thunderous_shot"] = 1000.0
		hero.powers.reload_required["whirling_strike"] = 1000.0
		hero.powers.reload_remaining["whirling_strike"] = 1000.0
		hero.powers.reload_required["war_cry"] = 1000.0
		hero.powers.reload_remaining["war_cry"] = 1000.0
		hero.power_activated.emit("hero", "war_cry")   # the hero uses a power: Cutter gains
		var cutter_after_hero: float = float(archer.powers.reload_remaining["thunderous_shot"])
		var hero_own: float = float(hero.powers.reload_remaining["war_cry"])
		var hero_other: float = float(hero.powers.reload_remaining["whirling_strike"])
		hero.power_activated.emit("hero", "war_cry")   # the same use announced again at once counts once
		var cutter_after_twice: float = float(archer.powers.reload_remaining["thunderous_shot"])
		archer.power_activated.emit("cutter", "thunderous_shot")   # Cutter uses a power: the hero gains
		gains[mode] = {"cutter": cutter_after_hero, "twice": cutter_after_twice, "hero_own": hero_own, "hero_other": hero_other,
			"hero_after_cutter": float(hero.powers.reload_remaining["whirling_strike"])}
	expect("hero wears it, map mode on: Cutter's power gains 25%% (1000 -> %.0f), once even if announced twice (%.0f)" % [gains["hero_wears"]["cutter"], gains["hero_wears"]["twice"]],
		is_equal_approx(gains["hero_wears"]["cutter"], 750.0) and is_equal_approx(gains["hero_wears"]["twice"], 750.0))
	expect("the user's own charge is not given the bonus by his own use", is_equal_approx(gains["hero_wears"]["hero_own"], 1000.0))
	expect("and the other way round: when Cutter uses a power the hero gains 25%% (%.0f)" % gains["hero_wears"]["hero_after_cutter"], is_equal_approx(gains["hero_wears"]["hero_after_cutter"], 750.0))
	expect("either member may wear it (Cutter wears it, the hero uses a power: Cutter gains 25%%)", is_equal_approx(gains["cutter_wears"]["cutter"], 750.0))
	expect("map mode off: the amulet gives no charge", is_equal_approx(gains["off"]["cutter"], 1000.0) and is_equal_approx(gains["off"]["hero_after_cutter"], 1000.0))
	expect("nobody wears it: no charge", is_equal_approx(gains["nobody"]["cutter"], 1000.0))
	hero.stats.unequip(Items.Slot.AMULET)
	archer.stats.unequip(Items.Slot.AMULET)

	# --- The tooltip line: map mode only ------------------------------------------------------------------------------------------------------------
	await _map_mode(true)
	for id in MapModeLegendaries.DEFS:
		var it: Dictionary = MapModeLegendaries.item(id)
		var lines: Array[String] = Items.lines(it)
		var shown: bool = lines.has("Legendary: " + String(MapModeLegendaries.DEFS[id]["text"]))
		expect("%s shows its legendary line on the card in map mode" % id, shown)
	expect("an ordinary unique has no legendary line", MapModeLegendaries.tooltip_line(Items.unique(UniqueDb.get_unique("assailing_talisman"))) == "")
	await _map_mode(false)
	expect("with map mode off the amulet's card has no legendary line", not Items.lines(MapModeLegendaries.item("heros_amulet")).any(func(l: String) -> bool: return l.begins_with("Legendary")))

	# --- The first champion of a run always drops one; the second does not guarantee one ---------------------------------------------------------
	_clear_loot()
	var champs: Array[Enemy] = []
	for i in 3:
		var z: Enemy = _foe(Nav.snap(hero, hero.global_position + Vector3(10 + i * 2, 0, 0)))
		Champion.attach(z, "shielded")
		z.health = 0.0
		champs.append(z)
	game.director._drop_loot(champs[0])
	expect("map mode off: a champion drops no legendary and the run flag is untouched", _count_legendaries() == 0 and not MapModeLegendaries.first_champion_dropped)
	await _map_mode(true)
	expect("a new map-mode run resets the flag", not MapModeLegendaries.first_champion_dropped)
	game.director._drop_loot(champs[1])
	var after_first: int = _count_legendaries()
	expect("the first champion in map mode drops a legendary (%d)" % after_first, after_first == 1 and MapModeLegendaries.first_champion_dropped)
	var legend_drop: LootDrop
	for drop in get_tree().get_nodes_in_group("loot"):
		if MapModeLegendaries.id_of((drop as LootDrop).item) != "":
			legend_drop = drop
	expect("it lies there under its own beam and pool, though ordinary drops have none", legend_drop != null and legend_drop._column != null and legend_drop._pool != null and legend_drop._light != null)
	game.director._drop_loot(champs[2])
	expect("the second champion does not guarantee one (still %d)" % _count_legendaries(), _count_legendaries() == 1)
	await _map_mode(false)
	await _map_mode(true)
	expect("a fresh run guarantees the first champion's legendary again", not MapModeLegendaries.first_champion_dropped)
	await _map_mode(false)
	var plain_drop: LootDrop = game.director.drop_item(hero.global_position + Vector3(4, 0, 0), MapModeLegendaries.item("splitbow"))
	await get_tree().process_frame
	expect("with map mode off even a legendary lies without a beam (the default game is unchanged)", plain_drop._column == null and plain_drop._pool == null)
	_clear_loot()
	for e in champs:
		if is_instance_valid(e):
			e.queue_free()

	print("MMLEGEND whirl=%s chain=%s sight=%s damage=%s bolts=%s gains=%s" % [results, chain, shots, damage_of, bolts, gains])
	archer.testing_disabled = archer_was_disabled
	hero.set_physics_process(true)
	TownState.reset()
	await get_tree().process_frame
