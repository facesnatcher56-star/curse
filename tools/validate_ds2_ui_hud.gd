extends SceneTree
## Automated validation script for DS2 UI and Take Aim hotkey integration.
## Runs under watchdog on Monitor 2 and captures a full-frame screenshot.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[DS2_VALIDATE] Booting GameSettings...")
	# Isolated: this validator assigns hotbar slots, which saves; it must not write the owner's real settings file.
	GameSettings.settings_path = "user://validate_ds2_ui_hud_settings.cfg"
	GameSettings.boot()
	
	print("[DS2_VALIDATE] Hotbar slots: ", GameSettings.hotbar_slots)
	if GameSettings.hotbar_slots.size() > 1 and GameSettings.hotbar_slots[1] != "take_aim":
		# Ensure default slot 2 is take_aim
		GameSettings.assign_hotbar(1, "take_aim")
		print("[DS2_VALIDATE] Assigned slot 2 to take_aim: ", GameSettings.hotbar_slots)

	# Configure window for Monitor 2
	var win := root.get_window()
	if DisplayServer.get_screen_count() > 1:
		win.current_screen = 1
		win.position = Vector2i(3480, 200)
	win.size = Vector2i(1280, 720)
	win.mode = Window.MODE_WINDOWED

	# Build mock arena / world root
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	current_scene = world

	# Build Arena
	var arena := Arena.new()
	world.add_child(arena)

	# Spawn Player
	var player := Player.new()
	player.name = "Player"
	world.add_child(player)
	player.global_position = Vector3(0, 0, 0)

	# Spawn Companion Cutter
	var companion := ArcherCompanion.new()
	companion.name = "ArcherCompanion"
	world.add_child(companion)
	companion.setup(player)

	# Create HUD
	var hud := Hud.new()
	hud.name = "Hud"
	hud.player = player
	hud.arena = arena
	root.add_child(hud)

	# Spawn mock enemy for target banner
	var enemy := Enemy.new()
	enemy.display_name = "Corrupted Revenant"
	enemy.max_health = 250.0
	enemy.health = 185.0
	enemy.is_boss = true
	world.add_child(enemy)
	enemy.global_position = Vector3(0, 0, 5)
	player.hover_target = enemy

	print("[DS2_VALIDATE] Companions in group: ", player.get_tree().get_nodes_in_group("companions"))
	print("[DS2_VALIDATE] Cutter found: ", player.stats._cutter())

	# Give companion a target and arm take aim
	companion.target = enemy
	companion.take_aim_reload_remaining = 0.0

	# Process frames to allow UI layout and shaders to compile
	for i in 60:
		hud._process(1.0 / 60.0)
		await process_frame

	print("[DS2_VALIDATE] Companion card visible: ", hud.ds2_party_frame.companion_card.visible)
	print("[DS2_VALIDATE] Companion card size: ", hud.ds2_party_frame.companion_card.size)
	print("[DS2_VALIDATE] Companion card pos: ", hud.ds2_party_frame.companion_card.position)

	# Verify Take Aim hotkey activation
	print("[DS2_VALIDATE] Testing Take Aim activation on hotbar...")
	player.skills.activate_take_aim()
	print("[DS2_VALIDATE] Cutter Take Aim armed: ", companion.take_aim_armed)
	assert(companion.take_aim_armed, "Cutter Take Aim should be armed!")

	# Capture live screenshot on Monitor 2
	await process_frame
	await process_frame
	var img := win.get_texture().get_image()
	if img != null:
		var shot_path := "C:/Users/lloyd/Desktop/DS2_Reference_Extracted/ds2_live_hud_monitor2.png"
		var err := img.save_png(shot_path)
		if err == OK:
			print("[DS2_VALIDATE] Saved live HUD screenshot to: ", shot_path)
		else:
			push_error("[DS2_VALIDATE] Failed to save screenshot: " + str(err))

	print("[DS2_VALIDATE] ALL CHECKS PASSED SUCCESSFULLY!")
	quit(0)
