extends PanelContainer
## DS2-style icon chart. Purchases still use the existing staged/confirm rules.
const TREES: Array[String] = ["melee", "ranged", "combat"]
const Chart := preload("res://game/ui/skill_tree_chart.gd")
var hero: Player
var staged: Dictionary = {}
var selected_tree: String = "melee"
var _focus_key: String = "tab_melee"
var _box: VBoxContainer
var _detail: PanelContainer
var _detail_label: Label

func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	position = Vector2(260, 40) if get_viewport_rect().size.x >= 1100 else Vector2(20, 30)
	size = Vector2(minf(760, get_viewport_rect().size.x - position.x - 20), minf(640, get_viewport_rect().size.y - 70))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	_detail = PanelContainer.new()
	_detail.name = "NodeDetails"
	_detail.top_level = true
	_detail.z_index = 20
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_theme_stylebox_override("panel", UiTheme.panel_box())
	_detail_label = ItemTile._label("", 14, UiTheme.TEXT)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size.x = 270
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(_detail_label)
	add_child(_detail)
	_detail.hide()
	_build()

func _build() -> void:
	_detail.hide()
	for child in _box.get_children(): child.free()
	var left := TownState.skill_points_left(staged)
	_box.add_child(ItemTile._label("Specialties", 24, UiTheme.TEXT))
	var tabs := HBoxContainer.new()
	tabs.name = "SpecializationTabs"
	_box.add_child(tabs)
	var levels := HeroAttributes.levels_from_xp(TownState.class_xp)
	for tree in TREES:
		_add_button(tabs, "tab_" + tree, "%s %d" % [HeroAttributes.CLASS_NAMES[tree], int(levels.get(tree, 0))], false, _switch_tree.bind(tree), 150)
		(tabs.get_child(-1) as Button).modulate = UiTheme.ACCENT if tree == selected_tree else Color.WHITE
	_box.add_child(ItemTile._label("Powers", 14, UiTheme.TEXT_DIM))
	var powers := HBoxContainer.new()
	powers.name = "PowerIcons"
	powers.add_theme_constant_override("separation", 10)
	_box.add_child(powers)
	for def in PowerDb.of_tree(selected_tree): _add_power(powers, def)
	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_box.add_child(scroll)
	var chart := Chart.new()
	chart.name = "SkillChart"
	chart.tree = selected_tree
	chart.staged = staged.duplicate()
	chart.raise_rank.connect(_raise)
	chart.lower_rank.connect(_lower)
	chart.inspect_node.connect(_inspect)
	chart.leave_node.connect(_hide_detail)
	scroll.add_child(chart)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_box.add_child(footer)
	_add_button(footer, "confirm", "Confirm", staged.is_empty(), _confirm)
	footer.add_child(ItemTile._label("%d points" % left, 17, UiTheme.ACCENT))
	_add_button(footer, "reset", "Reset", staged.is_empty(), func() -> void: staged = {}; _rebuild())
	_add_button(footer, "back", "Back", false, func() -> void: (get_parent() as Hud)._open_character())
	_box.add_child(ItemTile._label("Select an icon to add a rank.  - removes an unconfirmed rank.", 12, UiTheme.TEXT_DIM))
	var focus := find_child(_focus_key, true, false) as Button
	if focus == null or focus.disabled: focus = find_child("tab_" + selected_tree, true, false) as Button
	focus.call_deferred("grab_focus")

func _switch_tree(tree: String) -> void:
	selected_tree = tree
	_focus_key = "tab_" + tree
	_rebuild()

func _ranks() -> Dictionary:
	var ranks := TownState.passive_ranks.duplicate()
	for id in staged: ranks[id] = int(ranks.get(id, 0)) + int(staged[id])
	return ranks

func _add_power(parent: Control, def: PowerDef) -> void:
	var rank := def.rank_for(_ranks())
	var button := UiTheme.button("", 48)
	button.name = "power_" + def.id
	button.custom_minimum_size = Vector2(48, 48)
	button.icon = Chart.icon_for(def.id)
	button.expand_icon = true
	Chart.style_icon_button(button)
	button.self_modulate = Color.WHITE if (rank > 0 and def.needs == "") or def.id == "take_aim" else Color(0.60, 0.57, 0.53)
	parent.add_child(button)
	var badge := ItemTile._label("C" if def.id == "take_aim" else str(rank), 13, UiTheme.TEXT)
	badge.position = Vector2(35, 32)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_constant_override("outline_size", 4)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_child(badge)
	button.mouse_entered.connect(func() -> void: _inspect(def.id, true, button))
	button.focus_entered.connect(func() -> void: _inspect(def.id, true, button))
	button.pressed.connect(func() -> void: _inspect(def.id, true, button))
	button.mouse_exited.connect(_hide_detail)
	button.focus_exited.connect(_hide_detail)

func _inspect(id: String, power: bool, button: Button) -> void:
	var text: String
	if power:
		var def := PowerDb.get_def(id)
		var rank := def.rank_for(_ranks())
		text = "%s  %d/3\n%s" % [def.display_name, rank, def.summary]
		if def.id == "take_aim":
			text = "%s — Cutter\n%s\nCutter's power; always available to him." % [def.display_name, def.summary]
		elif rank < 3:
			var requirements: PackedStringArray = []
			for required in def.ranks[rank]:
				var passive := PassiveDb.get_def(String(required))
				requirements.append("%s %d" % [passive.display_name if passive != null else String(required).capitalize(), int(def.ranks[rank][required])])
			text += "\nNext rank: " + ", ".join(requirements)
		if def.needs != "": text += "\nNot implemented: " + def.needs
	else:
		var def := PassiveDb.get_def(id)
		var rank := TownState.passive_rank(id, staged)
		text = "%s  %d/%d" % [def.display_name, rank, PassiveDef.MAX_RANK]
		if rank > 0: text += "\nCurrent: " + def.describe(rank)
		if rank < PassiveDef.MAX_RANK: text += "\nNext: " + def.describe(rank + 1)
		var blocker := TownState.passive_blocker(id, staged)
		if blocker != "": text += "\n" + blocker
		if def.needs != "": text += "\nNo effect yet: needs " + def.needs
	_detail_label.text = text
	_detail.size = Vector2(296, 0)
	_detail.show()
	_place_detail.call_deferred(button)

func _place_detail(button: Button) -> void:
	if not is_instance_valid(button): return
	var viewport_size := get_viewport_rect().size
	var at := button.global_position + Vector2(button.size.x + 12, 4)
	_detail.global_position = Vector2(clampf(at.x, 8, viewport_size.x - _detail.size.x - 8), clampf(at.y, 8, viewport_size.y - _detail.size.y - 8))

func _hide_detail() -> void:
	_detail.hide()

func _add_button(parent: Control, key: String, text: String, disabled: bool, action: Callable, width: float = 100.0) -> void:
	var button := UiTheme.button(text, width)
	button.name = key
	button.disabled = disabled
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func() -> void:
		_focus_key = key
		action.call())
	parent.add_child(button)

func _raise(id: String) -> void:
	_focus_key = id + "_plus"
	if TownState.passive_blocker(id, staged) == "": staged[id] = int(staged.get(id, 0)) + 1
	_rebuild()

func _lower(id: String) -> void:
	_focus_key = id + "_plus"
	if int(staged.get(id, 0)) <= 0: return
	var trial := staged.duplicate()
	trial[id] = int(trial[id]) - 1
	if int(trial[id]) == 0: trial.erase(id)
	if _valid(trial): staged = trial
	_rebuild()

static func _valid(choice: Dictionary) -> bool:
	var left := choice.duplicate()
	var done: Dictionary = {}
	var progress := true
	while progress and not left.is_empty():
		progress = false
		for id in left.keys():
			if TownState.passive_blocker(String(id), done) == "":
				done[id] = int(done.get(id, 0)) + 1
				left[id] = int(left[id]) - 1
				if int(left[id]) == 0: left.erase(id)
				progress = true
	return left.is_empty()

func _confirm() -> void:
	if TownState.buy_passives(staged):
		staged = {}
		_focus_key = "confirm"
	_rebuild()

func _rebuild() -> void:
	call_deferred("_build")
