extends Node3D
## Developer-only close inspection view; uses actual Player, PlayerStats and CharacterModel attachment systems.
const WEAPON_IDS: Array[String] = ["longsword", "greatsword", "axe_1h", "mace", "club", "dagger", "axe_2h", "hammer_2h"]
const CAMERA_DISTANCE_MIN := 2.0
const CAMERA_DISTANCE_MAX := 7.0
const CAMERA_TARGET_HEIGHT := 1.2
const CAPTURE_FOLDER := "user://equipment_inspector"
const CAPTURE_REVIEW_DIR := "res://docs/screenshots/equipment_inspector"

var player: Player
var camera: Camera3D
var orbit_yaw: float = 0.0
var orbit_pitch: float = -0.03
var camera_distance: float = 3.0
var orbit_dragging: bool = false
var selected_index: int = 0
var default_capture_camera: bool = true
var paused_preview: bool = false
var playback_speed: float = 1.0
var preview_animation: String = ""
var last_attack_animation: String = ""
var preview_duration: float = 0.0
var preview_elapsed: float = 0.0
var preview_paused_at_strike: bool = false
var timeline_slider: HSlider
var timeline_label: Label
var title_label: Label
var status_label: Label
var weapon_selector: OptionButton
var capture_counter: int = 0

func _ready() -> void:
	TownState.persist = false
	TownState.reset()
	_build_stage()
	_build_player()
	_build_interface()
	_equip_selected()
	_sync_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_stage() -> void:
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#111820")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c8d3dd")
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, -28.0, 0.0)
	key_light.light_energy = 1.8
	key_light.shadow_enabled = true
	add_child(key_light)
	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill_light.light_color = Color("#a7c7e7")
	fill_light.light_energy = 0.65
	add_child(fill_light)
	var floor: MeshInstance3D = MeshInstance3D.new()
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(8.0, 8.0)
	floor.mesh = floor_mesh
	floor.position.y = -0.04
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color("#273039")
	floor_material.roughness = 0.94
	floor.material_override = floor_material
	add_child(floor)
	camera = Camera3D.new()
	camera.name = "InspectorCamera"
	camera.fov = 42.0
	camera.current = true
	add_child(camera)

func _build_player() -> void:
	player = Player.new()
	player.name = "ActualPlayableHero"
	player.member_id = "hero"
	player.position = Vector3.ZERO
	player.rotation.y = PI
	add_child(player)
	# Let the real production Player._ready build the rig, default weapon and stats first.
	player.set_physics_process(false)
	for child: Node in player.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	player.model.loop("idle_alert")

func _build_interface() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "InspectorControls"
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(370.0, 320.0)
	layer.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 23)
	box.add_child(title_label)
	weapon_selector = OptionButton.new()
	weapon_selector.name = "WeaponSelector"
	for weapon_id: String in WEAPON_IDS:
		var def: ItemDef = ItemDb.get_def(weapon_id)
		weapon_selector.add_item(def.display_name if def != null else weapon_id)
	weapon_selector.item_selected.connect(_on_weapon_selected)
	box.add_child(weapon_selector)
	var equip_row: HBoxContainer = HBoxContainer.new()
	var equip_button: Button = Button.new()
	equip_button.text = "Equip"
	equip_button.pressed.connect(_equip_selected)
	equip_row.add_child(equip_button)
	var unequip_button: Button = Button.new()
	unequip_button.text = "Unequip"
	unequip_button.pressed.connect(_unequip_weapon)
	equip_row.add_child(unequip_button)
	box.add_child(equip_row)
	var animation_row: HBoxContainer = HBoxContainer.new()
	for pair: Array in [["Idle", "idle_alert"], ["Walk", "walk"], ["Run", "run"]]:
		var button: Button = Button.new()
		button.text = String(pair[0])
		button.pressed.connect(_play_loop.bind(String(pair[1])))
		animation_row.add_child(button)
	box.add_child(animation_row)
	var attack_row: HBoxContainer = HBoxContainer.new()
	for pair: Array in [["Attack 1", "atk_slash"], ["Attack 2", "atk2_slash"]]:
		var button: Button = Button.new()
		button.text = String(pair[0])
		button.pressed.connect(_play_attack.bind(String(pair[1])))
		attack_row.add_child(button)
	box.add_child(attack_row)
	var playback_row: HBoxContainer = HBoxContainer.new()
	var pause_button: Button = Button.new()
	pause_button.text = "Pause / Resume"
	pause_button.pressed.connect(_toggle_pause)
	playback_row.add_child(pause_button)
	var slow_button: Button = Button.new()
	slow_button.text = "Slow 0.25×"
	slow_button.pressed.connect(_set_slow)
	playback_row.add_child(slow_button)
	var normal_button: Button = Button.new()
	normal_button.text = "Normal 1×"
	normal_button.pressed.connect(_set_normal)
	playback_row.add_child(normal_button)
	box.add_child(playback_row)
	var timing_row: HBoxContainer = HBoxContainer.new()
	var strike_button: Button = Button.new()
	strike_button.text = "Pause at strike"
	strike_button.pressed.connect(_pause_at_strike)
	timing_row.add_child(strike_button)
	var recover_button: Button = Button.new()
	recover_button.text = "Recovery"
	recover_button.pressed.connect(_play_recovery)
	timing_row.add_child(recover_button)
	box.add_child(timing_row)
	timeline_label = Label.new()
	timeline_label.text = "Animation time: —"
	box.add_child(timeline_label)
	timeline_slider = HSlider.new()
	timeline_slider.min_value = 0.0
	timeline_slider.max_value = 1.0
	timeline_slider.step = 0.01
	timeline_slider.value_changed.connect(_seek_preview)
	box.add_child(timeline_slider)
	var camera_row: HBoxContainer = HBoxContainer.new()
	var front_view: Button = Button.new()
	front_view.text = "Front"
	front_view.pressed.connect(_set_view.bind(0.0))
	camera_row.add_child(front_view)
	var three_quarter: Button = Button.new()
	three_quarter.text = "3/4"
	three_quarter.pressed.connect(_set_view.bind(-0.45))
	camera_row.add_child(three_quarter)
	var closer: Button = Button.new()
	closer.text = "Closer"
	closer.pressed.connect(_zoom.bind(-0.3))
	camera_row.add_child(closer)
	var farther: Button = Button.new()
	farther.text = "Farther"
	farther.pressed.connect(_zoom.bind(0.3))
	camera_row.add_child(farther)
	var reset_view: Button = Button.new()
	reset_view.text = "Reset View"
	reset_view.pressed.connect(_reset_camera)
	camera_row.add_child(reset_view)
	box.add_child(camera_row)
	var capture_button: Button = Button.new()
	capture_button.text = "Capture screenshot"
	capture_button.pressed.connect(_capture)
	box.add_child(capture_button)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	var help: Label = Label.new()
	help.text = "Keys: ←/→ weapon, I idle, W walk, R run, 1/2 attacks, Space pause, +/- zoom\nDrag background to orbit; mouse wheel zooms."
	help.position = Vector2(20.0, 680.0)
	help.add_theme_color_override("font_color", Color("#edf0e6"))
	layer.add_child(help)

func _equip_selected() -> void:
	if player == null or weapon_selector == null:
		return
	paused_preview = false
	preview_animation = ""
	player.model.anim.speed_scale = 1.0
	player.model.loop("idle_alert")
	selected_index = weapon_selector.selected
	var weapon_id: String = WEAPON_IDS[selected_index]
	var def: ItemDef = ItemDb.get_def(weapon_id)
	if def == null:
		status_label.text = "Missing ItemDef: " + weapon_id
		return
	var item: Dictionary = Items.build(def, 20, Items.Rarity.NORMAL)
	# This isolated developer scene bypasses the normal campaign's item gates; no real save is loaded or written.
	item["id"] = weapon_id
	player.stats.equipment.erase(Items.Slot.WEAPON)
	player.stats.equipment[Items.Slot.WEAPON] = item
	player.stats.refresh()
	player.refresh_weapon_model()
	player.model.loop("idle_alert")
	status_label.text = "Equipped: %s | production attached weapon: %s | holder: %s" % [def.display_name,
		String((player.stats.equipment.get(Items.Slot.WEAPON, {}) as Dictionary).get("def", "none")),
		"present" if player.model.weapon != null else "MISSING"]
	title_label.text = def.display_name + (" — two-handed" if bool(def.profile.get("two_handed", false)) else " — one-handed")

func _unequip_weapon() -> void:
	if player == null:
		return
	paused_preview = false
	preview_animation = ""
	player.model.anim.speed_scale = 1.0
	player.stats.equipment.erase(Items.Slot.WEAPON)
	player.stats.refresh()
	player.refresh_weapon_model()
	player.model.loop("idle_alert")
	status_label.text = "Unequipped | default fallback model: " + ("present" if player.model.weapon != null else "none")
	title_label.text = "Unequipped"

func _on_weapon_selected(index: int) -> void:
	selected_index = index
	_equip_selected()

func _play_loop(clip: String) -> void:
	paused_preview = false
	preview_animation = ""
	if player.model.anim.animation_finished.is_connected(_on_animation_finished):
		player.model.anim.animation_finished.disconnect(_on_animation_finished)
	preview_animation = "game/" + clip
	preview_duration = player.model.anim.get_animation(preview_animation).length
	preview_elapsed = 0.0
	preview_paused_at_strike = false
	timeline_slider.max_value = maxf(preview_duration, 0.01)
	timeline_slider.value = 0.0
	player.model.anim.speed_scale = playback_speed
	player.model.loop(clip)
	status_label.text = "Playing %s on the actual Player rig" % clip

func _play_attack(clip: String) -> void:
	if player.model.anim.animation_finished.is_connected(_on_animation_finished):
		player.model.anim.animation_finished.disconnect(_on_animation_finished)
	player.rotation.y = camera.rotation.y
	var def: ItemDef = ItemDb.get_def(WEAPON_IDS[selected_index])
	var two_hand_clips: Dictionary = def.profile.get("two_hand_clips", {}) if def != null else {}
	var configured: Dictionary = two_hand_clips.get(clip, {})
	var actual_clip: String = String(configured.get("clip", clip))
	var speed: float = playback_speed * float(configured.get("speed", 1.0))
	if not player.model.anim.has_animation("game/" + actual_clip):
		status_label.text = "Animation unavailable: " + actual_clip
		return
	paused_preview = false
	preview_animation = "game/" + actual_clip
	last_attack_animation = preview_animation
	preview_duration = player.model.anim.get_animation(preview_animation).length
	preview_elapsed = 0.0
	preview_paused_at_strike = false
	timeline_slider.max_value = maxf(preview_duration, 0.01)
	timeline_slider.value = 0.0
	player.model.once(actual_clip, 0.0, speed, 0.12)
	player.model.anim.animation_finished.connect(_on_animation_finished, CONNECT_ONE_SHOT)
	status_label.text = "Playing attack: %s (%.2fs)" % [actual_clip, preview_duration]

func _apply_preview_pose(seconds: float) -> void:
	if preview_animation.is_empty():
		return
	player.model.anim.speed_scale = 0.0
	player.model.manual(preview_animation.trim_prefix("game/"), 0.0)
	player.model.scrub(clampf(seconds, 0.0, preview_duration))
	paused_preview = true
	preview_elapsed = clampf(seconds, 0.0, preview_duration)
	timeline_slider.set_value_no_signal(preview_elapsed)
	timeline_label.text = "Animation time: %.2f / %.2fs" % [preview_elapsed, preview_duration]

func _pause_at_strike() -> void:
	if preview_animation.is_empty() and not last_attack_animation.is_empty():
		preview_animation = last_attack_animation
		preview_duration = player.model.anim.get_animation(preview_animation).length
	if preview_animation.is_empty():
		_play_attack("atk_slash")
		await get_tree().process_frame
		await get_tree().process_frame
	if preview_animation.is_empty() or preview_duration <= 0.0:
		status_label.text = "Attack clip unavailable; cannot pose at strike"
		return
	# A stable three-quarter point near contact; user can refine the exact timestamp on the slider.
	var strike_time: float = preview_duration * 0.72
	_apply_preview_pose(strike_time)
	preview_paused_at_strike = true
	status_label.text = "Paused near strike at %.2fs / %.2fs — adjust timeline if desired" % [strike_time, preview_duration]

func _play_recovery() -> void:
	if preview_animation.is_empty() and not last_attack_animation.is_empty():
		preview_animation = last_attack_animation
		preview_duration = player.model.anim.get_animation(preview_animation).length
	if preview_animation.is_empty():
		_play_attack("atk_slash")
		await get_tree().process_frame
		await get_tree().process_frame
	if preview_animation.is_empty() or preview_duration <= 0.0:
		status_label.text = "Attack clip unavailable; cannot pose in recovery"
		return
	var recovery_time: float = preview_duration * 0.88
	_apply_preview_pose(recovery_time)
	preview_paused_at_strike = false
	status_label.text = "Paused in recovery at %.2fs / %.2fs" % [recovery_time, preview_duration]

func _seek_preview(seconds: float) -> void:
	if preview_animation.is_empty() and not last_attack_animation.is_empty():
		preview_animation = last_attack_animation
		preview_duration = player.model.anim.get_animation(preview_animation).length
		timeline_slider.max_value = maxf(preview_duration, 0.01)
	if preview_animation.is_empty():
		return
	_apply_preview_pose(seconds)
	preview_paused_at_strike = false
	timeline_label.text = "Animation time: %.2f / %.2fs" % [preview_elapsed, preview_duration]
	status_label.text = "Paused at %.2fs" % preview_elapsed

func _on_animation_finished(_animation_name: StringName) -> void:
	if player != null and not paused_preview:
		player.model.loop("idle_alert")
		preview_elapsed = preview_duration
		if timeline_slider != null:
			timeline_slider.set_value_no_signal(preview_elapsed)
		status_label.text = "Attack recovered; returned to idle"
		if player.model.anim.animation_finished.is_connected(_on_animation_finished):
			player.model.anim.animation_finished.disconnect(_on_animation_finished)

func _toggle_pause() -> void:
	paused_preview = not paused_preview
	if player.model.anim.current_animation.begins_with("game/atk"):
		preview_animation = player.model.anim.current_animation
		preview_duration = player.model.anim.get_animation(preview_animation).length
		preview_elapsed = player.model.anim.current_animation_position
		timeline_slider.max_value = maxf(preview_duration, 0.01)
		timeline_slider.set_value_no_signal(preview_elapsed)
		preview_paused_at_strike = false
	if paused_preview:
		player.model.anim.speed_scale = 0.0
	else:
		player.model.anim.speed_scale = playback_speed
	status_label.text = "Animation paused" if paused_preview else "Animation resumed"

func _set_slow() -> void:
	playback_speed = 0.25
	player.model.anim.speed_scale = playback_speed
	status_label.text = "Playback speed 0.25×"

func _set_normal() -> void:
	playback_speed = 1.0
	player.model.anim.speed_scale = playback_speed
	status_label.text = "Playback speed 1×"

func _set_view(yaw: float) -> void:
	default_capture_camera = false
	orbit_yaw = yaw
	orbit_pitch = -0.03
	_sync_camera()

func _zoom(amount: float) -> void:
	default_capture_camera = false
	camera_distance = clampf(camera_distance + amount, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)
	_sync_camera()

func _reset_camera() -> void:
	default_capture_camera = true
	orbit_yaw = -0.35
	orbit_pitch = -0.06
	camera_distance = 2.6
	_sync_camera()

func _sync_camera() -> void:
	if camera == null:
		return
	var target: Vector3 = player.global_position + Vector3.UP * CAMERA_TARGET_HEIGHT if player != null else Vector3.UP
	var direction: Vector3 = Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
	camera.global_position = target + direction * camera_distance
	camera.look_at(target, Vector3.UP)

func _process(delta: float) -> void:
	if player != null and not paused_preview and player.model.anim != null:
		player.model.anim.speed_scale = playback_speed
		if not preview_animation.is_empty() and player.model.anim.current_animation == preview_animation:
			preview_elapsed = minf(player.model.anim.current_animation_position, preview_duration)
			if timeline_slider != null:
				timeline_slider.set_value_no_signal(preview_elapsed)
			if timeline_label != null:
				timeline_label.text = "Animation time: %.2f / %.2fs" % [preview_elapsed, preview_duration]
	_sync_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_zoom(-0.3)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_zoom(0.3)
		elif mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			orbit_dragging = mouse_button.pressed
	if event is InputEventMouseMotion and orbit_dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		orbit_yaw -= motion.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch - motion.relative.y * 0.004, -0.8, 0.55)
		_sync_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		match key.keycode:
			KEY_LEFT:
				weapon_selector.select(wrapi(weapon_selector.selected - 1, 0, WEAPON_IDS.size()))
				_on_weapon_selected(weapon_selector.selected)
			KEY_RIGHT:
				weapon_selector.select(wrapi(weapon_selector.selected + 1, 0, WEAPON_IDS.size()))
				_on_weapon_selected(weapon_selector.selected)
			KEY_I: _play_loop("idle_alert")
			KEY_W: _play_loop("walk")
			KEY_R: _play_loop("run")
			KEY_1: _play_attack("atk_slash")
			KEY_2: _play_attack("atk_slash_l")
			KEY_SPACE: _toggle_pause()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _zoom(-0.25)
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom(0.25)

func _capture() -> void:
	if default_capture_camera:
		orbit_yaw = -0.35
		orbit_pitch = -0.06
		camera_distance = 2.6
		_sync_camera()
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var weapon_id: String = WEAPON_IDS[selected_index]
	var current_clip: String = player.model.anim.current_animation
	var state: String = "unequipped" if title_label.text == "Unequipped" else "strike" if preview_paused_at_strike else "recovery" if paused_preview and preview_elapsed > 0.0 else "movement" if current_clip in ["game/walk", "game/run"] else "attack" if current_clip.begins_with("game/atk") else "idle" if current_clip == "game/idle_alert" else "live"
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var base_name: String = "%s_%s_%03d_%s" % [weapon_id, state, capture_counter, timestamp]
	var user_dir: String = ProjectSettings.globalize_path(CAPTURE_FOLDER)
	DirAccess.make_dir_recursive_absolute(user_dir)
	var user_path: String = user_dir.path_join(base_name + ".png")
	var user_error: Error = image.save_png(user_path)
	var review_dir: String = ProjectSettings.globalize_path(CAPTURE_REVIEW_DIR)
	DirAccess.make_dir_recursive_absolute(review_dir)
	var review_path: String = review_dir.path_join(base_name + ".png")
	var review_error: Error = image.save_png(review_path)
	status_label.text = "Saved: %s%s" % [user_path if user_error == OK else "user capture failed", " | repo: " + review_path if review_error == OK else " | repo capture failed"]
	capture_counter += 1
