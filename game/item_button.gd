extends Button
## Item actions share the same stats card as their icon and name.
var item: Dictionary
var worn: Variant
func _make_custom_tooltip(_text: String) -> Object:
	return ItemTile.card(item, worn)
