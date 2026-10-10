extends Label
var item: Dictionary
var worn: Variant
var show_compare: bool = true
var equip_hint: bool = false
func _make_custom_tooltip(_text: String) -> Object:
	return ItemTile.card(item, worn, show_compare, equip_hint)
