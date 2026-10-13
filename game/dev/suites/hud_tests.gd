extends DevSuite
## Self-test: character sheet, orbs, minimap fog, inventory equipping and the owner-feedback pass.

func _test_character_ui() -> void:
	TownState.persist = false
	TownState.reset()
	var town := TownScene.new()
	town.with_road = false
	game.add_child(town)
	await get_tree().process_frame
	var gate: Node3D = town.town_gate
	expect("town gate has two hinged leaves", gate.leaves.size() == 2 and gate.leaves[0] != null and gate.leaves[1] != null)
	town.player.position = Vector3(0, 0, -15)
	await get_tree().create_timer(0.9).timeout
	expect("approaching opens both doors", gate.openness > 0.95 and absf(gate.leaves[0].rotation.y) > 1.4)
	town.player.position = Vector3(0, 0, -35)
	await get_tree().create_timer(0.9).timeout
	expect("leaving closes the doors", gate.openness < 0.05)
	town.player.position = Vector3(0, 0, -25)
	await get_tree().create_timer(0.9).timeout
	expect("approaching from outside opens doors", gate.openness > 0.95)
	var previous_hover_pad: bool = Gamepad.active
	Gamepad.active = true
	var trader: TownNpc = town.npcs["marlow"]
	town.player.position = trader.position + Vector3(0, 0, 1)
	town._process(0)
	expect("NPC hover card shows name and profession", town.hud.prompt.contains(trader.def.display_name) and town.hud.prompt.contains(trader.def.title))
	var trader_anchor: Vector2 = town.get_viewport().get_camera_3d().unproject_position(trader.position + Vector3(0, 2.6, 0))
	expect("NPC card is anchored over the NPC", town.hud.prompt_position.distance_to(trader_anchor) < 1)
	var stash: Dictionary = town._spot("stash")
	town.player.position = stash["pos"]
	town._process(0)
	expect("stash prompt appears over the stash", town.hud.prompt.contains("stash") and town.hud.prompt_position.distance_to(town.get_viewport().get_camera_3d().unproject_position(stash["pos"] + Vector3(0, 2.6, 0))) < 1)
	Gamepad.active = previous_hover_pad
	var view_hud: Hud = town.combat_hud
	town.player.stats.bag.append(Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "Falchion"))
	var toggle := InputEventAction.new()
	toggle.action = "gear"
	toggle.pressed = true
	view_hud._input(toggle)
	await get_tree().create_timer(0.3).timeout
	expect("opening the character view pauses gameplay", get_tree().paused)
	expect("character portrait is a separate viewport", view_hud.character_panel.find_children("*", "SubViewport", true, false).size() == 1)
	var sheet: Control = view_hud.character_panel
	var character_rect: Rect2 = sheet.get_global_rect()
	expect("character view blocks clicks inside its panel, not outside it",
		view_hud.covers(character_rect.get_center()) and not view_hud.covers(Vector2(100, 100)))
	expect("character sheet shows the DS2 human starting attributes, life and mana",
		sheet.attributes_label.text.contains("STR 12  DEX 11  INT 11") and sheet.attributes_label.text.contains("Life 64  Mana 55"))
	expect("character sheet exposes all four class levels, defences and nine equipment slots",
		sheet.classes_label.text.contains("Melee 0") and sheet.classes_label.text.contains("Ranged 0")
		and sheet.classes_label.text.contains("Combat Magic 0") and sheet.classes_label.text.contains("Nature Magic 0")
		and sheet.gear_text().contains("Armor") and sheet.gear_text().contains("Magic find 10%") and sheet._doll_tiles.size() == 9)
	var falchion_item: Dictionary = town.player.stats.bag.filter(func(it: Dictionary) -> bool: return String(it["name"]).contains("Falchion"))[0]
	var falchion_tile: ItemTile = _inventory_item_control(view_hud, falchion_item, false) as ItemTile
	var card_visible: bool = false
	if falchion_tile != null:
		var details: Control = falchion_tile.get_node_or_null("ItemDetails") as Control
		var motion := InputEventMouseMotion.new()
		motion.position = falchion_tile.get_global_rect().get_center()
		get_viewport().push_input(motion, true)
		await get_tree().process_frame
		if details != null and details.visible and details.get_child_count() > 0:
			var card: Control = details.get_child(0) as Control
			var card_labels: Array[Node] = card.find_children("*", "Label", true, false)
			card_visible = card_labels.size() > 3 and card_labels.any(func(label: Label) -> bool: return label.text == String(falchion_item["name"]))
	expect("backpack item tiles show the full stats card on hover", card_visible)
	var previous_pad: bool = Gamepad.active
	Gamepad.active = true
	var tiles: Array[Node] = view_hud.character_panel.find_children("*", "Control", true, false).filter(func(node: Node) -> bool: return node is ItemTile)
	if not tiles.is_empty():
		var tile := tiles[0] as ItemTile
		tile.grab_focus()
		await get_tree().process_frame
		expect("controller focus shows the item stats card", tile.get_child(0).visible)
	Gamepad.active = previous_pad
	var old: Dictionary = town.player.stats.equipment[Items.Slot.WEAPON]
	var old_saved: Dictionary = Items.to_save(old)
	var has_equip_button: bool = false
	for button in view_hud.character_panel.find_children("*", "Button", true, false):
		if button.text == "Equip":
			has_equip_button = true
	expect("bag items carry no Equip button (the card says how: R-click)", not has_equip_button)
	expect("the bag item's tile exists", falchion_tile != null)
	if falchion_tile != null:
		await _inventory_mouse_click(falchion_tile, MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	var old_is_in_bag: bool = town.player.stats.bag.any(func(it: Dictionary) -> bool: return Items.to_save(it) == old_saved)
	expect("equipping from bag swaps old gear into bag", town.player.stats.equipment[Items.Slot.WEAPON]["name"].contains("Falchion") and old_is_in_bag)
	view_hud._input(toggle)
	expect("Tab toggles closed and resumes gameplay", not view_hud.show_gear and not get_tree().paused)
	town.queue_free()
	await get_tree().process_frame

## Owner playtest feedback 1: a checkbox keeps one padding in every state, the minimap shows no enemy count, ground drops carry no beam
## or ring, and picking gear up is silent.
func _test_owner_feedback_1() -> void:
	TownState.persist = false
	await get_tree().process_frame
	# Retries must wait for fair service, never bypass the per-tick cap.
	var nav_state: Dictionary = {}
	var fresh_goal: Vector3 = Nav.snap(player, player.global_position + Vector3(8.0, 0.0, 0.0))
	for i in 12:
		Nav.route(player, fresh_goal, nav_state, 0.016)
		await get_tree().physics_frame
	expect("queued routing serves an actor without exceeding the tick budget", nav_state.has("queries") and Nav.queries_peak <= Nav.QUERIES_PER_TICK)
	# 1: checkbox states share their padding (otherwise the label jumps onto the tick under the mouse)
	var theme: Theme = UiTheme.get_theme()
	var reference: Vector4 = Vector4.ZERO
	var same: bool = true
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box: StyleBox = theme.get_stylebox(state, "CheckBox")
		var margins := Vector4(box.get_content_margin(SIDE_LEFT), box.get_content_margin(SIDE_TOP), box.get_content_margin(SIDE_RIGHT), box.get_content_margin(SIDE_BOTTOM))
		if state == "normal":
			reference = margins
		elif margins != reference:
			same = false
	expect("a checkbox has the same padding in every state", same and reference.x > 0.0)
	# 2: the minimap source no longer prints a count
	var source: String = FileAccess.get_file_as_string("res://game/hud.gd")
	expect("the minimap does not print how many enemies are left", not source.contains("\"%d left\""))
	# 5: a rare drop has no light, column or floor ring
	var rare: LootDrop = LootDrop.create(Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "Falchion"))
	add_child(rare)
	await get_tree().process_frame
	expect("a rare drop has no beam, ring or light", rare._column == null and rare._pool == null and rare._light == null)
	rare.queue_free()
	# 4: picking gear up says nothing on the HUD line
	var stats: PlayerStats = player.stats
	player.message_time = 0.0
	player.message = ""
	var drop_item: Dictionary = Items.make(Items.Slot.AMULET, Items.Rarity.NORMAL, 1, "Charm")
	var text: String = stats.pickup(drop_item)
	expect("picking an item up still reports what happened to callers", text.contains("Charm"))
	expect("but the HUD message line says nothing", player.message_time <= 0.0 and player.message == "")
	# 12: stamina is off as a resource (no drain, no slowdown, no dodge cost or gate)
	expect("stamina is switched off", not PlayerStats.STAMINA_ON)
	player.stats.stamina = 0.0
	player.combat_timer = 5.0
	var free_speed: float = player.stats.run_speed
	expect("an 'exhausted' hero in a fight is not slowed", is_equal_approx(player.movement._travel_speed(1.0), free_speed))
	player.stats.stamina = 60.0
	player.movement._travel_speed(1.0)
	expect("moving in a fight spends nothing", is_equal_approx(player.stats.stamina, 60.0))
	player.stats.stamina = 0.0
	player.stats.cooldowns["dodge"] = 0.0
	player.skills.cancel_action()
	player.movement.rolling = false
	player.movement.try_roll(player.global_position + Vector3(0, 0, 4))
	expect("the dodge works at zero stamina and charges none", player.movement.rolling and is_equal_approx(player.stats.stamina, 0.0))
	player.movement.rolling = false
	# the "New ability learned" plate and the zone name
	hud.ability_toast_time = 0.0
	hud.show_ability_toast("nonsense")
	expect("an unknown skill id shows no ability plate", hud.ability_toast_time <= 0.0)
	hud.show_ability_toast("fireball")
	expect("a known skill shows the ability plate for a few seconds", hud.ability_toast_id == "fireball" and hud.ability_toast_time > 3.0)
	hud.ability_toast_time = 0.0
	expect("the HUD names the place the hero stands in", hud.zone_name() != "" and hud.zone_subtitle() != "")

## Owner playtest feedback 9: the minimap draws the map (ground, solid props) with a fog of war that the hero's walking uncovers; live things
## obey the same fog.
func _test_minimap_fog() -> void:
	await get_tree().process_frame
	expect("the minimap has no fog of war by default (the owner asked for none)", not MinimapMap.fog_on)
	var plain := MinimapMap.new()
	plain.ensure_built(get_tree())
	expect("without fog everything counts as seen", plain.is_explored(player.global_position + Vector3(500, 0, 500)))
	MinimapMap.fog_on = true   # the rest exercises the fog machinery, which stays behind the switch
	var test_prop: Dictionary = {"position": player.global_position + Vector3(6, 0, 6), "radius": 2.0}
	arena.obstacles.append(test_prop)   # (a known solid, whatever the test arena happens to hold)
	var map := MinimapMap.new()
	map.ensure_built(get_tree())
	expect("the map is built from the arena in the scene", map.terrain != null and map.cols > 0 and map.rows > 0 and map.ground_cells > 1000)
	var here: Vector3 = player.global_position
	expect("before the hero has looked anywhere nothing is explored", map.revealed_cells == 0 and not map.is_explored(here))
	map.reveal(here, true)
	expect("the ground where the hero stands is uncovered", map.is_explored(here) and map.revealed_cells > 100)
	var far: Vector3 = here + Vector3(MinimapMap.REVEAL + 8.0, 0, 0)
	expect("the ground beyond his sight stays dark", not map.is_explored(far))
	var near_count: int = map.revealed_cells
	map.reveal(here + Vector3(0.3, 0, 0))
	expect("standing about the same place uncovers nothing more (and costs nothing)", map.revealed_cells == near_count)
	map.reveal(here + Vector3(20.0, 0, 0))
	expect("walking on uncovers more, and it stays uncovered behind him", map.revealed_cells > near_count and map.is_explored(here) and map.is_explored(far))
	var spread: float = float(map.revealed_cells) / float(map.ground_cells)
	expect("the fog only ever covers part of the world after a short walk (%.0f%% seen)" % [spread * 100.0], spread > 0.0 and spread < 1.0)
	var rebuilt: int = map.revealed_cells
	map.ensure_built(get_tree())
	expect("asking for the same map again keeps what was seen", map.revealed_cells == rebuilt)
	map.forget()
	expect("forgetting puts the fog back", map.revealed_cells == 0 and not map.is_explored(here))
	# The terrain: ground inside, nothing outside the world, solids marked
	expect("a point outside every arena is not ground", map.terrain.get_pixel(0, 0).a == 0.0 or not Rect2(map.origin, Vector2(map.cols, map.rows) * MinimapMap.CELL).has_point(Vector2(-9999, -9999)))
	var solids: int = 0
	for y in map.rows:
		for x in map.cols:
			solids += 1 if map.kinds[y * map.cols + x] == MinimapMap.K_SOLID else 0
	expect("a prop is on the map as a solid disc (%d cells)" % solids, solids >= 8)
	arena.obstacles.erase(test_prop)
	# Live things obey the fog: a monster beyond sight is not shown, a near one is
	var close: Enemy = _spawn_enemy(here + Vector3(8, 0, 0))
	var distant: Enemy = _spawn_enemy(here + Vector3(0, 0, 36))
	expect("a monster inside sight is on the map", hud.enemy_in_sight(close))
	expect("a monster beyond sight is not", not hud.enemy_in_sight(distant))
	close.queue_free()
	distant.queue_free()
	MinimapMap.fog_on = false

func _test_orb_hud() -> void:
	await get_tree().process_frame
	hud._process(0.0)
	var screen: Vector2 = get_viewport().get_visible_rect().size
	expect("health and mana have opposite bottom vessels", hud.health_orb.position.x < screen.x * 0.5 and hud.mana_orb.position.x > screen.x * 0.5 and hud.health_orb.position.y > screen.y * 0.5)
	expect("both orb vessels block world clicks", hud.covers(Hud.orb_rect(screen, false).get_center()) and hud.covers(Hud.orb_rect(screen, true).get_center()))
	expect("map is above mana and blocks world clicks", Hud.minimap_rect(screen).end.y < Hud.orb_rect(screen, true).position.y and hud.covers(Hud.minimap_rect(screen).get_center()))
	var orb: Control = hud.health_orb
	orb.update_value(30, 120, 0.25, Vector3(5, 0, 0))
	expect("health level follows the resource fraction", is_equal_approx(orb.level, 0.25) and orb.numbers.text == "30 / 120")
	expect("damage and movement disturb the liquid", float(orb.fluid.get_shader_parameter("slosh")) > 0 and float(orb.fluid.get_shader_parameter("lean")) > 0)
	orb.update_value(0, 120, 1, Vector3.ZERO)
	expect("an empty resource drains completely", is_zero_approx(orb.displayed) and is_zero_approx(float(orb.fluid.get_shader_parameter("fill_level"))))
	orb.update_value(120, 120, 1, Vector3.ZERO)
	expect("restoring health refills the vessel", is_equal_approx(orb.displayed, 1))
	orb.update_value(0, 0, 1, Vector3.ZERO)
	expect("zero capacity stays finite and empty", is_finite(orb.level) and is_zero_approx(orb.level))
	var started: float = orb.clock
	orb.update_value(120, 120, 0.1, Vector3.ZERO)
	expect("the Blender fluid loop advances", orb.clock > started)
	for width in [960.0, 1280.0, 1920.0]:
		var view := Vector2(width, 720)
		var cell: float = hud.hotbar_slot_size(view)
		var count: int = player.skills.hotbar.size() + 2
		var tray_width: float = cell * count + 8 * (count - 1)
		expect("skill tray clears both vessels at %d px" % width, (width - tray_width) * 0.5 - 24 >= Hud.orb_rect(view, false).end.x)
	var first_target := Actor.new()
	first_target.display_name = "Feedback Target"
	first_target.max_health = 100.0
	first_target.health = first_target.max_health
	var second_target := Actor.new()
	second_target.display_name = "Second Feedback Target"
	second_target.max_health = 60.0
	second_target.health = second_target.max_health
	var target_banner := hud.ds2_target_banner as Ds2TargetBanner
	target_banner.update_target(first_target, 0.0)
	var full_health_width: float = target_banner._hp_fill.size.x
	first_target.health = first_target.max_health * 0.6
	target_banner.update_target(first_target, 0.016)
	expect("target health falls immediately when damaged", is_equal_approx(target_banner._hp_fill.size.x, first_target.max_health * 0.6 / first_target.max_health * Ds2TargetBanner.BAR_WIDTH))
	expect("damage leaves a short trail at the previous health", is_equal_approx(target_banner._damage_trail.size.x, full_health_width) and target_banner._trail_hold > 0.0)
	expect("target damage gives a brief restrained hit flash", target_banner._hit_flash > 0.0 and target_banner._hit_flash <= Ds2TargetBanner.HIT_FLASH_SECONDS)
	first_target.health = first_target.max_health * 0.8
	target_banner.update_target(first_target, 0.016)
	expect("health regeneration catches the trail up immediately", is_equal_approx(target_banner._damage_trail.size.x, target_banner._hp_fill.size.x) and is_zero_approx(target_banner._trail_hold))
	target_banner.update_target(second_target, 0.0)
	expect("target switching resets the trail and flash", is_equal_approx(target_banner._damage_trail.size.x, target_banner._hp_fill.size.x) and is_zero_approx(target_banner._hit_flash))
	first_target.dead = true
	target_banner.update_target(first_target, 0.0)
	expect("target death clears the health bar and delayed trail", is_zero_approx(target_banner._hp_fill.size.x) and is_zero_approx(target_banner._damage_trail.size.x) and is_zero_approx(target_banner._hit_flash))
	first_target.dead = false
	target_banner.update_target(null, 0.1)
	expect("target disappearance clears stale target text and trail", target_banner._name_label.text.is_empty() and is_zero_approx(target_banner._damage_trail.size.x))
	expect("target banner and bar layers pass world clicks through", target_banner.mouse_filter == Control.MOUSE_FILTER_IGNORE and target_banner._damage_trail.mouse_filter == Control.MOUSE_FILTER_IGNORE and target_banner._hp_fill.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	first_target.free()
	second_target.free()

func _test_inventory_equip() -> void:
	TownState.persist = false
	player.stats.bag.clear()
	var item: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 1, "Falchion")
	var old: Dictionary = player.stats.equipment[Items.Slot.WEAPON]
	player.stats.bag.append(item)
	hud.show_gear = true
	hud._open_character()
	await get_tree().create_timer(0.2).timeout
	var buttons: Array[Node] = hud.character_panel.find_children("*", "Button", true, false)
	var equip: Button = null
	for button in buttons:
		if button.text == "Equip":
			equip = button
			break
	expect("bag items carry no Equip button (the card says how: R-click)", equip == null)
	var item_tile: Control = _inventory_item_control(hud, item, false)
	expect("the bag item has a tile", item_tile != null)
	if item_tile != null:
		# The hover card for a bag item ends with the hint.
		var hint_card: Control = ItemTile.card(item, old, true, true)
		var hint_texts: Array[String] = []
		for label in hint_card.find_children("*", "Label", true, false):
			hint_texts.append((label as Label).text)
		hint_card.free()
		expect("a bag item's card ends with (R-click to equip)", hint_texts.has("(R-click to equip)") or hint_texts.has("(Confirm to equip)"))
		expect("a ground or trader card has no such hint", not ItemTile.card(item, old, true).find_children("*", "Label", true, false).any(func(l: Node) -> bool: return (l as Label).text.contains("to equip")))
		await _inventory_mouse_click(item_tile, MOUSE_BUTTON_RIGHT)
		expect("a right-click equips the bag item", Items.to_save(player.stats.equipment[Items.Slot.WEAPON]) == Items.to_save(item))
		expect("equipping puts old gear in bag", _bag_has_item(old) and not _bag_has_item(item))
	# Right-click the icon to swap back; names also support a double-click.
	var tile: Control = _inventory_item_control(hud, old, false)
	expect("old weapon is available in bag", tile != null)
	if tile != null:
		await _inventory_mouse_click(tile, MOUSE_BUTTON_RIGHT)
		expect("right-clicking the icon equips", Items.to_save(player.stats.equipment[Items.Slot.WEAPON]) == Items.to_save(old) and _bag_has_item(item))
	var armor: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.RARE, 1, "Plate Cuirass")
	player.stats.bag.append(armor)
	hud._open_character()
	await get_tree().create_timer(0.1).timeout
	var item_name: Control = _inventory_item_control(hud, armor, false)
	if item_name != null:
		await _inventory_mouse_click(item_name, MOUSE_BUTTON_LEFT, true)
		expect("double-clicking a sized icon equips armor and updates defenses", Items.to_save(player.stats.equipment[Items.Slot.ARMOR]) == Items.to_save(armor) and is_equal_approx(player.armor, player.stats.total_armor()))
	else:
		expect("bag armor has a clickable sized icon", false)
	var ring: Dictionary = Items.make(Items.Slot.RING, Items.Rarity.NORMAL, 1, "Charm")
	player.stats.bag.append(ring)
	hud._open_character()
	await get_tree().create_timer(0.1).timeout
	tile = _inventory_item_control(hud, ring, false)
	if tile != null:
		tile.grab_focus()
		var accept := InputEventJoypadButton.new()
		accept.button_index = JOY_BUTTON_A
		accept.pressed = true
		get_viewport().push_input(accept, true)
		await get_tree().process_frame
		accept = accept.duplicate()
		accept.pressed = false
		get_viewport().push_input(accept, true)
		await get_tree().process_frame
		expect("controller confirmation equips focused icon into empty slot", Items.to_save(player.stats.equipment.get(Items.Slot.RING, {})) == Items.to_save(ring) and not _bag_has_item(ring))
		expect("controller focus stays on remaining bag items", get_viewport().gui_get_focus_owner() is ItemTile)
	else:
		expect("bag trinket is focusable", false)
	expect("equipment changes keep inventory open and gameplay paused", hud.show_gear and get_tree().paused)
	hud.close_character()
	await get_tree().process_frame

func _bag_has_item(item: Dictionary) -> bool:
	return player.stats.bag.any(func(it: Dictionary) -> bool: return Items.to_save(it) == Items.to_save(item))

func _inventory_item_control(view_hud: Hud, item: Dictionary, name_only: bool) -> Control:
	for control in view_hud.character_panel.find_children("*", "Control", true, false):
		if name_only and control.get_script() == preload("res://game/item_name.gd") and control.item == item:
			return control
		if not name_only and control is ItemTile and Items.to_save(control.item) == Items.to_save(item):
			return control
	return null

func _inventory_mouse_click(control: Control, button: int, double: bool = false) -> void:
	var pointer: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	get_viewport().push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = button as MouseButton
	click.position = pointer
	click.pressed = true
	click.double_click = double
	get_viewport().push_input(click, true)
	await get_tree().process_frame
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click, true)
	await get_tree().process_frame
