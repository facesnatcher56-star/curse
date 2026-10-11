extends PanelContainer
## The skill screen: DS2's passive trees (Melee, Ranged, Combat Magic). Skill points are chosen with + and - (staged, nothing is bought
## yet), then Confirm buys them for good (DS2 has no respec) or Reset clears the choice. Opened from the character screen; mouse and
## controller alike (every control is a focusable button). Lives in Hud.character_panel, so the HUD's pause and close handling apply.

const TREES: Array[String] = ["melee", "ranged", "combat"]

var hero: Player
var staged: Dictionary = {}   # passive id -> ranks chosen but not confirmed
var _focus_key: String = ""   # the button that had focus, to give it back after a rebuild
var _box: VBoxContainer

func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	position = Vector2(40, 60)
	size = Vector2(minf(1080, get_viewport_rect().size.x - 80), minf(640, get_viewport_rect().size.y - 160))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)
	_build()

func _build() -> void:
	for child in _box.get_children():
		child.free()
	var left: int = TownState.skill_points_left(staged)
	_box.add_child(ItemTile._label("Skills — %d point%s to spend" % [left, "" if left == 1 else "s"], 24, UiTheme.TEXT))
	_box.add_child(ItemTile._label("One point a level. Choose with + and -, then Confirm: what is bought is kept for good.", 14, UiTheme.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.name = "scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true   # a controller moving down a tree brings the row into view
	_box.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(columns)
	var levels: Dictionary = HeroAttributes.levels_from_xp(TownState.class_xp)
	for tree in TREES:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		columns.add_child(column)
		column.add_child(ItemTile._label("%s %d" % [HeroAttributes.CLASS_NAMES[tree], int(levels.get(tree, 0))], 19, UiTheme.BRONZE_LIGHT.lightened(0.2)))
		for def in PassiveDb.of_tree(tree):
			_add_row(column, def)
		column.add_child(ItemTile._label("Powers", 16, UiTheme.BRONZE_LIGHT.lightened(0.2)))
		for power in PowerDb.of_tree(tree):
			_add_power_row(column, power)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	_box.add_child(buttons)
	_add_button(buttons, "confirm", "Confirm", staged.is_empty(), _confirm)
	_add_button(buttons, "reset", "Reset", staged.is_empty(), func() -> void: staged = {}; _rebuild())
	_add_button(buttons, "back", "Back", false, func() -> void: (get_parent() as Hud)._open_character())
	var focus: Control = find_child(_focus_key, true, false) as Control if _focus_key != "" else null
	if focus == null or (focus as Button).disabled:
		focus = find_child("back", true, false) as Control
	focus.call_deferred("grab_focus")

func _add_row(parent: Control, def: PassiveDef) -> void:
	var rank: int = TownState.passive_rank(def.id, staged)
	var blocker: String = TownState.passive_blocker(def.id, staged)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var name_label: Label = ItemTile._label(def.display_name, 15, UiTheme.TEXT if rank > 0 or blocker == "" else UiTheme.TEXT_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var rank_color: Color = Color(0.95, 0.8, 0.5) if int(staged.get(def.id, 0)) > 0 else UiTheme.TEXT
	row.add_child(ItemTile._label("%d/%d" % [rank, PassiveDef.MAX_RANK], 15, rank_color))
	_add_button(row, def.id + "_minus", "-", int(staged.get(def.id, 0)) <= 0, _lower.bind(def.id), 30, true)
	_add_button(row, def.id + "_plus", "+", blocker != "", _raise.bind(def.id), 30, true)
	var line: String = (def.describe(rank) if rank > 0 else "") + ("" if rank >= PassiveDef.MAX_RANK else
		("   next: " if rank > 0 else "Rank 1: ") + def.describe(rank + 1))
	if blocker != "" and blocker != "No skill points left" and rank < PassiveDef.MAX_RANK:
		line += "   (%s)" % blocker
	if def.needs != "":
		line += "   No effect yet: needs %s" % def.needs
	var detail: Label = ItemTile._label(line, 11, Color(0.85, 0.5, 0.42) if blocker != "" and blocker != "No skill points left" else UiTheme.TEXT_DIM)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 280
	parent.add_child(detail)

## A power: its rank (opened by passive ranks, nothing to spend) and what the next rank needs, counting the ranks chosen here.
func _add_power_row(parent: Control, def: PowerDef) -> void:
	var ranks: Dictionary = TownState.passive_ranks.duplicate()
	for id in staged:
		ranks[id] = int(ranks.get(id, 0)) + int(staged[id])
	var rank: int = def.rank_for(ranks)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label: Label = ItemTile._label(def.display_name, 14, UiTheme.TEXT if rank > 0 and def.needs == "" else UiTheme.TEXT_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = def.summary
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(name_label)
	row.add_child(ItemTile._label("" if def.id == "take_aim" else "Rank %d/3" % rank, 14, UiTheme.TEXT if rank > 0 else UiTheme.TEXT_DIM))
	var line: String = ""
	if def.id == "take_aim":
		line = "Cutter's power: his next arrow, always at hand"
	elif def.needs == "not built yet":
		line = "Coming soon"
	elif def.needs != "":
		line = "Not in the game yet (needs %s)" % def.needs
	elif rank < 3:
		var parts: PackedStringArray = []
		for passive in def.ranks[rank]:
			var passive_def: PassiveDef = PassiveDb.get_def(String(passive))
			parts.append("%s %d" % [passive_def.display_name if passive_def != null else String(passive).capitalize(), int(def.ranks[rank][passive])])
		line = "Rank %d: %s" % [rank + 1, ", ".join(parts)]
	if line != "":
		var detail: Label = ItemTile._label(line, 11, UiTheme.TEXT_DIM)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = 280
		parent.add_child(detail)

func _add_button(parent: Control, key: String, text: String, disabled: bool, action: Callable, width: float = 120.0, small: bool = false) -> void:
	var button: Button = UiTheme.button(text, width)
	if small:
		button.custom_minimum_size = Vector2(width, 26)
		button.add_theme_font_size_override("font_size", 15)
	button.name = key
	button.disabled = disabled
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func() -> void:
		_focus_key = key
		action.call())
	parent.add_child(button)

func _raise(id: String) -> void:
	if TownState.passive_blocker(id, staged) == "":
		staged[id] = int(staged.get(id, 0)) + 1
	_rebuild()

## Takes a chosen rank back, unless another chosen rank needs it.
func _lower(id: String) -> void:
	if int(staged.get(id, 0)) <= 0:
		return
	var trial: Dictionary = staged.duplicate()
	trial[id] = int(trial[id]) - 1
	if int(trial[id]) == 0:
		trial.erase(id)
	if _valid(trial):
		staged = trial
	_rebuild()

## Whether every chosen rank could be bought, one at a time, in some order (the order they were chosen in does not matter).
static func _valid(choice: Dictionary) -> bool:
	var left: Dictionary = choice.duplicate()
	var done: Dictionary = {}
	var progress: bool = true
	while progress and not left.is_empty():
		progress = false
		for id in left.keys():
			if TownState.passive_blocker(String(id), done) == "":
				done[id] = int(done.get(id, 0)) + 1
				left[id] = int(left[id]) - 1
				if int(left[id]) == 0:
					left.erase(id)
				progress = true
	return left.is_empty()

func _confirm() -> void:
	if TownState.buy_passives(staged):
		staged = {}
		_focus_key = "back"
	_rebuild()

func _rebuild() -> void:
	call_deferred("_build")
