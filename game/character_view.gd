extends PanelContainer

var hero: Player
var _equipping: bool = false
var _bag_tiles: Array[ItemTile] = []
var _bag_scroll: ScrollContainer
var level_label: Label
var xp_label: Label
var xp_bar: Control
var points_label: Label
var progression_button: Button

func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	position = Vector2(40, 70)
	size = Vector2(minf(900, get_viewport_rect().size.x - 80), minf(590, get_viewport_rect().size.y - 180))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	row.add_child(left)
	left.add_child(ItemTile._label(hero.display_name + " — Character", 24, UiTheme.TEXT))
	_add_progression(left)
	var portrait := SubViewportContainer.new()
	portrait.custom_minimum_size = Vector2(280, 290)
	portrait.stretch = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(portrait)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(280, 290)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	portrait.add_child(viewport)
	var model: Node3D = hero.visual.duplicate()
	for animation in model.find_children("*", "AnimationPlayer", true, false):
		(animation as AnimationPlayer).play("game/idle_alert")
	viewport.add_child(model)
	model.position = Vector3.ZERO
	model.rotation.y = 0.35
	var camera := Camera3D.new()
	var bounds: AABB = CharacterModel._bounds_of(hero.visual)
	var centre: Vector3 = bounds.get_center()
	camera.fov = 35
	camera.position = centre + Vector3(0, 0, maxf(bounds.size.y, 1.0) * 2.0)
	viewport.add_child(camera)
	camera.look_at(centre)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_color = Color(0.92, 0.79, 0.61)
	light.light_energy = 2.0
	viewport.add_child(light)
	left.add_child(ItemTile._label("Health %d   Armour %d" % [hero.max_health, hero.armor], 16, UiTheme.TEXT))
	var worn := HBoxContainer.new()
	left.add_child(worn)
	for slot in 3:
		if hero.stats.equipment.has(slot):
			var tile := ItemTile.create(hero.stats.equipment[slot], null, 52)
			tile.show_compare = false
			var column := VBoxContainer.new()
			worn.add_child(column)
			column.add_child(tile)
			column.add_child(ItemTile.name_label(hero.stats.equipment[slot], null, false))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var bag_head := HBoxContainer.new()
	right.add_child(bag_head)
	var bag_title: Label = ItemTile._label("Bag — %d items" % hero.stats.bag.size(), 24, UiTheme.TEXT)
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_head.add_child(bag_title)
	progression_button = UiTheme.button("PROGRESSION", 170)   # passives and evolutions: where the points are spent
	progression_button.pressed.connect(func() -> void: (get_parent() as Hud).open_progression())
	bag_head.add_child(progression_button)
	right.add_child(ItemTile._label("Confirm to equip" if Gamepad.active else "Right-click or double-click to equip", 14, UiTheme.TEXT_DIM))
	var scroll := ScrollContainer.new()
	_bag_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = clampi(int((size.x - 350) / 110), 1, 4)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for i in hero.stats.bag.size():
		var item: Dictionary = hero.stats.bag[i]
		var column := VBoxContainer.new()
		grid.add_child(column)
		var tile := ItemTile.create(item, hero.stats.equipment.get(int(item["slot"])), 56)
		column.add_child(tile)
		_bag_tiles.append(tile)
		tile.gui_input.connect(_item_input.bind(item, tile))
		var item_name := ItemTile.name_label(item, hero.stats.equipment.get(int(item["slot"])))
		column.add_child(item_name)
		item_name.gui_input.connect(_item_input.bind(item, item_name))
		var button := UiTheme.button("Equip", 84)
		column.add_child(button)
		button.pressed.connect(_equip_item.bind(item))
		ItemTile.decorate_button(button, item, hero.stats.equipment.get(int(item["slot"])))
	if hero.stats.bag.is_empty():
		grid.add_child(ItemTile._label("Your bag is empty.", 16, UiTheme.TEXT))
	var close := UiTheme.button("Close", 110)
	right.add_child(close)
	close.pressed.connect(func() -> void:
		(get_parent() as Hud).close_character())
	close.grab_focus()

## The hero's permanent level and how far through it, read from TownState (the only place it lives). At the cap: "MAX LEVEL" and a full bar.
## It follows the progression events while the screen is open (no polling), so XP earned in play shows without closing it.
func _add_progression(parent: Control) -> void:
	var xp: int = TownState.hero_xp
	TownState.events.hero_xp_changed.connect(_on_xp_changed)
	TownState.events.hero_build_changed.connect(_on_build_changed)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	level_label = ItemTile._label("Level %d" % TownState.hero_level, 20, UiTheme.BRONZE_LIGHT.lightened(0.3))
	row.add_child(level_label)
	xp_label = ItemTile._label(HeroProgression.progress_text(xp), 15, UiTheme.TEXT_DIM)
	xp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(xp_label)
	xp_bar = Control.new()
	xp_bar.custom_minimum_size = Vector2(280, 10)
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.draw.connect(func() -> void:
		UiTheme.draw_bar(xp_bar, Rect2(Vector2(2, 1), xp_bar.size - Vector2(4, 2)), HeroProgression.level_fraction(TownState.hero_xp), UiTheme.EMBER.darkened(0.2), "", ThemeDB.fallback_font))
	parent.add_child(xp_bar)
	points_label = ItemTile._label(_points_text(), 14, UiTheme.TEXT_DIM)   # quiet: a summary, nothing can be spent yet
	parent.add_child(points_label)

func _points_text() -> String:
	return "Passive Points %d     Evolution Points %d" % [TownState.passive_points_available(), TownState.evolution_points_available()]

func focus_progression_button() -> void:
	if progression_button != null:
		progression_button.grab_focus()

func _on_xp_changed(_old_xp: int, new_xp: int) -> void:
	if level_label == null:
		return
	level_label.text = "Level %d" % HeroProgression.level_for_xp(new_xp)
	xp_label.text = HeroProgression.progress_text(new_xp)
	xp_bar.queue_redraw()
	points_label.text = _points_text()

func _on_build_changed() -> void:
	if points_label != null:
		points_label.text = _points_text()

func _exit_tree() -> void:
	if TownState.events.hero_build_changed.is_connected(_on_build_changed):
		TownState.events.hero_build_changed.disconnect(_on_build_changed)
	if TownState.events.hero_xp_changed.is_connected(_on_xp_changed):
		TownState.events.hero_xp_changed.disconnect(_on_xp_changed)

func _item_input(event: InputEvent, item: Dictionary, control: Control) -> void:
	var click := event as InputEventMouseButton
	var activate: bool = click != null and click.pressed and (click.button_index == MOUSE_BUTTON_RIGHT or (click.button_index == MOUSE_BUTTON_LEFT and click.double_click))
	if activate or (event.is_action_pressed("ui_accept") and not event.is_echo()):
		control.accept_event()
		_equip_item(item)

func _equip_item(item: Dictionary) -> void:
	var index: int = hero.stats.bag.find(item)
	if _equipping or index < 0:
		return
	if hero.stats.weapon_locked and int(item["slot"]) == Items.Slot.WEAPON:   # the weapon is out in the world: nothing is swapped until it is back
		hero._say("Recall your weapon first")
		return
	_equipping = true
	var old: Variant = hero.stats.equipment.get(int(item["slot"]))
	hero.stats.bag.remove_at(index)
	hero.stats.equip(item)
	if old != null:
		hero.stats.bag.append(old)
	var town := hero.get_parent() as TownScene
	if town != null:
		TownState.take_gear(hero.stats.equipment)
		TownState.save()
	(get_parent() as Hud)._open_character()
	if Gamepad.active:
		(get_parent() as Hud).character_panel.call_deferred("_focus_bag_item", index)

func _focus_bag_item(index: int) -> void:
	if not _bag_tiles.is_empty():
		var tile: ItemTile = _bag_tiles[clampi(index, 0, _bag_tiles.size() - 1)]
		tile.grab_focus()
		_bag_scroll.ensure_control_visible(tile)
