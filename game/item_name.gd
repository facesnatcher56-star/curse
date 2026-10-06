extends Label
var item: Dictionary
var worn: Variant
var show_compare: bool = true
func _make_custom_tooltip(_text: String) -> Object:
	return ItemTile.card(item, worn, show_compare)
