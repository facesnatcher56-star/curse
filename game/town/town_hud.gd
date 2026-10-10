class_name TownHud
extends Control
## What the town screen shows outside the panels: gold, food and potions (icons and numbers), the job you have taken, what the hero is near ("E  Talk to Marlow"),
## and a short feed of what has been happening in town.

var quest_line: String = ""    # "Cleanse the Crypt Road: 1 / 3", set by the world every frame
var side_lines: Array[String] = []   # the other quests and events that are running, one line each (see Quests.tracker_lines)
var quest_ready: bool = false  # the quest is done: a coin shows, the keeper has your reward
var prompt: String = ""
var prompt_position := Vector2.ZERO
var cards: Array[Dictionary] = []     # the named monsters and what they are plotting, and standing effects (see Monsters.cards): {title, sub, frac, tint}
var pointers: Array[Dictionary] = []  # arrows at the screen edge toward what is off screen: {screen, tint}
var feed: Array[String] = []
var on_road: bool = false             # the hero is out beyond the walls: the town's chatter is not shown
var log_lines: Array[Dictionary] = []   # what has been told: {text, age, life}
const FEED_SECONDS := 7.0
var _feed_age: Dictionary = {}
var overlay_rects: Array[Rect2] = []   # rectangles actually drawn, for ground-card clearance
var modal_source: Hud   # the combat HUD that owns the character / progression screens (see modal_open)
var heading: Font = UiTheme.heading_font()

## Something to tell the player: it goes into the small message box low on the left (never a big banner across the screen), one line per
## line of `text`, and fades after a while. `seconds` only makes a message linger a little longer or shorter.
func show_banner(text: String, seconds: float = 3.0) -> void:
	for line in text.split("
"):
		if line.strip_edges() == "":
			continue
		log_lines.append({"text": line.strip_edges(), "age": 0.0, "life": clampf(5.0 + seconds * 1.5, 7.0, 14.0)})
	while log_lines.size() > 12:
		log_lines.pop_front()

## The character screen is open: it covers the left of the screen, and this HUD is drawn above it. The side quests, plots, edge arrows and the
## message box wait (the message box is also held, not aged, so the guidance is still there on closing); the resources and the main quest stay.
func modal_open() -> bool:
	return modal_source != null and modal_source.show_gear

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if modal_open():
		queue_redraw()
		return
	for entry in log_lines:
		entry["age"] = float(entry["age"]) + delta
	log_lines = log_lines.filter(func(entry: Dictionary) -> bool: return float(entry["age"]) < float(entry["life"]))
	for entry in feed:   # how long each line has been up (a line that is repeated later counts from the start again once it has left the feed)
		_feed_age[entry] = float(_feed_age.get(entry, 0.0)) + delta
	for key in _feed_age.keys():
		if not feed.has(key):
			_feed_age.erase(key)
	queue_redraw()

func _draw() -> void:
	overlay_rects.clear()
	var font: Font = ThemeDB.fallback_font
	var heading: Font = UiTheme.heading_font()
	var size_px: Vector2 = get_viewport_rect().size
	var is_ds2: bool = modal_source != null and modal_source.use_ds2_ui
	if not is_ds2:
		# The name of the place, top left, in the engraved face, with what kind of ground it is beneath it.
		var zone: String = modal_source.zone_name() if modal_source != null else "The Last Hearth"
		var subtitle: String = modal_source.zone_subtitle() if modal_source != null else "Safe Haven"
		UiTheme.text(self, UiTheme.heading_font(), Vector2(34, 44), zone.to_upper(), 22, UiTheme.TEXT)
		UiTheme.text(self, font, Vector2(34, 66), subtitle, 15, UiTheme.TEXT_DIM)
		# Resources: a quiet strip under the title, an icon and a number each (coins, bread, potions).
		var short: bool = TownState.rationing()
		var values: Array[String] = [str(TownState.gold), str(TownState.food), str(TownState.potions)]
		var ids: Array[String] = ["gold", "food", "potion"]
		var icon_px: float = 24.0
		var gap: float = 20.0
		var bar_width: float = 24.0
		for i in 3:
			bar_width += UiTheme.stat_width(font, values[i], icon_px, 18) + (gap if i < 2 else 0.0)
		var strip := Rect2(14, 76, bar_width, 34)
		draw_rect(strip, Color(0, 0, 0, 0.38))
		draw_rect(Rect2(strip.position, Vector2(strip.size.x, 1.0)), UiTheme.BRONZE.darkened(0.2))
		overlay_rects.append(strip)
		var x: float = 26.0
		for i in 3:
			var warn: bool = i == 1 and short
			x += UiTheme.draw_stat(self, font, Vector2(x, 81.0), ids[i], values[i], icon_px, 18,
				Color(1.0, 0.55, 0.5) if warn else Color.WHITE, Color(1.0, 0.5, 0.45) if warn else Color(0.95, 0.9, 0.78)) + gap
	else:
		# In DS2 mode, party cards occupy top-left (0..172). Place town resource indicators below party cards cleanly.
		var short: bool = TownState.rationing()
		var values: Array[String] = [str(TownState.gold), str(TownState.food), str(TownState.potions)]
		var ids: Array[String] = ["gold", "food", "potion"]
		var icon_px: float = 20.0
		var gap: float = 16.0
		var bar_width: float = 20.0
		for i in 3:
			bar_width += UiTheme.stat_width(font, values[i], icon_px, 14) + (gap if i < 2 else 0.0)
		var strip := Rect2(8, 178, bar_width, 28)
		draw_rect(strip, Color(0.12, 0.11, 0.10, 0.88))
		draw_rect(strip, Color(0.38, 0.34, 0.28, 0.85), false, 1.0)
		overlay_rects.append(strip)
		var x: float = 16.0
		for i in 3:
			var warn: bool = i == 1 and short
			x += UiTheme.draw_stat(self, font, Vector2(x, 182.0), ids[i], values[i], icon_px, 14,
				Color(1.0, 0.55, 0.5) if warn else Color.WHITE, Color(1.0, 0.5, 0.45) if warn else Color(0.95, 0.9, 0.78)) + gap
	var modal: bool = modal_open()
	# The tracker: anchored top-right in DS2 mode, or under top-right map in classic mode.
	var map_rect: Rect2 = Hud.minimap_rect(size_px)
	var tx: float = size_px.x - 300.0 if is_ds2 else (map_rect.end.x - 292.0)
	var ty: float = 24.0 if is_ds2 else (map_rect.end.y + 66.0)
	var tracker_top: float = ty
	var gold: Color = Color(1.0, 0.85, 0.5)
	if quest_line != "":
		var parts: PackedStringArray = quest_line.split(": ", true, 1)
		var marker := Vector2(tx + 12.0, ty + 3.0)
		if quest_ready:   # done and waiting to be handed in: the coin
			var icon: Texture2D = UiTheme.status_icon("gold")
			if icon != null:
				draw_texture_rect(icon, Rect2(marker - Vector2(11, 11), Vector2(22, 22)), false)
		else:
			draw_arc(marker, 10.0, 0.0, TAU, 28, UiTheme.EMBER.lightened(0.15), 2.0)
			UiTheme.text(self, UiTheme.heading_font(), marker + Vector2(-3.0, 6.0), "!", 15, UiTheme.EMBER.lightened(0.25))
		UiTheme.text(self, UiTheme.heading_font(), Vector2(tx + 32.0, ty + 9.0), parts[0].to_upper(), 16, gold if quest_ready else UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 260.0)
		ty += 32.0
		if parts.size() > 1:
			_check_line(Vector2(tx + 8.0, ty), parts[1], quest_ready, font)
			ty += 26.0
	if not side_lines.is_empty() and not modal:
		ty += 8.0
		var diamond := Vector2(tx + 12.0, ty + 3.0)
		draw_colored_polygon(PackedVector2Array([diamond + Vector2(0, -8), diamond + Vector2(8, 0), diamond + Vector2(0, 8), diamond + Vector2(-8, 0)]), UiTheme.MANA.lightened(0.45))
		draw_colored_polygon(PackedVector2Array([diamond + Vector2(0, -4.5), diamond + Vector2(4.5, 0), diamond + Vector2(0, 4.5), diamond + Vector2(-4.5, 0)]), Color(0.03, 0.04, 0.06))
		UiTheme.text(self, UiTheme.heading_font(), Vector2(tx + 32.0, ty + 9.0), "OPTIONAL", 16, UiTheme.TEXT)
		ty += 30.0
		for i in mini(side_lines.size(), 5):
			_check_line(Vector2(tx + 8.0, ty), side_lines[i], false, font)
			ty += 25.0
	if ty > tracker_top:
		overlay_rects.append(Rect2(tx - 8.0, tracker_top - 16.0, 300.0, ty - tracker_top + 22.0))
	# The left column under the resources: the monsters' plots, below.
	var card_y: float = 128.0
	# What the monsters are plotting: only the plots that are running (those are the ones to act on), one slim line each with a bar. The
	# rest (monsters just wandering, standing effects) is in the Chronicle.
	for card in cards:
		if modal or float(card["frac"]) < 0.0:
			continue
		var line: String = "%s: %s" % [String(card["title"]).split(",")[0], String(card["sub"]).replace("plotting ", "")]
		var card_w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 34.0
		UiTheme.draw_panel(self, Rect2(14, card_y, card_w, 30), 0.7)
		overlay_rects.append(Rect2(14, card_y, card_w, 30))
		var tint: Color = card["tint"]
		draw_rect(Rect2(17, card_y + 3, 3, 24), tint)
		UiTheme.text(self, font, Vector2(28, card_y + 19), line, 14, Color(0.93, 0.88, 0.78))
		draw_rect(Rect2(24, card_y + 26, card_w - 20, 2), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(24, card_y + 26, (card_w - 20) * clampf(float(card["frac"]), 0.0, 1.0), 2), tint)
		card_y += 36.0
	# Arrows at the edge of the screen toward the monsters and plots that are off screen.
	var centre: Vector2 = size_px * 0.5
	for pointer in pointers:
		if modal:
			break
		var dir: Vector2 = (pointer["screen"] as Vector2) - centre
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		var reach: float = minf((size_px.x * 0.5 - 40.0) / maxf(absf(dir.x), 0.001), (size_px.y * 0.5 - 40.0) / maxf(absf(dir.y), 0.001))
		var tip: Vector2 = centre + dir * reach
		var side := Vector2(-dir.y, dir.x)
		var arrow := PackedVector2Array([tip + dir * 12.0, tip - dir * 8.0 + side * 9.0, tip - dir * 8.0 - side * 9.0])
		var outline := PackedVector2Array([tip + dir * 15.0, tip - dir * 11.0 + side * 12.5, tip - dir * 11.0 - side * 12.5])
		draw_colored_polygon(outline, Color(0, 0, 0, 0.7))
		draw_colored_polygon(arrow, pointer["tint"])
	# The message box, low on the left, clear of the bars and the map: what the town has been up to and what has just happened, oldest at
	# the top, each line fading after a few seconds.
	var shown: Array[Dictionary] = []
	for entry in (feed if not on_road else []):
		if float(_feed_age.get(entry, 0.0)) < FEED_SECONDS:
			shown.append({"text": entry, "age": float(_feed_age.get(entry, 0.0)), "life": FEED_SECONDS, "dim": true})
	for entry in log_lines:
		shown.append(entry)
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["age"]) > float(b["age"]))
	if shown.size() > 7:
		shown = shown.slice(shown.size() - 7)
	if not shown.is_empty() and not modal:
		var box_h: float = 14.0 + 21.0 * shown.size()
		var box_y: float = size_px.y - 238.0 - box_h - (150.0 if modal_source != null and modal_source.ability_toast_time > 0.0 else 0.0)   # (above the ability plate when it is up)
		var box_w: float = 0.0
		for entry in shown:
			box_w = maxf(box_w, font.get_string_size(String(entry["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
		box_w = minf(box_w, 520.0) + 28.0
		var newest: float = float((shown[shown.size() - 1])["age"])
		var box_fade: float = clampf((float((shown[shown.size() - 1])["life"]) - newest) / 1.5, 0.0, 1.0)
		draw_rect(Rect2(14, box_y, box_w, box_h), Color(0, 0, 0, 0.38 * box_fade))
		overlay_rects.append(Rect2(14, box_y, box_w, box_h))
		for i in shown.size():
			var entry: Dictionary = shown[i]
			var fade: float = clampf((float(entry["life"]) - float(entry["age"])) / 1.5, 0.0, 1.0)
			var tint: Color = Color(0.74, 0.71, 0.66) if bool(entry.get("dim", false)) else Color(0.96, 0.88, 0.7)
			UiTheme.text(self, font, Vector2(26, box_y + 20.0 + 21.0 * i), String(entry["text"]), 15, Color(tint.r, tint.g, tint.b, fade), HORIZONTAL_ALIGNMENT_LEFT, 520.0)
	# Prompt, bottom centre.
	if prompt != "":
		# Small plain text, no tile (the owner found the big boxed prompt too much when hovering NPCs and chests).
		var box := interaction_prompt_rect()
		UiTheme.text(self, font, Vector2(box.position.x + 8, box.position.y + 19), prompt, PROMPT_FONT, UiTheme.TEXT)

const PROMPT_FONT := 16

## Shared with ground-loot placement: this is the rectangle actually drawn above.
func interaction_prompt_rect() -> Rect2:
	if prompt.is_empty():
		return Rect2()
	var width: float = ThemeDB.fallback_font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, PROMPT_FONT).x
	var screen := get_viewport_rect().size
	return Rect2(clampf(prompt_position.x - width * 0.5 - 8, 8, maxf(8, screen.x - width - 24)), maxf(8, prompt_position.y - 28), width + 16, 26)


## Whether a screen point lies on one of the panels drawn here (nothing in town needs to block the mouse, so never).
func covers(_point: Vector2) -> bool:
	return false

## One line of the tracker: a small box to tick (ticked when it is done), then the text, cut to fit the column.
func _check_line(at: Vector2, text: String, done: bool, font: Font) -> void:
	var box := Rect2(at + Vector2(0, -2), Vector2(13, 13))
	draw_rect(box, Color(0, 0, 0, 0.5))
	draw_rect(box, UiTheme.BRONZE_LIGHT.darkened(0.2), false, 1.5)
	if done:
		draw_line(box.position + Vector2(3, 7), box.position + Vector2(6, 10), UiTheme.EMBER.lightened(0.2), 2.0)
		draw_line(box.position + Vector2(6, 10), box.position + Vector2(11, 3), UiTheme.EMBER.lightened(0.2), 2.0)
	var shown: String = text
	while shown.length() > 4 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x > 252.0:
		shown = shown.substr(0, shown.length() - 2)
	if shown != text:
		shown = shown.strip_edges() + "..."
	UiTheme.text(self, font, at + Vector2(22, 10), shown, 15, Color(0.86, 0.83, 0.76))
