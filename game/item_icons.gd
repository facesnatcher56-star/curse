class_name ItemIcons
extends RefCounted
## Item pictures. Every base item has an icon (rendered from its Blender model by tools/blender/make_items.py); this frames it in its
## rarity colour so an item is told apart by its picture, not by a line of text. Hovering shows the details (see ItemTile / the HUD card).

const ICON_DIR := "res://assets/icons/items/"

static var _icons: Dictionary = {}
static var _badges: Dictionary = {}

## The bare icon for an item's base (a Falchion, a Plate Cuirass...), or null if there is none.
static func icon_for(item: Dictionary) -> Texture2D:
	var key: String = String(item["def"])
	if not _icons.has(key):
		var path: String = ItemDb.get_def(key).icon_path
		_icons[key] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icons[key]

## The icon on a dark tile with a rarity-coloured frame and a faint glow behind it, as a ready-made texture. Cached per base and rarity.
static func badge(item: Dictionary, size: int = 96) -> Texture2D:
	var key: String = "%s/%d/%d" % [item["def"], int(item["rarity"]), size]
	if _badges.has(key):
		return _badges[key]
	var color: Color = Items.RARITY_COLORS[int(item["rarity"])]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var edge: int = mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			var d: float = Vector2(x - size * 0.5, y - size * 0.5).length() / (size * 0.5)
			var base: Color = Color(0.05, 0.048, 0.06, 0.96)
			base = base.lerp(Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 0.96), clampf(0.55 - d * 0.5, 0.0, 0.5) * (0.4 if int(item["rarity"]) == 0 else 1.0))
			if edge < 2:
				base = Color(0.0, 0.0, 0.0, 1.0)
			elif edge < 4:
				base = color.darkened(0.15) if int(item["rarity"]) > 0 else Color(0.42, 0.4, 0.37)
			elif edge == 4:
				base = Color(0, 0, 0, 0.6)
			img.set_pixel(x, y, base)
	var icon: Texture2D = icon_for(item)
	if icon != null:
		var src: Image = icon.get_image()
		src.convert(Image.FORMAT_RGBA8)
		var inner: int = size - 14
		src.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
		img.blend_rect(src, Rect2i(0, 0, inner, inner), Vector2i(7, 7))
	var texture := ImageTexture.create_from_image(img)
	_badges[key] = texture
	return texture
