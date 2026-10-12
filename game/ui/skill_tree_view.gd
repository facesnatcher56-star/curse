extends PanelContainer
## DS2-style icon chart. Purchases still use the existing staged/confirm rules.
const TREES: Array[String] = ["melee", "ranged", "combat"]
const Chart := preload("res://game/ui/skill_tree_chart.gd")
var hero: Player
var member_id: String:
	get: return hero.member_id if is_instance_valid(hero) else "hero"
var staged: Dictionary = {}
var selected_tree: String = "melee"
var _focus_key: String = "tab_melee"
var _box: VBoxContainer
var _detail: PanelContainer
var _detail_label: RichTextLabel
var _chart: Control

const MET_COLOR := Color(0.47, 0.86, 0.46)
const UNMET_COLOR := Color(0.93, 0.30, 0.24)

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_meta("reserve_party_cards", true)
	add_theme_stylebox_override("panel", UiTheme.parchment_box())
	UiTheme.paper_detail(self)
	UiTheme.crest(self)
	UiTheme.responsive_window(self, Vector2(760, 640))
	position = Vector2(260, 40)
	size = Vector2(760, 640) # Responsive fitting keeps the chart usable instead of crushing its scroll area.
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	_detail = PanelContainer.new()
	_detail.name = "NodeDetails"
	_detail.top_level = true
	_detail.z_index = 20
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_theme_stylebox_override("panel", UiTheme.tooltip_box())
	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = true
	_detail_label.scroll_active = false
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.add_theme_font_size_override("normal_font_size", 14)
	_detail_label.add_theme_color_override("default_color", UiTheme.TEXT)
	_detail_label.custom_minimum_size.x = 270
	_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(_detail_label)
	add_child(_detail)
	_detail.hide()
	_build()

func _build() -> void:
	_detail.hide()
	for child in _box.get_children(): child.free()
	var left := TownState.skill_points_left(staged, member_id)
	_box.add_child(ItemTile._label((hero.display_name + " — " if is_instance_valid(hero) else "") + "Specialties", 28, UiTheme.PAPER_INK))
	var tabs := HBoxContainer.new()
	tabs.name = "SpecializationTabs"
	_box.add_child(tabs)
	var levels := HeroAttributes.levels_from_xp(PartyManager.current().member(member_id).class_xp)
	for tree in TREES:
		_add_button(tabs, "tab_" + tree, "%s %d" % [HeroAttributes.CLASS_NAMES[tree], int(levels.get(tree, 0))], false, _switch_tree.bind(tree), 150)
		UiTheme.style_button(tabs.get_child(-1) as Button, Color(1.0, 0.42, 0.32) if tree == selected_tree else Color.WHITE)
	_box.add_child(ItemTile._label("Powers", 14, UiTheme.PAPER_INK))
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
	chart.member_id = member_id
	chart.staged = staged.duplicate()
	chart.raise_rank.connect(_raise)
	chart.lower_rank.connect(_lower)
	chart.inspect_node.connect(_inspect)
	chart.leave_node.connect(_hide_detail)
	scroll.add_child(chart)
	_chart = chart
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_box.add_child(footer)
	_add_button(footer, "confirm", "Confirm", staged.is_empty(), _confirm)
	UiTheme.style_button(footer.get_child(-1) as Button, Color(0.48, 0.75, 0.50))
	footer.add_child(ItemTile._label("%d points" % left, 17, UiTheme.PAPER_INK))
	_add_button(footer, "reset", "Reset", staged.is_empty(), func() -> void: staged = {}; _rebuild())
	UiTheme.style_button(footer.get_child(-1) as Button, Color(1.0, 0.42, 0.32))
	_add_button(footer, "back", "Back", false, func() -> void: (get_parent() as Hud)._open_character())
	_box.add_child(ItemTile._label("Select an icon to add a rank.  - removes an unconfirmed rank.", 12, UiTheme.PAPER_DIM))
	var focus := find_child(_focus_key, true, false) as Button
	if focus == null or focus.disabled: focus = find_child("tab_" + selected_tree, true, false) as Button
	focus.call_deferred("grab_focus")

func _switch_tree(tree: String) -> void:
	selected_tree = tree
	_focus_key = "tab_" + tree
	_rebuild()

func _ranks() -> Dictionary:
	var ranks := PartyManager.current().member(member_id).passive_ranks.duplicate()
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
	button.self_modulate = Color.WHITE if rank > 0 and def.needs == "" else Color(0.60, 0.57, 0.53)
	parent.add_child(button)
	var badge := ItemTile._label(str(rank), 13, UiTheme.TEXT)
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
	var pulse: Dictionary = {}
	if power:
		var def := PowerDb.get_def(id)
		var ranks := _ranks()
		var rank := def.rank_for(ranks)
		text = "%s  %d/3
%s" % [_plain(def.display_name), rank, _plain(def.summary)]
		if rank < 3:
			# What the next rank needs, each line green once met and red until then; the same passives pulse on the chart.
			text += "

Requirements (%s):" % ("unlocks the power" if rank == 0 else "next rank")
			for required in def.ranks[rank]:
				var passive := PassiveDb.get_def(String(required))
				var need: int = int(def.ranks[rank][required])
				var have: int = int(ranks.get(required, 0))
				var met: bool = have >= need
				var where: String = "" if passive == null or passive.tree == selected_tree else "  [%s tree]" % HeroAttributes.CLASS_NAMES.get(passive.tree, passive.tree)
				text += requirement_line(passive.display_name if passive != null else String(required).capitalize(), need, have, where)
				pulse[String(required)] = met
		if def.needs != "": text += "
Not implemented: " + _plain(def.needs)
	else:
		var def := PassiveDb.get_def(id)
		var rank := TownState.passive_rank(id, staged, member_id)
		text = "%s  %d/%d" % [_plain(def.display_name), rank, PassiveDef.MAX_RANK]
		if rank > 0: text += "
Current: " + _plain(def.describe(rank))
		if rank < PassiveDef.MAX_RANK: text += "
Next: " + _plain(def.describe(rank + 1))
		if rank < PassiveDef.MAX_RANK:
			text += "\n\nRequirements (next rank):"
			var levels := HeroAttributes.levels_from_xp(PartyManager.current().member(member_id).class_xp)
			text += requirement_line(HeroAttributes.CLASS_NAMES[def.tree], def.class_level, int(levels.get(def.tree, 0)))
			for required in def.prereqs:
				var prerequisite := PassiveDb.get_def(String(required))
				var have := TownState.passive_rank(String(required), staged, member_id)
				var need := int(def.prereqs[required])
				text += requirement_line(prerequisite.display_name, need, have)
				pulse[String(required)] = have >= need
			text += requirement_line("Skill points", 1, TownState.skill_points_left(staged, member_id))
		else:
			text += "\nMaximum rank reached."
		if def.needs != "": text += "
No effect yet: needs " + _plain(def.needs)
	_detail_label.text = text
	if _chart != null and is_instance_valid(_chart) and _chart.has_method("set_pulse"):
		_chart.set_pulse(pulse)
	_detail.size = Vector2(296, 0)
	_detail.show()
	_place_detail.call_deferred(button)

## Game text shown through BBCode: brackets would otherwise be read as tags.
static func _plain(text: String) -> String:
	return text.replace("[", "[lb]")

## Powers and passives share requirement colors and explicit required/current values.
static func requirement_line(title: String, need: int, have: int, suffix: String = "") -> String:
	return "\n[color=#%s]%s %d  (you have %d)%s[/color]" % [
		(MET_COLOR if have >= need else UNMET_COLOR).to_html(false), _plain(title), need, have, _plain(suffix)]

func _place_detail(button: Button) -> void:
	if not is_instance_valid(button): return
	var viewport_size := get_viewport_rect().size
	var at := button.global_position + Vector2(button.size.x + 12, 4)
	_detail.global_position = Vector2(clampf(at.x, 8, viewport_size.x - _detail.size.x - 8), clampf(at.y, 8, viewport_size.y - _detail.size.y - 8))

func _hide_detail() -> void:
	_detail.hide()
	if _chart != null and is_instance_valid(_chart) and _chart.has_method("set_pulse"):
		_chart.set_pulse({})

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
	if TownState.passive_blocker(id, staged, member_id) == "": staged[id] = int(staged.get(id, 0)) + 1
	_rebuild()

func _lower(id: String) -> void:
	_focus_key = id + "_plus"
	if int(staged.get(id, 0)) <= 0: return
	var trial := staged.duplicate()
	trial[id] = int(trial[id]) - 1
	if int(trial[id]) == 0: trial.erase(id)
	if _valid(trial, member_id): staged = trial
	_rebuild()

static func _valid(choice: Dictionary, member_id: String = "hero") -> bool:
	var left := choice.duplicate()
	var done: Dictionary = {}
	var progress := true
	while progress and not left.is_empty():
		progress = false
		for id in left.keys():
			if TownState.passive_blocker(String(id), done, member_id) == "":
				done[id] = int(done.get(id, 0)) + 1
				left[id] = int(left[id]) - 1
				if int(left[id]) == 0: left.erase(id)
				progress = true
	return left.is_empty()

func _confirm() -> void:
	if TownState.buy_passives(staged, member_id):
		staged = {}
		_focus_key = "confirm"
	_rebuild()

func _rebuild() -> void:
	call_deferred("_build")
