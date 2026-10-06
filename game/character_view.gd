extends PanelContainer

var hero: Player
var _equipping: bool = false
var _bag_tiles: Array[ItemTile] = []
var _bag_scroll: ScrollContainer

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
	var portrait := SubViewportContainer.new()
	portrait.custom_minimum_size = Vector2(280, 340)
	portrait.stretch = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(portrait)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(280, 340)
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
			var tile := ItemTile.create(hero.stats.equipment[slot], null, 76)
			tile.show_compare = false
			var column := VBoxContainer.new()
			worn.add_child(column)
			column.add_child(tile)
			column.add_child(ItemTile.name_label(hero.stats.equipment[slot], null, false))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(ItemTile._label("Bag — %d items" % hero.stats.bag.size(), 24, UiTheme.TEXT))
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
		var tile := ItemTile.create(item, hero.stats.equipment.get(int(item["slot"])), 84)
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
