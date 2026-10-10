extends SceneTree
## Developer check of the HUD's progression feedback (ProgressionHud): ordinary XP, one level, several levels in one award, the point text of
## every milestone kind, the points-available mark and its clearing after a spend, the max-level strip, scene re-entry (no duplicate event
## connection), and the progression panel still opening and closing. With --progshots=DIR it also saves screenshots at the game viewport.
## Run with a real window for screenshots (Forward+):
##   GODOT_HEADLESS= tools/run_godot.sh LOG 120 -- --script res://tools/progression_hud_check.gd -- --progshots=DIR
## User arguments make it a developer session: the production save is never touched (SavePolicy keeps it in memory).

var out_dir: String = ""
var failures: int = 0
var main: Node

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--progshots="):
			out_dir = arg.substr(12)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func expect(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _enter() -> Hud:
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 4:
		await process_frame
	return main.hud

func _leave() -> void:
	main.queue_free()
	await process_frame
	await process_frame

func _shot(shot_name: String) -> void:
	if out_dir == "":
		return
	await process_frame
	await process_frame
	var image: Image = root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [out_dir, shot_name])
	print("shot %s %s" % [shot_name, image.get_size()])

## Spends every point there is, through the same doors the panel uses.
func _spend_all() -> void:
	var bought: bool = true
	while bought:
		bought = false
		for id in BuildDefs.PASSIVE_ORDER:
			if TownState.can_buy_passive(id):
				bought = TownState.buy_passive(id)
				break
	bought = true
	while bought:
		bought = false
		for skill in BuildDefs.EVOLUTION_SKILLS:
			for evolution in BuildDefs.SKILLS[skill]["order"]:
				if TownState.can_select_evolution(skill, evolution):
					bought = TownState.select_evolution(skill, evolution)
					break

func _run() -> void:
	TownState.reset()
	var connections_before: int = TownState.events.hero_leveled.get_connections().size()
	var hud: Hud = await _enter()
	var ph: ProgressionHud = hud.progression_hud
	expect("the HUD has a progression strip at level 1", ph != null and ProgressionHud.level_text() == "LV 1" and ProgressionHud.xp_text() == "0 / 100")
	expect("a fresh hero shows no points waiting", ProgressionHud.points_available_text() == "")

	# Ordinary XP: progress moves, no plate.
	TownState.add_hero_xp(40, false)
	expect("ordinary XP updates the strip without a level plate", ProgressionHud.xp_text() == "40 / 100" and hud.level_toast_time == 0.0 and ph.toast_count == 0)
	await _shot("1_normal_xp")

	# One level: LEVEL 2, passive only.
	TownState.add_hero_xp(70)
	expect("one level: one plate, LEVEL 2, +1 Passive Point", hud.level_toast_text == "LEVEL 2" and hud.level_toast_points == "+1 Passive Point" and ph.toast_count == 1)
	expect("passive-only milestone text", HeroProgression.points_text(1, 0) == "+1 Passive Point")
	expect("evolution-only milestone text", HeroProgression.points_text(0, 1) == "+1 Evolution Point")
	expect("both-point milestone text", HeroProgression.points_text(1, 1) == "+1 Passive Point   +1 Evolution Point")
	expect("no-point milestone text is empty", HeroProgression.points_text(0, 0) == "")
	expect("points waiting are shown", ProgressionHud.points_available_text() == "1 Passive point available")
	await _shot("2_level2_points")
	ph.toast_time = 0.0

	# Real milestones through the real door. Level 2 -> 3: evolution only. 4 -> 5: nothing. 5 -> 6: both.
	TownState.add_hero_xp(HeroProgression.xp_for_level(3) - TownState.hero_xp)
	expect("evolution-only level (3)", hud.level_toast_text == "LEVEL 3" and hud.level_toast_points == "+1 Evolution Point")
	ph.toast_time = 0.0
	TownState.add_hero_xp(HeroProgression.xp_for_level(4) - TownState.hero_xp)
	ph.toast_time = 0.0
	TownState.add_hero_xp(HeroProgression.xp_for_level(5) - TownState.hero_xp)
	expect("a level with no points (5): LEVEL 5 and no point line", hud.level_toast_text == "LEVEL 5" and hud.level_toast_points == "")
	ph.toast_time = 0.0
	TownState.add_hero_xp(HeroProgression.xp_for_level(6) - TownState.hero_xp)
	expect("a level with both (6)", hud.level_toast_text == "LEVEL 6" and hud.level_toast_points == "+1 Passive Point   +1 Evolution Point")
	ph.toast_time = 0.0

	# A multi-level award is one plate with the totals (6 -> 12: passive 3 -> 6 = +3, evolution 2 -> 4 = +2).
	var count_before: int = ph.toast_count
	TownState.add_hero_xp(HeroProgression.xp_for_level(12) - TownState.hero_xp)
	expect("a multi-level award is one plate", ph.toast_count == count_before + 1 and hud.level_toast_text == "LEVEL 12" and ph.toast_levels == 6)
	expect("it carries the total points of every level crossed", hud.level_toast_points == "+3 Passive Points   +2 Evolution Points")
	await _shot("3_multilevel_plate")

	# An award landing while the plate is still up is folded in, not stacked (12 -> 15: passive 6 -> 7, evolution 4 -> 5).
	TownState.add_hero_xp(HeroProgression.xp_for_level(15) - TownState.hero_xp)
	expect("a second award on the live plate folds in", ph.toast_levels == 9 and hud.level_toast_text == "LEVEL 15" and hud.level_toast_points == "+4 Passive Points   +3 Evolution Points")
	ph.toast_time = 0.0

	# Points clear after a legal spend.
	var waiting_before: int = TownState.passive_points_available()
	expect("passive points are waiting before the spend", waiting_before > 0 and ProgressionHud.points_available_text().contains("Passive"))
	var spent: bool = false
	for id in BuildDefs.PASSIVE_ORDER:
		if TownState.can_buy_passive(id):
			spent = TownState.buy_passive(id)
			break
	expect("a legal spend lowers the waiting count", spent and TownState.passive_points_available() == waiting_before - 1)
	_spend_all()
	expect("the mark clears once everything buyable is bought (the rest has nothing to buy)", ProgressionHud.points_waiting()["passive"] == 0 and ProgressionHud.points_waiting()["evolution"] == 0 and ProgressionHud.points_available_text() == "")
	await _shot("6_spent_no_mark")

	# Max level.
	TownState.dev_set_hero_level(HeroProgression.MAX_LEVEL)
	ph.toast_time = 0.0
	await process_frame
	expect("max level reads LV 30 / MAX", ProgressionHud.level_text() == "LV 30" and ProgressionHud.xp_text() == "MAX")
	var count_max: int = ph.toast_count
	TownState.add_hero_xp(500)
	expect("XP past the cap changes nothing and raises no plate", ProgressionHud.xp_text() == "MAX" and ph.toast_count == count_max and ph.toast_time == 0.0)
	await _shot("4_max_level")

	# The progression panel still opens, closes and takes focus.
	TownState.dev_set_hero_level(6)
	hud.show_gear = true
	hud._open_character()
	await process_frame
	hud.open_progression()
	await process_frame
	await process_frame
	expect("the panel opens over the HUD", hud.progression_panel != null and hud.progression_panel.is_inside_tree())
	await _shot("5_panel_open")
	hud.close_progression()
	await process_frame
	expect("the panel closes", hud.progression_panel == null)

	# Re-entry: no duplicate connection or plate.
	await _leave()
	expect("leaving the scene drops its event connections", TownState.events.hero_leveled.get_connections().size() == connections_before)
	var hud2: Hud = await _enter()
	expect("re-entering connects exactly once", TownState.events.hero_leveled.get_connections().size() == connections_before + 1)
	TownState.dev_set_hero_level(2)
	hud2.progression_hud.toast_count = 0
	TownState.add_hero_xp(HeroProgression.xp_for_level(3) - TownState.hero_xp)
	expect("one award after re-entry is one plate", hud2.progression_hud.toast_count == 1)
	await _leave()

	print("progression_hud_check: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
