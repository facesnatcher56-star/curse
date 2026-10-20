extends DevSuite
## The map-mode drop model (issue #82, game/map_mode/map_drops.gd): with the flag off the DS2 drops are untouched; in map mode the guard of a group is
## decided at spawn and is what the node map says, champions always drop magic, every cleared node pays gold plus an item or a potion and shows a
## loot summary, loot is party-fit, upgrades roll high, and a seeded run of the dungeon lands on the run target (15-20 items, ~8 magic, 3-4 rare,
## 1-2 legendary).

## A typical run skips the swarm pit (node 2) and the Reliquary (node 8: the Ghoul Warren and the Reliquary both lead to the Ossuary).
const SKIPPED := [2, 8]
const RUN_SEED := 20261019
const SIM_RUNS := 120

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _wait_state(m: MapMode, wanted: MapMode.State, max_frames: int) -> void:
	var n: int = 0
	while m.state != wanted and n < max_frames:
		await get_tree().physics_frame
		n += 1

func _test_map_drops() -> void:
	_flag_off_unchanged()
	_guards_and_labels()
	_chest_contents()
	_party_fit()
	_value_bias()
	_fight_log()
	_trend_marks()
	_simulated_runs()
	await _champion_drops()
	await _chest_opens()
	await _run_pays_out()


# --- Flag off: the default game's drops are exactly what they were ------------------------------------------------------------------------------

func _flag_off_unchanged() -> void:
	expect("map-mode drops are off without the flag", not MapDrops.enabled() and not MapMode.active)
	expect("the DS2 monster tables are untouched", MonsterLoot.TABLES["normal"] == [0.6625, 0.12, 0.03, 0.06, 0.035] and MonsterLoot.TABLES["strong"] == [0.515, 0.14, 0.04, 0.08, 0.048]
		and is_equal_approx(float(Items.DROPS["normal"]["item"]), 0.08) and Items.DROPS["normal"]["window"] == Vector2i(-5, 1))
	var same: bool = true
	for tier in ["weak", "normal", "strong", "miniboss"]:
		seed(4242)
		var a: Array = []
		for i in 60:
			a.append(MonsterLoot.roll(3, tier, 20.0, 1.0, 10.0))
		seed(4242)
		var b: Array = []
		for i in 60:
			b.append(MapDrops.enemy_loot(3, tier, 20.0, 1.0, 10.0))
		same = same and JSON.stringify(a) == JSON.stringify(b)
	expect("with the flag off MapDrops.enemy_loot is MonsterLoot.roll, roll for roll", same)
	seed(77)
	var champ_a: Array = []
	for i in 30:
		champ_a.append(Champion.loot(3, "normal", 0.0))
	seed(77)
	var champ_b: Array = []
	for i in 30:
		champ_b.append(MapDrops.champion_loot(3, "normal", 0.0))
	expect("with the flag off a champion's drop is Champion.loot, roll for roll", JSON.stringify(champ_a) == JSON.stringify(champ_b))
	expect("with the flag off a magic item's modifiers come from DS2's whole window (mean %.1f levels under the item)" % -_mod_offset(false, Items.Rarity.MAGIC), _mod_offset(false, Items.Rarity.MAGIC) < -6.0)


# --- Guards ---------------------------------------------------------------------------------------------------------------------------------

func _guards_and_labels() -> void:
	var rows: Array[Dictionary] = MapModeLayout.nodes()
	var a: Array = []
	var b: Array = []
	for n in rows:
		a.append(MapDrops.plan_for(n, 1234))
		b.append(MapDrops.plan_for(n, 1234))
	expect("a node's guard is a pure function of the run seed", JSON.stringify(a) == JSON.stringify(b))
	var kinds: Dictionary = {}
	var chest_groups: int = 0
	var groups: int = 0
	var boss_ok: bool = true
	var champion_ok: bool = true
	var poi_ok: bool = true
	for s in 200:
		for n in rows:
			var plan: Dictionary = MapDrops.plan_for(n, s + 1)
			kinds[plan["guard"]] = int(kinds.get(plan["guard"], 0)) + 1
			var kind: String = String(n["kind"])
			if kind in ["pack", "swarm", "champion", "boss"]:
				groups += 1
				chest_groups += 1 if bool(plan["chest"]) else 0
			boss_ok = boss_ok and (kind != "boss" or plan["guard"] == "hoard")
			champion_ok = champion_ok and (kind != "champion" or plan["guard"] == "gilded")
			poi_ok = poi_ok and (kind != "chest" or plan["guard"] in ["wooden", "iron", "cursed"]) and (kind != "start" or plan["guard"] == "")
	var share: float = float(chest_groups) / float(groups)
	print("  guards over 200 run seeds: ", kinds, "  chest share of groups %.2f" % share)
	expect("about 70%% of groups guard a chest (%.2f)" % share, share > 0.62 and share < 0.78)
	expect("the boss always guards a Hoard, a champion a Gilded chest, the side branches a Wooden, Iron or Cursed one", boss_ok and champion_ok and poi_ok)
	expect("every guard kind turns up: Wooden, Iron, Gilded, Cursed, Hoard, shrine, gold, potion cache",
		kinds.has("wooden") and kinds.has("iron") and kinds.has("gilded") and kinds.has("cursed") and kinds.has("hoard") and kinds.has("shrine") and kinds.has("gold") and kinds.has("potions"))
	# The dungeon decides at spawn; the node map shows the same thing; the chest standing behind the group is that kind.
	var dungeon := MapModeDungeon.new()
	dungeon.plan_guards(RUN_SEED)
	var m := MapMode.new()   # not in the tree: only its label is read
	m.graph = MapGraph.from_layout()
	m.dungeon = dungeon
	var fixed_ok: bool = true
	var labels_ok: bool = true
	var behind_ok: bool = true
	var chest_n: int = 0
	var snapshot: String = JSON.stringify(dungeon.node_plans)
	MapDrops.new_run(RUN_SEED + 99)   # a later run seed changes nothing about the spawned dungeon
	for n in rows:
		var id: int = int(n["id"])
		var plan: Dictionary = dungeon.node_plans[id]
		var label: String = m.node_label(id)
		if bool(plan["chest"]):
			chest_n += 1
			var chest: Chest = dungeon.node_chests.get(id) as Chest
			fixed_ok = fixed_ok and chest != null and chest.guard == plan["guard"] and chest.drop_level > 0
			labels_ok = labels_ok and label.contains(String(plan["title"]))
			if chest != null and String(n["kind"]) in ["pack", "swarm", "champion", "boss"]:
				var centre: Vector2 = n["pos"]
				var spot := Vector2(chest.position.x, chest.position.z)
				var dist: float = centre.distance_to(spot)
				behind_ok = behind_ok and dist >= 1.5 and dist <= 3.0 and _in_room(id, spot)
		elif not (String(n["kind"]) in ["start", "shrine"]):
			labels_ok = labels_ok and label.contains(String(plan["title"]))
	expect("each chest guard has its Chest in the dungeon at spawn, of the planned kind (%d chests)" % chest_n, fixed_ok and chest_n >= 5)
	expect("the node map's label names that kind: Guards: Iron chest, a shrine, a pile of gold ... (also after a new run seed)", labels_ok and snapshot == JSON.stringify(dungeon.node_plans))
	expect("a group's chest stands 2 m behind it, inside its room", behind_ok)
	var marker_ok: bool = false
	for mk in m._graph_markers():
		marker_ok = marker_ok or (String(mk["guard"]) != "" and mk["state"] == "reachable")
	expect("the markers carry the guard for the overlay badge", marker_ok)
	expect("a chest node is labelled by its chest, the boss by its hoard", m.node_label(12).contains("Cursed chest") and m.node_label(5).contains("Wooden chest") and m.node_label(11).contains("Boss hoard"))
	for chest in dungeon.node_chests.values():
		(chest as Node).free()
	m.free()
	dungeon.free()
	MapDrops.run_seed = 0


func _in_room(id: int, spot: Vector2) -> bool:
	for n in MapModeLayout.NODES:
		if int(n["id"]) == id:
			var cell: Vector2i = MapModeLayout.cell_of(spot)
			var r: Array = n["rect"]
			return cell.x >= int(r[0]) and cell.x <= int(r[2]) and cell.y >= int(r[1]) and cell.y <= int(r[3])
	return false


# --- What a chest holds ---------------------------------------------------------------------------------------------------------------------

func _chest_contents() -> void:
	MapDrops.forced = true
	seed(31)
	var ok: Dictionary = {"wooden": true, "iron": true, "gilded": true, "cursed": true, "hoard": true}
	var sizes: Dictionary = {}
	for i in 120:
		for kind in ok:
			var items: Array[Dictionary] = MapDrops.chest_items(kind, 3)
			var tiers: Dictionary = MapDrops.count_tiers(items)
			var magic_or_better: int = items.size() - int(tiers["normal"])
			if not sizes.has(kind):
				sizes[kind] = {}
			sizes[kind][items.size()] = int(sizes[kind].get(items.size(), 0)) + 1
			var good: bool = true
			match kind:
				"wooden": good = items.size() >= 1 and items.size() <= 2 and int(tiers["rare"]) + int(tiers["legendary"]) == 0
				"iron": good = items.size() >= 2 and items.size() <= 3 and magic_or_better >= 1 and int(tiers["legendary"]) == 0
				"gilded": good = int(tiers["rare"]) + int(tiers["legendary"]) >= 1 and items.size() <= 3
				"cursed": good = int(tiers["legendary"]) >= 1
				"hoard": good = items.size() >= 4 and items.size() <= 5 and int(tiers["legendary"]) >= 1 and magic_or_better >= 2
			ok[kind] = bool(ok[kind]) and good
	for kind in ok:
		expect("a %s chest holds what the table says (120 rolls, sizes %s)" % [kind, str(sizes[kind])], ok[kind])
	var rare_irons: int = 0
	var gilded_leg: int = 0
	for i in 600:
		rare_irons += 1 if int(MapDrops.count_tiers(MapDrops.chest_items("iron", 3))["rare"]) > 0 else 0
		gilded_leg += 1 if int(MapDrops.count_tiers(MapDrops.chest_items("gilded", 3))["legendary"]) > 0 else 0
	expect("an Iron chest sometimes has a rare (%d of 600) and a Gilded one rarely a legendary (%d of 600)" % [rare_irons, gilded_leg],
		rare_irons > 120 and rare_irons < 300 and gilded_leg > 5 and gilded_leg < 70)
	var wooden_magic: int = 0
	var wooden_n: int = 0
	for i in 300:
		for item in MapDrops.chest_items("wooden", 3):
			wooden_n += 1
			wooden_magic += 1 if int(item["rarity"]) == Items.Rarity.MAGIC else 0
	expect("a Wooden chest is mostly normal or magic items (%d of %d magic)" % [wooden_magic, wooden_n], wooden_n > 0 and wooden_magic * 10 < wooden_n * 8)
	var enemy_items: int = 0
	var enemy_gold: int = 0
	var enemy_potions: int = 0
	var enemy_n: int = 4000
	for i in enemy_n:
		var loot: Dictionary = MapDrops.enemy_loot(3, "normal")
		enemy_items += 0 if (loot["item"] as Dictionary).is_empty() else 1
		enemy_gold += 1 if int(loot["gold"]) > 0 else 0
		enemy_potions += int(loot["health"]) + int(loot["mana"])
	print("  enemy drops per %d kills: %d items, %d gold, %d potions" % [enemy_n, enemy_items, enemy_gold, enemy_potions])
	expect("a normal enemy drops gold often (~35%), an item ~5%, a potion sometimes", float(enemy_gold) / enemy_n > 0.3 and float(enemy_gold) / enemy_n < 0.4
		and float(enemy_items) / enemy_n > 0.035 and float(enemy_items) / enemy_n < 0.065 and enemy_potions > enemy_n / 25 and enemy_potions < enemy_n / 6)
	MapDrops.forced = false


# --- Party fit ------------------------------------------------------------------------------------------------------------------------------

func _party_fit() -> void:
	MapDrops.forced = true
	seed(5150)
	var fit: int = 0
	var total: int = 1500
	for i in total:
		fit += 1 if MapDrops.fits_party(MapDrops.make_item("magic1", 3)) else 0
	var share: float = float(fit) / total
	seed(5150)
	var plain_fit: int = 0
	for i in total:
		plain_fit += 1 if MapDrops.fits_party(Items.item_of_kind("magic1", 3, Vector2i(-5, 1))) else 0
	print("  party-fit share of drops: %.2f (%.2f unbiased)" % [share, float(plain_fit) / total])
	expect("about 60%% or more of item drops are bases the warrior or the Cutter can use (%.2f)" % share, share >= 0.55 and share >= float(plain_fit) / total - 0.02)
	expect("a level-2 sword and a level-2 bow fit the party; a level-40 sword and a robe (no Combat skill) do not",
		MapDrops.fits_party(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Longsword")) and MapDrops.fits_party(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow"))
		and not MapDrops.fits_party(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 40, "Longsword")) and not MapDrops.fits_party(Items.build(ItemDb.get_def("apprentice_robe"), 4, Items.Rarity.NORMAL)))
	MapDrops.forced = false


# --- Upgrades roll high ---------------------------------------------------------------------------------------------------------------------

## The mean level of an item's modifiers relative to the item's own level (a higher modifier tier is a bigger number).
func _mod_offset(on: bool, rarity: int) -> float:
	MapDrops.forced = on
	seed(8)
	var sum: float = 0.0
	var n: int = 0
	for i in 300:
		var item: Dictionary = Items.make(Items.Slot.WEAPON if i % 3 != 0 else Items.Slot.ARMOR, rarity, 14)
		for id in item["mods"]:
			sum += float(AffixDb.get_def(String(id)).level) - float(item["level"])
			n += 1
	MapDrops.forced = false
	return sum / maxf(float(n), 1.0)


func _value_bias() -> void:
	for rarity in [Items.Rarity.MAGIC, Items.Rarity.RARE]:
		var off: float = _mod_offset(false, rarity)
		var on: float = _mod_offset(true, rarity)
		print("  %s modifier level vs item level: %.1f flag off, %.1f in map mode" % [Items.RARITY_NAMES[rarity], off, on])
		expect("map mode: %s modifiers come from the top of the window (%.1f levels vs %.1f under the item with the flag off)" % [Items.RARITY_NAMES[rarity], on, off], on > off + 3.0)
	# a modifier that has a value range (magic find) rolls in the top part of it
	MapDrops.forced = true
	var low: float = 1.0
	var affix: AffixDef = AffixDb.get_def("magic_find_3")
	seed(3)
	for i in 200:
		low = minf(low, (MapDrops.roll_value(affix, Items.Rarity.RARE) - affix.value) / (affix.value_ceiling - affix.value))
	MapDrops.forced = false
	expect("a ranged modifier never rolls below its floor in map mode (lowest %.2f of its range)" % low, low >= 0.5 - 0.01)


# --- The fight log counts loot --------------------------------------------------------------------------------------------------------------

func _fight_log() -> void:
	var log := MapFightLog.new()
	log.begin_fight("Pack", 0.0)
	log.note_item(Items.make(Items.Slot.WEAPON, Items.Rarity.MAGIC, 3))
	log.note_item(Items.make(Items.Slot.ARMOR, Items.Rarity.RARE, 3))
	log.note_item(Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 3))
	log.note_gold(12)
	var row: Dictionary = log.end_fight(5.0)
	log.begin_fight("Boss", 6.0)
	log.note_item(Items.unique(UniqueDb.uniques().values()[0]))
	log.note_item(Items.make(Items.Slot.WEAPON, Items.Rarity.MAGIC, 3))
	log.note_gold(30)
	log.end_fight(9.0)
	log.note_item(Items.make(Items.Slot.WEAPON, Items.Rarity.MAGIC, 3))   # no fight active: ignored
	var lines: PackedStringArray = log.summary_lines()
	var tiers: Dictionary = row["items"]
	expect("a fight row counts its items by rarity and its gold (%s)" % str(tiers), tiers["magic"] == 1 and tiers["rare"] == 1 and tiers["normal"] == 1 and tiers["legendary"] == 0 and int(row["gold"]) == 12)
	expect("the totals line reports the run's items by rarity and gold (%s)" % lines[lines.size() - 1], lines[lines.size() - 1].contains("loot 5 items") and lines[lines.size() - 1].contains("1 legendary") and lines[lines.size() - 1].contains("42 gold"))
	expect("each fight line mentions its loot", log.row_line(row).contains("loot") and log.row_line(row).contains("12 gold"))


# --- The pickup/summary arrows --------------------------------------------------------------------------------------------------------------

func _trend_marks() -> void:
	var stats: PlayerStats = player.stats
	var worn: Variant = stats.equipment.get(Items.Slot.WEAPON)
	var base: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Longsword")
	stats.equipment[Items.Slot.WEAPON] = base
	var better: Dictionary = base.duplicate(true)
	better["stats"]["min"] = float(base["stats"]["min"]) * 2.0
	better["stats"]["max"] = float(base["stats"]["max"]) * 2.0
	var worse: Dictionary = base.duplicate(true)
	worse["stats"]["min"] = float(base["stats"]["min"]) * 0.5
	worse["stats"]["max"] = float(base["stats"]["max"]) * 0.5
	expect("the arrow compares with what is worn by the item card's own comparison: better +1, worse -1, the same 0",
		LootAppraisal.trend(better, stats) == 1 and LootAppraisal.trend(worse, stats) == -1 and LootAppraisal.trend(base.duplicate(true), stats) == 0)
	var rows: Array[Dictionary] = HudLootCards.summary_rows({"items": [better, worse]}, [player])
	expect("the summary rows carry up / down marks (%s)" % str(rows.map(func(r: Dictionary) -> int: return int(r["mark"]))),
		rows.size() == 2 and int(rows[0]["mark"]) == HudLootCards.Mark.UP and int(rows[1]["mark"]) == HudLootCards.Mark.DOWN)
	var high: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 40, "Longsword")
	var locked: Array[Dictionary] = HudLootCards.summary_rows({"items": [high]}, [player])
	expect("an item nobody can wear yet is marked locked", int(locked[0]["mark"]) == HudLootCards.Mark.LOCKED)
	if worn == null:
		stats.equipment.erase(Items.Slot.WEAPON)
	else:
		stats.equipment[Items.Slot.WEAPON] = worn


# --- The seeded full-run simulation ---------------------------------------------------------------------------------------------------------

## Rolls every node in `visited` through the drop model: its enemies' own drops, a champion's item, and what the node guards. Returns the items.
func _roll_run(dungeon: MapModeDungeon, visited: Array) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for n in MapModeLayout.nodes():
		var id: int = int(n["id"])
		if not visited.has(id):
			continue
		var level: int = dungeon.level_for_node(id, dungeon._stage_of(id))
		for pair in n["groups"]:
			var tier: String = EnemyDb.get_def(String(pair[0])).tier
			for i in int(pair[1]):
				var loot: Dictionary = MapDrops.enemy_loot(level, tier)
				if not (loot["item"] as Dictionary).is_empty():
					items.append(loot["item"])
		if String(n["champion"]) != "":
			items.append(MapDrops.champion_loot(level, "normal"))
		var plan: Dictionary = dungeon.node_plans[id]
		if bool(plan["chest"]):
			items.append_array(MapDrops.chest_items(String(plan["guard"]), level))
	return items


func _simulated_runs() -> void:
	MapDrops.forced = true
	var dungeon := MapModeDungeon.new()
	var all_ids: Array = []
	var typical: Array = []
	for n in MapModeLayout.nodes():
		all_ids.append(int(n["id"]))
		if not SKIPPED.has(int(n["id"])):
			typical.append(int(n["id"]))
	# One fixed run, exactly the target.
	seed(RUN_SEED)
	dungeon.plan_guards(RUN_SEED)
	var one: Dictionary = MapDrops.count_tiers(_roll_run(dungeon, typical))
	var one_n: int = int(one["normal"]) + int(one["magic"]) + int(one["rare"]) + int(one["legendary"])
	print("  SIMULATED RUN (seed %d, typical route, %d nodes): %d items = %s" % [RUN_SEED, typical.size(), one_n, str(one)])
	expect("the seeded run gives 15 to 20 items (%d)" % one_n, one_n >= 15 and one_n <= 20)
	expect("with about 8 magic (%d), 3 to 4 rare (%d) and 1 to 2 legendary (%d)" % [one["magic"], one["rare"], one["legendary"]],
		int(one["magic"]) >= 6 and int(one["magic"]) <= 10 and int(one["rare"]) >= 3 and int(one["rare"]) <= 4 and int(one["legendary"]) >= 1 and int(one["legendary"]) <= 2)
	# Many runs: the means sit on the target.
	var sums := {"normal": 0, "magic": 0, "rare": 0, "legendary": 0}
	var full := {"normal": 0, "magic": 0, "rare": 0, "legendary": 0}
	var in_range: int = 0
	for s in SIM_RUNS:
		seed(RUN_SEED + s + 1)
		dungeon.plan_guards(RUN_SEED + s + 1)
		var counts: Dictionary = MapDrops.count_tiers(_roll_run(dungeon, typical))
		var n: int = 0
		for k in sums:
			sums[k] = int(sums[k]) + int(counts[k])
			n += int(counts[k])
		in_range += 1 if n >= 14 and n <= 22 else 0
		var every: Dictionary = MapDrops.count_tiers(_roll_run(dungeon, all_ids))
		for k in full:
			full[k] = int(full[k]) + int(every[k])
	var mean := {}
	var full_mean := {}
	for k in sums:
		mean[k] = float(sums[k]) / SIM_RUNS
		full_mean[k] = float(full[k]) / SIM_RUNS
	var mean_n: float = float(mean["normal"]) + float(mean["magic"]) + float(mean["rare"]) + float(mean["legendary"])
	var full_n: float = float(full_mean["normal"]) + float(full_mean["magic"]) + float(full_mean["rare"]) + float(full_mean["legendary"])
	print("  SIMULATED MEANS over %d runs, typical route: %.1f items = %s" % [SIM_RUNS, mean_n, str(mean)])
	print("  SIMULATED MEANS over %d runs, every node cleared: %.1f items = %s" % [SIM_RUNS, full_n, str(full_mean)])
	expect("over %d seeded runs the mean is 15 to 20 items (%.1f)" % [SIM_RUNS, mean_n], mean_n >= 15.0 and mean_n <= 20.0)
	expect("the means are ~8 magic (%.1f), 3 to 4 rare (%.1f), 1 to 2 legendary (%.1f)" % [mean["magic"], mean["rare"], mean["legendary"]],
		float(mean["magic"]) >= 6.5 and float(mean["magic"]) <= 9.5 and float(mean["rare"]) >= 2.8 and float(mean["rare"]) <= 4.2 and float(mean["legendary"]) >= 1.5 and float(mean["legendary"]) <= 2.5)
	expect("most runs (%d of %d) land between 14 and 22 items" % [in_range, SIM_RUNS], in_range * 10 >= SIM_RUNS * 8)
	expect("clearing every node gives more than the typical run, and stays in reach (%.1f items)" % full_n, full_n > mean_n and full_n <= 30.0)
	for chest in dungeon.node_chests.values():
		(chest as Node).free()
	dungeon.free()
	MapDrops.forced = false
	MapDrops.run_seed = 0


# --- Champions (live) -----------------------------------------------------------------------------------------------------------------------

func _champion_drops() -> void:
	MapDrops.forced = true
	seed(2)
	var all_magic: bool = true
	for i in 300:
		all_magic = all_magic and int(MapDrops.champion_loot(3, "normal")["rarity"]) >= Items.Rarity.MAGIC
	MapDrops.forced = false
	expect("a champion's drop is magic or better, 300 rolls", all_magic)
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await _frames(2)
	var m := MapMode.new()
	game.add_child(m)
	expect("map mode is on for the live champion check", MapDrops.enabled())
	for i in 4:
		var z: Enemy = game.director.spawn_enemy(Nav.snap(player, player.global_position + Vector3(14.0 + 2.0 * i, 0.0, 4.0)), "zombie", WorldThreat.threat_for_level(2), "normal")
		z.aggro_range = 0.0
		z.alert_delay = 999.0
		Champion.attach(z, "fast")
		z.credit_hero()
		z._apply_damage(z.max_health + 10.0)
	await _frames(10)
	var magic_n: int = 0
	var drops: int = 0
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop != null and not drop.is_queued_for_deletion():
			drops += 1
			magic_n += 1 if int(drop.item["rarity"]) >= Items.Rarity.MAGIC else 0
	expect("four champions killed in map mode left at least four magic-or-better items on the ground (%d of %d drops)" % [magic_n, drops], magic_n >= 4)
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("orbs"):
		node.queue_free()
	m.queue_free()
	await _frames(3)
	expect("map mode is off again", not MapMode.active)


# --- A chest opens (lid and spray) ----------------------------------------------------------------------------------------------------------

func _chest_opens() -> void:
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await _frames(2)
	var chest := Chest.create("hoard", 4)
	game.add_child(chest)
	chest.global_position = Nav.snap(player, player.global_position + Vector3(10.0, 0.0, 0.0))
	await _frames(2)
	var opened: bool = chest.open()
	await _frames(3)
	var drops: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop != null and not drop.is_queued_for_deletion():
			drops.append(drop.item)
	var tiers: Dictionary = MapDrops.count_tiers(drops)
	expect("opening a Boss Hoard sprays 4 to 5 items with a legendary among them (%s)" % str(tiers), opened and chest.opened and drops.size() >= 4 and drops.size() <= 5 and int(tiers["legendary"]) >= 1)
	expect("a chest opens once", not chest.open())
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("orbs"):
		node.queue_free()
	chest.queue_free()
	await _frames(2)


# --- A run on the arena: every clear pays, shows the summary, and reopens the map ------------------------------------------------------------

func _run_pays_out() -> void:
	var cutter: Player = game.companion
	var cutter_was_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = false
	var base: Vector3 = player.global_position
	var spots: Array[Vector3] = [Nav.snap(player, base), Nav.snap(player, base + Vector3(18.0, 0.0, 0.0)), Nav.snap(player, base + Vector3(18.0, 0.0, -18.0)),
		Nav.snap(player, base + Vector3(36.0, 0.0, -18.0)), Nav.snap(player, base + Vector3(36.0, 0.0, 0.0))]
	var rows: Array = [
		{"id": 0, "kind": "start", "name": "Start", "pos": Vector2(spots[0].x, spots[0].z), "groups": [], "champion": ""},
		{"id": 1, "kind": "pack", "name": "Pack", "pos": Vector2(spots[1].x, spots[1].z), "groups": [["zombie", 2]], "champion": ""},
		{"id": 2, "kind": "shrine", "name": "Shrine", "pos": Vector2(spots[2].x, spots[2].z), "groups": [], "champion": ""},
		{"id": 3, "kind": "chest", "name": "Cache", "pos": Vector2(spots[3].x, spots[3].z), "groups": [], "champion": ""},
		{"id": 4, "kind": "boss", "name": "Boss", "pos": Vector2(spots[4].x, spots[4].z), "groups": [["zombie", 1]], "champion": ""}]
	var links: Array = []
	for pair in [[0, 1], [1, 2], [2, 3], [1, 4]]:
		links.append({"a": pair[0], "b": pair[1], "waypoints": [Vector2(spots[pair[0]].x, spots[pair[0]].z), Vector2(spots[pair[1]].x, spots[pair[1]].z)]})
	var g: MapGraph = MapGraph.from_rows(rows, links)
	var pack: Array[Enemy] = []
	for i in 2:
		pack.append(_spawn_enemy(Nav.snap(player, spots[1] + Vector3(2.0 * i, 0.0, 0.0)), "zombie", 1.0))
	var boss: Enemy = _spawn_enemy(spots[4], "zombie", 1.0)
	for e in pack:
		e.group_id = 931
		e.aggro_range = 0.0
	boss.group_id = 932
	boss.aggro_range = 0.0
	seed(RUN_SEED)
	MapDrops.run_seed = RUN_SEED
	var m := MapMode.new()
	m.use_graph(g, {1: 931, 4: 932})
	game.add_child(m)
	m.setup(player, cutter, hud)
	await _wait_state(m, MapMode.State.MAP, 120)
	expect("the map names what the boss guards before the player picks", m.state == MapMode.State.MAP and m.node_label(4).contains("Guards: Boss hoard"))
	var pack_plan: Dictionary = m.plan_of(1)
	expect("and the pack's label is its planned guard (%s)" % String(pack_plan["title"]), m.node_label(1).contains(String(pack_plan["title"])))
	# --- the pack ---
	m.overlay.selected.emit(1)
	await _wait_state(m, MapMode.State.FIGHT, 150)
	for e in pack:
		e.credit_hero()
		e._apply_damage(e.max_health + 10.0)
	await _wait_state(m, MapMode.State.COLLECT, 30)
	var saw_card: bool = false
	var guard_chest: Chest = m.node_chests.get(1) as Chest
	var n: int = 0
	while m.state != MapMode.State.MAP and n < 600:
		saw_card = saw_card or not hud.loot_cards.summary.is_empty()
		await get_tree().physics_frame
		n += 1
	var paid: Dictionary = m.loot_tally
	expect("a cleared pack paid gold and an item or a potion (%d gold, %d items, %d potions)" % [paid["gold"], (paid["items"] as Array).size(), int(paid["health"]) + int(paid["mana"])],
		int(paid["gold"]) > 0 and ((paid["items"] as Array).size() + int(paid["health"]) + int(paid["mana"])) >= 1)
	saw_card = saw_card or not hud.loot_cards.summary.is_empty()
	expect("the loot summary card shows over the reopened map, with no waiting for it (owner decision)", saw_card and m.state == MapMode.State.MAP and m.overlay.is_open()
		and not hud.loot_cards.summary.is_empty())
	if bool(pack_plan["chest"]):
		expect("a pack that guards a chest opened it by itself on the clear", guard_chest != null and guard_chest.opened and guard_chest.guard == pack_plan["guard"])
	# --- the shrine and the chest side branches ---
	for node_id in [2, 3]:
		m.overlay.selected.emit(node_id)
		await _wait_state(m, MapMode.State.COLLECT, 200)
		var seen: bool = false
		n = 0
		while m.state != MapMode.State.MAP and n < 600:
			seen = seen or not hud.loot_cards.summary.is_empty()
			await get_tree().physics_frame
			n += 1
		seen = seen or not hud.loot_cards.summary.is_empty()
		var p2: Dictionary = m.loot_tally
		expect("the %s paid gold and an item or a potion too, and showed its summary (%d gold, %d items, %d potions)" % [rows[node_id]["kind"], p2["gold"], (p2["items"] as Array).size(), int(p2["health"]) + int(p2["mana"])],
			seen and int(p2["gold"]) > 0 and ((p2["items"] as Array).size() + int(p2["health"]) + int(p2["mana"])) >= 1)
	# --- the boss ---
	m.overlay.selected.emit(4)
	await _wait_state(m, MapMode.State.FIGHT, 300)
	boss.credit_hero()
	boss._apply_damage(boss.max_health + 10.0)
	await _wait_state(m, MapMode.State.COLLECT, 60)
	var hoard: Chest = m.node_chests.get(4) as Chest
	var hoard_items: Array = (m.loot_tally["items"] as Array)
	var legendary: int = int(MapDrops.count_tiers(hoard_items)["legendary"])
	expect("the boss's Hoard opened by itself with 4 to 5 items and a legendary (%d items, %d legendary)" % [hoard_items.size(), legendary],
		hoard != null and hoard.opened and hoard.guard == "hoard" and hoard_items.size() >= 4 and hoard_items.size() <= 6 and legendary >= 1)
	await _wait_state(m, MapMode.State.DONE, 600)
	expect("clearing the boss still ends the run", m.state == MapMode.State.DONE and m.run_complete)
	var lines: PackedStringArray = m.log.summary_lines()
	print("  ", lines[lines.size() - 1])
	expect("the run's fight log totals report the loot", lines[lines.size() - 1].contains("loot ") and lines[lines.size() - 1].contains("items"))
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("orbs"):
		node.queue_free()
	for chest in m.node_chests.values():
		if is_instance_valid(chest):
			(chest as Node).queue_free()
	m.overlay.queue_free()
	m.queue_free()
	await _frames(3)
	MapDrops.run_seed = 0
	cutter.testing_disabled = cutter_was_disabled
	expect("map mode is off again at the end", not MapMode.active and not MapDrops.enabled())


# --- Developer capture (`-- --mmlootshot=<dir>`, 1080p on the second monitor): what the drop model looks like with the full HUD --------------

func _shot(dir: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, label])
	print("[mmlootshot] ", label)


func _map_loot_shot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	MapDrops.forced = true
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await _frames(3)
	# 1. The node map with the chest kinds named in the tooltips.
	var cutter: Player = game.companion
	var m := MapMode.new()
	var g: MapGraph = MapGraph.from_layout()
	m.use_graph(g, {})
	game.add_child(m)
	m.setup(player, cutter, hud)
	await _wait_state(m, MapMode.State.MAP, 200)
	for id in [0, 1, 3, 4, 6, 9, 10, 14]:
		g.mark_cleared(id)
	m.overlay.open(m.markers(), Vector3.ZERO, false)
	for id in [8, 12, 11, 13]:
		m.overlay._focus = id
		m.overlay._focus_shown = true
		m.overlay.queue_redraw()
		await _frames(4)
		await _shot(dir, "map_node_%d" % id)
	m.overlay.close()
	m.queue_free()
	await _frames(4)
	# 2. The five chests, closed; then the Boss Hoard open (lid and spray).
	var base: Vector3 = Nav.snap(player, player.global_position)
	player.global_position = base
	cutter.global_position = Nav.snap(player, base + Vector3(-2.5, 0.0, 1.5))
	var kinds: Array[String] = ["wooden", "iron", "gilded", "cursed", "hoard"]
	var chests: Array[Chest] = []
	for i in kinds.size():
		var chest := Chest.create(kinds[i], 4)
		game.add_child(chest)
		chest.global_position = Nav.snap(player, base + Vector3(-4.0 + 2.8 * float(i), 0.0, -3.0))
		chest.rotation.y = PI
		chests.append(chest)
		var tag := Label3D.new()   # names the kind in the capture
		tag.text = kinds[i].capitalize()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.006
		tag.no_depth_test = true
		tag.outline_size = 12
		game.add_child(tag)
		tag.global_position = chest.global_position + Vector3(0.0, 2.2, 0.0)
	await _frames(20)
	await _shot(dir, "chests_closed")
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	chests[4].open()
	await get_tree().create_timer(0.35).timeout
	await _shot(dir, "hoard_opening")
	await get_tree().create_timer(0.8).timeout
	await _shot(dir, "hoard_open")
	# 3. The loot summary for it, then with the inventory open.
	var tally := {"gold": 148, "health": 1, "mana": 0, "items": []}
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop != null:
			(tally["items"] as Array).append(drop.item)
	var rows: Array[Dictionary] = HudLootCards.summary_rows(tally, [player, cutter])
	hud.loot_cards.show_summary("The Warden's Court", tally, rows, 600.0)
	await _frames(6)
	await _shot(dir, "summary_hoard")
	hud._open_character()
	await _frames(8)
	await _shot(dir, "inventory_open_over_summary")
	hud.close_character()
	await _frames(6)
	await _shot(dir, "summary_after_inventory_closed")
	hud.loot_cards.hide_summary()
	MapDrops.forced = false
	get_tree().quit()
