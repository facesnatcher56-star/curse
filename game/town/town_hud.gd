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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
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
	var font: Font = ThemeDB.fallback_font
	var size_px: Vector2 = get_viewport_rect().size
	# Resources, top left: an icon and a number each (coins, bread, potions). The bread goes red when the clan is on short rations.
	var short: bool = TownState.rationing()
	var values: Array[String] = [str(TownState.gold), str(TownState.food), str(TownState.potions)]
	var ids: Array[String] = ["gold", "food", "potion"]
	var icon_px: float = 32.0
	var gap: float = 26.0
	var bar_width: float = 28.0
	for i in 3:
		bar_width += UiTheme.stat_width(font, values[i], icon_px, 22) + (gap if i < 2 else 0.0)
	UiTheme.draw_panel(self, Rect2(14, 14, bar_width, 46), 0.8)
	var x: float = 28.0
	for i in 3:
		var warn: bool = i == 1 and short
		x += UiTheme.draw_stat(self, font, Vector2(x, 21.0), ids[i], values[i], icon_px, 22,
			Color(1.0, 0.55, 0.5) if warn else Color.WHITE, Color(1.0, 0.5, 0.45) if warn else Color(0.95, 0.9, 0.78)) + gap
	# The quest, top right: its name and how far it has got, and a coin when it is done and waiting to be handed in.
	if quest_line != "":
		var text_width: float = font.get_string_size(quest_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var plate_width: float = text_width + 52.0 + (36.0 if quest_ready else 0.0)
		UiTheme.draw_panel(self, Rect2(size_px.x - plate_width - 14, 14, plate_width, 44), 0.8)
		var qx: float = size_px.x - plate_width - 14 + 20
		if quest_ready:
			var icon: Texture2D = UiTheme.status_icon("gold")
			if icon != null:
				draw_texture_rect(icon, Rect2(Vector2(qx, 20), Vector2(30, 30)), false)
			qx += 36.0
		UiTheme.text(self, font, Vector2(qx, 43), quest_line, 18, UiTheme.TEXT if not quest_ready else Color(1.0, 0.85, 0.5))
	# The other quests and events: a compact list in the left column (the right is the main quest and the map), small type, no wasted space.
	var card_y: float = 196.0   # left side, under the bars
	if not side_lines.is_empty():
		var widest: float = 0.0
		for line in side_lines:
			widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
		widest = minf(widest, 360.0)
		var plate_h: float = 12.0 + 18.0 * side_lines.size()
		UiTheme.draw_panel(self, Rect2(14, card_y, widest + 28.0, plate_h), 0.6)
		for i in side_lines.size():
			UiTheme.text(self, font, Vector2(26, card_y + 20 + 18.0 * i), side_lines[i], 13, Color(0.9, 0.86, 0.78), HORIZONTAL_ALIGNMENT_LEFT, 360.0)
		card_y += plate_h + 8.0
	# What the monsters are plotting: only the plots that are running (those are the ones to act on), one slim line each with a bar. The
	# rest (monsters just wandering, standing effects) is in the Chronicle.
	for card in cards:
		if float(card["frac"]) < 0.0:
			continue
		var line: String = "%s: %s" % [String(card["title"]).split(",")[0], String(card["sub"]).replace("plotting ", "")]
		var card_w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 34.0
		UiTheme.draw_panel(self, Rect2(14, card_y, card_w, 30), 0.7)
		var tint: Color = card["tint"]
		draw_rect(Rect2(17, card_y + 3, 3, 24), tint)
		UiTheme.text(self, font, Vector2(28, card_y + 19), line, 14, Color(0.93, 0.88, 0.78))
		draw_rect(Rect2(24, card_y + 26, card_w - 20, 2), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(24, card_y + 26, (card_w - 20) * clampf(float(card["frac"]), 0.0, 1.0), 2), tint)
		card_y += 36.0
	# Arrows at the edge of the screen toward the monsters and plots that are off screen.
	var centre: Vector2 = size_px * 0.5
	for pointer in pointers:
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
	if not shown.is_empty():
		var box_h: float = 14.0 + 21.0 * shown.size()
		var box_y: float = size_px.y - 238.0 - box_h
		var box_w: float = 0.0
		for entry in shown:
			box_w = maxf(box_w, font.get_string_size(String(entry["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
		box_w = minf(box_w, 520.0) + 28.0
		var newest: float = float((shown[shown.size() - 1])["age"])
		var box_fade: float = clampf((float((shown[shown.size() - 1])["life"]) - newest) / 1.5, 0.0, 1.0)
		draw_rect(Rect2(14, box_y, box_w, box_h), Color(0, 0, 0, 0.38 * box_fade))
		for i in shown.size():
			var entry: Dictionary = shown[i]
			var fade: float = clampf((float(entry["life"]) - float(entry["age"])) / 1.5, 0.0, 1.0)
			var tint: Color = Color(0.74, 0.71, 0.66) if bool(entry.get("dim", false)) else Color(0.96, 0.88, 0.7)
			UiTheme.text(self, font, Vector2(26, box_y + 20.0 + 21.0 * i), String(entry["text"]), 15, Color(tint.r, tint.g, tint.b, fade), HORIZONTAL_ALIGNMENT_LEFT, 520.0)
	# Prompt, bottom centre.
	if prompt != "":
		var width: float = font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var box := Rect2(clampf(prompt_position.x - width * 0.5 - 24, 8, maxf(8, size_px.x - width - 56)), maxf(8, prompt_position.y - 50), width + 48, 50)
		UiTheme.draw_panel(self, box, 0.9)
		UiTheme.text(self, font, Vector2(box.position.x + 24, box.position.y + 34), prompt, 24, UiTheme.TEXT)


## Whether a screen point lies on one of the panels drawn here (nothing in town needs to block the mouse, so never).
func covers(_point: Vector2) -> bool:
	return false
