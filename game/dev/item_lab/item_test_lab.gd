class_name ItemTestLab
extends Node3D
## Minimal, developer-only Item Test Lab for Curse.
## Integrates genuine character models, rigs, animations, ItemDefs, equipment rules,
## combat formulas, and training dummy testing under complete save isolation.

const SAVE_NAMESPACE := "user://dev_item_lab/"

## Layout, in canvas units (the project stretches a 1280 x 720 canvas, so these hold at every resolution). The boss bar and the party frame
## occupy the top edge, the hotbar the bottom edge and the minimap the bottom-right corner.
const LAB_MARGIN := 16.0
const LAB_TOP_BAR_Y := 64.0
const LAB_DOCK_Y := 168.0
const LAB_RIGHT_DOCK_WIDTH := 360.0
const LAB_BOTTOM_CLEARANCE := 190.0
## The smallest canvas the panels fit in unscaled (top bar width, dock heights plus the HUD bars). A smaller one (a large interface scale on a
## small window) scales the Lab overlay down just enough, never up.
const LAB_DESIGN_SIZE := Vector2(1080.0, 730.0)

var _fitted_canvas := Vector2.ZERO

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
	for arg in args:
		if arg.begins_with("--labsizes="):   # e.g. --labsizes=1920x1080,3440x1440 --labdir=C:/shots
			call_deferred("_run_layout_shots", arg.substr(11), _arg_value(args, "--labdir="))

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
	lab_ui_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)   # sized by _fit_lab_ui to the visible canvas
	lab_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(lab_ui_root)

	# Top Control Bar: Lab title, dummy configuration, and reset options
	var top_bar := PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", UiTheme.panel_box())
	top_bar.position = Vector2(LAB_MARGIN, LAB_TOP_BAR_Y)
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
	spawner_panel.position = Vector2(LAB_MARGIN, LAB_DOCK_Y)
	spawner_panel.stats_refresh_requested.connect(_refresh_all_stats)
	lab_ui_root.add_child(spawner_panel)

	# Right Dock: Stats Readout & Combat Log
	# Anchored to the right edge of the scaled canvas (lab_ui_root fills it), so it follows any resolution or aspect ratio, ultrawide included.
	# It stops above the HUD's bottom bar and minimap and shares the height between its two panels.
	var right_dock := VBoxContainer.new()
	right_dock.anchor_left = 1.0
	right_dock.anchor_right = 1.0
	right_dock.anchor_top = 0.0
	right_dock.anchor_bottom = 1.0
	right_dock.offset_left = -(LAB_RIGHT_DOCK_WIDTH + LAB_MARGIN)
	right_dock.offset_right = -LAB_MARGIN
	right_dock.offset_top = LAB_DOCK_Y
	right_dock.offset_bottom = -LAB_BOTTOM_CLEARANCE
	right_dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_dock.add_theme_constant_override("separation", 10)
	lab_ui_root.add_child(right_dock)

	stats_readout = LabStatsReadout.new()
	stats_readout.player = player
	stats_readout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_readout.size_flags_stretch_ratio = 3.0
	right_dock.add_child(stats_readout)

	combat_log = LabCombatLog.new()
	combat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	combat_log.size_flags_stretch_ratio = 2.0
	right_dock.add_child(combat_log)

func _process(_delta: float) -> void:
	if is_instance_valid(lab_ui_root) and get_viewport().get_visible_rect().size != _fitted_canvas:
		_fit_lab_ui()

## Sizes the overlay to the visible canvas (it changes with the window and the interface scale) and shrinks it when the canvas is too small.
func _fit_lab_ui() -> void:
	_fitted_canvas = get_viewport().get_visible_rect().size
	var fit: float = minf(1.0, minf(_fitted_canvas.x / LAB_DESIGN_SIZE.x, _fitted_canvas.y / LAB_DESIGN_SIZE.y))
	lab_ui_root.scale = Vector2(fit, fit)
	lab_ui_root.position = Vector2.ZERO
	lab_ui_root.size = _fitted_canvas / fit

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
	await get_tree().create_timer(0.5).timeout
	_capture_to_file("res://docs/screenshots/item_lab_720p.png")

	print("[item_lab] All screenshots captured successfully!")
	get_tree().quit()

static func _arg_value(args: PackedStringArray, prefix: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""

## Developer tool: captures the Item Lab at each `WxH`, once plain and once with a dropdown open, into `dir` (absolute path).
func _run_layout_shots(sizes: String, dir: String) -> void:
	await get_tree().create_timer(1.0).timeout
	for entry in sizes.split(","):
		var parts := entry.split("x")
		if parts.size() != 2:
			continue
		var size := Vector2i(int(parts[0]), int(parts[1]))
		var window := get_window()
		window.mode = Window.MODE_WINDOWED
		window.borderless = true
		window.size = size
		window.position = DisplayServer.screen_get_position(window.current_screen)
		await get_tree().create_timer(0.8).timeout
		if spawner_panel != null:
			spawner_panel._item_def_option.get_popup().hide()
		_save_png(dir.path_join("lab_%dx%d.png" % [size.x, size.y]))
		if spawner_panel != null:
			spawner_panel._item_def_option.show_popup()
			await get_tree().create_timer(0.4).timeout
			_save_png(dir.path_join("lab_%dx%d_dropdown.png" % [size.x, size.y]))
			spawner_panel._item_def_option.get_popup().hide()
		print("[item_lab_layout] ", size, " window=", window.size, " canvas=", lab_ui_root.size)
		if spawner_panel != null:
			await _layout_dropdown_probe(spawner_panel._rarity_option, dir.path_join("lab_%dx%d_selected.png" % [size.x, size.y]))
	get_tree().quit()

## Developer tool: opens `dropdown` and picks an entry with injected pointer events, then clicks open ground, and reports whether the hero moved.
func _layout_dropdown_probe(dropdown: OptionButton, shot_path: String) -> void:
	player.movement.has_goal = false
	var to_pixels: Transform2D = get_window().get_final_transform()
	var center: Vector2 = to_pixels * (dropdown.get_global_transform() * (dropdown.size * 0.5))
	await _probe_click(center)
	var popup: PopupMenu = dropdown.get_popup()
	var opened: bool = popup.visible
	var moved_on_open: bool = player.movement.has_goal
	var entry := Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * 0.6)
	await _probe_click(to_pixels * entry)
	_save_png(shot_path)
	var moved_on_select: bool = player.movement.has_goal
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	player.cursor_override = player.global_position + Vector3(2.0, 0.0, 2.0)
	await _probe_click(to_pixels * Vector2(canvas.x * 0.62, canvas.y * 0.45))
	print("[item_lab_probe] popup opened=", opened, " moved on open=", moved_on_open, " popup closed after select=", not popup.visible, " selected=", dropdown.get_item_text(dropdown.selected),
		" moved on select=", moved_on_select, " next ground click moves=", player.movement.has_goal)
	player.cursor_override = Vector3.INF
	player.movement.has_goal = false

func _probe_click(pixel: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.global_position = pixel
	Input.parse_input_event(motion)
	await get_tree().create_timer(0.15).timeout
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = pixel
		click.global_position = pixel
		click.pressed = pressed
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(click)
		await get_tree().create_timer(0.12).timeout

func _save_png(abs_path: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	print("[item_lab_layout] saved ", abs_path, " ", img.get_size(), " err=", img.save_png(abs_path))

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
