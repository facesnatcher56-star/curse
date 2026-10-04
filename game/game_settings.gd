class_name GameSettings
extends RefCounted
## Player-facing settings: audio, video, key bindings and a few gameplay options.
## Everything is saved to user://settings.cfg and re-applied at startup by boot().

const PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const WINDOW_MODES: Array[String] = ["Windowed", "Borderless", "Fullscreen"]
const MSAA_LEVELS: Array[String] = ["Off", "2x", "4x", "8x"]

## Rebindable actions in the order they are shown: [action, label].
const ACTIONS: Array = [
	["click", "Move / Attack"],
	["alt_skill", "Right-click skill"],
	["skill_1", "Hotbar 1 (Power Strike)"],
	["skill_2", "Hotbar 2 (Cleave)"],
	["skill_3", "Hotbar 3 (Fireball)"],
	["skill_4", "Hotbar 4 (Potion)"],
	["skill_5", "Hotbar 5 (Skewer)"],
	["skill_6", "Hotbar 6 (Leap)"],
	["dodge", "Dodge roll"],
	["stand_still", "Stand still (hold)"],
	["gear", "Show gear (hold)"],
	["zoom_in", "Camera zoom in"],
	["zoom_out", "Camera zoom out"],
	["pause", "Pause menu"],
	["restart", "Restart after death"],
]

static var master_volume: float = 0.8
static var sfx_enabled: bool = false
static var window_mode: int = 0
static var resolution_index: int = 0
static var vsync: bool = true
static var msaa_index: int = 2
static var screen_shake: float = 1.0
static var show_damage_numbers: bool = true
static var zoom_step: float = 0.12   # camera zoom change per wheel notch

## action -> {"type": "key"|"mouse", "code": int}. Only actions the player changed are stored here.
static var custom_bindings: Dictionary = {}

## Call once at startup (menu and game scenes both do): loads, registers inputs, applies everything.
static func boot() -> void:
	load_from_disk()
	InputSetup.apply()
	apply_bindings()
	apply_all()

static func apply_all() -> void:
	apply_audio()
	apply_video()
	Sfx.enabled = sfx_enabled

static func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)

static func apply_video() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][msaa_index]
	if DisplayServer.get_name() == "headless":
		return
	var screen: int = DisplayServer.window_get_current_screen()
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen)
	match window_mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var size: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
			size = Vector2i(mini(size.x, screen_size.x), mini(size.y, screen_size.y))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen_pos + (screen_size - size) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(screen_size)
			DisplayServer.window_set_position(screen_pos)
		2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

# --- key bindings ---------------------------------------------------------------

static func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "code": int((event as InputEventKey).physical_keycode)}
	if event is InputEventMouseButton:
		return {"type": "mouse", "code": int((event as InputEventMouseButton).button_index)}
	return {}

static func dict_to_event(data: Dictionary) -> InputEvent:
	if data.get("type") == "key":
		var key := InputEventKey.new()
		key.physical_keycode = int(data["code"]) as Key
		return key
	if data.get("type") == "mouse":
		var mouse := InputEventMouseButton.new()
		mouse.button_index = int(data["code"]) as MouseButton
		return mouse
	return null

static func apply_bindings() -> void:
	for action in custom_bindings:
		var event: InputEvent = dict_to_event(custom_bindings[action])
		if event != null and InputMap.has_action(action):
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, event)

## Human-readable binding for an action ("1", "Space", "Mouse Right").
static func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		return "Unbound"
	var event: InputEvent = events[0]
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Mouse Left"
			MOUSE_BUTTON_RIGHT:
				return "Mouse Right"
			MOUSE_BUTTON_MIDDLE:
				return "Mouse Middle"
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel Down"
		return "Mouse %d" % (event as InputEventMouseButton).button_index
	if event is InputEventKey:
		var key := event as InputEventKey
		return OS.get_keycode_string(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	return event.as_text()

## Compact version for small UI (hotbar key hints).
static func short_binding_text(action: String) -> String:
	return binding_text(action).replace("Mouse Left", "LMB").replace("Mouse Right", "RMB").replace("Mouse Middle", "MMB") \
		.replace("Wheel Up", "Wh+").replace("Wheel Down", "Wh-")

## Rebinds `action` to `event`. If another action already uses it, the two swap, so nothing is lost silently.
static func rebind(action: String, event: InputEvent) -> void:
	var new_data: Dictionary = event_to_dict(event)
	if new_data.is_empty():
		return
	var old_events: Array[InputEvent] = InputMap.action_get_events(action)
	var old_data: Dictionary = event_to_dict(old_events[0]) if not old_events.is_empty() else {}
	for other in ACTIONS:
		var other_action: String = other[0]
		if other_action == action:
			continue
		var other_events: Array[InputEvent] = InputMap.action_get_events(other_action)
		if not other_events.is_empty() and event_to_dict(other_events[0]) == new_data:
			if old_data.is_empty():
				InputMap.action_erase_events(other_action)
				custom_bindings[other_action] = {}
			else:
				_set_binding(other_action, old_data)
	_set_binding(action, new_data)

static func _set_binding(action: String, data: Dictionary) -> void:
	custom_bindings[action] = data
	InputMap.action_erase_events(action)
	var event: InputEvent = dict_to_event(data)
	if event != null:
		InputMap.action_add_event(action, event)

static func reset_bindings() -> void:
	custom_bindings.clear()
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		InputMap.erase_action(action)
	InputSetup.apply()

# --- persistence -------------------------------------------------------------------

static func save_to_disk() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	config.set_value("video", "window_mode", window_mode)
	config.set_value("video", "resolution_index", resolution_index)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "msaa_index", msaa_index)
	config.set_value("gameplay", "screen_shake", screen_shake)
	config.set_value("gameplay", "show_damage_numbers", show_damage_numbers)
	config.set_value("gameplay", "zoom_step", zoom_step)
	for action in custom_bindings:
		config.set_value("input", action, custom_bindings[action])
	config.save(PATH)

static func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	master_volume = float(config.get_value("audio", "master_volume", master_volume))
	sfx_enabled = bool(config.get_value("audio", "sfx_enabled", sfx_enabled))
	window_mode = int(config.get_value("video", "window_mode", window_mode))
	resolution_index = int(config.get_value("video", "resolution_index", resolution_index))
	vsync = bool(config.get_value("video", "vsync", vsync))
	msaa_index = int(config.get_value("video", "msaa_index", msaa_index))
	screen_shake = float(config.get_value("gameplay", "screen_shake", screen_shake))
	show_damage_numbers = bool(config.get_value("gameplay", "show_damage_numbers", show_damage_numbers))
	zoom_step = float(config.get_value("gameplay", "zoom_step", zoom_step))
	custom_bindings.clear()
	if config.has_section("input"):
		for action in config.get_section_keys("input"):
			var data: Variant = config.get_value("input", action)
			if data is Dictionary and not (data as Dictionary).is_empty():
				custom_bindings[action] = data
