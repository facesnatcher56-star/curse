extends DevSuite
## Actual town HUD/window regression coverage. Never loads or writes production saves.
const SkillView := preload("res://game/ui/skill_tree_view.gd")

func _settle() -> void:
	for i in 5: await get_tree().process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join("curse_audit_" + name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("UI_AUDIT_CAPTURE ", path)

func _test_ui_audit() -> void:
	TownState.persist = false
	TownState.reset()
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	await _settle()
	var town := TownScene.new()
	town.with_road = false
	game.add_child(town)
	hud.hide()
	await _settle()
	var ui := town.combat_hud
	ui.ds2_potion_dock.find_child("utility_inventory", true, false).pressed.emit()
	await _settle()
	expect("inventory owns modal state and stays inside gameplay viewport", ui.show_gear
		and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(ui.character_panel.get_global_rect()))
	expect("town overlays leave inventory unobstructed", town.hud.modal_open() and town.hud.overlay_rects.is_empty())
	await _capture("inventory_empty")
	town.player.stats.add_to_bag(Items.build(ItemDb.get_def("greatsword"), 1, Items.Rarity.NORMAL))
	ui._open_character()
	await _settle()
	var grid: Control = ui.character_panel.find_child("BackpackGrid", true, false)
	expect("all backpack rows are visible", grid.get_global_rect().end.y <= ui.character_panel.get_global_rect().end.y)
	grid.tiles[0].grab_focus()
	var select := InputEventAction.new()
	select.action = "ui_select"
	select.pressed = true
	grid.handle_input(select, 0)
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	get_viewport().push_input(cancel, true)
	await _settle()
	expect("cancel restores a moving item without closing inventory", ui.show_gear and grid.moving == -1)
	await _capture("inventory_populated")
	var motion := InputEventMouseMotion.new()
	for button in ui.character_panel.find_children("*", "Button", true, false):
		if button.text != "Close": continue
		motion.position = button.get_global_rect().get_center()
		get_viewport().push_input(motion, true)
		await _settle()
		expect("inventory close button is actually hovered", button.is_hovered())
		await _capture("button_hover")
		break
	var rotate := InputEventAction.new()
	rotate.action = "inventory_rotate"
	rotate.pressed = true
	get_viewport().push_input(rotate, true)
	await _settle()
	expect("rotation works in the actual town inventory", grid.tiles[0].size.x > grid.tiles[0].size.y * 3)
	await _capture("inventory_rotated")
	ui.open_skills()
	await _settle()
	var view: Control = ui.character_panel
	var red := "[color=#" + SkillView.UNMET_COLOR.to_html(false) + "]"
	var green := "[color=#" + SkillView.MET_COLOR.to_html(false) + "]"
	for tree in view.TREES:
		view._switch_tree(tree)
		await _settle()
		for def in PassiveDb.of_tree(tree):
			var button: Button = view.find_child(def.id + "_plus", true, false)
			button.grab_focus()
			await _settle()
			var text: String = view._detail_label.text
			expect("unmet class requirement is red for " + def.id, text.contains(red + HeroAttributes.CLASS_NAMES[tree] + " " + str(def.class_level)))
			expect("unlearned skill does not claim a current effect: " + def.id, not text.contains("Current:"))
			var before: Dictionary = view.staged.duplicate()
			button.pressed.emit()
			await _settle()
			expect("locked skill cannot stage a purchase: " + def.id, view.staged == before)
		await _capture("locked_" + tree)
	TownState.dev_set_hero_level(30)
	view._switch_tree("melee")
	await _settle()
	var barricade: Button = view.find_child("barricade_plus", true, false)
	barricade.grab_focus()
	await _settle()
	expect("met class and missing prerequisite are shown together", view._detail_label.text.contains(green + "Melee 5")
		and view._detail_label.text.contains(red + "Fortitude 1"))
	await _capture("passive_requirements")
	view.find_child("fortitude_plus", true, false).pressed.emit()
	await _settle()
	view.find_child("barricade_plus", true, false).grab_focus()
	await _settle()
	expect("staged prerequisites turn green without pretending learned", view._detail_label.text.contains(green + "Fortitude 1")
		and TownState.passive_rank("fortitude") == 0)
	view.find_child("confirm", true, false).pressed.emit()
	await _settle()
	expect("confirm commits only affordable unlocked ranks", TownState.passive_rank("fortitude") == 1)
	TownState.passive_ranks["fortitude"] = PassiveDef.MAX_RANK
	view._inspect("fortitude", false, view.find_child("fortitude_plus", true, false))
	expect("capped skills have no fictitious next rank", view._detail_label.text.contains("Maximum rank") and not view._detail_label.text.contains("Next:"))
	TownState.passive_ranks = {}
	TownState.dev_set_hero_level(1)
	view.staged = {"fortitude": 2}
	view._inspect("critical_strike", false, view.find_child("critical_strike_plus", true, false))
	expect("no points is red as well", view._detail_label.text.contains(red + "Skill points 1  (you have 0)"))
	ui.close_character()
	await _settle()
	expect("closing restores town overlays", not town.hud.modal_open() and not town.hud.overlay_rects.is_empty())
	ui.ds2_potion_dock.find_child("utility_journal", true, false).pressed.emit()
	await _settle()
	expect("journal utility opens the real chronicle", town.panel.visible and town.panel.current == "chronicle")
	town.panel.close()
	await _settle()
	# Opening town services must replace any character modal, not stack two windows.
	for page in ["stash", "board", "chronicle", "marlow"]:
		ui._open_character()
		await _settle()
		match page:
			"stash": town.panel.open_stash()
			"board": town.panel.open_board()
			"chronicle": town.panel.open_chronicle()
			_: town.panel.open_npc(page)
		await _settle()
		expect("town page replaces character window: " + page, not ui.show_gear and ui.character_panel == null and town.panel.visible)
		await _capture(page)
		town.panel.close()
		await _settle()
	var forbidden: Dictionary = Items.build(ItemDb.get_def("greatsword"), 1, Items.Rarity.NORMAL)
	expect("ground and menu cards share requirement coloring", ItemTile.stat_line_color(forbidden, Items.requirement_text(forbidden)).is_equal_approx(SkillView.UNMET_COLOR))
	var card := ItemTile.card(forbidden, null, false)
	var has_red := false
	for label in card.find_children("*", "Label", true, false):
		if label.text.contains("Requires "):
			has_red = label.get_theme_color("font_color").is_equal_approx(SkillView.UNMET_COLOR)
	expect("item requirements stay red even when comparison is disabled", has_red)
	card.free()
	var damage_text := town.player.stats.skill_damage_text("take_aim")
	for i in 20:
		expect("Take Aim tooltip never rolls random damage", town.player.stats.skill_damage_text("take_aim") == damage_text)
	town.pause_menu.open()
	await _settle()
	expect("pause menu takes controller focus", town.pause_menu.is_ancestor_of(get_viewport().gui_get_focus_owner()))
	await _capture("pause")
	town.pause_menu._open_settings()
	await _settle()
	var settings := town.pause_menu._settings
	for tab in 4:
		settings.select_tab(tab)
		settings.focus_first()
		await _settle()
		expect("settings tab stays inside viewport: " + str(tab), get_viewport().get_visible_rect().encloses(settings.get_global_rect()))
		expect("settings tab has controller focus: " + str(tab), settings.is_ancestor_of(get_viewport().gui_get_focus_owner()))
		await _capture("settings_" + str(tab))
	town.pause_menu.close()
	get_tree().paused = false
	town.queue_free()
	await _settle()
	hud.show()
	TownState.reset()
