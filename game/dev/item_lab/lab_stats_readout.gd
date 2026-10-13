class_name LabStatsReadout
extends PanelContainer
## Live equipment and character statistics developer readout.
## Displays genuine PlayerStats and Actor fields, distinguishing effective totals from raw modifiers.

var player: Player
var _content_label: Label

func _init() -> void:
	custom_minimum_size = Vector2(360, 160)

func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var title := Label.new()
	title.text = "Character Stats"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UiTheme.BRONZE_LIGHT)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_content_label = Label.new()
	_content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_label.custom_minimum_size = Vector2(320, 0)
	_content_label.add_theme_font_size_override("font_size", 13)
	_content_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(_content_label)

	refresh()

func update_player(target_player: Player) -> void:
	player = target_player
	refresh()

func refresh() -> void:
	if _content_label == null:
		return
	if player == null or not is_instance_valid(player) or player.stats == null:
		_content_label.text = "No character selected."
		return

	var s: PlayerStats = player.stats
	var melee_range: Vector2 = s.weapon_range(1.0)
	var ranged_range: Vector2 = s.ranged_range()
	var lines: PackedStringArray = []

	# Attributes
	lines.append("--- Attributes ---")
	lines.append("Level: %d  (Melee %d / Ranged %d / CM %d)" % [
		player.level,
		HeroAttributes.class_level(int(player.character.class_xp.get("melee", 0))),
		HeroAttributes.class_level(int(player.character.class_xp.get("ranged", 0))),
		HeroAttributes.class_level(int(player.character.class_xp.get("combat", 0)))
	])
	lines.append("STR: %d  (gear +%d)" % [int(s.strength), int(s.gear_stat("str"))])
	lines.append("DEX: %d  (gear +%d)" % [int(s.dexterity), int(s.gear_stat("dex"))])
	lines.append("INT: %d  (gear +%d)" % [int(s.intelligence), int(s.gear_stat("int"))])

	# Vitals
	lines.append("\n--- Vitals ---")
	lines.append("Life: %.1f / %.1f  (gear +%d)" % [player.health, player.max_health, int(s.gear_stat("life"))])
	lines.append("Mana: %.1f / %.1f  (gear +%d)" % [s.mana, s.max_mana, int(s.gear_stat("mana"))])

	# Offense
	lines.append("\n--- Damage & Combat ---")
	lines.append("Melee Range: %d - %d" % [int(melee_range.x), int(melee_range.y)])
	lines.append("Ranged Range: %d - %d" % [int(ranged_range.x), int(ranged_range.y)])
	lines.append("Crit Chance: %.1f%%  (Mult: %.1fx)" % [player.crit_chance * 100.0, player.crit_mult])
	lines.append("Attack Speed: %.2f" % [s.attack_speed()])
	lines.append("Power damage: %+d%%" % int(round((s.power_damage_mult() - 1.0) * 100.0)))
	for element in Combat.ELEMENTS:
		var low: float = Combat.added_damage(player, element)
		var high: float = Combat.added_damage_max(player, element)
		if low > 0.0 or high > 0.0:
			lines.append("Added %s: %d - %d" % [element.capitalize(), int(low), int(high)])

	# Defense
	lines.append("\n--- Defenses ---")
	lines.append("Armor: %.1f  (gear +%d, +%d%%)" % [player.armor, int(s.gear_stat("armor")), int(s.gear_stat("armor_pct"))])
	lines.append("Block: %.1f%%  (Ranged Block: %.1f%%)" % [player.block_chance * 100.0, player.ranged_block_chance * 100.0])
	lines.append("Dodge: %.1f%% melee / %.1f%% ranged   Toughness: %.1f%%" % [Combat.dodge_chance_against(player, Combat.DamageType.PHYSICAL) * 100.0,
		Combat.dodge_chance_against(player, Combat.DamageType.RANGED) * 100.0, player.toughness * 100.0])
	lines.append("Physical component: %.1f%%" % [player.physical_resist * 100.0])
	lines.append("Effective physical — Melee: %.1f%% | Ranged: %.1f%%" % [
		Combat.effective_resistance(player, Combat.DamageType.PHYSICAL) * 100.0,
		Combat.effective_resistance(player, Combat.DamageType.RANGED) * 100.0])
	lines.append("Magic component: %.1f%%" % [player.magical_resist * 100.0])
	for element in Combat.ELEMENTS:
		var kind: int = {"fire": Combat.DamageType.FIRE, "ice": Combat.DamageType.ICE,
			"lightning": Combat.DamageType.LIGHTNING, "death": Combat.DamageType.DEATH}[element]
		lines.append("%s Resistance: %.1f%% (%.1f%% vs magic)" % [element.capitalize(),
			Combat.resistance_of(player, element) * 100.0, Combat.effective_resistance(player, kind) * 100.0])

	# Utility & Effects
	lines.append("\n--- Recovery & Modifiers ---")
	lines.append("Life Steal: %.1f%%  (Life/Hit: +%d)" % [s.gear_stat("life_steal"), int(s.gear_stat("life_per_hit"))])
	lines.append("Mana Steal: %.1f%%  (Mana/Hit: +%d)" % [s.gear_stat("mana_steal"), int(s.gear_stat("mana_per_hit"))])
	lines.append("Reflect: %.1f%%" % [s.gear_stat("reflect")])
	lines.append("Magic Find: %.1f%%  Gold Find: +%d%%" % [s.magic_find(), int(s.gear_stat("gold_find"))])

	# Equipped summary
	lines.append("\n--- Equipped Weapon ---")
	var w: Variant = s.equipment.get(Items.Slot.WEAPON)
	if w != null:
		var w_dict: Dictionary = w as Dictionary
		lines.append("%s (%s)" % [String(w_dict.get("name", "Unknown")), Items.RARITY_NAMES[int(w_dict.get("rarity", 0))]])
		var def: ItemDef = ItemDb.get_def(String(w_dict.get("def", "")))
		if def != null:
			lines.append("Family: %s | 2H: %s" % [def.item_type, str(bool(def.profile.get("two_handed", false)))])
	else:
		lines.append("Bare hands (Unarmed)")

	_content_label.text = "\n".join(lines)
