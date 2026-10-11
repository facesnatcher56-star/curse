extends Label
var item: Dictionary
var worn: Variant
var show_compare: bool = true
var equip_hint: bool = false
func _ready() -> void:
	mouse_entered.connect(func() -> void: self_modulate = Color(1.10, 1.08, 1.04))
	mouse_exited.connect(func() -> void: self_modulate = Color.WHITE)

func _make_custom_tooltip(_text: String) -> Object:
	return ItemTile.card(item, worn, show_compare, equip_hint)
