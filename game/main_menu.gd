extends Node3D
## Main menu: the knight standing in the ruins with zombies watching from the dark, plus Play / Settings / Quit.

const GAME_SCENE := "res://game/main.tscn"
const KNIGHT_DIR := "res://assets/models/knight2"
const ZOMBIE_DIR := "res://assets/models/zombie"

var _camera: Camera3D
var _angle: float = 0.6
var _panel_holder: Control
var _buttons: VBoxContainer
var _settings: SettingsMenu

func _ready() -> void:
	GameSettings.boot()
	_build_backdrop()
	_build_ui()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--menushot"):
		_capture(args)

func _process(delta: float) -> void:
	_angle += delta * 0.07
	var radius: float = 6.2
	_camera.position = Vector3(sin(_angle) * radius, 1.7, cos(_angle) * radius)
	_camera.look_at(Vector3(0, 1.25, 0))

# --- scene -----------------------------------------------------------------------------

func _build_backdrop() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.035)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.4, 0.45, 0.6)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.05, 0.06, 0.09)
	environment.fog_density = 0.035
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40, 150, 0)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	add_child(moon)

	var arena := Arena.new()
	add_child(arena)
	arena.build(false)  # the menu backdrop does not need a navmesh

	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.65, 0.35)
	torch.light_energy = 2.4
	torch.omni_range = 9.0
	torch.position = Vector3(1.4, 2.2, 1.6)
	add_child(torch)
	torch.add_child(FlickerLight.new())

	var knight: CharacterModel = CharacterModel.build(KNIGHT_DIR, ["idle_alert"])
	add_child(knight)
	knight.loop("idle_alert")
	knight.rotation.y = 0.5
	if ResourceLoader.exists(Player.SWORD_PATH):
		knight.attach_weapon(Player.SWORD_PATH, "RightHand", Player.GRIPS[3], 1.1, 0.12, Player.HAND_GRIP_POINT)

	# Zombies loitering at the edge of the light.
	for i in 7:
		var angle: float = TAU * float(i) / 7.0 + 0.3
		var zombie: CharacterModel = CharacterModel.build(ZOMBIE_DIR, ["idle"])
		add_child(zombie)
		zombie.position = Vector3(sin(angle), 0, cos(angle)) * randf_range(7.5, 10.5)
		zombie.rotation.y = angle + PI
		zombie.loop("idle", randf_range(0.8, 1.1))
		zombie.anim.seek(randf() * 3.0, true)

	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.current = true
	add_child(_camera)

# --- UI ---------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 14)
	_buttons.position = Vector2(110, 250)
	root.add_child(_buttons)
	_buttons.add_child(UiTheme.title_label("CURSE", 96))
	var tagline := Label.new()
	tagline.text = "Survive the night. Break the curse."
	tagline.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_buttons.add_child(tagline)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	_buttons.add_child(spacer)
	var play := UiTheme.button("Play")
	play.pressed.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	_buttons.add_child(play)
	var settings := UiTheme.button("Settings")
	settings.pressed.connect(_open_settings)
	_buttons.add_child(settings)
	var quit := UiTheme.button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	_buttons.add_child(quit)
	play.grab_focus()

	_panel_holder = CenterContainer.new()
	_panel_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_holder.visible = false
	root.add_child(_panel_holder)
	_settings = SettingsMenu.new()
	_settings.closed.connect(_close_settings)
	_panel_holder.add_child(_settings)

func _open_settings() -> void:
	_buttons.visible = false
	_panel_holder.visible = true

func _close_settings() -> void:
	_panel_holder.visible = false
	_buttons.visible = true

## `-- --menushot[=settings:N]`: save a PNG of the menu (optionally with a settings tab open) and quit.
func _capture(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--tab="):
			_open_settings()
			_settings.select_tab(int(arg.substr(6)))
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_menu.png")
	get_tree().quit()
