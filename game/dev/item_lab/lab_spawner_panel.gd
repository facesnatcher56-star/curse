class_name LabSpawnerPanel
extends PanelContainer
## Developer item browser, generator, and spawner panel for Item Test Lab.
## Supports all implemented ItemDefs, filtering, level variants, rarities, deterministic affixes,
## and equip requirement checks.

signal item_spawned(item: Dictionary)
signal item_equipped(item: Dictionary, success: bool, reason: String)
signal stats_refresh_requested

var player: Player

# UI controls
var _filter_option: OptionButton
var _item_def_option: OptionButton
var _level_option: OptionButton
var _rarity_option: OptionButton
var _affix_prefix_option: OptionButton
var _affix_suffix_option: OptionButton
var _status_label: Label
var _preview_label: Label

# Cached definitions
var _all_defs: Array[ItemDef] = []
var _filtered_defs: Array[ItemDef] = []

enum FilterType { ALL, WEAPON, ARMOR, SHIELD, JEWELRY }

func _init() -> void:
	custom_minimum_size = Vector2(360, 480)

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var title := Label.new()
	title.text = "Item Generator & Spawner"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UiTheme.BRONZE_LIGHT)
	vbox.add_child(title)

	# 1. Category Filter
	var filter_row := HBoxContainer.new()
	vbox.add_child(filter_row)
	var filter_lbl := Label.new()
	filter_lbl.text = "Category:"
	filter_lbl.custom_minimum_size.x = 80
	filter_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	filter_row.add_child(filter_lbl)
	_filter_option = OptionButton.new()
	_filter_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_option.add_item("All Items", FilterType.ALL)
	_filter_option.add_item("Weapons", FilterType.WEAPON)
	_filter_option.add_item("Armor", FilterType.ARMOR)
	_filter_option.add_item("Shields", FilterType.SHIELD)
	_filter_option.add_item("Jewelry", FilterType.JEWELRY)
	_filter_option.item_selected.connect(_on_filter_changed)
	filter_row.add_child(_filter_option)

	# 2. Base Item Definition
	var def_row := HBoxContainer.new()
	vbox.add_child(def_row)
	var def_lbl := Label.new()
	def_lbl.text = "Base Item:"
	def_lbl.custom_minimum_size.x = 80
	def_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	def_row.add_child(def_lbl)
	_item_def_option = OptionButton.new()
	_item_def_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_def_option.item_selected.connect(_on_def_selected)
	def_row.add_child(_item_def_option)

	# 3. Level Variant
	var lvl_row := HBoxContainer.new()
	vbox.add_child(lvl_row)
	var lvl_lbl := Label.new()
	lvl_lbl.text = "Item Level:"
	lvl_lbl.custom_minimum_size.x = 80
	lvl_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	lvl_row.add_child(lvl_lbl)
	_level_option = OptionButton.new()
	_level_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_option.item_selected.connect(_on_variant_or_rarity_changed)
	lvl_row.add_child(_level_option)

	# 4. Rarity
	var rar_row := HBoxContainer.new()
	vbox.add_child(rar_row)
	var rar_lbl := Label.new()
	rar_lbl.text = "Rarity:"
	rar_lbl.custom_minimum_size.x = 80
	rar_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	rar_row.add_child(rar_lbl)
	_rarity_option = OptionButton.new()
	_rarity_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in [Items.Rarity.NORMAL, Items.Rarity.MAGIC, Items.Rarity.RARE]:
		_rarity_option.add_item(Items.RARITY_NAMES[r], r)
	_rarity_option.item_selected.connect(_on_variant_or_rarity_changed)
	rar_row.add_child(_rarity_option)

	# 5. Optional Affix Override (Deterministic testing)
	var pre_row := HBoxContainer.new()
	vbox.add_child(pre_row)
	var pre_lbl := Label.new()
	pre_lbl.text = "Prefix:"
	pre_lbl.custom_minimum_size.x = 80
	pre_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	pre_row.add_child(pre_lbl)
	_affix_prefix_option = OptionButton.new()
	_affix_prefix_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_affix_prefix_option.item_selected.connect(func(_i: int) -> void: _update_preview())
	pre_row.add_child(_affix_prefix_option)

	var suf_row := HBoxContainer.new()
	vbox.add_child(suf_row)
	var suf_lbl := Label.new()
	suf_lbl.text = "Suffix:"
	suf_lbl.custom_minimum_size.x = 80
	suf_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	suf_row.add_child(suf_lbl)
	_affix_suffix_option = OptionButton.new()
	_affix_suffix_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_affix_suffix_option.item_selected.connect(func(_i: int) -> void: _update_preview())
	suf_row.add_child(_affix_suffix_option)

	# Item Details Preview & Equip Requirement Feedback
	var prev_panel := PanelContainer.new()
	prev_panel.custom_minimum_size.y = 110
	vbox.add_child(prev_panel)
	_preview_label = Label.new()
	_preview_label.add_theme_font_size_override("font_size", 12)
	_preview_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prev_panel.add_child(_preview_label)

	# Action Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var add_bag_btn := UiTheme.button("Add to Bag", 110.0)
	add_bag_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_bag_btn.pressed.connect(_on_add_to_bag_pressed)
	btn_row.add_child(add_bag_btn)

	var equip_btn := UiTheme.button("Direct Equip", 110.0)
	equip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_btn.pressed.connect(_on_equip_pressed)
	btn_row.add_child(equip_btn)

	var unequip_weapon_btn := UiTheme.button("Unequip Wpn", 90.0)
	unequip_weapon_btn.pressed.connect(_on_unequip_weapon_pressed)
	btn_row.add_child(unequip_weapon_btn)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

	_load_all_defs()
	_populate_filtered_defs()

func _load_all_defs() -> void:
	_all_defs.clear()
	for def in ItemDb.all().values():
		_all_defs.append(def as ItemDef)
	_all_defs.sort_custom(func(a: ItemDef, b: ItemDef) -> bool: return a.display_name.nocasecmp_to(b.display_name) < 0)

func _populate_filtered_defs() -> void:
	var filter_idx: int = _filter_option.get_selected_id()
	_filtered_defs.clear()
	_item_def_option.clear()

	for def in _all_defs:
		var match_filter := false
		match filter_idx:
			FilterType.ALL:
				match_filter = true
			FilterType.WEAPON:
				match_filter = def.slot == Items.Slot.WEAPON
			FilterType.ARMOR:
				match_filter = def.slot in [Items.Slot.ARMOR, Items.Slot.HELM, Items.Slot.GLOVES, Items.Slot.BOOTS]
			FilterType.SHIELD:
				match_filter = def.slot == Items.Slot.SHIELD
			FilterType.JEWELRY:
				match_filter = def.slot in [Items.Slot.RING, Items.Slot.AMULET]
		if match_filter:
			_filtered_defs.append(def)
			_item_def_option.add_item(def.display_name, _filtered_defs.size() - 1)

	if _filtered_defs.size() > 0:
		_item_def_option.select(0)
		_on_def_selected(0)
	else:
		_update_preview()

func _on_filter_changed(_index: int) -> void:
	_populate_filtered_defs()

func _on_def_selected(index: int) -> void:
	if index < 0 or index >= _filtered_defs.size():
		return
	var def: ItemDef = _filtered_defs[index]

	# Populate level variants
	_level_option.clear()
	for lvl in def.levels:
		_level_option.add_item("Level %d" % lvl, lvl)
	_level_option.select(0)

	_update_affix_options(def)
	_update_preview()

func _on_variant_or_rarity_changed(_index: int) -> void:
	var def := _get_selected_def()
	if def != null:
		_update_affix_options(def)
	_update_preview()

func _update_affix_options(def: ItemDef) -> void:
	_affix_prefix_option.clear()
	_affix_suffix_option.clear()
	_affix_prefix_option.add_item("(None / Auto)", 0)
	_affix_suffix_option.add_item("(None / Auto)", 0)

	var kind: String = Items.KINDS[def.slot]
	var lvl: int = _level_option.get_selected_id()
	var window: Vector2i = Items.RARE_MOD_WINDOW if _rarity_option.get_selected_id() == Items.Rarity.RARE else Items.MAGIC_MOD_WINDOW
	var low: int = maxi(lvl + window.x, 1)
	var high: int = lvl + window.y

	var prefixes := AffixDb.eligible(kind, low, high, "prefix")
	for a in prefixes:
		_affix_prefix_option.add_item(a.title + " (Lvl %d)" % a.level)
		_affix_prefix_option.set_item_metadata(_affix_prefix_option.item_count - 1, a.id)

	var suffixes := AffixDb.eligible(kind, low, high, "suffix")
	for a in suffixes:
		_affix_suffix_option.add_item(a.title + " (Lvl %d)" % a.level)
		_affix_suffix_option.set_item_metadata(_affix_suffix_option.item_count - 1, a.id)

func _get_selected_def() -> ItemDef:
	var idx := _item_def_option.get_selected_id()
	if idx >= 0 and idx < _filtered_defs.size():
		return _filtered_defs[idx]
	return null

func build_current_item() -> Dictionary:
	var def := _get_selected_def()
	if def == null:
		return {}

	var level: int = _level_option.get_selected_id()
	if level <= 0:
		level = def.levels[0] if def.levels.size() > 0 else 1
	var rarity: int = _rarity_option.get_selected_id()

	# Check explicit affix selection
	var explicit_mods: Array = []
	var pre_idx := _affix_prefix_option.selected
	if pre_idx > 0:
		var pre_id: Variant = _affix_prefix_option.get_item_metadata(pre_idx)
		if pre_id != null and str(pre_id) != "":
			explicit_mods.append(str(pre_id))
	var suf_idx := _affix_suffix_option.selected
	if suf_idx > 0:
		var suf_id: Variant = _affix_suffix_option.get_item_metadata(suf_idx)
		if suf_id != null and str(suf_id) != "":
			explicit_mods.append(str(suf_id))

	var mods: Array = explicit_mods
	if mods.is_empty():
		mods = Items.roll_mods(def, level, rarity)

	return Items.build(def, level, rarity, mods)

func _update_preview() -> void:
	if _preview_label == null:
		return
	var item := build_current_item()
	if item.is_empty():
		_preview_label.text = "No item selected."
		return

	var lines: PackedStringArray = []
	var r_color: Color = Items.RARITY_COLORS[int(item.get("rarity", 0))]
	lines.append("%s (Level %d)" % [String(item.get("name", "Unknown")), int(item.get("level", 1))])

	# Stats summary
	var stats_dict: Dictionary = item.get("stats", {})
	if stats_dict.has("min") and stats_dict.has("max"):
		lines.append("Base Damage: %d - %d" % [int(stats_dict.min), int(stats_dict.max)])
	if stats_dict.has("armor"):
		lines.append("Base Armor: %d" % [int(stats_dict.armor)])

	# Modifiers
	var mods_dict: Dictionary = Items.mods_of(item)
	for stat in mods_dict:
		lines.append(AffixDb.describe_stat(stat, float(mods_dict[stat])))

	# Equip requirement & check
	var req_text := Items.requirement_text(item)
	if req_text != "":
		var can_wear := true
		if player != null and is_instance_valid(player):
			can_wear = Items.hero_can_wear(item, player.member_id)
		lines.append("\nRequirement: %s [%s]" % [req_text, "MET" if can_wear else "UNMET"])
	else:
		lines.append("\nRequirement: None [MET]")

	_preview_label.text = "\n".join(lines)

func _on_add_to_bag_pressed() -> void:
	if player == null or not is_instance_valid(player) or player.stats == null:
		_show_status("Player not available.", Color.RED)
		return
	var item := build_current_item()
	if item.is_empty():
		return

	if player.stats.add_to_bag(item):
		_show_status("Added %s to bag." % item.name, UiTheme.ACCENT)
		item_spawned.emit(item)
		stats_refresh_requested.emit()
	else:
		_show_status("Inventory full!", Color.RED)

func _on_equip_pressed() -> void:
	if player == null or not is_instance_valid(player) or player.stats == null:
		_show_status("Player not available.", Color.RED)
		return
	var item := build_current_item()
	if item.is_empty():
		return

	var can_wear := Items.hero_can_wear(item, player.member_id)
	if not can_wear:
		var req_msg := Items.requirement_text(item)
		_show_status("Equip failed: %s" % req_msg, Color.RED)
		item_equipped.emit(item, false, req_msg)
		return

	var off: Variant = player.stats.equip(item, false)
	if off != null:
		_show_status("Equipped %s." % item.name, UiTheme.ACCENT)
		item_equipped.emit(item, true, "")
		stats_refresh_requested.emit()
	else:
		_show_status("Equip rejected by system.", Color.RED)
		item_equipped.emit(item, false, "Equip rejected")

func _on_unequip_weapon_pressed() -> void:
	if player == null or not is_instance_valid(player) or player.stats == null:
		return
	if player.stats.equipment.has(Items.Slot.WEAPON):
		player.stats.unequip(Items.Slot.WEAPON)
		_show_status("Weapon unequipped.", UiTheme.TEXT_DIM)
		stats_refresh_requested.emit()
	else:
		_show_status("No weapon equipped.", UiTheme.TEXT_DIM)

func _show_status(msg: String, color: Color) -> void:
	if _status_label != null:
		_status_label.text = msg
		_status_label.add_theme_color_override("font_color", color)
