class_name LabCombatLog
extends PanelContainer
## Combat log recorder and viewer for the developer Item Test Lab.
## Displays genuine combat resolution data from Combat.resolve and Actor.receive.

var _log_list: VBoxContainer
var _scroll: ScrollContainer
var _max_entries: int = 50

func _init() -> void:
	custom_minimum_size = Vector2(360, 140)

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var title := Label.new()
	title.text = "Combat Log"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UiTheme.BRONZE_LIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	var clear_btn := UiTheme.button("Clear", 60.0)
	clear_btn.custom_minimum_size = Vector2(60, 24)
	clear_btn.pressed.connect(clear_log)
	header_row.add_child(clear_btn)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(340, 90)
	vbox.add_child(_scroll)

	_log_list = VBoxContainer.new()
	_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_log_list)

func record_hit(result: Dictionary, attacker: Actor, defender: Actor) -> void:
	if _log_list == null:
		return
	var outcome: int = int(result.get("outcome", Combat.Outcome.HIT))
	var dmg: float = float(result.get("damage", 0.0))
	var dmg_type: int = int(result.get("type", Combat.DamageType.PHYSICAL))
	var skill_id: String = String(result.get("skill_id", "basic"))

	var outcome_str := "HIT"
	var color := UiTheme.TEXT
	match outcome:
		Combat.Outcome.MISS:
			outcome_str = "MISS"
			color = Color(0.6, 0.6, 0.6)
		Combat.Outcome.BLOCK:
			outcome_str = "BLOCK"
			color = Color(0.9, 0.8, 0.4)
		Combat.Outcome.CRITICAL:
			outcome_str = "CRIT!"
			color = Color(1.0, 0.35, 0.2)
		Combat.Outcome.HIT:
			outcome_str = "HIT"
			color = Color(0.9, 0.9, 0.9)

	var type_str := "Physical"
	if dmg_type == Combat.DamageType.RANGED:
		type_str = "Ranged"
	elif Combat.ELEMENT_OF_TYPE.has(dmg_type):
		type_str = String(Combat.ELEMENT_OF_TYPE[dmg_type]).capitalize()

	var attacker_name := attacker.display_name if is_instance_valid(attacker) else "Attacker"
	var weapon_name := "Unarmed"
	if attacker is Player and (attacker as Player).stats != null:
		var w: Variant = (attacker as Player).stats.equipment.get(Items.Slot.WEAPON)
		if w != null:
			weapon_name = String((w as Dictionary).get("name", "Weapon"))

	var text := "[%s] %s with %s -> %.1f %s (%s)" % [
		outcome_str, attacker_name, weapon_name, dmg, type_str, skill_id
	]
	# Added elemental damage rides inside the total (after resistance, before crit and armour): name each part once.
	var added: Dictionary = result.get("added_elements", {})
	if not added.is_empty():
		var parts: PackedStringArray = []
		for element in Combat.ELEMENTS:
			if added.has(element):
				parts.append("%.1f %s" % [float(added[element]), String(element).capitalize()])
		text += " [incl. added %s]" % ", ".join(parts)

	# Check for leech or restored values
	if attacker is Player and outcome >= Combat.Outcome.HIT:
		var p := attacker as Player
		var l_gain: float = p.stats.gear_stat("life_per_hit") + p.stats.gear_stat("life_steal") / 100.0 * dmg
		var m_gain: float = p.stats.gear_stat("mana_per_hit") + p.stats.gear_stat("mana_steal") / 100.0 * dmg
		if l_gain > 0.0 or m_gain > 0.0:
			text += " [+%.1f HP, +%.1f MP]" % [l_gain, m_gain]

	var entry := Label.new()
	entry.text = text
	entry.add_theme_font_size_override("font_size", 12)
	entry.add_theme_color_override("font_color", color)
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_list.add_child(entry)

	if _log_list.get_child_count() > _max_entries:
		var oldest := _log_list.get_child(0)
		_log_list.remove_child(oldest)
		oldest.queue_free()

	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	if _scroll != null:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func clear_log() -> void:
	if _log_list != null:
		for child in _log_list.get_children():
			_log_list.remove_child(child)
			child.queue_free()
