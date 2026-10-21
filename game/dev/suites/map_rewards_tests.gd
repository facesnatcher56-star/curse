extends DevSuite
## Map mode's reward panel (issue #87, game/ui/map_reward_panel.gd): its verdict is the shared comparison, Equip wears the item on the right member
## (PlayerStats.equip_from_bag, the autoplay's call), the panel never covers the party on screen, the chest icons and tiles exist for every tier and
## rarity, and a ground name plate never leaves the screen.

func _weapon(damage_scale: float, level: int = 1, name: String = "") -> Dictionary:
	var it: Dictionary = Items.build(ItemDb.get_def("club"), level, Items.Rarity.NORMAL)
	it["stats"] = (it["stats"] as Dictionary).duplicate(true)
	if it["stats"].has("max"):
		it["stats"]["min"] = float(it["stats"]["min"]) * damage_scale
		it["stats"]["max"] = float(it["stats"]["max"]) * damage_scale
	it["name"] = name if name != "" else "Test blade x%.1f" % damage_scale
	return it

func _helm(armor: float, item_name: String) -> Dictionary:
	var it: Dictionary = Items.build(ItemDb.get_def("leather_cap"), 1, Items.Rarity.NORMAL)
	it["stats"] = {"armor": armor}
	it["name"] = item_name
	return it

func _balance(item: Dictionary, current: Variant, member_id: String) -> int:
	var b: int = 0
	for line in Items.compare(item, current, member_id):
		if String(line.get("key", "")) != Items.WARNING_KEY:
			b += int(line["sign"])
	return b

func _test_map_rewards() -> void:
	TownState.persist = false
	TownState.reset()
	var hero: Player = player
	var cutter: Player = game.companion
	var party: Array = [hero, cutter]
	hero.set_physics_process(false)
	var cutter_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = true
	cutter.set_physics_process(false)
	var saved_hero: Dictionary = hero.stats.equipment.duplicate(true)
	var saved_cutter: Dictionary = cutter.stats.equipment.duplicate(true)
	var saved_bag: Array = hero.stats.bag.duplicate(true)
	hero.stats.bag.clear()
	var State = MapRewardPanel.State

	# --- the verdict is the shared comparison -------------------------------------------------------------------------------------------
	var weak: Dictionary = _weapon(1.0)
	hero.stats.equipment.clear()
	hero.stats.equipment[Items.Slot.WEAPON] = weak
	var top: Dictionary = _weapon(100.0, 1, "Unbeatable blade")   # the Cutter's weapon: nothing here beats it, so only the warrior's slots are in play
	cutter.stats.equipment[Items.Slot.WEAPON] = top
	hero.stats.refresh()
	cutter.stats.refresh()
	var strong: Dictionary = _weapon(3.0)
	var worse: Dictionary = _weapon(0.5)
	var locked: Dictionary = _weapon(10.0, 40, "Too high a blade")
	var left_over: Dictionary = _weapon(2.0, 1, "Left on the floor")
	for it in [strong, worse, locked]:
		hero.stats.add_to_bag(it)
	var up_info: Dictionary = MapRewardPanel.classify(strong, party)
	var down_info: Dictionary = MapRewardPanel.classify(worse, party)
	var lock_info: Dictionary = MapRewardPanel.classify(locked, party)
	var full_info: Dictionary = MapRewardPanel.classify(left_over, party)
	expect("setup: the shared comparison calls the strong blade better, the weak one worse, the level 40 one unwearable",
		_balance(strong, weak, "hero") > 0 and LootAppraisal.trend(strong, hero.stats) > 0 and LootAppraisal.trend(worse, hero.stats) < 0
		and not Items.hero_can_wear(locked, "hero") and not Items.hero_can_wear(locked, "cutter"))
	expect("an upgrade is UPGRADE for the warrior (it matches LootAppraisal.trend)", int(up_info["state"]) == State.UPGRADE and String(up_info["member"]) == "hero" and int(up_info["bag_index"]) >= 0)
	expect("a worse piece is DOWNGRADE, not an upgrade", int(down_info["state"]) == State.DOWNGRADE)
	expect("an unwearable piece is LOCKED and says only what is lacking (%s)" % String(lock_info["need"]),
		int(lock_info["state"]) == State.LOCKED and String(lock_info["need"]) == Items.requirement_card_text(locked, String(lock_info["member"])).replace("Requires ", "Needs ")
		and String(lock_info["need"]).begins_with("Needs ") and not String(lock_info["need"]).contains("have"))
	expect("an item left on the ground is Inventory full, whatever it would be", int(full_info["state"]) == State.FULL)
	expect("only STATE badges remain: none for upgrade / downgrade / unusable (the headline on the buttons says that), Inventory full (amber)",
		String(MapRewardPanel.badge_of(up_info)["text"]) == "" and String(MapRewardPanel.badge_of(down_info)["text"]) == "" and String(MapRewardPanel.badge_of(lock_info)["text"]) == ""
		and String(MapRewardPanel.badge_of(full_info)["text"]) == "Inventory full" and MapRewardPanel.badge_of(full_info)["color"] == MapRewardPanel.AMBER)
	var twin: Dictionary = weak.duplicate(true)
	twin["name"] = "Same blade, other name"
	hero.stats.add_to_bag(twin)
	expect("an equal piece is SIDEGRADE", int(MapRewardPanel.classify(twin, party)["state"]) == State.SIDEGRADE and LootAppraisal.trend(twin, hero.stats) == 0)
	expect("a worn piece is WORN, and its badge is neutral, not the upgrade green", int(MapRewardPanel.classify(weak, party)["state"]) == State.WORN
		and MapRewardPanel.badge_of(MapRewardPanel.classify(weak, party))["color"] == MapRewardPanel.NEUTRAL)
	hero.stats.bag.erase(twin)

	# --- the panel on the real HUD: tiles, badges, count-up, Equip ----------------------------------------------------------------------------
	var tally := {"gold": 148, "health": 2, "mana": 1, "items": [strong, worse, locked, left_over]}
	hud.show_gear = false
	hud.loot_cards.show_summary("The Warden's Court", tally, HudLootCards.summary_rows(tally, party), 60.0, "hoard")
	var panel: MapRewardPanel = hud.loot_cards.reward_panel
	await get_tree().process_frame
	await get_tree().process_frame
	expect("the reward panel is on the HUD", panel != null and panel.get_parent() == hud and panel.visible and panel.tiles.size() == 4)
	var equips: int = 0
	for entry in panel.tiles:
		equips += 1 if entry["equip"] != null else 0
	expect("wearable pieces in the bag have an enabled Equip button (upgrade and downgrade); the unusable one has it disabled; the left-over one has none",
		equips == 3 and not (panel.tiles[0]["equip"] as Button).disabled and not (panel.tiles[1]["equip"] as Button).disabled and (panel.tiles[2]["equip"] as Button).disabled and panel.tiles[3]["equip"] == null)
	expect("the Equip button names who it equips (%s)" % (panel.tiles[0]["equip"] as Button).text, (panel.tiles[0]["equip"] as Button).text == "Equip on %s" % hero.display_name)
	expect("gold and potions count up from zero to the totals", panel.shown_counts().x < 148 and panel.shown_counts().y < 3)
	panel.finish_count()
	expect("and end on them", panel.shown_counts() == Vector2i(148, 3))
	expect("the header carries the node's name and the chest kind", panel.title == "The Warden's Court" and panel.guard == "hoard")
	var before_name: String = String(hero.stats.equipment[Items.Slot.WEAPON]["name"])
	(panel.tiles[0]["equip"] as Button).pressed.emit()
	await get_tree().process_frame
	expect("pressing Equip wears the upgrade on the warrior (%s -> %s)" % [before_name, String(hero.stats.equipment[Items.Slot.WEAPON]["name"])],
		String(hero.stats.equipment[Items.Slot.WEAPON]["name"]) == String(strong["name"]) and String(cutter.stats.equipment[Items.Slot.WEAPON]["name"]) == "Unbeatable blade")
	expect("the replaced piece goes to the bag, and the tile now reads Equipped on the warrior", hero.stats.bag.any(func(i: Dictionary) -> bool: return String(i["name"]) == before_name)
		and int(panel.tiles[0]["info"]["state"]) == State.WORN and panel.tiles[0]["equip"] == null)
	expect("equipping again does nothing", not panel.equip_item(strong))
	hud.loot_cards.hide_summary()
	await get_tree().create_timer(MapRewardPanel.FADE_SECONDS + 0.2).timeout
	expect("it fades by itself and is gone", not is_instance_valid(panel) and hud.loot_cards.reward_panel == null)

	# --- Equip picks the right member: a piece only the Cutter can use goes on her ------------------------------------------------------------
	var helm: Dictionary = Items.build(ItemDb.get_def("leather_cap"), 1, Items.Rarity.NORMAL)
	cutter.stats.equipment.erase(Items.Slot.HELM)
	var unbeatable: Dictionary = Items.build(ItemDb.get_def("iron_helm"), 1, Items.Rarity.NORMAL)
	unbeatable["stats"] = {"armor": 9999}
	unbeatable["name"] = "Unbeatable helm"
	hero.stats.equipment[Items.Slot.HELM] = unbeatable
	hero.stats.refresh()
	cutter.stats.refresh()
	hero.stats.add_to_bag(helm)
	var helm_info: Dictionary = MapRewardPanel.classify(helm, party)
	expect("the verdict names the Cutter for a piece the warrior's better helm outclasses (%s)" % String(helm_info["who"]),
		int(helm_info["state"]) == State.UPGRADE and String(helm_info["member"]) == "cutter" and LootAppraisal.trend(helm, hero.stats) < 0)
	var tally2 := {"gold": 5, "health": 0, "mana": 0, "items": [helm]}
	hud.loot_cards.show_summary("Test", tally2, HudLootCards.summary_rows(tally2, party), 60.0, "wooden")
	var panel2: MapRewardPanel = hud.loot_cards.reward_panel
	await get_tree().process_frame
	expect("the Cutter's button headlines a gain for her", String(MapRewardPanel.headline(helm, cutter)["text"]).begins_with(Items.UP) and panel2.selected == "cutter")
	(panel2.tiles[0]["equip"] as Button).pressed.emit()
	expect("Equip puts it on the Cutter, not the warrior", cutter.stats.equipment.has(Items.Slot.HELM) and String(hero.stats.equipment[Items.Slot.HELM]["name"]) == "Unbeatable helm"
		and not hero.stats.bag.any(func(i: Dictionary) -> bool: return String(i["name"]) == String(helm["name"])))
	hud.loot_cards.hide_summary()

	# --- the panel never covers the party on screen -------------------------------------------------------------------------------------------
	var camera: Camera3D = get_viewport().get_camera_3d()
	var big_tally := {"gold": 90, "health": 1, "mana": 0, "items": []}
	for i in 6:
		(big_tally["items"] as Array).append(Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 12, "Longsword") if i % 2 == 0 else MapModeLegendaries.item("gravecaller_maul"))
	hud.loot_cards.show_summary("Crowded", big_tally, [], 60.0, "iron")
	var crowded: MapRewardPanel = hud.loot_cards.reward_panel
	for i in 5:
		await get_tree().process_frame
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var safe: Rect2 = MapRewardPanel.safe_rect(hud, screen)
	var covered: int = 0
	for body in party:
		var feet: Vector2 = camera.unproject_position((body as Node3D).global_position)
		var head: Vector2 = camera.unproject_position((body as Node3D).global_position + Vector3(0, 1.8, 0))
		covered += 1 if crowded.rect().has_point(feet) or crowded.rect().has_point(head) else 0
	expect("six tiles: the panel (%s on a %s screen) covers neither party member projected through the real camera" % [crowded.rect(), screen], covered == 0)
	expect("it stays inside the safe area (above the hotbar and vessels) and on screen (panel %s, safe %s)" % [crowded.rect(), safe], safe.grow(1.0).encloses(crowded.rect()) or crowded.rect().size.y >= safe.size.y - 1.0)
	expect("a tall list scrolls rather than growing past it", crowded.rect().end.y <= safe.end.y + 1.0)
	hud.loot_cards.hide_summary()
	# The docking choice: with the party on the right the panel goes to the left edge, below the party cards.
	var wide := Rect2(Vector2(16, 24), Vector2(1888, 820))
	var avoid_right: Array[Vector2] = [Vector2(1700, 400)]
	var avoid_left: Array[Vector2] = [Vector2(300, 400)]
	var no_one: Array[Vector2] = []
	var panel_size := Vector2(MapRewardPanel.WIDTH, 500)
	expect("docking: the right edge by default, the left edge (under the party cards) when the party stands on the right",
		String(MapRewardPanel.dock(panel_size, wide, no_one, 260.0)["side"]) == "right" and String(MapRewardPanel.dock(panel_size, wide, avoid_right, 260.0)["side"]) == "left"
		and (MapRewardPanel.dock(panel_size, wide, avoid_right, 260.0)["rect"] as Rect2).position.y >= 260.0 and String(MapRewardPanel.dock(panel_size, wide, avoid_left, 260.0)["side"]) == "right")

	# --- the title and chest kind come from the node actually visited ---------------------------------------------------------------------------
	var mm := MapMode.new()
	mm.use_graph(MapGraph.from_layout(), {})
	mm.hud = hud
	game.add_child(mm)
	var checked: int = 0
	for id in [mm.graph.boss_id, 5, 12]:
		mm._visit_node = int(id)
		mm._visit_kind = "group"
		var shown: bool = mm._show_loot_summary([])
		var shown_panel: MapRewardPanel = hud.loot_cards.reward_panel
		checked += 1 if shown and shown_panel != null and shown_panel.title == String(mm.graph.row(int(id)).get("name", "")) and shown_panel.guard == String(mm.plan_of(int(id)).get("guard", "")) else 0
		hud.loot_cards.hide_summary()
	expect("the panel names the node that was visited and its planned chest kind (boss hoard included): %d of 3" % checked, checked == 3 and String(mm.plan_of(mm.graph.boss_id)["guard"]) == "hoard")
	mm.queue_free()

	# --- a legendary tile is larger and carries its effect in full -----------------------------------------------------------------------------
	var legend: Dictionary = MapModeLegendaries.item("gravecaller_maul")
	var line: Dictionary = MapRewardPanel.key_line(legend, "hero")
	expect("a legendary's key line is its whole effect", String(line["section"]) == "legendary" and String(line["text"]).begins_with("Legendary: ") and String(line["text"]).length() > 20)
	var rare: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 12, "Longsword")
	expect("an ordinary item's key line is one modifier or its base stat", String(MapRewardPanel.key_line(rare, "hero")["text"]) != "" and String(MapRewardPanel.key_line(rare, "hero")["section"]) in ["trait", "mods", "base"])

	# --- ground name plates never leave the screen ---------------------------------------------------------------------------------------------
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame
	var ground: Vector3 = Nav.snap(hero, hero.global_position)
	var depth: float = camera.global_position.distance_to(ground)
	var long_item: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 12, "Longsword")
	long_item["name"] = "Cruel Longsword of Haste and Many Other Long Words"
	var right_edge: Vector3 = camera.project_position(Vector2(screen.x - 4.0, screen.y * 0.4), depth)
	var left_edge: Vector3 = camera.project_position(Vector2(4.0, screen.y * 0.4), depth)
	right_edge.y = ground.y
	left_edge.y = ground.y
	var d_right: LootDrop = game.director.drop_item(right_edge, long_item.duplicate(true))
	var d_left: LootDrop = game.director.drop_item(left_edge, long_item.duplicate(true))
	d_right._end = right_edge
	d_left._end = left_edge
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.5).timeout
	hud.show_gear = false
	var plates: Array[Dictionary] = hud.loot_cards._layout_loot_names(ThemeDB.fallback_font)
	var off: int = 0
	for entry in plates:
		var r: Rect2 = entry["rect"]
		off += 0 if (r.position.x >= 0.0 and r.end.x <= screen.x and r.position.y >= 0.0 and r.end.y <= screen.y) else 1
	expect("plates at the left and right screen edges stay inside the screen (%d placed, %d off screen)" % [plates.size(), off], off == 0)
	var top_spot: Vector3 = camera.project_position(Vector2(screen.x * 0.5, 3.0), depth)
	top_spot.y = ground.y
	var d_top: LootDrop = game.director.drop_item(top_spot, long_item.duplicate(true))
	d_top._end = top_spot
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.5).timeout
	var top_plates: Array[Dictionary] = hud.loot_cards._layout_loot_names(ThemeDB.fallback_font)
	var top_ok: bool = true
	for entry in top_plates:
		var tr: Rect2 = entry["rect"]
		top_ok = top_ok and tr.position.y >= 0.0 and tr.end.y <= screen.y
	expect("a plate over an item at the top edge stays on screen too (%d placed)" % top_plates.size(), top_ok)
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()

	# --- map mode never wears a pickup, and the selector says who the panel is for -----------------------------------------------------------------
	hero.stats.equipment.clear()
	cutter.stats.equipment.clear()
	hero.stats.bag.clear()
	var empty_helm: Dictionary = Items.build(ItemDb.get_def("leather_cap"), 1, Items.Rarity.NORMAL)
	expect("setup: both members can wear the cap", Items.hero_can_wear(empty_helm, "hero") and Items.hero_can_wear(empty_helm, "cutter"))
	var flag_off: String = hero.stats.pickup(empty_helm.duplicate(true))
	expect("flag off (the default game): a pickup into an empty slot is worn at once, as before (%s)" % flag_off, hero.stats.equipment.has(Items.Slot.HELM) and flag_off.begins_with("Equipped"))
	hero.stats.equipment.erase(Items.Slot.HELM)
	hero.stats.bag.clear()
	MapMode.current = MapMode.new()
	expect("map mode on: the loot appraisal still calls a piece for an empty slot an upgrade", LootAppraisal.of(empty_helm, hero.stats) == LootAppraisal.Verdict.UPGRADE and not hero.stats.takes_empty_slot(empty_helm))
	hero.stats.pickup(empty_helm.duplicate(true))
	cutter.stats.pickup(empty_helm.duplicate(true))
	expect("map mode on: an empty slot is NOT filled by a pickup, for the warrior or the Cutter; both go to the shared bag",
		not hero.stats.equipment.has(Items.Slot.HELM) and not cutter.stats.equipment.has(Items.Slot.HELM) and hero.stats.bag.size() == 2 and cutter.stats.bag.size() == 2)
	hero.stats.bag.clear()
	var helm_old_hero: Dictionary = _helm(10, "Hero old cap")
	var helm_old_cutter: Dictionary = _helm(30, "Cutter old cap")
	var helm_mid: Dictionary = _helm(20, "Middling cap")
	hero.stats.equipment[Items.Slot.HELM] = helm_old_hero
	cutter.stats.equipment[Items.Slot.HELM] = helm_old_cutter
	hero.stats.refresh()
	cutter.stats.refresh()
	hero.stats.add_to_bag(helm_mid)
	var tally3 := {"gold": 1, "health": 0, "mana": 0, "items": [helm_mid]}
	hud.loot_cards.show_summary("Selector", tally3, [], 60.0, "wooden")
	var sp: MapRewardPanel = hud.loot_cards.reward_panel
	await get_tree().process_frame
	await get_tree().process_frame
	expect("default selection: the member the clear helps most (the warrior: an upgrade for him, a downgrade for the Cutter), and the selector has both buttons",
		MapRewardPanel.default_member([helm_mid], party) == "hero" and sp.selected == "hero" and sp.selector_buttons.size() == 2)
	expect("nothing is worn just because it is selected", String(hero.stats.equipment[Items.Slot.HELM]["name"]) == "Hero old cap" and String(cutter.stats.equipment[Items.Slot.HELM]["name"]) == "Cutter old cap")
	expect("warrior selected: Equip on Hero (and no verdict badge)", sp.tiles[0]["badge"] == null
		and (sp.tiles[0]["equip"] as Button).text == "Equip on %s" % hero.display_name)
	sp.select_member("cutter")
	await get_tree().process_frame
	expect("switching to the Cutter re-reads the same item for her: Downgrade, Equip on Cutter",
		sp.selected == "cutter" and String(MapRewardPanel.headline(helm_mid, cutter)["text"]).begins_with(Items.DOWN) and (sp.tiles[0]["equip"] as Button).text == "Equip on %s" % cutter.display_name and sp.tiles.size() == 1)
	expect("and still wore nothing", String(hero.stats.equipment[Items.Slot.HELM]["name"]) == "Hero old cap" and String(cutter.stats.equipment[Items.Slot.HELM]["name"]) == "Cutter old cap" and hero.stats.bag.size() == 1)
	# keyboard: Tab, 1 and 2
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	sp._input(tab)
	var ok_tab: bool = sp.selected == "hero"
	var key2 := InputEventKey.new()
	key2.keycode = KEY_2
	key2.pressed = true
	sp._input(key2)
	var ok_two: bool = sp.selected == "cutter"
	var key1 := InputEventKey.new()
	key1.keycode = KEY_1
	key1.pressed = true
	sp._input(key1)
	expect("keyboard: Tab cycles, 2 picks the Cutter, 1 picks the warrior", ok_tab and ok_two and sp.selected == "hero")
	# controller: LB / RB, and Left / Right once the list has the focus
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	sp._input(rb)
	var ok_rb: bool = sp.selected == "cutter"
	var lb := InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb.pressed = true
	sp._input(lb)
	var ok_lb: bool = sp.selected == "hero"
	sp._focus(0)
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	sp._input(right)
	var ok_right: bool = sp.selected == "cutter"
	var left := InputEventAction.new()
	left.action = "ui_left"
	left.pressed = true
	sp._input(left)
	expect("controller: RB / LB switch member, and Right / Left do too while the list has the focus", ok_rb and ok_lb and ok_right and sp.selected == "hero")
	get_viewport().gui_release_focus()
	# Equip goes to the selected member only; the old piece goes to the bag; the tile says so; the other member sees it as worn by the warrior
	(sp.tiles[0]["equip"] as Button).pressed.emit()
	await get_tree().process_frame
	expect("Equip wore it on the selected warrior only, the Cutter is untouched",
		String(hero.stats.equipment[Items.Slot.HELM]["name"]) == "Middling cap" and String(cutter.stats.equipment[Items.Slot.HELM]["name"]) == "Cutter old cap")
	expect("the replaced cap went to the bag and the tile reads Equipped on Hero",
		hero.stats.bag.any(func(i: Dictionary) -> bool: return String(i["name"]) == "Hero old cap") and String(MapRewardPanel.badge_of(sp.tiles[0]["info"])["text"]) == "Equipped on %s" % hero.display_name
		and sp.tiles[0]["equip"] == null)
	sp.select_member("cutter")
	await get_tree().process_frame
	var other_equip: Button = sp.tiles[0]["equip"]
	expect("for the Cutter it is Worn by Hero, with Equip disabled and explained, and equipping it fails",
		String(MapRewardPanel.badge_of(sp.tiles[0]["info"])["text"]) == "Worn by %s" % hero.display_name and other_equip != null and other_equip.disabled and other_equip.tooltip_text.contains("Worn by") and not sp.equip_item(helm_mid))
	hud.loot_cards.hide_summary()

	# default selection when the other member gains more
	hero.stats.equipment[Items.Slot.HELM] = _helm(40, "Hero great cap")
	cutter.stats.equipment[Items.Slot.HELM] = _helm(5, "Cutter poor cap")
	hero.stats.refresh()
	cutter.stats.refresh()
	expect("default selection: the Cutter when the clear helps her most, the warrior on a tie",
		MapRewardPanel.default_member([helm_mid], party) == "cutter" and MapRewardPanel.default_member([], party) == "hero")

	# a two-handed weapon against a worn shield, and an item neither can use
	var saved_ranks: Dictionary = hero.character.passive_ranks.duplicate()
	hero.character.passive_ranks["overbear"] = 1   # (DS2: a two-handed weapon needs Overbear)
	var two: Dictionary = {}
	for id in ["axe_2h", "greatsword", "hammer_2h"]:
		var cand: Dictionary = Items.build(ItemDb.get_def(id), 1, Items.Rarity.NORMAL)
		if Items.hero_can_wear(cand, "hero"):
			two = cand
			break
	var shield: Dictionary = Items.build(ItemDb.get_def("heater_shield"), 1, Items.Rarity.NORMAL)
	if not two.is_empty() and Items.hero_can_wear(shield, "hero"):
		hero.stats.equipment.clear()
		hero.stats.equipment[Items.Slot.SHIELD] = shield
		hero.stats.refresh()
		hero.stats.bag.clear()
		hero.stats.add_to_bag(two)
		var conflict: Dictionary = MapRewardPanel.classify_for(two, party, "hero")
		expect("a two-handed weapon over a worn shield is a CONFLICT that says what it replaces, and it can still be equipped",
			int(conflict["state"]) == State.CONFLICT and String(MapRewardPanel.badge_of(conflict)["text"]) == "Replaces Shield" and MapRewardPanel.can_equip(conflict))
	else:
		expect("setup: a two-handed weapon and a shield the warrior can wear exist (two %s, shield %s, needs: %s)" % [not two.is_empty(), Items.hero_can_wear(shield, "hero"), Items.requirement_text(Items.build(ItemDb.get_def("axe_2h"), 1, Items.Rarity.NORMAL), "hero")], false)
	hero.character.passive_ranks = saved_ranks
	var nobody: Dictionary = _weapon(10.0, 40, "Beyond both")
	hero.stats.bag.clear()
	hero.stats.add_to_bag(nobody)
	var nb: Dictionary = MapRewardPanel.classify_for(nobody, party, "cutter")
	expect("an item neither can use: the reason reads Can't use: Needs ..., both buttons get the red cross, no Equip",
		int(nb["state"]) == State.LOCKED and String(nb["need"]).begins_with("Can't use: Needs ") and String(MapRewardPanel.headline(nobody, cutter)["plain"]).begins_with(MapRewardPanel.cross()) and not MapRewardPanel.can_equip(nb)
		and String(MapRewardPanel.classify_for(nobody, party, "hero")["need"]).begins_with("Can't use: Needs "))

	# --- headlines on the selector buttons, no verdict badges, expanding in place -----------------------------------------------------
	hero.stats.equipment.clear()
	cutter.stats.equipment.clear()
	hero.stats.bag.clear()
	var blade_hero: Dictionary = _weapon(1.0, 1, "Hero blade")
	hero.stats.equipment[Items.Slot.WEAPON] = blade_hero
	hero.stats.equipment[Items.Slot.HELM] = _helm(10, "Hero cap")
	cutter.stats.equipment[Items.Slot.HELM] = _helm(30, "Cutter cap")
	hero.stats.refresh()
	cutter.stats.refresh()
	var up_blade: Dictionary = _weapon(3.0, 1, "Better blade")
	var down_blade: Dictionary = _weapon(0.5, 1, "Weaker blade")
	var twin_blade: Dictionary = blade_hero.duplicate(true)
	twin_blade["name"] = "Twin blade"
	var cap_new: Dictionary = _helm(20, "Fresh cap")
	var derived: String = ""
	for cl in Items.compare(up_blade, blade_hero, "hero"):
		if String(cl["key"]) == "damage":
			derived = "%s Damage +%s" % [Items.UP, String(cl["delta"]).substr(2)]
	var h_up: Dictionary = MapRewardPanel.headline(up_blade, hero)
	expect("weapon headline: damage, the shared comparison's own number (%s)" % String(h_up["plain"]), derived != "" and String(h_up["text"]) == derived and int(h_up["sign"]) > 0 and MapRewardPanel.headline_key(up_blade) == "damage")
	var h_down: Dictionary = MapRewardPanel.headline(down_blade, hero)
	expect("a weaker weapon: red down arrow and the number (%s)" % String(h_down["text"]), String(h_down["text"]).begins_with("%s Damage -" % Items.DOWN) and MapRewardPanel.headline_color(h_down) == MapRewardPanel.SOFT_RED)
	var h_same: Dictionary = MapRewardPanel.headline(twin_blade, hero)
	expect("an equal weapon: = Damage, grey", String(h_same["text"]) == "= Damage" and MapRewardPanel.headline_color(h_same) == MapRewardPanel.DIM and int(h_same["sign"]) == 0)
	var h_cap_hero: Dictionary = MapRewardPanel.headline(cap_new, hero)
	var h_cap_cutter: Dictionary = MapRewardPanel.headline(cap_new, cutter)
	expect("armor headline: armor, per member (%s for Hero, %s for Cutter)" % [String(h_cap_hero["text"]), String(h_cap_cutter["text"])],
		MapRewardPanel.headline_key(cap_new) == "armor" and String(h_cap_hero["text"]) == "%s Armor +10" % Items.UP and String(h_cap_cutter["text"]) == "%s Armor -10" % Items.DOWN)
	var ring: Dictionary = Items.make(Items.Slot.RING, Items.Rarity.RARE, 12)
	var ring_key: String = MapRewardPanel.headline_key(ring)
	var h_ring: Dictionary = MapRewardPanel.headline(ring, hero)
	expect("ring / amulet headline: its best (first) modifier (%s: %s)" % [ring_key, String(h_ring["text"])], ring_key.begins_with("mod:") and String(h_ring["text"]).begins_with(Items.UP))
	var h_empty: Dictionary = MapRewardPanel.headline(_weapon(2.0), cutter)
	expect("an empty slot is all gain, with the item's own number", cutter.stats.equipment.has(Items.Slot.WEAPON) == false and int(h_empty["sign"]) > 0 and String(h_empty["text"]).begins_with("%s Damage +" % Items.UP))
	var far: Dictionary = _weapon(10.0, 40, "Out of reach")
	var h_far: Dictionary = MapRewardPanel.headline(far, hero)
	expect("a member who cannot use it: a red cross, then the would-be change as if usable; the reason is kept apart",
		not bool(h_far["usable"]) and String(h_far["plain"]).begins_with(MapRewardPanel.cross()) and String(h_far["text"]).begins_with("%s Damage +" % Items.UP) and String(h_far["need"]).begins_with("Needs ")
		and MapRewardPanel.headline_bbcode(h_far).contains(MapRewardPanel.cross()))

	hero.stats.add_to_bag(cap_new)
	hero.stats.add_to_bag(far)
	var tally4 := {"gold": 1, "health": 0, "mana": 0, "items": [cap_new, far]}
	hud.loot_cards.show_summary("Headlines", tally4, [], 60.0, "wooden")
	var hp: MapRewardPanel = hud.loot_cards.reward_panel
	await get_tree().process_frame
	await get_tree().process_frame
	var hero_summary: RichTextLabel = hp.selector_summaries["hero"]
	var cutter_summary: RichTextLabel = hp.selector_summaries["cutter"]
	expect("the buttons show the headline of the first item by default (Hero: %s | Cutter: %s)" % [hero_summary.text, cutter_summary.text],
		hero_summary.text.contains("Armor +10") and cutter_summary.text.contains("Armor -10") and MapAutoGear.key_of(hp.subject) == MapAutoGear.key_of(cap_new))
	hp.set_subject(far)
	var far_hero_tip: String = (hp.selector_buttons["hero"] as Button).tooltip_text
	expect("hovering or focusing the second item moves the summary to it; the member who cannot use it gets the cross, and the tooltip carries the reason (%s)" % far_hero_tip.replace("\n", " / "),
		hero_summary.text.contains(MapRewardPanel.cross()) and hero_summary.text.contains("Damage") and far_hero_tip.contains("Needs "))
	expect("the verdict badges are gone: an unworn tile has no badge at all, and Equip stays (enabled for the cap, disabled and explained for the unusable blade)",
		hp.tiles[0]["badge"] == null and hp.tiles[1]["badge"] == null and not (hp.tiles[0]["equip"] as Button).disabled and (hp.tiles[1]["equip"] as Button).disabled and (hp.tiles[1]["equip"] as Button).tooltip_text.contains("Needs "))
	# expanding in place
	hp.toggle_expand(cap_new)
	await get_tree().process_frame
	expect("clicking a tile opens its full details in place (the shared card, compared with the selected member's cap)",
		bool(hp.tiles[0]["open"]) and hp.tiles[0]["panel"].find_child("Details", true, false) != null and not bool(hp.tiles[1]["open"]))
	hp.toggle_expand(far)
	await get_tree().process_frame
	expect("opening another closes the first", not bool(hp.tiles[0]["open"]) and bool(hp.tiles[1]["open"]) and hp.tiles[0]["panel"].find_child("Details", true, false) == null)
	hp.toggle_expand(far)
	await get_tree().process_frame
	expect("clicking it again closes it", not bool(hp.tiles[1]["open"]) and hp.expanded_key == "")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hp._tile_clicked(click, cap_new)
	await get_tree().process_frame
	expect("a left click on a tile opens it", bool(hp.tiles[0]["open"]))
	# controller: A opens a tile, A on its Equip button wears it
	hp.toggle_expand(cap_new)   # closed again
	await get_tree().process_frame
	hp.select_member("hero")
	hp._focus(0)
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	hp._input(accept)
	await get_tree().process_frame
	var owner_now: Control = get_viewport().gui_get_focus_owner()
	expect("controller: A on a focused tile opens it and moves the focus to its Equip button; nothing is worn yet",
		bool(hp.tiles[0]["open"]) and owner_now == hp.tiles[0]["equip"] and String(hero.stats.equipment[Items.Slot.HELM]["name"]) == "Hero cap")
	hp._input(accept)
	await get_tree().process_frame
	expect("and A on the Equip button wears it on the selected member", String(hero.stats.equipment[Items.Slot.HELM]["name"]) == "Fresh cap" and String(cutter.stats.equipment[Items.Slot.HELM]["name"]) == "Cutter cap")
	hud.loot_cards.hide_summary()
	await get_tree().create_timer(MapRewardPanel.FADE_SECONDS + 0.2).timeout

	# --- the key line is never cut; the panel has no permanent key hints ------------------------------------------------------------------------
	var trait_items: Array = []
	for base in MapModeTraits.TABLE:
		trait_items.append(Items.build(ItemDb.get_def(String(base)), 1, Items.Rarity.NORMAL))
	for id in MapModeLegendaries.DEFS:
		trait_items.append(MapModeLegendaries.item(String(id)))
	hud.loot_cards.show_summary("Long lines", {"gold": 0, "health": 0, "mana": 0, "items": trait_items}, [], 60.0, "iron")
	var lp: MapRewardPanel = hud.loot_cards.reward_panel
	await get_tree().process_frame
	await get_tree().process_frame
	var uncut: int = 0
	var checked_lines: int = 0
	var longest: String = ""
	for entry in lp.tiles:
		var expected: String = String(MapRewardPanel.key_line(entry["item"], "hero")["text"])
		if expected == "":
			continue
		var found: Label = null
		for lab in (entry["panel"] as Node).find_children("*", "Label", true, false):
			if (lab as Label).text == expected:
				found = lab
		checked_lines += 1
		if found != null and found.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and found.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and found.custom_minimum_size.x >= 150.0:
			uncut += 1
		if expected.length() > longest.length():
			longest = expected
	expect("every trait and legendary key line wraps in full (word wrap, no trimming): %d of %d, longest \"%s\"" % [uncut, checked_lines, longest], checked_lines >= 10 and uncut == checked_lines)
	var signet_line: String = MapModeTraits.line_for("signet")
	var signet_label: Label = MapRewardPanel.key_label(signet_line, MapRewardPanel.NEUTRAL, 322.0)
	expect("the Signet's trait line is not trimmed", signet_line.contains("When you use a power") and signet_label.text == signet_line and signet_label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and signet_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART)
	signet_label.free()
	var tile_equip: Button = null
	for entry in lp.tiles:
		if entry["equip"] != null:
			tile_equip = entry["equip"]
	expect("Equip is on a row of its own under the text, not beside it", tile_equip == null or tile_equip.get_parent() is VBoxContainer)
	expect("the footer is just the Continue button: no permanent key hint, no member marks, no 'for X' note",
		lp.find_child("Hint", true, false) == null and lp.find_child("Marks", true, false) == null and lp.find_child("Note", true, false) == null and lp.continue_button != null)
	hud.loot_cards.hide_summary()
	await get_tree().create_timer(MapRewardPanel.FADE_SECONDS + 0.2).timeout
	MapMode.current.free()
	MapMode.current = null

	# --- clean up ---------------------------------------------------------------------------------------------------------------------------------
	hero.stats.equipment.clear()
	for place in saved_hero:
		hero.stats.equipment[place] = saved_hero[place]
	cutter.stats.equipment.clear()
	for place in saved_cutter:
		cutter.stats.equipment[place] = saved_cutter[place]
	hero.stats.bag.assign(saved_bag)
	hero.stats.refresh()
	cutter.stats.refresh()
	cutter.testing_disabled = cutter_disabled
	cutter.set_physics_process(true)
	hero.set_physics_process(true)
	hud.loot_cards.hide_summary()
