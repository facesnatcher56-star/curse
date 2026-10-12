class_name ItemTestLab
extends Node3D
## Minimal, developer-only Item Test Lab for Curse.
## Integrates genuine character models, rigs, animations, ItemDefs, equipment rules,
## combat formulas, and training dummy testing under complete save isolation.

const SAVE_NAMESPACE := "user://dev_item_lab/"

var player: Player
var dummy: TrainingDummy
var rig: CameraRig
var hud: Hud
var pause_menu: PauseMenu

# Lab dev panels
var spawner_panel: LabSpawnerPanel
var stats_readout: LabStatsReadout
var combat_log: LabCombatLog
var lab_ui_root: Control

# Controls for dummy & character configuration
var _dummy_level_spin: SpinBox
var _dummy_armor_spin: SpinBox
var _char_level_spin: SpinBox
var _stance_overbear_check: CheckBox
var _stance_barricade_check: CheckBox

func _ready() -> void:
	# The main game already booted settings before launching self-tests. Rebooting
	# here would restore saved audio settings in the middle of a test fixture.
	if not OS.get_cmdline_user_args().has("--selftest"):
		GameSettings.boot()
	# Enforce strictly developer-only isolation
	SavePolicy.ensure_folder(SAVE_NAMESPACE + "town.json")
	TownState.persist = false
	TownState.reset()

	# Clear any prior state and grant basic testing passives/levels
	_setup_test_player_state()

	_build_lab_environment()
	_spawn_player()
	_spawn_training_dummy()
	_build_lab_ui()

	# Focus initial camera view
	if rig != null and player != null:
		rig.global_position = player.global_position
		rig.set_zoom_now(2.5)

	# Initial stats refresh
	call_deferred("_refresh_all_stats")

	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	if args.has("--labshot"):
		call_deferred("_run_lab_shots", args)

func _setup_test_player_state() -> void:
	# Start with level 10 so tester can test various item tiers immediately,
	# but expose controls to adjust level and stance passives in real-time.
	TownState.dev_set_hero_level(10)
	TownState.passive_ranks = {
		"overbear": 1,
		"barricade": 1
	}

func _build_lab_environment() -> void:
	# Simple, clearly lit testing room with Arena ground
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.2
	world_env.environment = env
	add_child(world_env)

	# Overhead key light and fill light for clear equipment and character visibility
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45, -30, 0)
	key_light.light_color = Color(1.0, 0.96, 0.9)
	key_light.light_energy = 1.4
	key_light.shadow_enabled = true
	add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-30, 150, 0)
	fill_light.light_color = Color(0.6, 0.7, 0.9)
	fill_light.light_energy = 0.6
	add_child(fill_light)

	# Clean ground plane with collision and navigation
	var arena_nav := NavigationRegion3D.new()
	add_child(arena_nav)

	var ground_body := StaticBody3D.new()
	ground_body.collision_layer = Actor.LAYER_WORLD
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	ground_shape.shape = box
	ground_shape.position = Vector3(0, -0.5, 0)
	ground_body.add_child(ground_shape)
	arena_nav.add_child(ground_body)

	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground_mesh.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.18, 0.17, 0.16) # Neutral dark stone
	ground_mat.roughness = 0.8
	ground_mesh.material_override = ground_mat
	arena_nav.add_child(ground_mesh)

	# Bake simple navigation mesh for movement and click-to-move
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	arena_nav.navigation_mesh = nav_mesh
	arena_nav.bake_navigation_mesh()

func _spawn_player() -> void:
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0, 2.0)
	player.visual.rotation.y = PI # Face North toward dummy

	# Starting gear (longsword + leather jerkin)
	var starter: Array[Dictionary] = Items.starting_gear()
	if starter.size() > 0:
		player.stats.equip(starter[0], false)
	if starter.size() > 1:
		player.stats.equip(starter[1], false)

	# Add camera rig following player
	rig = CameraRig.new()
	rig.target = player
	add_child(rig)
	rig.global_position = player.global_position

func _spawn_training_dummy() -> void:
	dummy = TrainingDummy.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -3.5) # Directly North of player
	dummy.hit_received.connect(_on_dummy_hit_received)

func _build_lab_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	# Real gameplay HUD for full hotbars, vitals orbs, and inventory (Tab)
	hud = Hud.new()
	hud.player = player
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(hud)

	pause_menu = PauseMenu.new()
	pause_menu.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	pause_menu.main_menu_requested.connect(func() -> void: get_tree().change_scene_to_file("res://game/menu.tscn"))
	canvas.add_child(pause_menu)

	lab_ui_root = Control.new()
	lab_ui_root.name = "LabUIRoot"
	lab_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lab_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(lab_ui_root)

	# Top Control Bar: Lab title, dummy configuration, and reset options
	var top_bar := PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", UiTheme.panel_box())
	top_bar.position = Vector2(16, 16)
	top_bar.custom_minimum_size = Vector2(800, 48)
	lab_ui_root.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 12)
	top_bar.add_child(top_hbox)

	var lab_title := Label.new()
	lab_title.text = "ITEM TEST LAB"
	lab_title.add_theme_font_size_override("font_size", 18)
	lab_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	top_hbox.add_child(lab_title)

	# Dummy Config
	var d_lvl_lbl := Label.new()
	d_lvl_lbl.text = "Dummy Lvl:"
	d_lvl_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	top_hbox.add_child(d_lvl_lbl)
	_dummy_level_spin = SpinBox.new()
	_dummy_level_spin.min_value = 1
	_dummy_level_spin.max_value = 50
	_dummy_level_spin.value = 1
	_dummy_level_spin.value_changed.connect(func(v: float) -> void: dummy.set_dummy_level(int(v)))
	top_hbox.add_child(_dummy_level_spin)

	var d_arm_lbl := Label.new()
	d_arm_lbl.text = "Armor:"
	d_arm_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	top_hbox.add_child(d_arm_lbl)
	_dummy_armor_spin = SpinBox.new()
	_dummy_armor_spin.min_value = 0
	_dummy_armor_spin.max_value = 500
	_dummy_armor_spin.value = 0
	_dummy_armor_spin.value_changed.connect(func(v: float) -> void: dummy.set_dummy_armor(v))
	top_hbox.add_child(_dummy_armor_spin)

	var reset_dummy_btn := UiTheme.button("Reset Dummy", 110.0)
	reset_dummy_btn.pressed.connect(func() -> void: dummy.reset_health())
	top_hbox.add_child(reset_dummy_btn)

	# Hero Level Override
	var c_lvl_lbl := Label.new()
	c_lvl_lbl.text = "Hero Lvl:"
	c_lvl_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	top_hbox.add_child(c_lvl_lbl)
	_char_level_spin = SpinBox.new()
	_char_level_spin.min_value = 1
	_char_level_spin.max_value = 50
	_char_level_spin.value = 10
	_char_level_spin.value_changed.connect(_on_hero_level_changed)
	top_hbox.add_child(_char_level_spin)

	var reset_lab_btn := UiTheme.button("Reset Lab", 90.0)
	reset_lab_btn.pressed.connect(_reset_lab_state)
	top_hbox.add_child(reset_lab_btn)

	var toggle_ui_btn := UiTheme.button("Toggle Panels", 110.0)
	toggle_ui_btn.pressed.connect(_toggle_panels)
	top_hbox.add_child(toggle_ui_btn)

	# Left Dock: Spawner Panel
	spawner_panel = LabSpawnerPanel.new()
	spawner_panel.player = player
	spawner_panel.position = Vector2(16, 76)
	spawner_panel.stats_refresh_requested.connect(_refresh_all_stats)
	lab_ui_root.add_child(spawner_panel)

	# Right Dock: Stats Readout & Combat Log
	var right_dock := VBoxContainer.new()
	right_dock.position = Vector2(get_viewport().size.x - 380, 76)
	right_dock.add_theme_constant_override("separation", 10)
	lab_ui_root.add_child(right_dock)

	stats_readout = LabStatsReadout.new()
	stats_readout.player = player
	right_dock.add_child(stats_readout)

	combat_log = LabCombatLog.new()
	right_dock.add_child(combat_log)

	# Keep UI responsive to screen resizing
	get_tree().root.size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()

func _on_viewport_resized() -> void:
	if not is_instance_valid(lab_ui_root) or stats_readout == null:
		return
	var vp_size: Vector2i = get_viewport().size
	var right_parent: Control = stats_readout.get_parent() as Control
	if right_parent != null:
		right_parent.position = Vector2(maxf(float(vp_size.x) - 380.0, 400.0), 76.0)

func _on_hero_level_changed(val: float) -> void:
	var lvl := int(val)
	TownState.dev_set_hero_level(lvl)
	player.stats.refresh()
	_refresh_all_stats()

func _toggle_panels() -> void:
	var visible_now: bool = not spawner_panel.visible
	spawner_panel.visible = visible_now
	stats_readout.get_parent().visible = visible_now

func _on_dummy_hit_received(result: Dictionary, defender: Actor) -> void:
	combat_log.record_hit(result, player, defender)
	_refresh_all_stats()

func _refresh_all_stats() -> void:
	if stats_readout != null:
		stats_readout.refresh()
	if spawner_panel != null:
		spawner_panel._update_preview()

func _reset_lab_state() -> void:
	# Completely restores test environment without touching production saves
	TownState.persist = false
	TownState.reset()
	_setup_test_player_state()
	player.stats.equipment.clear()
	player.stats.bag.clear()
	var starter: Array[Dictionary] = Items.starting_gear()
	if starter.size() > 0: player.stats.equip(starter[0], false)
	if starter.size() > 1: player.stats.equip(starter[1], false)
	player.stats.refresh()
	player.health = player.max_health
	player.stats.mana = player.stats.max_mana
	dummy.reset_health()
	combat_log.clear_log()
	_char_level_spin.value = 10
	_refresh_all_stats()

func _run_lab_shots(_args: PackedStringArray) -> void:
	# Wait for first frames to settle
	await get_tree().create_timer(1.0).timeout

	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_viewport().size = Vector2i(1920, 1080)
	_on_viewport_resized()
	await get_tree().create_timer(0.6).timeout

	# Select Weapons filter in spawner panel to showcase the weapon selector
	if spawner_panel != null:
		spawner_panel._filter_option.select(1)
		spawner_panel._on_filter_changed(1)
		for i in range(spawner_panel._filtered_defs.size()):
			if spawner_panel._filtered_defs[i].id == "axe_1h":
				spawner_panel._item_def_option.select(i)
				spawner_panel._on_def_selected(i)
				break
		spawner_panel._on_equip_pressed()
		player.refresh_weapon_model()
		_refresh_all_stats()

	await get_tree().create_timer(0.5).timeout
	_capture_to_file("res://docs/screenshots/item_lab_overview.png")

	# Combat hit against the dummy
	var melee_rng: Vector2 = player.stats.weapon_range(1.0)
	var dmg: float = randf_range(melee_rng.x, melee_rng.y)
	var hit: Dictionary = Combat.resolve(player, dummy, dmg, Combat.DamageType.PHYSICAL, false, 1.0)
	hit["skill_id"] = "basic"
	dummy.receive(hit, player.global_position)
	await get_tree().create_timer(0.5).timeout
	_capture_to_file("res://docs/screenshots/item_lab_combat.png")

	# Open HUD inventory
	if hud != null:
		hud._open_character()
	await get_tree().create_timer(0.5).timeout
	_capture_to_file("res://docs/screenshots/item_lab_inventory.png")

	# 720p responsive check
	if hud != null:
		hud.close_character()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_viewport().size = Vector2i(1280, 720)
	_on_viewport_resized()
	await get_tree().create_timer(0.5).timeout
	_capture_to_file("res://docs/screenshots/item_lab_720p.png")

	print("[item_lab] All screenshots captured successfully!")
	get_tree().quit()

func _capture_to_file(res_path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(res_path)
	var tex := get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img != null:
		var err := img.save_png(abs_path)
		if err == OK:
			print("[item_lab_screenshot] Saved ", abs_path)
		else:
			printerr("[item_lab_screenshot] Failed saving to ", abs_path, " err: ", err)
	else:
		printerr("[item_lab_screenshot] Viewport image is null")
