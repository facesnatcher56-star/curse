extends SceneTree
## Focused self-test for the Hearthward Waystation Field Respite (task waystation-field-respite-085).
##
## Validates:
##   1. Physical setup, placement in tollhouse (x=11.0, z=124.2), and discoverability.
##   2. Safe out-of-combat usability and modest partial restoration (+35 HP, +25 MP).
##   3. Single-use guard per road visit (cannot be used repeatedly).
##   4. In-combat guard (cannot rest while combat timer is active or threatened).
##   5. Full-strength guard (does not waste single use when already at full resources).
##   6. Repeat road entry semantics and expedition reset.
##   7. Controller and keyboard prompt parity ([E] vs [A]).
##   8. Real-renderer screenshot capture when requested (--respiteshots=DIR).
##
## Run: tools/run_godot.sh LOG 60 -- -s tools/waystation_respite_check.gd [--respiteshots=DIR]

var out_dir: String = ""
var failures: int = 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--respiteshots="):
			out_dir = arg.substr(15)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func expect(label: String, ok: bool) -> void:
	print("%s  %s" % ["  [PASS]" if ok else "  [FAIL]", label])
	if not ok:
		failures += 1

func _capture(filename: String) -> void:
	if out_dir == "":
		return
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var path: String = "%s/%s.png" % [out_dir, filename]
		img.save_png(path)
		print("  [RENDER] Saved: %s" % path)

func _run() -> void:
	print("=== WAYSTATION FIELD RESPITE CHECK START ===")
	TownState.persist = false
	InputSetup.apply()
	TownState.job = {}
	Gamepad.active = false

	# 1. World & Road setup
	var arena: Arena = CryptRoad.make_arena()
	root.add_child(arena)
	arena.build(false)

	var road: CryptRoad = CryptRoad.new()
	root.add_child(road)
	current_scene = road
	road.build(arena)

	var player: Player = Player.new()
	root.add_child(player)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 50.0
	root.add_child(cam)

	var light := DirectionalLight3D.new()
	light.light_energy = 0.9
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	root.add_child(light)

	for i in 3:
		await process_frame

	player.global_position = road.at(11.0, 126.0) # Near tollhouse hearth
	cam.global_position = road.at(8.0, 128.5) + Vector3(0.0, 3.2, 0.0)
	cam.look_at(road.at(11.0, 124.2) + Vector3(0.0, 1.2, 0.0), Vector3.UP)

	# --- TEST 1: Placement and Discovery ---
	var respite: WaystationRespite = WaystationEncounter.get_respite(road)
	expect("Respite node exists at waystation via WaystationEncounter.get_respite", respite != null)

	var expected_pos: Vector3 = road.at(11.0, 124.2)
	expect("Respite positioned inside ruined tollhouse near z=124.2, x=11.0", respite.global_position.distance_to(expected_pos) < 1.0)
	expect("Respite has warm hearth ember light", respite._light != null and respite._light.light_color.r > 0.8)
	expect("Respite has billboard prompt tag", respite._tag != null)

	# Discovery check: player at 6m distance
	player.global_position = road.at(11.0, 130.2)
	respite._update_prompt()
	expect("At 6m distance, prompt shows discoverable location/warm embers cue", respite._tag.visible and respite._tag.text.contains("Warm Embers"))

	# Close interaction check: player at 1.8m
	player.global_position = road.at(11.0, 125.5)
	player.health = 80.0
	respite._update_prompt()
	expect("Within 2.8m, prompt shows [E] keyboard rest interaction", respite._tag.visible and respite._tag.text.contains("[E]") and respite._tag.text.contains("+35 HP"))

	# --- TEST 2: Out of Combat Usability & Modest Partial Recovery ---
	player.health = 50.0 # Deplete HP (out of 120)
	player.stats.mana = 20.0 # Deplete Mana (out of 80)
	player.combat_timer = 0.0
	player.attack_target = null
	var potions_before: int = player.stats.potions
	var ult_before: float = player.stats.ult_charge

	var check1: Dictionary = respite.can_rest(player)
	expect("Can rest when safely out of combat with missing resources", check1.allowed)

	var used_ok: bool = respite.attempt_rest(player)
	expect("attempt_rest succeeds", used_ok)
	expect("Partial HP restored (+35 HP, resulting in 85)", is_equal_approx(player.health, 85.0))
	expect("Partial Mana restored (+25 MP, resulting in 45)", is_equal_approx(player.stats.mana, 45.0))
	expect("Does NOT refill scarce potions (potions count unchanged)", player.stats.potions == potions_before)
	expect("Does NOT charge ultimate", is_equal_approx(player.stats.ult_charge, ult_before))
	expect("Respite marked as used", respite.is_used)

	# --- TEST 3: Single-Use Guard ---
	var check2: Dictionary = respite.can_rest(player)
	expect("Single-use guard: repeat rest blocked on same visit", not check2.allowed and check2.reason == "already_used")

	var repeat_used: bool = respite.attempt_rest(player)
	expect("Repeat attempt fails and does not restore resources", not repeat_used and is_equal_approx(player.health, 85.0))

	respite._update_prompt()
	expect("Prompt reflects cold embers after use", respite._tag.text.contains("Embers cold"))

	# --- TEST 4: In-Combat Guard ---
	respite.reset_visit()
	expect("reset_visit clears is_used flag", not respite.is_used)

	player.health = 60.0
	player.combat_timer = 5.0 # Player recently in combat
	var check_combat: Dictionary = respite.can_rest(player)
	expect("In-combat guard: blocked while player.combat_timer > 0", not check_combat.allowed and check_combat.reason == "in_combat")

	var combat_attempt: bool = respite.attempt_rest(player)
	expect("In-combat attempt fails", not combat_attempt)
	expect("In-combat attempt does NOT consume single-use respite", not respite.is_used)
	expect("Player health unchanged during blocked combat attempt", is_equal_approx(player.health, 60.0))

	# Clear combat timer
	player.combat_timer = 0.0
	expect("Out of combat again, can rest", respite.can_rest(player).allowed)

	# --- TEST 5: Full Strength Guard ---
	respite.reset_visit()
	player.health = player.max_health
	player.stats.mana = player.stats.max_mana

	var check_full: Dictionary = respite.can_rest(player)
	expect("Full-strength guard: blocked when already at 100% HP and MP", not check_full.allowed and check_full.reason == "already_full")

	var full_attempt: bool = respite.attempt_rest(player)
	expect("Full-strength attempt fails and preserves respite for later", not full_attempt and not respite.is_used)

	# --- TEST 6: Repeat Road Entry & Expedition Reset ---
	player.health = 40.0
	player.stats.mana = 20.0
	respite.attempt_rest(player)
	expect("Respite used on first expedition visit", respite.is_used)

	# Simulate return to town and new road departure
	TownState.expedition = false
	respite._track_road_visit()
	TownState.expedition = true
	respite._track_road_visit()
	expect("New road expedition resets respite single-use guard", not respite.is_used)

	# --- TEST 7: Controller / Gamepad Parity ---
	Gamepad.active = false
	respite._update_prompt()
	expect("Keyboard mode displays [E] key cue", respite._tag.text.contains("[E]"))

	Gamepad.active = true
	respite._update_prompt()
	expect("Gamepad mode displays [A] button cue", respite._tag.text.contains("[A]"))
	Gamepad.active = false


	# Regression coverage for task090: authoritative ownership, zero-progress regrow,
	# recreation, actual rebound input, cap clipping and native camera screenshots.
	player.set_physics_process(false)
	player.set_process(false)
	respite.set_physics_process(false)
	respite._player_ref = player
	TownState.expedition = true
	respite.reset_visit()
	player.health = player.max_health - 1.0
	player.stats.mana = player.stats.max_mana - 1.0
	expect("Clipped recovery succeeds", respite.attempt_rest(player))
	expect("HP/MP clip at caps", player.health == player.max_health and player.stats.mana == player.stats.max_mana)
	for z in [166.0, 124.2, -21.0, -63.8]:
		road.in_world = z < 0.0
		player.global_position.z = z
		respite._track_road_visit()
		expect("Same expedition crossing z=%s stays spent" % z, respite.is_used)
	road.in_world = false
	player.global_position = respite.global_position + Vector3(0,0,1.3)
	var before_props := road.placed.size()
	WaystationEncounter.build(road, arena)
	expect("Repeated build retains same respite and props", WaystationEncounter.get_respite(road) == respite and road.placed.size() == before_props)
	respite.free()
	respite = WaystationEncounter.ensure_respite(road)
	respite._player_ref = player
	respite.set_physics_process(false)
	player.health = 50
	player.stats.mana = 20
	expect("Recreated component cannot recover twice", respite.is_used and not respite.attempt_rest(player) and player.health == 50)
	var another_road := CryptRoad.new()
	root.add_child(another_road)
	another_road.arena = arena
	var another_respite := WaystationEncounter.ensure_respite(another_road)
	expect("Road recreation in same expedition stays spent", another_respite.is_used and not another_respite.attempt_rest(player))
	another_road.free()
	# A real authoritative end advances the day, even if no component saw the flag.
	TownState.end_expedition()
	TownState.begin_expedition()
	respite._track_road_visit()
	expect("Authoritative completed expedition resets", not respite.is_used)
	expect("New expedition permits recovery", respite.attempt_rest(player))
	road.director = RunDirector.new()
	root.add_child(road.director)
	road.director.player = player
	road.nests_destroyed = 0
	road.regrow()
	expect("Explicit zero-progress regrow resets immediately", not respite.is_used)
	await process_frame
	for enemy in get_nodes_in_group("enemies"):
		enemy.free()
	player.combat_timer = 0
	player.attack_target = null
	var threat := Enemy.new()
	root.add_child(threat)
	threat.set_physics_process(false)
	threat.set_process(false)
	threat.global_position = player.global_position
	threat._aggro = true
	expect("Living alert threat prevents rest", not respite.can_rest(player).allowed)
	threat.free()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	InputMap.action_erase_events("interact")
	InputMap.action_add_event("interact", key)
	Gamepad.active = false
	respite._update_prompt()
	expect("Rebound keyboard cue displays F", respite._tag.text.contains("[F]"))
	respite._unhandled_input(key)
	expect("Actual rebound F input rests", respite.is_used)
	respite.reset_visit()
	player.health = 50
	player.stats.mana = 20
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	pad.pressed = true
	InputMap.action_erase_events("interact")
	InputMap.action_add_event("interact", pad)
	Gamepad.active = true
	respite._update_prompt()
	expect("Rebound controller cue displays X", respite._tag.text.contains("[X]"))
	respite._unhandled_input(pad)
	expect("Actual rebound X input rests", respite.is_used)
	respite.reset_visit()
	InputMap.action_erase_events("interact")
	respite._update_prompt()
	expect("Unbound controller cue is truthful", respite._tag.text.contains("[Unbound]"))
	InputMap.action_add_event("interact", pad)
	InputMap.action_add_event("interact", key)
	player.health = 50
	player.stats.mana = 20
	await create_timer(2.0).timeout
	var rig := CameraRig.new()
	rig.target = player
	root.add_child(rig)
	rig.global_position = player.global_position
	for zoom in [1.0, 2.6, 4.2]:
		rig.set_zoom_now(zoom)
		Gamepad.active = false
		respite._update_prompt()
		await create_timer(0.3).timeout
		expect("Prompt remains native 24px at zoom %s" % zoom, respite._tag.get_theme_font_size("font_size") == 24 and respite._tag.visible)
		await _capture("task090-keyboard-zoom%s" % zoom)
	Gamepad.active = true
	respite._update_prompt()
	await _capture("task090-controller-X")
	respite.attempt_rest(player)
	respite._update_prompt()
	await create_timer(1.5).timeout
	await _capture("task090-spent")

	# --- TEST 8: Screenshot Capture ---
	await _capture("waystation_field_respite_hearth")

	print("=== WAYSTATION FIELD RESPITE CHECK COMPLETED (Failures: %d) ===" % failures)
	quit(1 if failures > 0 else 0)
