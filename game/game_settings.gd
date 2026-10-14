class_name GameSettings
extends RefCounted
## Player-facing settings: audio, video, key bindings and a few gameplay options.
## Everything is saved to user://settings.cfg and re-applied at startup by boot().

const PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const WINDOW_MODES: Array[String] = ["Windowed", "Borderless", "Fullscreen"]
const MSAA_LEVELS: Array[String] = ["Off", "2x", "4x", "8x"]
## How much of the screen resolution the 3D world is drawn at (the interface stays sharp); upscaled with FSR. The biggest lever on frame rate.
const RENDER_SCALES: Array[float] = [1.0, 0.85, 0.75, 0.67]
const RENDER_SCALE_LABELS: Array[String] = ["100% (sharpest)", "85%", "75% (steadier)", "67% (fastest)"]

## Rebindable actions in the order they are shown: [action, label].
const ACTIONS: Array = [
	["click", "Move / Attack"],
	["alt_skill", "Right-click skill"],
	["skill_1", "Hotbar 1 (Brutal Attack)"],
	["skill_2", "Hotbar 2 (Take Aim)"],
	["skill_3", "Hotbar 3"],
	["skill_4", "Hotbar 4 (Skewer)"],
	["skill_5", "Hotbar 5 (Leap)"],
	["skill_6", "Hotbar 6 (Earthshatter)"],
	["use_potion", "Use health potion"],
	["use_mana_potion", "Use mana potion"],
	["companion_attack", "Direct companion to target (A)"],
	["party_switch", "Switch active party member"],
	["dodge", "Dodge roll"],
	["stand_still", "Stand still (hold)"],
	["gear", "Open / close character and inventory"],
	["inventory_rotate", "Rotate backpack item (inventory only)"],
	["camera_rotate", "Rotate camera (hold and drag)"],
	["zoom_in", "Camera zoom in"],
	["zoom_out", "Camera zoom out"],
	["interact", "Talk / use (in town)"],
	["chronicle", "Chronicle (events and threats)"],
	["pause", "Pause menu"],
	["restart", "Restart after death"],
]

## Controller options (see Gamepad).
static var swap_sticks: bool = false       # move on the right stick, aim on the left
static var stick_deadzone: float = 0.22
static var vibration: bool = true
## Controller button rebinds: action -> {"type": "button", "code": n} or {"type": "axis", "axis": n} (triggers).
static var custom_pad_bindings: Dictionary = {}

static var master_volume: float = 0.8
static var sfx_enabled: bool = true
static var window_mode: int = 0
static var resolution_index: int = 0   # index into RESOLUTIONS: the player's choice; the offered list depends on the monitor (see effective_resolution_index)
static var monitor_index: int = -1     # -1 = never chosen, so the primary monitor is used
static var monitor_rect: Rect2i = Rect2i()   # the chosen monitor's position and size: a reordered or unplugged monitor is not mistaken for another
## Where settings are read and written. Only tests change this (to an isolated file); the game always uses PATH.
static var settings_path: String = PATH
static var vsync: bool = true
static var render_scale_index: int = 1   # 85% by default: the Steam Deck cannot hold 60 at full resolution in a crowded fight
static var msaa_index: int = 0   # off by default: MSAA cost a couple of ms a frame on the Steam Deck
static var ui_size: float = 1.0   # the player's own multiplier on how big the interface is (on top of the resolution-aware default)
static var _watching_size: bool = false
static var screen_shake: float = 1.0
static var show_damage_numbers: bool = true
static var slow_motion: bool = true   # brief slow-motion on the biggest hits (Skewer kick, Earthshatter)
static var zoom_step: float = 0.12   # camera zoom change per wheel notch

## action -> {"type": "key"|"mouse", "code": int}. Only actions the player changed are stored here.
static var custom_bindings: Dictionary = {}
## Which skill is on which key (see HotbarLayout). SkillController shares `hotbar_slots` itself, so a change here is a change there.
static var hotbar_slots: Array[String] = HotbarLayout.DEFAULT_SLOTS.duplicate()
static var hotbar_alt: String = HotbarLayout.DEFAULT_ALT
const HOTBAR_LAYOUT_REV := 4

static func reset_hotbar() -> void:
	# SkillController deliberately keeps this exact Array reference. Reset its
	# contents in place so an already-spawned hero immediately sees the defaults.
	hotbar_slots.resize(HotbarLayout.DEFAULT_SLOTS.size())
	for i in HotbarLayout.DEFAULT_SLOTS.size():
		hotbar_slots[i] = HotbarLayout.DEFAULT_SLOTS[i]
	hotbar_alt = HotbarLayout.DEFAULT_ALT

## Moves a skill onto a slot (a swap with wherever it was) and saves, so the layout is kept for next time. Not saved during self-tests.
static func assign_hotbar(slot: int, id: String) -> void:
	var body := PartyManager.current().active_body()
	if body != null:
		body.skills.assign_slot(slot, id)
		return
	hotbar_alt = HotbarLayout.assign(hotbar_slots, hotbar_alt, slot, id)
	if not OS.get_cmdline_user_args().has("--selftest"):
		save_to_disk()

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

## The interface is laid out for a 1280 x 720 window and scales with the window, but not all the way: the bigger the window, the smaller
## the interface is as a share of the screen (a quarter of the window's growth is not applied), so it never swallows a big monitor.
## `ui_size` is the player's own adjustment on top.
static func apply_ui_scale() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var fitted: float = maxf(minf(float(root.size.x) / 1280.0, float(root.size.y) / 720.0), 0.01)
	root.content_scale_factor = clampf(pow(fitted, -0.45) * ui_size, 0.3, 3.0)

static func apply_video() -> void:
	if not _watching_size:
		_watching_size = true
		var main_window: Window = (Engine.get_main_loop() as SceneTree).root
		main_window.size_changed.connect(apply_ui_scale)
		main_window.focus_entered.connect(recover_monitor)   # event-driven, not polled: see recover_monitor
	apply_ui_scale()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var scale: float = RENDER_SCALES[clampi(render_scale_index, 0, RENDER_SCALES.size() - 1)]
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = scale
	root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][msaa_index]
	if DisplayServer.get_name() == "headless" or monitor_rects().is_empty():
		return
	var screen: int = apply_monitor()
	var full: Rect2i = Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	match window_mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			# A window fits the usable area (the display minus the taskbar), so it never sits under the taskbar.
			var area: Rect2i = area_for_mode(true, full, usable)
			var size: Vector2i = RESOLUTIONS[effective_resolution_index(area.size)]
			size = Vector2i(mini(size.x, area.size.x), mini(size.y, area.size.y))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(area.position + (area.size - size) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			# Borderless covers the whole display, so it uses the full size (not the usable area).
			DisplayServer.window_set_size(full.size)
			DisplayServer.window_set_position(full.position)
		2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

# --- monitors ------------------------------------------------------------------------
# IMPORTANT: resolution choices are a FILTERED LIST OF FIXED PRESETS (RESOLUTIONS) that fit the chosen monitor. They are not the monitor's
# hardware mode list: Godot 4 does not report one, so a monitor's supported modes cannot be shown. Windowed presets must fit the monitor's
# usable area (excluding the taskbar); fullscreen and borderless use the full display size.
# Monitors are read when needed (startup, menu open, window focus) and are not watched for changes.

## Position and size of every monitor the OS reports, in desktop coordinates. Empty without a real display (headless).
static func monitor_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if DisplayServer.get_name() == "headless":
		return out
	for i in DisplayServer.get_screen_count():
		out.append(Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)))
	return out

static func primary_monitor() -> int:
	if DisplayServer.get_name() == "headless":
		return 0
	return DisplayServer.get_primary_screen()

## Which monitor to use. A saved rectangle must still match one of the monitors, otherwise the primary one is used (the saved index may now
## point at a different screen). With nothing saved, the index is used if it is valid, else the primary monitor.
static func resolve_monitor(saved_index: int, saved_rect: Rect2i, rects: Array[Rect2i], primary: int) -> int:
	if rects.is_empty():
		return 0
	var fallback: int = clampi(primary, 0, rects.size() - 1)
	if saved_rect.size != Vector2i.ZERO:
		var found: int = rects.find(saved_rect)
		return found if found >= 0 else fallback
	if saved_index >= 0 and saved_index < rects.size():
		return saved_index
	return fallback

## "Display 0: 3440 x 1440 (primary)". The number is Godot's screen index (the order DisplayServer reports). Godot gives no reliable mapping
## to Windows display numbers or monitor model names, so neither is shown.
static func monitor_names(rects: Array[Rect2i], primary: int) -> Array[String]:
	var out: Array[String] = []
	for i in rects.size():
		var label: String = "Display %d: %d x %d" % [i, rects[i].size.x, rects[i].size.y]
		if i == primary:
			label += " (primary)"
		out.append(label)
	return out

## Indices into RESOLUTIONS that fit a monitor of this size. Never empty: when even the smallest preset does not fit, it is offered and
## the window is clamped to the monitor when it is opened.
static func fitting_resolution_indices(monitor_size: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i].x <= monitor_size.x and RESOLUTIONS[i].y <= monitor_size.y:
			out.append(i)
	if out.is_empty():
		out.append(0)
	return out

## The player's saved choice when it fits this monitor; otherwise the largest preset that does (so a bigger monitor gets the choice back).
static func effective_resolution_index(monitor_size: Vector2i) -> int:
	var allowed: Array[int] = fitting_resolution_indices(monitor_size)
	if allowed.has(resolution_index):
		return resolution_index
	return allowed[allowed.size() - 1]

## The monitor in use right now, resolved from the saved choice (no change is made to the window).
static func current_monitor_index() -> int:
	return resolve_monitor(monitor_index, monitor_rect, monitor_rects(), primary_monitor())

## The area resolution presets must fit: the usable area for windowed, the full display otherwise.
static func area_for_mode(windowed: bool, full: Rect2i, usable: Rect2i) -> Rect2i:
	return usable if windowed else full

## Full and usable rectangles of one screen (Rect2i() when there is no such screen).
static func monitor_area(index: int, windowed: bool) -> Rect2i:
	if DisplayServer.get_name() == "headless" or index < 0 or index >= DisplayServer.get_screen_count():
		return Rect2i()
	var full: Rect2i = Rect2i(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index))
	return area_for_mode(windowed, full, DisplayServer.screen_get_usable_rect(index))

static func current_monitor_size(windowed: bool) -> Vector2i:
	return monitor_area(current_monitor_index(), windowed).size

## True when the window must be moved: the chosen monitor is gone, or the window is on no valid screen. Pure, so it can be tested.
static func needs_recovery(chosen: Rect2i, rects: Array[Rect2i], current_screen: int) -> bool:
	if rects.is_empty():
		return false
	if current_screen < 0 or current_screen >= rects.size():
		return true
	return chosen.size != Vector2i.ZERO and not rects.has(chosen)

## Runs when the game window gains focus (an event, not a timer), and can be called after a display change. If the chosen monitor was
## disconnected, apply_video moves the window to the primary monitor (see resolve_monitor). Nothing is changed when all is well.
static func recover_monitor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if needs_recovery(monitor_rect, monitor_rects(), DisplayServer.window_get_current_screen()):
		apply_video()

## Monitor names for the settings menu; a single placeholder without a display.
static func monitor_names_now() -> Array[String]:
	var rects: Array[Rect2i] = monitor_rects()
	if rects.is_empty():
		return ["Current display"]
	return monitor_names(rects, primary_monitor())

## True when the chosen monitor is no longer connected, so the window was moved to a fallback monitor.
static func monitor_missing() -> bool:
	var rects: Array[Rect2i] = monitor_rects()
	return not rects.is_empty() and monitor_rect.size != Vector2i.ZERO and not rects.has(monitor_rect)

## The player picked a monitor in the settings menu. The change is applied (and saved on close) through apply_video.
static func select_monitor(index: int) -> void:
	var rects: Array[Rect2i] = monitor_rects()
	if index < 0 or index >= rects.size():
		return
	monitor_index = index
	monitor_rect = rects[index]
	apply_video()

## Resolves the monitor, records it as the chosen one and moves the window onto it (leaving exclusive fullscreen first, if needed).
static func apply_monitor() -> int:
	var rects: Array[Rect2i] = monitor_rects()
	var screen: int = resolve_monitor(monitor_index, monitor_rect, rects, primary_monitor())
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(screen)
	monitor_index = screen
	monitor_rect = rects[screen]
	return screen

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

# --- controller bindings ---------------------------------------------------------------

const PAD_BUTTON_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start", 7: "L3", 8: "R3", 9: "LB",
	10: "RB", 11: "D-Up", 12: "D-Down", 13: "D-Left", 14: "D-Right"}
const PAD_AXIS_NAMES := {4: "LT", 5: "RT"}

static func pad_event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadButton:
		return {"type": "button", "code": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if PAD_AXIS_NAMES.has(int(motion.axis)) and motion.axis_value > 0.5:
			return {"type": "axis", "axis": int(motion.axis)}
	return {}

static func dict_to_pad_event(data: Dictionary) -> InputEvent:
	if data.get("type") == "button":
		var button := InputEventJoypadButton.new()
		button.device = -1   # any controller
		button.button_index = int(data["code"]) as JoyButton
		return button
	if data.get("type") == "axis":
		var motion := InputEventJoypadMotion.new()
		motion.device = -1
		motion.axis = int(data["axis"]) as JoyAxis
		motion.axis_value = 1.0
		return motion
	return null

static func _pad_events(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			out.append(event)
	return out

static func _erase_pad(action: String) -> void:
	for event in _pad_events(action):
		InputMap.action_erase_event(action, event)

## "A", "RT", "D-Up" ... or "Unbound".
static func pad_binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	var events: Array[InputEvent] = _pad_events(action)
	if events.is_empty():
		return "Unbound"
	var event: InputEvent = events[0]
	if event is InputEventJoypadButton:
		return PAD_BUTTON_NAMES.get(int((event as InputEventJoypadButton).button_index), "Button %d" % int((event as InputEventJoypadButton).button_index))
	return PAD_AXIS_NAMES.get(int((event as InputEventJoypadMotion).axis), "Axis")

## Rebinds the controller button of `action`. A button already used by another action swaps with it, so nothing is lost silently.
static func rebind_pad(action: String, event: InputEvent) -> void:
	var new_data: Dictionary = pad_event_to_dict(event)
	if new_data.is_empty():
		return
	var old_events: Array[InputEvent] = _pad_events(action)
	var old_data: Dictionary = pad_event_to_dict(old_events[0]) if not old_events.is_empty() else {}
	for other in ACTIONS:
		var other_action: String = other[0]
		if other_action == action:
			continue
		var other_events: Array[InputEvent] = _pad_events(other_action)
		if not other_events.is_empty() and pad_event_to_dict(other_events[0]) == new_data:
			if old_data.is_empty():
				_erase_pad(other_action)
				custom_pad_bindings[other_action] = {}
			else:
				_set_pad_binding(other_action, old_data)
	_set_pad_binding(action, new_data)

static func _set_pad_binding(action: String, data: Dictionary) -> void:
	custom_pad_bindings[action] = data
	_erase_pad(action)
	var event: InputEvent = dict_to_pad_event(data)
	if event != null:
		InputMap.action_add_event(action, event)

## The keyboard/mouse events of an action (its controller buttons are kept separately and never rebound here).
static func _kb_events(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			out.append(event)
	return out

static func _erase_kb(action: String) -> void:
	for event in _kb_events(action):
		InputMap.action_erase_event(action, event)

static func apply_bindings() -> void:
	for action in custom_pad_bindings:
		var pad_event: InputEvent = dict_to_pad_event(custom_pad_bindings[action])
		if InputMap.has_action(action):
			_erase_pad(action)
			if pad_event != null:
				InputMap.action_add_event(action, pad_event)
	for action in custom_bindings:
		var event: InputEvent = dict_to_event(custom_bindings[action])
		if event != null and InputMap.has_action(action):
			_erase_kb(action)
			InputMap.action_add_event(action, event)

## Human-readable binding for an action ("1", "Space", "Mouse Right").
static func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	var events: Array[InputEvent] = _kb_events(action)
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
	if Gamepad.active and pad_binding_text(action) not in ["Unbound", "-"]:
		return pad_binding_text(action)
	return binding_text(action).replace("Mouse Left", "LMB").replace("Mouse Right", "RMB").replace("Mouse Middle", "MMB") \
		.replace("Wheel Up", "Wh+").replace("Wheel Down", "Wh-")

## Rebinds `action` to `event`. If another action already uses it, the two swap, so nothing is lost silently.
static func rebind(action: String, event: InputEvent) -> void:
	var new_data: Dictionary = event_to_dict(event)
	if new_data.is_empty():
		return
	var old_events: Array[InputEvent] = _kb_events(action)
	var old_data: Dictionary = event_to_dict(old_events[0]) if not old_events.is_empty() else {}
	for other in ACTIONS:
		var other_action: String = other[0]
		if other_action == action:
			continue
		var other_events: Array[InputEvent] = _kb_events(other_action)
		if not other_events.is_empty() and event_to_dict(other_events[0]) == new_data:
			if old_data.is_empty():
				_erase_kb(other_action)
				custom_bindings[other_action] = {}
			else:
				_set_binding(other_action, old_data)
	_set_binding(action, new_data)

static func _set_binding(action: String, data: Dictionary) -> void:
	custom_bindings[action] = data
	_erase_kb(action)
	var event: InputEvent = dict_to_event(data)
	if event != null:
		InputMap.action_add_event(action, event)

static func reset_bindings() -> void:
	custom_bindings.clear()
	custom_pad_bindings.clear()
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		InputMap.erase_action(action)
	InputSetup.apply()

# --- persistence -------------------------------------------------------------------

## `path` (or settings_path when empty) is the file written. Tests set settings_path or pass a path; the game uses PATH.
static func save_to_disk(path: String = "") -> void:
	var target: String = path if path != "" else settings_path
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	config.set_value("video", "window_mode", window_mode)
	config.set_value("video", "resolution_index", resolution_index)
	config.set_value("video", "monitor_index", monitor_index)
	config.set_value("video", "monitor_rect", monitor_rect)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "msaa_index", msaa_index)
	config.set_value("video", "render_scale_index", render_scale_index)
	config.set_value("video", "ui_size", ui_size)
	config.set_value("gameplay", "screen_shake", screen_shake)
	config.set_value("gameplay", "show_damage_numbers", show_damage_numbers)
	config.set_value("gameplay", "slow_motion", slow_motion)
	config.set_value("gameplay", "zoom_step", zoom_step)
	config.set_value("controller", "swap_sticks", swap_sticks)
	config.set_value("controller", "stick_deadzone", stick_deadzone)
	config.set_value("controller", "vibration", vibration)
	config.set_value("hotbar", "slots", hotbar_slots.duplicate())
	config.set_value("hotbar", "alt", hotbar_alt)
	config.set_value("hotbar", "layout_rev", HOTBAR_LAYOUT_REV)
	for action in custom_bindings:
		config.set_value("input", action, custom_bindings[action])
	for action in custom_pad_bindings:
		config.set_value("input_pad", action, custom_pad_bindings[action])
	config.save(target)

static func load_from_disk(path: String = "") -> void:
	var config := ConfigFile.new()
	if config.load(path if path != "" else settings_path) != OK:
		return
	master_volume = float(config.get_value("audio", "master_volume", master_volume))
	sfx_enabled = bool(config.get_value("audio", "sfx_enabled", sfx_enabled))
	window_mode = clampi(int(config.get_value("video", "window_mode", window_mode)), 0, WINDOW_MODES.size() - 1)
	resolution_index = clampi(int(config.get_value("video", "resolution_index", resolution_index)), 0, RESOLUTIONS.size() - 1)
	monitor_index = int(config.get_value("video", "monitor_index", monitor_index))
	var saved_rect: Variant = config.get_value("video", "monitor_rect", Rect2i())
	monitor_rect = saved_rect if saved_rect is Rect2i else Rect2i()
	vsync = bool(config.get_value("video", "vsync", vsync))
	msaa_index = int(config.get_value("video", "msaa_index", msaa_index))
	render_scale_index = clampi(int(config.get_value("video", "render_scale_index", render_scale_index)), 0, RENDER_SCALES.size() - 1)
	ui_size = clampf(float(config.get_value("video", "ui_size", ui_size)), 0.5, 1.5)
	screen_shake = float(config.get_value("gameplay", "screen_shake", screen_shake))
	show_damage_numbers = bool(config.get_value("gameplay", "show_damage_numbers", show_damage_numbers))
	slow_motion = bool(config.get_value("gameplay", "slow_motion", slow_motion))
	zoom_step = float(config.get_value("gameplay", "zoom_step", zoom_step))
	swap_sticks = bool(config.get_value("controller", "swap_sticks", swap_sticks))
	stick_deadzone = float(config.get_value("controller", "stick_deadzone", stick_deadzone))
	vibration = bool(config.get_value("controller", "vibration", vibration))
	var saved_slots: Array = config.get_value("hotbar", "slots", [])
	var saved_alt: String = String(config.get_value("hotbar", "alt", HotbarLayout.DEFAULT_ALT))
	var hotbar_rev: int = int(config.get_value("hotbar", "layout_rev", 0))
	if hotbar_rev >= HOTBAR_LAYOUT_REV and HotbarLayout.is_valid(saved_slots, saved_alt):
		for i in hotbar_slots.size():
			hotbar_slots[i] = String(saved_slots[i])
		hotbar_alt = saved_alt
	else:
		reset_hotbar()
	custom_pad_bindings.clear()
	if config.has_section("input_pad"):
		for action in config.get_section_keys("input_pad"):
			var pad_data: Variant = config.get_value("input_pad", action)
			if pad_data is Dictionary and not (pad_data as Dictionary).is_empty():
				custom_pad_bindings[action] = pad_data
	custom_bindings.clear()
	if config.has_section("input"):
		for action in config.get_section_keys("input"):
			var data: Variant = config.get_value("input", action)
			if data is Dictionary and not (data as Dictionary).is_empty():
				custom_bindings[action] = data
