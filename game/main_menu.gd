extends Node3D
## Main menu: the knight standing in the ruins with zombies watching from the dark, plus Play / Settings / Quit.

const GAME_SCENE := "res://game/town.tscn"   # Play starts in the world: the town, with the Crypt Road already loaded beyond its gate
const KNIGHT_DIR := "res://assets/models/knight2"
const ZOMBIE_DIR := "res://assets/models/zombie"

var _camera: Camera3D
var _angle: float = 0.6
var _panel_holder: Control
var _buttons: VBoxContainer
var _settings: SettingsMenu
var _settings_button: Button

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
	NightSky.apply(environment, Vector3(-0.5, 0.17, -0.85), true)   # a blood moon, hanging ahead of the camera's starting view
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

	# A dark vignette: the edges of the screen fall away into the night, and the left side is darker still so the menu reads.
	var vignette := TextureRect.new()
	var radial := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.0))
	gradient.set_color(1, Color(0, 0, 0, 0.78))
	gradient.set_offset(0, 0.45)
	radial.gradient = gradient
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(0.5, 0.5)
	radial.fill_to = Vector2(1.0, 0.5)
	radial.width = 512
	radial.height = 288
	vignette.texture = radial
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)
	var shade := TextureRect.new()
	var side := GradientTexture2D.new()
	var side_gradient := Gradient.new()
	side_gradient.set_color(0, Color(0.01, 0.01, 0.02, 0.8))
	side_gradient.set_color(1, Color(0.01, 0.01, 0.02, 0.0))
	side.gradient = side_gradient
	side.fill_from = Vector2(0, 0.5)
	side.fill_to = Vector2(1, 0.5)
	side.width = 256
	side.height = 8
	shade.texture = side
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_right = 0.55
	shade.anchor_bottom = 1.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	root.add_child(_embers())

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.position = Vector2(110, 190)
	root.add_child(_buttons)
	var title := UiTheme.title_label("CURSE", 120)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_color", Color(0.93, 0.76, 0.45))
	_buttons.add_child(title)
	# An ember-coloured rule under the title, and the tagline.
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.EMBER.r, UiTheme.EMBER.g, UiTheme.EMBER.b, 0.75)
	rule.custom_minimum_size = Vector2(360, 3)
	_buttons.add_child(rule)
	var tagline := Label.new()
	tagline.text = "Survive the night. Break the curse."
	tagline.add_theme_font_size_override("font_size", 20)
	tagline.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_buttons.add_child(tagline)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	_buttons.add_child(spacer)
	var play := UiTheme.button("Play", 320.0)
	play.pressed.connect(func() -> void: LoadingScreen.go(get_tree(), GAME_SCENE))
	_buttons.add_child(play)
	_settings_button = UiTheme.button("Settings", 320.0)
	_settings_button.pressed.connect(_open_settings)
	_buttons.add_child(_settings_button)
	var quit := UiTheme.button("Quit", 320.0)
	quit.pressed.connect(func() -> void: get_tree().quit())
	_buttons.add_child(quit)
	play.grab_focus()

	var footer := Label.new()
	footer.text = "Mouse and keyboard, or a controller (D-pad and A to choose)"
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	footer.position = Vector2(110, 0)
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_top = -44.0
	root.add_child(footer)

	_panel_holder = CenterContainer.new()
	_panel_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_holder.visible = false
	root.add_child(_panel_holder)
	_settings = SettingsMenu.new()
	_settings.closed.connect(_close_settings)
	_panel_holder.add_child(_settings)

## Embers drifting up the screen: a few dozen small warm sparks, slow and dim, so the menu is never quite still.
func _embers() -> CPUParticles2D:
	var embers := CPUParticles2D.new()
	embers.amount = 46
	embers.lifetime = 7.0
	embers.preprocess = 7.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(760, 8)
	embers.position = Vector2(760, 740)
	embers.direction = Vector2(0, -1)
	embers.spread = 22.0
	embers.gravity = Vector2(6, -8)
	embers.initial_velocity_min = 24.0
	embers.initial_velocity_max = 64.0
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 3.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.62, 0.22, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.55, 0.18, 0.85))
	ramp.add_point(0.7, Color(0.9, 0.32, 0.1, 0.5))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.15, 0.05, 0.0))
	embers.color_ramp = ramp
	return embers

func _open_settings() -> void:
	_buttons.visible = false
	_panel_holder.visible = true
	_settings.focus_first.call_deferred()

func _close_settings() -> void:
	_panel_holder.visible = false
	_buttons.visible = true
	_settings_button.grab_focus()

## `-- --menushot[=settings:N]`: save a PNG of the menu (optionally with a settings tab open) and quit.
func _capture(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--tab="):
			_open_settings()
			_settings.select_tab(int(arg.substr(6)))
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_menu.png")
	get_tree().quit()
