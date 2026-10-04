class_name PauseMenu
extends Control
## In-game menu (Esc): resume, settings, restart, back to the main menu, quit. Pauses the game while open.

signal resumed
signal restart_requested
signal main_menu_requested

var _buttons: VBoxContainer
var _settings_holder: CenterContainer
var _settings: SettingsMenu
var _closed_frame: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 14)
	center.add_child(_buttons)
	_buttons.add_child(UiTheme.title_label("Paused", 52))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	_buttons.add_child(spacer)
	_add_button("Resume", close)
	_add_button("Settings", _open_settings)
	_add_button("Restart run", func() -> void:
		close()
		restart_requested.emit())
	_add_button("Main menu", func() -> void:
		close()
		main_menu_requested.emit())
	_add_button("Quit game", func() -> void: get_tree().quit())

	_settings_holder = CenterContainer.new()
	_settings_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_holder.visible = false
	add_child(_settings_holder)
	_settings = SettingsMenu.new()
	_settings.closed.connect(_close_settings)
	_settings_holder.add_child(_settings)

func _add_button(text: String, action: Callable) -> void:
	var button := UiTheme.button(text)
	button.pressed.connect(action)
	_buttons.add_child(button)

## True while open, and for the rest of the frame it closed in (so one Esc press cannot close then reopen it).
func is_open() -> bool:
	return visible or Engine.get_process_frames() == _closed_frame

func open() -> void:
	visible = true
	_buttons.get_parent().visible = true
	_settings_holder.visible = false
	get_tree().paused = true
	(_buttons.get_child(2) as Button).grab_focus()

func close() -> void:
	_closed_frame = Engine.get_process_frames()
	visible = false
	get_tree().paused = false
	resumed.emit()

func _open_settings() -> void:
	_buttons.get_parent().visible = false
	_settings_holder.visible = true

func _close_settings() -> void:
	_settings_holder.visible = false
	_buttons.get_parent().visible = true

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if _settings_holder.visible:
		_settings.close()
	else:
		close()
