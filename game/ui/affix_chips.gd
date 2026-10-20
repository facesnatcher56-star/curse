class_name AffixChips
extends Control
## The champion affix chips under the target banner: one chip per affix, each a small icon, the title in the affix colour and the one-line effect
## (Champion.AFFIXES[id].effect). Chips are full-width rows stacked downward, so 2-3 affixes never overlap or clip.

const CHIP_W := 480.0
const CHIP_H := 28.0
const GAP := 3.0
const MAX_CHIPS := 3

## Shows one chip for each id (AFFIXES keys); an empty array clears the row.
func set_ids(ids: Array) -> void:
	var key: String = ",".join(PackedStringArray(ids))
	if has_meta("ids") and String(get_meta("ids")) == key:
		return
	set_meta("ids", key)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var row := 0
	for id in ids:
		if row >= MAX_CHIPS or not Champion.AFFIXES.has(id):
			continue
		_add_chip(String(id), row)
		row += 1
	size = Vector2(CHIP_W, maxf(row * (CHIP_H + GAP) - GAP, 0.0))

func chip_count() -> int:
	return get_child_count()

func _add_chip(id: String, row: int) -> void:
	var data: Dictionary = Champion.AFFIXES[id]
	var color: Color = data.color
	var chip := Panel.new()
	chip.position = Vector2(0, row * (CHIP_H + GAP))
	chip.size = Vector2(CHIP_W, CHIP_H)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.04, 0.04, 0.94)
	box.set_border_width_all(2)
	box.border_color = Color(color, 0.9)
	box.set_corner_radius_all(4)
	chip.add_theme_stylebox_override("panel", box)
	add_child(chip)
	var badge := AffixIcon.Badge.new()
	badge.affix_id = id
	badge.tint = color
	badge.position = Vector2(5, 2)
	badge.size = Vector2(24, 24)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(badge)
	var title := Label.new()
	title.text = String(data.title).to_upper()
	title.position = Vector2(36, 0)
	title.size = Vector2(104, CHIP_H)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiTheme.heading_font())
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", color.lightened(0.15))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 3)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(title)
	var effect := Label.new()
	effect.text = String(data.effect)
	effect.position = Vector2(142, 0)
	effect.size = Vector2(CHIP_W - 150.0, CHIP_H)
	effect.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effect.add_theme_font_override("font", ThemeDB.fallback_font)
	effect.add_theme_font_size_override("font_size", 15)
	effect.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9))
	effect.add_theme_color_override("font_outline_color", Color.BLACK)
	effect.add_theme_constant_override("outline_size", 2)
	effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(effect)
