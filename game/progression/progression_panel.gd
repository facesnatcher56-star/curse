class_name ProgressionPanel
extends PanelContainer
## Where the hero spends the points his level earns (see BuildDefs, TownState): a PASSIVES section and an EVOLUTIONS section, opened from the
## character screen. It only reads and asks: every purchase goes through TownState.buy_passive / select_evolution, never into the save. A purchase
## always asks first (there is no respec yet), the buttons are all ordinary focusable controls so the controller can reach everything, and the
## panel follows the build and XP events so it stays right while open. Worn metal, bronze, ember; no tree art.

signal closed

const CARD_WIDTH := 540.0

var section: String = "passives"
var points_label: Label
var passive_tab: Button
var evolution_tab: Button
var back_button: Button
var passive_cards: Dictionary = {}       # passive id -> Button
var evolution_cards: Dictionary = {}     # "skill/evolution" -> Button
var confirm_box: PanelContainer          # present while a purchase waits for a yes
var confirm_button: Button
var cancel_button: Button
var confirm_text: Label
var pending: Dictionary = {}             # {kind: "passive" | "evolution", skill, id}
var _content: VBoxContainer

func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector2(40, 70)
	size = Vector2(minf(900, get_viewport_rect().size.x - 80), minf(590, get_viewport_rect().size.y - 180))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	column.add_child(head)
	head.add_child(ItemTile._label("Progression", 24, UiTheme.TEXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	points_label = ItemTile._label("", 16, UiTheme.BRONZE_LIGHT.lightened(0.25))
	head.add_child(points_label)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	column.add_child(tabs)
	passive_tab = UiTheme.button("PASSIVES", 170)
	evolution_tab = UiTheme.button("EVOLUTIONS", 170)
	tabs.add_child(passive_tab)
	tabs.add_child(evolution_tab)
	passive_tab.pressed.connect(show_section.bind("passives"))
	evolution_tab.pressed.connect(show_section.bind("evolutions"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true   # the controller walks the cards: the one in focus is always scrolled into view
	column.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	back_button = UiTheme.button("Back", 130)
	back_button.pressed.connect(close)
	column.add_child(back_button)
	TownState.events.hero_build_changed.connect(_refresh)
	TownState.events.hero_xp_changed.connect(_on_xp_changed)
	_refresh()
	_focus_first()

func _exit_tree() -> void:
	if TownState.events.hero_build_changed.is_connected(_refresh):
		TownState.events.hero_build_changed.disconnect(_refresh)
	if TownState.events.hero_xp_changed.is_connected(_on_xp_changed):
		TownState.events.hero_xp_changed.disconnect(_on_xp_changed)

func _on_xp_changed(_old_xp: int, _new_xp: int) -> void:
	_refresh()

func show_section(which: String) -> void:
	section = which
	pending = {}
	_refresh()
	_focus_first()

func close() -> void:
	closed.emit()

## Escape / controller back: dismisses a question first, then leaves the screen.
func back() -> void:
	if not pending.is_empty():
		_cancel()
	else:
		close()

# --- Building --------------------------------------------------------------------------------------------------------------------

func _refresh() -> void:
	if _content == null:
		return
	points_label.text = "Passive Points %d     Evolution Points %d" % [TownState.passive_points_available(), TownState.evolution_points_available()]
	passive_tab.text = "PASSIVES" if section != "passives" else "[ PASSIVES ]"
	evolution_tab.text = "EVOLUTIONS" if section != "evolutions" else "[ EVOLUTIONS ]"
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	passive_cards.clear()
	evolution_cards.clear()
	confirm_box = null
	confirm_button = null
	cancel_button = null
	if section == "passives":
		_build_passives()
	else:
		_build_evolutions()
	if not pending.is_empty():
		_build_confirm()
	_link_focus()

func _card(title: String, text: String, state: String, state_color: Color, tooltip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CARD_WIDTH, 74)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.text = "%s    %s\n%s" % [title, state, text]
	b.tooltip_text = tooltip
	b.add_theme_color_override("font_color", state_color)
	b.add_theme_color_override("font_hover_color", state_color.lightened(0.15))
	b.add_theme_color_override("font_focus_color", state_color.lightened(0.15))
	b.add_theme_font_size_override("font_size", 15)
	return b

func _build_passives() -> void:
	_content.add_child(ItemTile._label("Each passive costs 1 Passive Point and is yours for good: there is no respec yet.", 14, UiTheme.TEXT_DIM))
	for id in BuildDefs.PASSIVE_ORDER:
		var def: Dictionary = BuildDefs.passive(id)
		var owned: bool = TownState.has_passive(id)
		var affordable: bool = TownState.can_buy_passive(id)
		var state: String = "PURCHASED" if owned else ("Cost %d" % BuildDefs.PASSIVE_COST if affordable else "Cost %d  (no point to spend)" % BuildDefs.PASSIVE_COST)
		var color: Color = UiTheme.BRONZE_LIGHT.lightened(0.3) if owned else (UiTheme.TEXT if affordable else UiTheme.TEXT_DIM)
		var card: Button = _card(String(def["name"]).to_upper(), String(def["text"]), state, color, "")
		card.pressed.connect(_request_passive.bind(id))
		_content.add_child(card)
		passive_cards[id] = card

func _build_evolutions() -> void:
	for skill_id in BuildDefs.EVOLUTION_SKILLS:
		var skill: Dictionary = BuildDefs.SKILLS[skill_id]
		var chosen: String = TownState.selected_evolution(skill_id)
		var head: String = "%s" % String(skill["name"]).to_upper()
		if chosen == "":
			head += "     baseline: charge the weapon in your hand, throw it, recall it, catch it."
		else:
			head += "     evolved: %s (permanent)" % String(BuildDefs.evolution(skill_id, chosen)["name"])
		var title := ItemTile._label(head, 16, UiTheme.TEXT)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size.x = CARD_WIDTH
		_content.add_child(title)
		_content.add_child(ItemTile._label("One evolution only, and it is permanent (no respec yet). Each costs 1 Evolution Point.", 14, UiTheme.TEXT_DIM))
		for evo_id in BuildDefs.evolution_order(skill_id):
			var def: Dictionary = BuildDefs.evolution(skill_id, evo_id)
			var selected: bool = chosen == evo_id
			var closed: bool = chosen != "" and not selected
			var affordable: bool = TownState.can_select_evolution(skill_id, evo_id)
			var state: String = "SELECTED" if selected else ("closed" if closed else ("Cost %d" % BuildDefs.EVOLUTION_COST if affordable else "Cost %d  (no point to spend)" % BuildDefs.EVOLUTION_COST))
			var color: Color = UiTheme.BRONZE_LIGHT.lightened(0.3) if selected else (UiTheme.TEXT_DIM if (closed or not affordable) else UiTheme.TEXT)
			var card: Button = _card(String(def["name"]).to_upper(), String(def["text"]), state, color, "")
			card.pressed.connect(_request_evolution.bind(skill_id, evo_id))
			_content.add_child(card)
			evolution_cards["%s/%s" % [skill_id, evo_id]] = card

func _build_confirm() -> void:
	confirm_box = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.075, 0.05, 0.97)
	box.border_color = UiTheme.EMBER
	box.set_border_width_all(2)
	box.set_content_margin_all(12)
	confirm_box.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	confirm_box.add_child(column)
	confirm_text = ItemTile._label(_confirm_message(), 16, UiTheme.TEXT)
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_text.custom_minimum_size.x = CARD_WIDTH - 24.0
	column.add_child(confirm_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	confirm_button = UiTheme.button("Confirm", 150)
	cancel_button = UiTheme.button("Cancel", 150)
	row.add_child(confirm_button)
	row.add_child(cancel_button)
	confirm_button.pressed.connect(_confirm)
	cancel_button.pressed.connect(_cancel)
	_content.add_child(confirm_box)
	_content.move_child(confirm_box, 0)
	# A permanent evolution defaults to NO (one stray press of the confirm key must not spend it); a passive defaults to yes.
	(cancel_button if String(pending["kind"]) == "evolution" else confirm_button).call_deferred("grab_focus")

func _confirm_message() -> String:
	if String(pending["kind"]) == "passive":
		return "Spend 1 Passive Point on %s? It stays with you; there is no respec yet." % String(BuildDefs.passive(String(pending["id"]))["name"]).to_upper()
	return "Spend 1 Evolution Point to evolve %s into %s? This is permanent: the other evolutions of this skill close for good, and there is no respec yet." % [
		String(BuildDefs.SKILLS[String(pending["skill"])]["name"]).to_upper(), String(BuildDefs.evolution(String(pending["skill"]), String(pending["id"]))["name"]).to_upper()]

# --- Asking and buying -----------------------------------------------------------------------------------------------------------

func _request_passive(id: String) -> void:
	if not TownState.can_buy_passive(id):
		return
	pending = {"kind": "passive", "skill": "", "id": id}
	_refresh()

func _request_evolution(skill_id: String, evolution_id: String) -> void:
	if not TownState.can_select_evolution(skill_id, evolution_id):
		return
	pending = {"kind": "evolution", "skill": skill_id, "id": evolution_id}
	_refresh()

func _confirm() -> void:
	if pending.is_empty():
		return
	var ask: Dictionary = pending
	pending = {}
	if String(ask["kind"]) == "passive":
		TownState.buy_passive(String(ask["id"]))
	else:
		TownState.select_evolution(String(ask["skill"]), String(ask["id"]))
	_refresh()   # (the build event has refreshed it already; a refused purchase still clears the question)
	_focus_first()

func _cancel() -> void:
	var was: Dictionary = pending
	pending = {}
	_refresh()
	var card: Button = (passive_cards.get(String(was.get("id", ""))) if String(was.get("kind", "")) == "passive" else evolution_cards.get("%s/%s" % [was.get("skill", ""), was.get("id", "")])) as Button
	if card != null:
		card.call_deferred("grab_focus")
	else:
		_focus_first()

# --- Controller focus ------------------------------------------------------------------------------------------------------------

func _focus_first() -> void:
	var first: Button = null
	for card in _cards():
		first = card
		break
	(first if first != null else passive_tab).call_deferred("grab_focus")

func _cards() -> Array[Button]:
	var out: Array[Button] = []
	if section == "passives":
		for id in BuildDefs.PASSIVE_ORDER:
			if passive_cards.has(id):
				out.append(passive_cards[id])
	else:
		for key in evolution_cards:
			out.append(evolution_cards[key])
	return out

## Tabs across the top, the cards down the middle, Back at the bottom: up and down walk that order, left and right switch sections.
func _link_focus() -> void:
	var cards: Array[Button] = _cards()
	var ring: Array[Control] = []
	ring.append(passive_tab)
	for c in cards:
		ring.append(c)
	if confirm_button != null:
		ring = [confirm_button, cancel_button]
	ring.append(back_button)
	for i in ring.size():
		var here: Control = ring[i]
		var up: Control = ring[maxi(i - 1, 0)]
		var down: Control = ring[mini(i + 1, ring.size() - 1)]
		here.focus_neighbor_top = here.get_path_to(up)
		here.focus_neighbor_bottom = here.get_path_to(down)
	passive_tab.focus_neighbor_right = passive_tab.get_path_to(evolution_tab)
	evolution_tab.focus_neighbor_left = evolution_tab.get_path_to(passive_tab)
	if confirm_button == null and not cards.is_empty():
		evolution_tab.focus_neighbor_bottom = evolution_tab.get_path_to(cards[0])
		cards[0].focus_neighbor_top = cards[0].get_path_to(passive_tab if section == "passives" else evolution_tab)
	if confirm_button != null:
		confirm_button.focus_neighbor_right = confirm_button.get_path_to(cancel_button)
		cancel_button.focus_neighbor_left = cancel_button.get_path_to(confirm_button)
