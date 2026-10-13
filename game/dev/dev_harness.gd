class_name DevHarness
extends DevSuite
## Developer tooling kept out of the game proper: the headless `--selftest` suite and the screenshot / pose tools.
## Main creates one of these and calls run_from_args(); when a dev flag is present it takes over the run.
##   --selftest [--only=NAME]   run the checks (CI runs this headless)
##   --skillshot=NAME, --aimshot, --hudshot, --hovershot, --rollshot, --poses, --clipsheet=, --shot
## This file only dispatches: the checks live in game/dev/suites/ (one file per area of the game), the screenshot tools in
## shots.gd and the measurements in perf.gd. They all extend DevSuite and talk to the running game through `game` (Main).

## Every file a check or tool may live in; a check or tool name is unique across them.
const SUITES := [
	preload("res://game/dev/suites/find_tests.gd"),
	preload("res://game/dev/suites/equipment_effect_tests.gd"),
	preload("res://game/dev/suites/equipment_hit_tests.gd"),
	preload("res://game/dev/suites/ranged_modifier_tests.gd"),
	preload("res://game/dev/suites/element_tests.gd"),
	preload("res://game/dev/suites/theme_tests.gd"),
	preload("res://game/dev/suites/ui_audit_tests.gd"),
	preload("res://game/dev/suites/inventory_tests.gd"),
	preload("res://game/dev/suites/power_ui_tests.gd"),
	preload("res://game/dev/suites/power_audio_tests.gd"),
	preload("res://game/dev/suites/combat_detail_tests.gd"),
	preload("res://game/dev/shots.gd"), preload("res://game/dev/perf.gd"),
	preload("res://game/dev/suites/skill_tests.gd"),
	preload("res://game/dev/suites/fireball_tests.gd"),
	preload("res://game/dev/suites/melee_tests.gd"),
	preload("res://game/dev/suites/knockdown_tests.gd"),
	preload("res://game/dev/suites/enemy_tests.gd"),
	preload("res://game/dev/suites/monster_tests.gd"),
	preload("res://game/dev/suites/camera_input_tests.gd"),
	preload("res://game/dev/suites/hud_tests.gd"),
	preload("res://game/dev/suites/loot_tests.gd"),
	preload("res://game/dev/suites/progression_tests.gd"),
	preload("res://game/dev/suites/town_tests.gd"),
	preload("res://game/dev/suites/world_tests.gd"),
	preload("res://game/dev/suites/quest_tests.gd"),
	preload("res://game/dev/suites/ds2_tests.gd"),
	preload("res://game/dev/suites/item_lab_tests.gd"),
	preload("res://game/dev/suites/equipment_integration_tests.gd"),
]

var _suites: Array[DevSuite] = []

func _init() -> void:
	harness = self

## Calls a check or tool by name on the suite that defines it (suites are created on first use).
func _run(method: String, args: Array = []) -> Variant:
	if _suites.is_empty():
		for script: GDScript in SUITES:
			var suite: DevSuite = script.new()
			suite.game = game
			suite.harness = self
			add_child(suite)
			_suites.append(suite)
	for suite in _suites:
		if suite.has_method(method):
			return await suite.callv(method, args)
	push_error("DevHarness: no suite defines " + method)
	return null

## Returns true when a developer mode was started (so Main should not begin a normal run).
func run_from_args() -> bool:
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().is_empty():
		if DisplayServer.get_screen_count() > 1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_current_screen(1)
			DisplayServer.window_set_size(Vector2i(1280, 720))
			DisplayServer.window_set_position(DisplayServer.screen_get_position(1) + Vector2i(120, 100))
		print("DEV_WINDOW screen=", DisplayServer.window_get_current_screen(), " position=", DisplayServer.window_get_position())
	if OS.get_cmdline_user_args().has("--wardenshot"):
		_run("_warden_shots")
	elif OS.get_cmdline_user_args().has("--skillshot=fireball"):
		_run("_skill_shots", ["fireball"])
	elif OS.get_cmdline_user_args().has("--enemyshot"):
		_run("_enemy_shot")
	elif OS.get_cmdline_user_args().has("--enemyfight"):
		_run("_enemy_fight")
	elif OS.get_cmdline_user_args().has("--archershot"):
		_run("_archer_shot")
	elif OS.get_cmdline_user_args().has("--takeaimshot"):
		_run("_take_aim_shot")
	elif OS.get_cmdline_user_args().has("--brutalshot"):
		_run("_brutal_shot")
	elif OS.get_cmdline_user_args().has("--skillshot=gibs"):
		_run("_gib_shots")
	elif OS.get_cmdline_user_args().has("--aimshot"):
		_run("_aim_shot")
	elif OS.get_cmdline_user_args().has("--pauseshot"):
		_run("_pause_shot")
	elif OS.get_cmdline_user_args().has("--hudshot"):
		_run("_hud_shot")
	elif OS.get_cmdline_user_args().has("--smashshot"):
		_run("_smash_shot")
	elif OS.get_cmdline_user_args().has("--dropshot"):
		_run("_drop_shot")
	elif OS.get_cmdline_user_args().has("--itemsheet"):
		_run("_item_sheet")
	elif OS.get_cmdline_user_args().has("--hovershot"):
		_run("_hover_shot")
	elif OS.get_cmdline_user_args().has("--rollshot"):
		_run("_roll_shots")
	elif OS.get_cmdline_user_args().has("--perf"):
		_run("_perf_bench")
	elif OS.get_cmdline_user_args().has("--poses"):
		_run("_pose_sheet")
	elif Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--handshot")):
		_run("_hand_shot")
	elif _clip_arg() != "":
		_run("_clip_sheet", [_clip_arg()])
	elif OS.get_cmdline_user_args().has("--roadreturn=clear") or OS.get_cmdline_user_args().has("--roadreturn=skipped"):
		_run("_measure_road_return")
	elif OS.get_cmdline_user_args().has("--selftest"):
		_run_selftest()
	elif OS.get_cmdline_user_args().has("--shot"):
		_next_wave()
		_run("_screenshot_demo")
	else:
		return false
	return true

func _clip_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clipsheet="):
			return arg.substr(12)
	return ""

## `--only=NAME` runs a single check, so a change can be verified without the whole suite.
const ONLY_TESTS := {
"rollshove": "_test_roll_shove",
"find": "_test_find",
"equipmenteffects": "_test_equipment_effects",
"equipmenthits": "_test_equipment_hits",
"rangedmods": "_test_ranged_modifiers",
"elements": "_test_elements",
"navigation": "_test_navigation",
"theme": "_test_ornate_theme",
"uiaudit": "_test_ui_audit",
"inventorygrid": "_test_inventory_grid",
"inventoryrotate": "_test_inventory_rotation",
"classnotice": "_test_class_notice",
"powerui": "_test_power_ui",
"skillintegrity": "_test_skill_integrity", "archer": "_test_archer_companion", "brutal": "_test_brutal_attack", "basicsingle": "_test_basic_single_target_physics", "armedfx": "_test_armed_power_fx", "hitinterrupt": "_test_hit_interruption_audit", "poweraudio": "_test_power_audio",
"actionqueue": "_test_action_queue", "classskills": "_test_class_skills", "ds2combat": "_test_ds2_combat", "ds2items": "_test_ds2_items", "skilltree": "_test_skill_tree", "powers": "_test_powers", "livepowers": "_test_live_powers",
	"movepriority": "_test_move_priority",
	"progression": "_test_progression", "worldprogression": "_test_world_progression", "xp": "_test_xp", "savepolicy": "_test_save_policy", "herodown": "_test_hero_knockdown",
"questlogic": "_test_quest_logic", "monsters": "_test_monsters", "dodgecancel": "_test_dodge_cancels_attack", "fireballframes": "_test_fireball_frames", "monsterscene": "_test_monster_scene", "roadrules": "_test_road_rules", "questworld": "_test_quest_world", "lootnames": "_test_loot_names", "hotbar": "_test_hotbar", "knockdown": "_test_knockdown", "world": "_test_world", "townlayout": "_test_town_layout", "crypt": "_test_crypt_road", "weaponstyle": "_test_weapon_styles", "twohand": "_test_two_hand", "fists": "_test_fists", "autoattack": "_test_auto_attack", "items": "_test_items", "swarm": "_test_swarm", "gibs": "_test_gibs",
	"warden": "_test_warden", "balance": "_test_balance", "enemies": "_test_enemies", "enemyspeed": "_test_enemy_speed", "firstwave": "_test_first_wave", "gamepad": "_test_gamepad", "loading": "_test_loading", "uiblock": "_test_ui_block", "behindcam": "_test_hover_behind_camera", "camera": "_test_camera_rotation", "startzoom": "_test_start_zoom", "deathragdoll": "_test_death_ragdoll", "enemyrun": "_test_enemy_run", "padmenus": "_test_pad_menus", "padtarget": "_test_pad_targeting", "padcamera": "_test_pad_camera_and_aim", "pausetest": "_test_pause_stops_game", "swordsound": "_test_sword_sound", "swordair": "_test_sword_miss_in_air", "fireballsound": "_test_fireball_sounds", "impact": "_test_impact", "fireblast": "_test_fire_blast", "loot": "_test_loot", "ownerfb1": "_test_owner_feedback_1", "bodyrecoil": "_test_body_recoil", "minimapfog": "_test_minimap_fog","destructibles": "_test_destructibles", "hitaggro": "_test_hit_aggro", "fireballcancel": "_test_fireball_cancel", "itemicons": "_test_item_icons", "lootui": "_test_loot_ui", "characterui": "_test_character_ui", "orbhud": "_test_orb_hud", "inventoryequip": "_test_inventory_equip", "townsim": "_test_town_sim", "townstate": "_test_town_state", "modifiers": "_test_run_modifiers", "townscene": "_test_town_scene", "hotkeys": "_test_hotkeys", "itemlab": "_test_item_lab", "equipmentintegration": "_test_equipment_integration",
}

var _failures: PackedStringArray = []

## Records a failed expectation (printed as [FAIL], which CI treats as an error) instead of just logging a boolean.
func record(label: String, condition: bool) -> void:
	if not condition:
		_failures.append(label)
		print("  [FAIL] ", label)

## Ends the run: exit code 0 when every expectation held, 1 otherwise.
func _finish() -> void:
	if _failures.is_empty():
		print("SELFTEST done")
		get_tree().quit(0)
	else:
		print("SELFTEST FAILED: ", ", ".join(_failures))
		print("SELFTEST done")
		get_tree().quit(1)

func _run_selftest() -> void:
	print("SELFTEST start")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only=") and ONLY_TESTS.has(arg.substr(7)):
			await _run(ONLY_TESTS[arg.substr(7)])
			_finish()
			return
	for action in ["click", "alt_skill", "stand_still", "restart", "skill_1", "skill_4"]:
		expect("input action %s exists" % action, InputMap.has_action(action))
	print("  camera current: ", rig.camera.current, "  pitch: ", rig.camera.rotation_degrees.x, "  fov: ", rig.camera.fov)

	await _run("_test_first_wave")
	await _run("_test_settings")
	await _run("_test_zoom")
	await _run("_test_hotkeys")
	await _run("_test_navigation")
	await _run("_test_roll_shove")
	await _run("_test_fireball")
	await _run("_test_items")
	await _run("_test_equipment_hits")
	await _run("_test_ranged_modifiers")
	await _run("_test_elements")
	await _run("_test_find")
	await _run("_test_equipment_effects")
	await _run("_test_ui_block")
	await _run("_test_hover_behind_camera")
	await _run("_test_camera_rotation")
	await _run("_test_start_zoom")
	await _run("_test_death_ragdoll")
	await _run("_test_enemy_run")
	await _run("_test_pad_menus")
	await _run("_test_pad_targeting")
	await _run("_test_pad_camera_and_aim")
	await _run("_test_sword_sound")
	await _run("_test_sword_miss_in_air")
	await _run("_test_fireball_sounds")
	await _run("_test_impact")
	await _run("_test_fire_blast")
	await _run("_test_gibs")
	await _run("_test_swarm")
	await _run("_test_gamepad")
	await _run("_test_loading")
	await _run("_test_enemies")
	await _run("_test_balance")
	await _run("_test_auto_attack")
	await _run("_test_fireball_cancel")
	await _run("_test_item_icons")
	await _run("_test_loot")
	await _run("_test_destructibles")
	await _run("_test_loot_ui")
	await _run("_test_town_sim")
	await _run("_test_town_state")
	await _run("_test_run_modifiers")
	await _run("_test_town_scene")

	var zombies: Array[Enemy] = []
	for i in 3:
		zombies.append(_spawn_enemy(Vector3(2.0 + i * 1.5, 0, 3.0)))
	player.attack_target = zombies[0]
	player.stats.mana = player.stats.max_mana
	await get_tree().create_timer(0.5).timeout
	# Exercise hotbar skills directly on the nearest zombie.
	for id in ["fireball"]:
		var target: Actor = player.enemy_near(player.global_position, 20.0)
		if target == null:
			break
		player.skills.queued_skill = id
		player.skills.queued_target = target
		await get_tree().create_timer(1.6).timeout
	await get_tree().create_timer(6.0).timeout

	# Roll: should move the hero ~4 m, grant brief invulnerability and not leave collision disabled.
	var before: Vector3 = player.global_position
	player.stats.stamina = player.stats.max_stamina
	player.movement.try_roll(player.global_position + Vector3(5, 0, 0))
	var roll_invuln: bool = player.invulnerable_time > 0.0
	await get_tree().create_timer(0.8).timeout
	expect("roll covers ground and is invulnerable", player.global_position.distance_to(before) > 3.0 and roll_invuln)
	expect("roll restores collision and ends", player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY) and not player.movement.rolling)
	print("  roll: moved ", snappedf(player.global_position.distance_to(before), 0.1), " m, invulnerable during=", roll_invuln,
		", mask restored=", player.collision_mask == (Actor.LAYER_WORLD | Actor.LAYER_ENEMY), ", rolling=", player.movement.rolling)

	# (Death behaviour has its own check: _test_death_ragdoll.)

	var names := ["MISS", "BLOCK", "HIT", "CRIT", "CRUSH", "WOUND"]
	var parts: Array[String] = []
	for key in Combat.tally.keys():
		parts.append("%s=%d" % [names[int(key)], int(Combat.tally[key])])
	print("  outcomes: ", ", ".join(parts))
	print("  kills: ", kills, "  player health: ", int(player.health), "  mana: ", int(player.stats.mana))
	_finish()
