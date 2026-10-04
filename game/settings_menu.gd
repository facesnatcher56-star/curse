class_name SettingsMenu
extends PanelContainer
## Audio / Video / Controls / Gameplay settings. Used by both the main menu and the in-game pause menu.
## Changes apply immediately and are saved when the menu is closed.

signal closed

var _tabs: TabContainer
var _binding_buttons: Dictionary = {}  # action -> keyboard/mouse binding Button
var _pad_buttons: Dictionary = {}      # action -> controller binding Button
var _listening_kind: String = "kb"
var _listening_action: String = ""
var _resolution_option: OptionButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # must work while the game is paused
	theme = UiTheme.get_theme()
	custom_minimum_size = Vector2(780, 560)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.add_child(UiTheme.title_label("Settings", 34))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_tabs.add_child(_build_audio())
	_tabs.add_child(_build_video())
	_tabs.add_child(_build_controls())
	_tabs.add_child(_build_gameplay())
	_tabs.set_tab_title(0, "Audio")
	_tabs.set_tab_title(1, "Video")
	_tabs.set_tab_title(2, "Controls")
	_tabs.set_tab_title(3, "Gameplay")
	var back := UiTheme.button("Back")
	back.pressed.connect(close)
	root.add_child(back)

func select_tab(index: int) -> void:
	_tabs.current_tab = index

func close() -> void:
	_cancel_listening()
	GameSettings.save_to_disk()
	closed.emit()

# --- building blocks ------------------------------------------------------------

func _page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	return page

func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(250, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _slider(value: float, max_value: float, on_change: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = max_value
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(240, 28)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(56, 0)
	readout.text = "%d%%" % int(round(value * 100.0))
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = "%d%%" % int(round(v * 100.0))
		on_change.call(v))
	box.add_child(slider)
	box.add_child(readout)
	return box

func _check(text: String, value: bool, on_change: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	box.toggled.connect(func(on: bool) -> void: on_change.call(on))
	return box

func _options(items: Array, selected: int, on_change: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(str(item))
	option.select(selected)
	option.item_selected.connect(func(i: int) -> void: on_change.call(i))
	return option

# --- tabs --------------------------------------------------------------------------

func _build_audio() -> Control:
	var page := _page()
	page.add_child(_row("Master volume", _slider(GameSettings.master_volume, 1.0, func(v: float) -> void:
		GameSettings.master_volume = v
		GameSettings.apply_audio())))
	page.add_child(_row("Sound effects", _check("Enabled", GameSettings.sfx_enabled, func(on: bool) -> void:
		GameSettings.sfx_enabled = on
		Sfx.enabled = on)))
	var note := Label.new()
	note.text = "Sound effects are synthesised in code. There is no music yet."
	note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	page.add_child(note)
	return page

func _build_video() -> Control:
	var page := _page()
	page.add_child(_row("Window mode", _options(GameSettings.WINDOW_MODES, GameSettings.window_mode, func(i: int) -> void:
		GameSettings.window_mode = i
		_resolution_option.disabled = i != 0
		GameSettings.apply_video())))
	var names: Array[String] = []
	for size in GameSettings.RESOLUTIONS:
		names.append("%d x %d" % [size.x, size.y])
	_resolution_option = _options(names, GameSettings.resolution_index, func(i: int) -> void:
		GameSettings.resolution_index = i
		GameSettings.apply_video())
	_resolution_option.disabled = GameSettings.window_mode != 0
	page.add_child(_row("Resolution (windowed)", _resolution_option))
	page.add_child(_row("Anti-aliasing", _options(GameSettings.MSAA_LEVELS, GameSettings.msaa_index, func(i: int) -> void:
		GameSettings.msaa_index = i
		GameSettings.apply_video())))
	page.add_child(_row("Vertical sync", _check("Enabled", GameSettings.vsync, func(on: bool) -> void:
		GameSettings.vsync = on
		GameSettings.apply_video())))
	return page

func _build_gameplay() -> Control:
	var page := _page()
	page.add_child(_row("Screen shake", _slider(GameSettings.screen_shake, 1.5, func(v: float) -> void:
		GameSettings.screen_shake = v)))
	var zoom_slider := HSlider.new()
	zoom_slider.min_value = 0.04
	zoom_slider.max_value = 0.3
	zoom_slider.step = 0.01
	zoom_slider.value = GameSettings.zoom_step
	zoom_slider.custom_minimum_size = Vector2(240, 28)
	zoom_slider.value_changed.connect(func(v: float) -> void: GameSettings.zoom_step = v)
	page.add_child(_row("Zoom sensitivity (scroll wheel)", zoom_slider))
	page.add_child(_row("Damage numbers", _check("Show", GameSettings.show_damage_numbers, func(on: bool) -> void:
		GameSettings.show_damage_numbers = on)))
	return page

func _build_controls() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := _page()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	var hint := Label.new()
	hint.text = ("Every action can be rebound on both the keyboard/mouse and the controller. Click a binding, then press the key, "
		+ "mouse button or controller button (triggers work too). Esc cancels. A binding already in use is swapped with this one. "
		+ "Aiming with a stick: hold a skill's button (e.g. Fireball) and move the aiming stick to place the target; it stays where you leave it.")
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(640, 0)
	page.add_child(hint)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(250, 0)
	header.add_child(spacer)
	for title in ["Keyboard / mouse", "Controller"]:
		var column := Label.new()
		column.text = title
		column.custom_minimum_size = Vector2(212, 0)
		column.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		header.add_child(column)
	page.add_child(header)
	for entry in GameSettings.ACTIONS:
		var action: String = entry[0]
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 12)
		var button := Button.new()
		button.custom_minimum_size = Vector2(200, 36)
		button.text = GameSettings.binding_text(action)
		button.pressed.connect(func() -> void: _start_listening(action, "kb"))
		_binding_buttons[action] = button
		pair.add_child(button)
		var pad_button := Button.new()
		pad_button.custom_minimum_size = Vector2(200, 36)
		pad_button.text = GameSettings.pad_binding_text(action)
		pad_button.pressed.connect(func() -> void: _start_listening(action, "pad"))
		_pad_buttons[action] = pad_button
		pair.add_child(pad_button)
		page.add_child(_row(entry[1], pair))
	page.add_child(_row("Swap sticks (move on right)", _check("Enabled", GameSettings.swap_sticks, func(on: bool) -> void:
		GameSettings.swap_sticks = on)))
	page.add_child(_row("Stick dead zone", _slider(GameSettings.stick_deadzone, 0.6, func(v: float) -> void:
		GameSettings.stick_deadzone = clampf(v, 0.05, 0.6))))
	page.add_child(_row("Controller vibration", _check("Enabled", GameSettings.vibration, func(on: bool) -> void:
		GameSettings.vibration = on)))
	var reset := UiTheme.button("Reset to defaults", 220)
	reset.pressed.connect(func() -> void:
		_cancel_listening()
		GameSettings.reset_bindings()
		_refresh_bindings())
	page.add_child(reset)
	return scroll

# --- rebinding --------------------------------------------------------------------

func _start_listening(action: String, kind: String = "kb") -> void:
	_cancel_listening()
	_listening_action = action
	_listening_kind = kind
	if kind == "pad":
		(_pad_buttons[action] as Button).text = "Press a button..."
	else:
		(_binding_buttons[action] as Button).text = "Press a key..."

func _cancel_listening() -> void:
	_listening_action = ""
	_refresh_bindings()

func _refresh_bindings() -> void:
	for action in _binding_buttons:
		(_binding_buttons[action] as Button).text = GameSettings.binding_text(action)
	for action in _pad_buttons:
		(_pad_buttons[action] as Button).text = GameSettings.pad_binding_text(action)

func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	if _listening_kind == "pad":
		var pad_data: Dictionary = GameSettings.pad_event_to_dict(event)
		var is_press: bool = (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed) or event is InputEventJoypadMotion
		if is_press and not pad_data.is_empty():
			get_viewport().set_input_as_handled()
			GameSettings.rebind_pad(_listening_action, event)
			_listening_action = ""
			_refresh_bindings()
		elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel_listening()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		get_viewport().set_input_as_handled()
		if key.physical_keycode == KEY_ESCAPE:
			_cancel_listening()
			return
		GameSettings.rebind(_listening_action, key)
		_listening_action = ""
		_refresh_bindings()
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed:
		# Ignore the click that started listening (it lands on the same button).
		var button: Button = _binding_buttons[_listening_action]
		if button.get_global_rect().has_point(mouse.global_position) and mouse.button_index == MOUSE_BUTTON_LEFT:
			return
		get_viewport().set_input_as_handled()
		GameSettings.rebind(_listening_action, mouse)
		_listening_action = ""
		_refresh_bindings()
