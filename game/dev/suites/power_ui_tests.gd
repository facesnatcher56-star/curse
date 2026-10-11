extends DevSuite
## UI-only regression and reproducible second-monitor screenshots; never saves.
const Visual := preload("res://game/ui/power_button_visual.gd")

func _settle() -> void:
	for i in 4: await get_tree().process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join("curse_ui_" + name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("UI_CAPTURE ", path)

func _test_power_ui() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.dev_set_hero_level(40)
	await _settle()
	expect("spent, partial, ready, armed and unavailable states are distinct",
		Visual.state(0, false) == "charging" and Visual.state(0.5, false) == "charging"
		and Visual.state(1, false) == "ready" and Visual.state(1, true) == "armed" and Visual.state(1, false, false) == "locked")
	hud.open_skills()
	await _settle()
	var view: Control = hud.character_panel
	var chart: Control = view.find_child("SkillChart", true, false)
	expect("one icon tree is shown, not three text columns", chart.points.size() == PassiveDb.of_tree("melee").size()
		and view.find_child("SpecializationTabs", true, false).get_child_count() == 3)
	expect("every prerequisite is represented by a chart path", chart.links.size() == 10)
	var node := chart.get_node("fortitude_plus") as Button
	expect("nodes have artwork and are controller focusable", node.icon != null and node.focus_mode == Control.FOCUS_ALL)
	node.grab_focus()
	await _settle()
	expect("controller focus reveals only the selected node's details", view._detail.visible and view._detail_label.text.contains("Fortitude"))
	var below := node.find_valid_focus_neighbor(SIDE_BOTTOM)
	expect("directional controller navigation reaches another chart node", below != null and chart.is_ancestor_of(below))
	await _capture("skill_detail")
	var power_def: PowerDef = null
	for def in PowerDb.of_tree("melee"):
		if def.id != "take_aim" and not def.ranks.is_empty() and def.rank_for(view._ranks()) == 0 and chart.points.has(String(def.ranks[0].keys()[0])):
			power_def = def
			break
	var power_button := view.find_child("power_" + power_def.id, true, false) as Button
	power_button.mouse_entered.emit()
	await _settle()
	var needed: String = String(power_def.ranks[0].keys()[0])
	expect("a hovered power lists Requirements, red while unmet, and pulses the passives it needs on the chart",
		view._detail_label.text.contains("Requirements") and view._detail_label.text.contains("[color=#" + view.UNMET_COLOR.to_html(false) + "]")
		and not view._detail_label.text.contains("Next rank") and chart._pulse.has(needed) and chart._pulse[needed] == false)
	await _capture("power_requirements")
	power_button.mouse_exited.emit()
	expect("leaving the power stops the pulse", chart._pulse.is_empty())
	node.pressed.emit()
	await _settle()
	expect("selecting a node stages a rank without buying it", int(view.staged.get("fortitude", 0)) == 1 and TownState.passive_rank("fortitude") == 0)
	view.find_child("tab_ranged", true, false).pressed.emit()
	await _settle()
	chart = view.find_child("SkillChart", true, false)
	expect("tabs replace the chart and preserve staged points", chart.tree == "ranged" and chart.points.has("critical_shot")
		and not chart.points.has("fortitude") and int(view.staged.get("fortitude", 0)) == 1)
	await _capture("ranged")
	view.find_child("tab_combat", true, false).pressed.emit()
	await _settle()
	expect("combat tab has its own diagram", view.find_child("SkillChart", true, false).points.has("devastation"))
	await _capture("combat")
	view.find_child("tab_melee", true, false).pressed.emit()
	await _settle()
	view.find_child("fortitude_minus", true, false).pressed.emit()
	await _settle()
	expect("minus removes only staged ranks", view.staged.is_empty())
	view.find_child("critical_strike_plus", true, false).pressed.emit()
	await _settle()
	view.find_child("confirm", true, false).pressed.emit()
	await _settle()
	expect("confirm commits the chosen rank", TownState.passive_rank("critical_strike") == 1 and view.staged.is_empty())
	view._hide_detail()
	await _settle()
	await _capture("melee")
	hud.close_character()
	await _settle()
	# Exercise the real HUD draw callbacks at fractional charge (previously an invalid cross-node draw).
	player.stats.brutal_reload_required = player.stats.ult_cost("brutal_attack")
	for charge in [0.0, 0.5, 1.0]:
		player.stats.brutal_reload_remaining = player.stats.ult_cost("brutal_attack") * (1.0 - charge)
		await _settle()
		expect("portrait mirrors actual recharge", is_equal_approx(hud.ds2_party_frame.hero_card._power_charge, charge))
		await _capture("power_" + str(int(charge * 100)))
	player.skills.brutal_armed = true
	expect("armed visual reads the real hero controller", Visual.armed(player, "brutal_attack"))
	await _settle()
	expect("portrait mirrors the real armed state", hud.ds2_party_frame.hero_card._power_armed)
	await _capture("power_armed")
	player.skills.brutal_armed = false
	var cutter := player.stats._cutter()
	if cutter != null:
		cutter.take_aim_armed = true
		await _settle()
		expect("Take Aim reads Cutter's actual armed state in both HUD locations", Visual.armed(player, "take_aim")
			and hud.ds2_party_frame.companion_card._power_armed)
		cutter.take_aim_armed = false
		cutter.take_aim_reload_required = 200
		cutter.take_aim_reload_remaining = 100
		await _settle()
		expect("Take Aim portrait and hotbar share the same recharge source", is_equal_approx(player.stats.ult_fraction("take_aim"), 0.5)
			and is_equal_approx(hud.ds2_party_frame.companion_card._power_charge, 0.5))
		await _capture("take_aim_half")
	TownState.reset()
