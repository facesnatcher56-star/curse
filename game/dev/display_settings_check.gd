extends SceneTree
## Focused headless check for the monitor and resolution settings: monitor labels, windowed (usable area) versus fullscreen and
## borderless (full display) sizing, the resolution fallback, the missing-monitor fallback and recovery, save/load persistence, and
## settings-file isolation. Never writes the real settings file. Stops at the first failing check.
## Run: godot --headless --path . --script res://game/dev/display_settings_check.gd

const TEST_PATH := "user://display_settings_check.cfg"
const LEFT := Rect2i(Vector2i(0, 0), Vector2i(3440, 1440))
const RIGHT := Rect2i(Vector2i(4300, 205), Vector2i(2400, 1350))
## The same monitor with a taskbar: usable area is shorter than the full display.
const RIGHT_USABLE := Rect2i(Vector2i(4300, 205), Vector2i(2400, 1290))

func _init() -> void:
	var checks: Array[Callable] = [_check_monitor_names, _check_mode_sizing, _check_resolution_fallback,
		_check_missing_monitor_fallback, _check_recovery, _check_round_trip, _check_isolation]
	var passed: int = 0
	for check in checks:
		var error: String = check.call()
		if error != "":
			print("DISPLAY_CHECK FAIL ", error)
			print("DISPLAY_CHECK RESULT FAILED after %d of %d checks" % [passed, checks.size()])
			quit(1)
			return
		passed += 1
		print("DISPLAY_CHECK ok ", check.get_method())
	print("DISPLAY_CHECK RESULT PASSED %d of %d checks" % [passed, checks.size()])
	quit(0)

func _check_monitor_names() -> String:
	var names: Array[String] = GameSettings.monitor_names([LEFT, RIGHT], 0)
	if names != ["Display 0: 3440 x 1440 (primary)", "Display 1: 2400 x 1350"]:
		return "monitor names were %s" % str(names)
	if GameSettings.monitor_names([], 0).size() != 0:
		return "no monitors should give no names"
	return ""

## Windowed presets fit the usable area; fullscreen and borderless use the full display.
func _check_mode_sizing() -> String:
	if GameSettings.area_for_mode(true, RIGHT, RIGHT_USABLE) != RIGHT_USABLE:
		return "windowed area is not the usable area"
	if GameSettings.area_for_mode(false, RIGHT, RIGHT_USABLE) != RIGHT:
		return "fullscreen/borderless area is not the full display"
	# A usable area 1000 high cannot hold 1920 x 1080 windowed, but the full display (1350 high) can.
	var short_usable := Rect2i(RIGHT.position, Vector2i(2400, 1000))
	if GameSettings.fitting_resolution_indices(GameSettings.area_for_mode(true, RIGHT, short_usable).size) != [0, 1]:
		return "windowed presets did not use the usable height"
	if GameSettings.fitting_resolution_indices(GameSettings.area_for_mode(false, RIGHT, short_usable).size) != [0, 1, 2]:
		return "fullscreen presets did not use the full height"
	if GameSettings.fitting_resolution_indices(RIGHT_USABLE.size) != [0, 1, 2]:
		return "1920 x 1080 should fit a 1290-high usable area"
	return ""

func _check_resolution_fallback() -> String:
	var saved: int = GameSettings.resolution_index
	var error: String = ""
	# 2400 x 1350 monitor: 2560 x 1440 does not fit, so 1280, 1600 and 1920 are offered.
	if GameSettings.fitting_resolution_indices(RIGHT.size) != [0, 1, 2]:
		error = "2400 x 1350 offered %s" % str(GameSettings.fitting_resolution_indices(RIGHT.size))
	elif GameSettings.fitting_resolution_indices(LEFT.size) != [0, 1, 2, 3]:
		error = "3440 x 1440 offered %s" % str(GameSettings.fitting_resolution_indices(LEFT.size))
	else:
		# Saved 2560 x 1440 on the 2400 x 1350 monitor falls back to the largest that fits (1920 x 1080). The saved choice itself is kept.
		GameSettings.resolution_index = 3
		if GameSettings.effective_resolution_index(RIGHT.size) != 2:
			error = "2560 x 1440 did not fall back to 1920 x 1080 on a 2400 x 1350 monitor"
		elif GameSettings.resolution_index != 3:
			error = "fallback changed the saved resolution choice"
		elif GameSettings.effective_resolution_index(LEFT.size) != 3:
			error = "saved 2560 x 1440 was not used on the 3440 x 1440 monitor"
		else:
			# A saved choice that fits is used as is.
			GameSettings.resolution_index = 1
			if GameSettings.effective_resolution_index(RIGHT.size) != 1:
				error = "a fitting saved resolution was not used"
			elif GameSettings.fitting_resolution_indices(Vector2i(1000, 600)) != [0]:
				# A monitor smaller than every preset: the smallest is offered, never an empty list.
				error = "tiny monitor offered %s" % str(GameSettings.fitting_resolution_indices(Vector2i(1000, 600)))
	GameSettings.resolution_index = saved
	return error

func _check_missing_monitor_fallback() -> String:
	# Saved on the right monitor, which is now unplugged: the primary (left) monitor is used.
	if GameSettings.resolve_monitor(1, RIGHT, [LEFT], 0) != 0:
		return "unplugged saved monitor did not fall back to the primary"
	# Monitor order changed: the saved monitor is found by its position and size, not its old index.
	if GameSettings.resolve_monitor(1, RIGHT, [RIGHT, LEFT], 1) != 0:
		return "reordered monitors did not find the saved monitor"
	# Nothing saved yet: primary monitor.
	if GameSettings.resolve_monitor(-1, Rect2i(), [LEFT, RIGHT], 1) != 1:
		return "first run did not use the primary monitor"
	# Saved index with no saved rectangle is still a valid index.
	if GameSettings.resolve_monitor(1, Rect2i(), [LEFT, RIGHT], 0) != 1:
		return "saved index without a rectangle was not used"
	# A saved index that no longer exists falls back to the primary.
	if GameSettings.resolve_monitor(5, Rect2i(), [LEFT, RIGHT], 0) != 0:
		return "out-of-range saved index did not fall back to the primary"
	if GameSettings.resolve_monitor(0, LEFT, [], 0) != 0:
		return "no monitors should resolve to 0"
	return ""

## Recovery runs only on a real problem: the chosen monitor is gone, or the window is on no valid screen.
func _check_recovery() -> String:
	if not GameSettings.needs_recovery(RIGHT, [LEFT], 0):
		return "chosen monitor was unplugged but no recovery was requested"
	if not GameSettings.needs_recovery(LEFT, [LEFT, RIGHT], 5):
		return "window on an invalid screen index was not recovered"
	if GameSettings.needs_recovery(LEFT, [LEFT, RIGHT], 1):
		return "recovery requested although the chosen monitor and screen are valid"
	if GameSettings.needs_recovery(Rect2i(), [LEFT], 0):
		return "recovery requested with no monitor chosen"
	if GameSettings.needs_recovery(RIGHT, [], 0):
		return "recovery requested without a display"
	return ""

func _check_round_trip() -> String:
	var saved_monitor: int = GameSettings.monitor_index
	var saved_rect: Rect2i = GameSettings.monitor_rect
	var saved_resolution: int = GameSettings.resolution_index
	var saved_mode: int = GameSettings.window_mode
	GameSettings.monitor_index = 1
	GameSettings.monitor_rect = RIGHT
	GameSettings.resolution_index = 3
	GameSettings.window_mode = 2
	GameSettings.save_to_disk(TEST_PATH)
	GameSettings.monitor_index = -1
	GameSettings.monitor_rect = Rect2i()
	GameSettings.resolution_index = 0
	GameSettings.window_mode = 0
	GameSettings.load_from_disk(TEST_PATH)
	var error: String = ""
	if GameSettings.monitor_index != 1 or GameSettings.monitor_rect != RIGHT:
		error = "monitor did not survive a save and load (index %d, rect %s)" % [GameSettings.monitor_index, str(GameSettings.monitor_rect)]
	elif GameSettings.resolution_index != 3 or GameSettings.window_mode != 2:
		error = "resolution or window mode did not survive a save and load"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	GameSettings.monitor_index = saved_monitor
	GameSettings.monitor_rect = saved_rect
	GameSettings.resolution_index = saved_resolution
	GameSettings.window_mode = saved_mode
	return error

## Saving with the test path set writes only that file, never the real settings file (its modification time must not change).
func _check_isolation() -> String:
	var real_path: String = GameSettings.PATH
	var real_before: int = FileAccess.get_modified_time(real_path) if FileAccess.file_exists(real_path) else -1
	var saved_path: String = GameSettings.settings_path
	GameSettings.settings_path = TEST_PATH
	GameSettings.save_to_disk()
	var wrote_test: bool = FileAccess.file_exists(TEST_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	GameSettings.settings_path = saved_path
	var real_after: int = FileAccess.get_modified_time(real_path) if FileAccess.file_exists(real_path) else -1
	if not wrote_test:
		return "save with settings_path set did not write the isolated file"
	if real_after != real_before:
		return "the real settings file was modified by an isolated save"
	if GameSettings.settings_path != GameSettings.PATH:
		return "settings_path was not restored"
	return ""

