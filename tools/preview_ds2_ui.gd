extends Control
## Standalone visual preview harness for Dungeon Siege II adapted UI layout.
## Launches on Monitor 2 (DISPLAY2) and captures a reference screenshot.

func _ready() -> void:
	# Configure window for Monitor 2 (DISPLAY2: 1920x1080 physical, 1280x720 canvas)
	var win := get_window()
	if DisplayServer.get_screen_count() > 1:
		win.current_screen = 1
		win.position = Vector2i(3480, 200)
	win.size = Vector2i(1280, 720)
	win.mode = Window.MODE_WINDOWED
	
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Dark background simulating the arena
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.07, 0.06, 1.0)
	add_child(bg)
	
	# Arena floor mock
	var floor := ColorRect.new()
	floor.position = Vector2(240, 80)
	floor.size = Vector2(800, 560)
	floor.color = Color(0.12, 0.10, 0.08, 0.7)
	add_child(floor)
	
	_build_top_left_party_cards()
	_build_top_center_target_banner()
	_build_bottom_left_potion_dock()
	_build_bottom_right_compass()
	
	# Wait for rendering to stabilize, then capture screenshot
	await get_tree().process_frame
	await get_tree().process_frame
	_capture_screenshot()

func _create_texture_rect(path: String, w: float, h: float, stretch: TextureRect.StretchMode = TextureRect.STRETCH_SCALE) -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = stretch
	if ResourceLoader.exists(path):
		tr.texture = load(path) as Texture2D
	tr.custom_minimum_size = Vector2(w, h)
	tr.size = Vector2(w, h)
	return tr

func _build_top_left_party_cards() -> void:
	var party_box := VBoxContainer.new()
	party_box.position = Vector2(24, 24)
	party_box.add_theme_constant_override("separation", 24)
	add_child(party_box)
	
	# 1. Hero Card
	party_box.add_child(_create_card("Knight (Hero)", "res://assets/ui/busts/knight.png", 0.95, 0.70, 0.65, false))
	# 2. Archer Companion Card
	party_box.add_child(_create_card("Archer Companion", "res://assets/ui/busts/priest.png", 0.82, 0.90, 0.35, true))

func _create_card(char_name: String, portrait_path: String, hp_pct: float, mana_pct: float, xp_pct: float, is_archer: bool) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(300, 84)
	
	# Portrait Box (74x74)
	var p_box := Control.new()
	p_box.position = Vector2(0, 0)
	p_box.custom_minimum_size = Vector2(74, 74)
	p_box.size = Vector2(74, 74)
	root.add_child(p_box)
	
	# Bust inside
	var bust := _create_texture_rect(portrait_path, 60, 60, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	bust.position = Vector2(7, 7)
	p_box.add_child(bust)
		
	# Outer 3D Frame
	var frame := _create_texture_rect("res://assets/ui/ds2/portrait_frame.png", 74, 74)
	p_box.add_child(frame)
	
	# Right Column (Vitals & Actions)
	var right_col := Control.new()
	right_col.position = Vector2(84, 0)
	right_col.size = Vector2(210, 80)
	root.add_child(right_col)
	
	# Name Label
	var name_lbl := Label.new()
	name_lbl.text = char_name
	name_lbl.position = Vector2(4, -18)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.86, 0.70))
	right_col.add_child(name_lbl)
	
	# Vitals Box
	var v_box := Control.new()
	v_box.position = Vector2(0, 0)
	v_box.custom_minimum_size = Vector2(180, 46)
	v_box.size = Vector2(180, 46)
	right_col.add_child(v_box)
	
	# Vitals Frame (drawn first as backing)
	var v_frame := _create_texture_rect("res://assets/ui/ds2/vitals_bars_frame.png", 180, 46)
	v_box.add_child(v_frame)

	# Health Fill (Red)
	var hp := ColorRect.new()
	hp.color = Color(0.85, 0.14, 0.10, 0.95)
	hp.position = Vector2(8, 5)
	hp.size = Vector2(164 * hp_pct, 10)
	v_box.add_child(hp)
	
	# Mana Fill (Blue)
	var mana := ColorRect.new()
	mana.color = Color(0.20, 0.44, 0.85, 0.95)
	mana.position = Vector2(8, 18)
	mana.size = Vector2(164 * mana_pct, 10)
	v_box.add_child(mana)
	
	# XP Fill (Purple)
	var xp := ColorRect.new()
	xp.color = Color(0.68, 0.30, 0.88, 0.95)
	xp.position = Vector2(8, 31)
	xp.size = Vector2(164 * xp_pct, 10)
	v_box.add_child(xp)
	
	# Action Slots Row
	var slots := HBoxContainer.new()
	slots.position = Vector2(0, 50)
	slots.add_theme_constant_override("separation", 6)
	right_col.add_child(slots)
	
	# Slot 1: Primary Weapon
	slots.add_child(_create_slot("res://assets/ui/ds2/action_slot_bezel.png", 26, "res://assets/icons/earthshatter.png"))
	# Slot 2: Power / Ultimate
	slots.add_child(_create_slot("res://assets/ui/ds2/power_bezel.png", 26, "res://assets/icons/earthshatter.png"))
	
	return root

func _create_slot(bezel_path: String, slot_size: int, icon_path: String) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(slot_size, slot_size)
	box.size = Vector2(slot_size, slot_size)
	
	var icon := _create_texture_rect(icon_path, slot_size - 6, slot_size - 6)
	icon.position = Vector2(3, 3)
	box.add_child(icon)
		
	var bezel := _create_texture_rect(bezel_path, slot_size, slot_size)
	box.add_child(bezel)
	
	return box

func _build_top_center_target_banner() -> void:
	var b_box := Control.new()
	b_box.position = Vector2((1280 - 400) / 2, 16)
	b_box.custom_minimum_size = Vector2(400, 44)
	b_box.size = Vector2(400, 44)
	add_child(b_box)
	
	var plaque := _create_texture_rect("res://assets/ui/ds2/target_banner.png", 400, 44)
	b_box.add_child(plaque)
	
	var lbl := Label.new()
	lbl.text = "GHOUL (LV. 3)  -  HEALTH 140 / 140"
	lbl.position = Vector2(0, 14)
	lbl.size = Vector2(400, 20)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.96, 0.88, 0.72))
	b_box.add_child(lbl)

func _build_bottom_left_potion_dock() -> void:
	var dock := HBoxContainer.new()
	dock.position = Vector2(28, 720 - 80)
	dock.add_theme_constant_override("separation", 16)
	add_child(dock)
	
	dock.add_child(_create_vial("res://assets/ui/ds2/potion_flask_health.png", "5", "Q"))
	dock.add_child(_create_vial("res://assets/ui/ds2/potion_flask_mana.png", "3", "E"))

func _create_vial(vial_path: String, count: String, key: String) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(44, 56)
	root.size = Vector2(44, 56)
	
	var vial := _create_texture_rect(vial_path, 44, 56)
	root.add_child(vial)
	
	var count_lbl := Label.new()
	count_lbl.text = count
	count_lbl.position = Vector2(28, 38)
	count_lbl.add_theme_font_size_override("font_size", 11)
	count_lbl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	root.add_child(count_lbl)
	
	var key_lbl := Label.new()
	key_lbl.text = "[%s]" % key
	key_lbl.position = Vector2(14, -14)
	key_lbl.add_theme_font_size_override("font_size", 10)
	key_lbl.add_theme_color_override("font_color", Color(0.80, 0.70, 0.55))
	root.add_child(key_lbl)
	
	return root

func _build_bottom_right_compass() -> void:
	var c_box := Control.new()
	c_box.position = Vector2(1280 - 150, 720 - 150)
	c_box.custom_minimum_size = Vector2(130, 130)
	c_box.size = Vector2(130, 130)
	add_child(c_box)
	
	var radar_bg := ColorRect.new()
	radar_bg.position = Vector2(16, 16)
	radar_bg.size = Vector2(98, 98)
	radar_bg.color = Color(0.14, 0.11, 0.09, 0.92)
	c_box.add_child(radar_bg)
	
	var ring := _create_texture_rect("res://assets/ui/ds2/compass_ring.png", 130, 130)
	c_box.add_child(ring)

func _capture_screenshot() -> void:
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://assets/ui/ds2/ds2_ui_preview_monitor2.png")
	img.save_png("C:/Users/lloyd/Desktop/DS2_Reference_Extracted/ds2_ui_preview_monitor2.png")
	print("[SCREENSHOT_SAVED_MONITOR2] -> res://assets/ui/ds2/ds2_ui_preview_monitor2.png")
	get_tree().quit(0)
