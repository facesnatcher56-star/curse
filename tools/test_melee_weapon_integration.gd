extends SceneTree
## Comprehensive integration verification suite for melee weapon expansion (Task 3D)
## Run: & $GodotBin --headless -s tools/test_melee_weapon_integration.gd

const NEW_WEAPONS := ["axe_1h", "mace", "club", "dagger", "axe_2h", "hammer_2h"]
const ONE_HANDED := ["axe_1h", "mace", "club", "dagger"]
const TWO_HANDED := ["axe_2h", "hammer_2h"]

const EXPECTED_SIZES := {
	"axe_1h": Vector2i(1, 3),
	"mace": Vector2i(1, 3),
	"club": Vector2i(1, 2),
	"dagger": Vector2i(1, 2),
	"axe_2h": Vector2i(2, 3),
	"hammer_2h": Vector2i(2, 3),
}

var fails := 0
var total_checks := 0

func _expect(cond: bool, what: String) -> void:
	total_checks += 1
	if cond:
		print("  [PASS] " + what)
	else:
		print("  [FAIL] " + what)
		fails += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	print("==================================================")
	print("MELEE WEAPON EXPANSION INTEGRATION VERIFICATION")
	print("==================================================")

	_test_item_definitions_present()
	_test_ds2_baseline_damage_and_speed()
	_test_models_and_icons_resolve()
	_test_one_handed_vs_two_handed_mechanics()
	_test_inventory_footprints()
	_test_loot_generation()
	_test_save_load_roundtrip()
	_test_two_hand_clips_and_animations()
	await _test_live_combat_rig_and_visual_attachment()

	print("==================================================")
	print("RESULTS: %d checks, %d failures" % [total_checks, fails])
	if fails == 0:
		print("ALL CHECKS PASSED (100%)")
		quit(0)
	else:
		print("VERIFICATION FAILED")
		quit(1)

func _test_item_definitions_present() -> void:
	print("\n--- Test 1: Item Definitions in ItemDb ---")
	for id in NEW_WEAPONS:
		var def: ItemDef = ItemDb.get_def(id)
		_expect(def != null, "ItemDb contains definition for '%s'" % id)
		if def != null:
			_expect(def.slot == Items.Slot.WEAPON, "'%s' slot is Slot.WEAPON (0)" % id)
			_expect(def.levels.size() == 5, "'%s' has 5 item level variants" % id)
			var sorted_lvls: Array[int] = def.levels.duplicate()
			sorted_lvls.sort()
			_expect(def.levels == sorted_lvls, "'%s' level variants are strictly ascending: %s" % [id, str(def.levels)])

func _test_ds2_baseline_damage_and_speed() -> void:
	print("\n--- Test 2: DS2 Baseline Damage and Speed Formulas ---")
	# DS2 formulas:
	# 1H curve: 3.4 + 0.74 * L, min = avg * 0.75, max = avg * 1.25, speed = 1.0
	# 2H curve: 5.2 + 1.20 * L, min = avg * 0.75, max = avg * 1.25, speed = 0.82
	var test_levels := [10, 30, 60]

	for id in ONE_HANDED:
		var def: ItemDef = ItemDb.get_def(id)
		if def == null: continue
		for lvl in test_levels:
			var stats: Dictionary = def.stats_at(lvl)
			var expected_avg: float = 3.4 + 0.74 * float(lvl)
			var expected_min: float = expected_avg * 0.75
			var expected_max: float = expected_avg * 1.25
			_expect(is_equal_approx(float(stats["min"]), expected_min) and is_equal_approx(float(stats["max"]), expected_max),
				"1H '%s' at level %d damage matches DS2 curve (%.2f - %.2f)" % [id, lvl, stats["min"], stats["max"]])
			_expect(is_equal_approx(float(stats["speed"]), 1.0),
				"1H '%s' attack speed is 1.00" % id)

	for id in TWO_HANDED:
		var def: ItemDef = ItemDb.get_def(id)
		if def == null: continue
		for lvl in test_levels:
			var stats: Dictionary = def.stats_at(lvl)
			var expected_avg: float = 5.2 + 1.2 * float(lvl)
			var expected_min: float = expected_avg * 0.75
			var expected_max: float = expected_avg * 1.25
			_expect(is_equal_approx(float(stats["min"]), expected_min) and is_equal_approx(float(stats["max"]), expected_max),
				"2H '%s' at level %d damage matches DS2 curve (%.2f - %.2f)" % [id, lvl, stats["min"], stats["max"]])
			_expect(is_equal_approx(float(stats["speed"]), 0.82),
				"2H '%s' attack speed is 0.82 (matching greatsword)" % id)

func _test_models_and_icons_resolve() -> void:
	print("\n--- Test 3: 3D Models and Icons Resolution ---")
	for id in NEW_WEAPONS:
		var def: ItemDef = ItemDb.get_def(id)
		if def == null: continue
		_expect(ResourceLoader.exists(def.model_path), "'%s' model path exists: %s" % [id, def.model_path])
		_expect(ResourceLoader.exists(def.icon_path), "'%s' icon path exists: %s" % [id, def.icon_path])

		var scene := load(def.model_path) as PackedScene
		_expect(scene != null, "'%s' model GLB loads as PackedScene" % id)
		if scene != null:
			var node := scene.instantiate()
			_expect(node != null, "'%s' model instantiates cleanly" % id)
			if node != null:
				var bounds: AABB = CharacterModel._bounds_of(node)
				_expect(bounds.size.length() > 0.1, "'%s' model has non-zero geometry: %s" % [id, str(bounds.size)])
				node.free()

		var icon := load(def.icon_path) as Texture2D
		_expect(icon != null, "'%s' icon loads as Texture2D" % id)
		if icon != null:
			_expect(icon.get_width() > 0 and icon.get_height() > 0, "'%s' icon has dimensions %dx%d" % [id, icon.get_width(), icon.get_height()])

func _test_one_handed_vs_two_handed_mechanics() -> void:
	print("\n--- Test 4: 1H vs 2H Mechanics, Requirements, and Hand Conflicts ---")
	for id in ONE_HANDED:
		var item: Dictionary = Items.build(ItemDb.get_def(id), 20, Items.Rarity.NORMAL)
		var req: Dictionary = Items.requirement(item)
		_expect(req["passive"] == "", "1H '%s' does not require stance passive (got '%s')" % [id, req["passive"]])
		_expect(not PlayerStats._two_handed(item), "1H '%s' is not classified as two_handed" % id)

	for id in TWO_HANDED:
		var item: Dictionary = Items.build(ItemDb.get_def(id), 20, Items.Rarity.NORMAL)
		var req: Dictionary = Items.requirement(item)
		_expect(req["passive"] == "overbear", "2H '%s' requires Overbear passive (got '%s')" % [id, req["passive"]])
		_expect(PlayerStats._two_handed(item), "2H '%s' is classified as two_handed" % id)
		_expect(Items.requirement_text(item).contains("Overbear"), "2H '%s' requirement text includes Overbear" % id)

func _test_inventory_footprints() -> void:
	print("\n--- Test 5: Inventory Footprints and Rotation ---")
	var grid := preload("res://game/inventory_grid.gd")
	for id in NEW_WEAPONS:
		var item: Dictionary = Items.build(ItemDb.get_def(id), 20, Items.Rarity.NORMAL)
		var expected: Vector2i = EXPECTED_SIZES[id]
		var footprint: Vector2i = grid.footprint(item)
		_expect(footprint == expected, "'%s' inventory footprint is %s (expected %s)" % [id, str(footprint), str(expected)])

		item["bag_rotated"] = true
		var rotated: Vector2i = grid.footprint(item)
		_expect(rotated == Vector2i(expected.y, expected.x), "'%s' rotated footprint is %s (expected %s)" % [id, str(rotated), str(Vector2i(expected.y, expected.x))])

func _test_loot_generation() -> void:
	print("\n--- Test 6: Loot Generation Integration ---")
	var drops_seen := {}
	for id in NEW_WEAPONS:
		drops_seen[id] = 0

	# Roll drops across level ranges [1..80] to verify all new weapons are reachable
	for i in 1200:
		var lvl: int = randi_range(1, 80)
		var picked: Dictionary = Items.pick_base(lvl - 4, lvl + 2, Items.Slot.WEAPON)
		var def_id: String = String(picked["def"].id)
		if drops_seen.has(def_id):
			drops_seen[def_id] += 1

	for id in NEW_WEAPONS:
		_expect(drops_seen[id] > 0, "Loot generator rolled '%s' (%d drops rolled)" % [id, drops_seen[id]])

	# Also verify item_of_kind generates valid items with affixes
	var bow_def: ItemDef = ItemDb.get_def("short_bow")
	_expect(bow_def != null and Items._affix_class(bow_def) == "ranger", "Short Bow resolves to ranger affix class")

	for id in NEW_WEAPONS:
		var def: ItemDef = ItemDb.get_def(id)
		_expect(Items._affix_class(def) == "fighter", "'%s' resolves to fighter affix class" % id)
		var magic: Dictionary = Items.build(def, 30, Items.Rarity.MAGIC, Items.roll_mods(def, 30, Items.Rarity.MAGIC))
		var rare: Dictionary = Items.build(def, 30, Items.Rarity.RARE, Items.roll_mods(def, 30, Items.Rarity.RARE))
		_expect(magic["mods"].size() >= 1 and magic["mods"].size() <= 2, "Magic '%s' has 1-2 affixes (%d)" % [id, magic["mods"].size()])
		_expect(rare["mods"].size() >= 3 and rare["mods"].size() <= 4, "Rare '%s' has 3-4 affixes (%d)" % [id, rare["mods"].size()])
		_expect(magic["name"] != "", "Magic '%s' generated formatted name: '%s'" % [id, magic["name"]])
		_expect(rare["name"] != "", "Rare '%s' generated formatted name: '%s'" % [id, rare["name"]])
		# Verify no ranged affixes on melee weapons
		var no_ranged := true
		for mod_id in (magic["mods"] + rare["mods"]):
			if String(mod_id).begins_with("ranged_"):
				no_ranged = false
		_expect(no_ranged, "'%s' does not carry ranger-exclusive affixes" % id)

func _test_save_load_roundtrip() -> void:
	print("\n--- Test 7: Serialization Save/Load Roundtrip ---")
	for id in NEW_WEAPONS:
		var def: ItemDef = ItemDb.get_def(id)
		var original: Dictionary = Items.build(def, 45, Items.Rarity.RARE, ["fire_added_1", "strength_2", "life_1"])
		var saved: Dictionary = Items.to_save(original)
		var loaded: Dictionary = Items.from_save(saved)

		_expect(loaded["def"] == original["def"], "'%s' def survived save/load" % id)
		_expect(loaded["level"] == original["level"], "'%s' level (%d) survived save/load" % [id, loaded["level"]])
		_expect(loaded["rarity"] == original["rarity"], "'%s' rarity survived save/load" % id)
		_expect(loaded["mods"] == original["mods"], "'%s' affixes survived save/load" % id)
		_expect(is_equal_approx(float(loaded["stats"]["min"]), float(original["stats"]["min"])), "'%s' min damage survived save/load" % id)
		_expect(is_equal_approx(float(loaded["stats"]["max"]), float(original["stats"]["max"])), "'%s' max damage survived save/load" % id)
		_expect(is_equal_approx(float(loaded["stats"]["speed"]), float(original["stats"]["speed"])), "'%s' speed survived save/load" % id)

func _test_two_hand_clips_and_animations() -> void:
	print("\n--- Test 8: Two-Hand Clips and Animations ---")
	for id in TWO_HANDED:
		var def: ItemDef = ItemDb.get_def(id)
		var clips: Dictionary = def.profile.get("two_hand_clips", {})
		_expect(not clips.is_empty(), "2H '%s' has two_hand_clips defined" % id)
		for action in ["atk_slash_r", "atk_thrust", "atk_slash_l", "atk_slash", "atk_finisher"]:
			_expect(clips.has(action), "2H '%s' maps action '%s'" % [id, action])
			if clips.has(action):
				var clip_name: String = String(clips[action].get("clip", ""))
				_expect(clip_name.begins_with("atk2_"), "2H '%s' action '%s' uses two-handed clip '%s'" % [id, action, clip_name])

	for id in ONE_HANDED:
		var def: ItemDef = ItemDb.get_def(id)
		var clips: Dictionary = def.profile.get("two_hand_clips", {})
		_expect(clips.is_empty(), "1H '%s' does not specify two_hand_clips (defaults to 1H swing)" % id)

func _test_live_combat_rig_and_visual_attachment() -> void:
	print("\n--- Test 9: Live Character Rig Weapon Equipping and Visual Attachment ---")
	TownState.persist = false
	TownState.reset()
	TownState.job = {}
	TownState.dev_set_hero_level(30)
	TownState.passive_ranks["overbear"] = 1 # grant overbear so 2H weapons can equip

	var main: Node = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main

	for i in 4:
		await process_frame

	var player: Player = main.player
	_expect(player != null, "Main game scene instantiated player successfully")
	if player == null: return

	var shield: Dictionary = Items.build(ItemDb.get_def("buckler"), 10, Items.Rarity.NORMAL)

	for id in NEW_WEAPONS:
		var def: ItemDef = ItemDb.get_def(id)
		var item: Dictionary = Items.build(def, 10, Items.Rarity.NORMAL)
		var equipped: Variant = player.stats.equip(item, false)
		_expect(equipped != null, "Player successfully equips '%s'" % id)

		player.refresh_weapon_model()
		await process_frame
		_expect(player.model != null and player.model.weapon != null, "'%s' attached 3D weapon node to character model" % id)
		_expect(player.model != null and player.model.weapon_base != null and player.model.weapon_tip != null, "'%s' established weapon trail base and tip anchors" % id)

		var r: Vector2 = player.stats.weapon_base_range()
		_expect(r.x > 0.0 and r.y > r.x, "'%s' evaluates valid combat weapon range (%.1f - %.1f)" % [id, r.x, r.y])

		# Hand conflict test: 2H weapons cannot wear shield simultaneously without displacement
		if TWO_HANDED.has(id):
			_expect(player.stats._hand_conflict(item) == Items.Slot.SHIELD, "2H '%s' reports hand conflict with shield slot" % id)
			_expect(player.stats._hand_conflict(shield) == Items.Slot.WEAPON, "Shield reports hand conflict with 2H '%s'" % id)

	main.queue_free()
	await process_frame
