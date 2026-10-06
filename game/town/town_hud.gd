class_name TownHud
extends Control
## What the town screen shows outside the panels: gold, food and potions (icons and numbers), the job you have taken, what the hero is near ("E  Talk to Marlow"),
## and a short feed of what has been happening in town.

var quest_line: String = ""    # "Cleanse the Crypt Road: 1 / 3", set by the world every frame
var quest_ready: bool = false  # the quest is done: a coin shows, the keeper has your reward
var prompt: String = ""
var prompt_position := Vector2.ZERO
var gate_hint: String = ""
var gate_hint_position := Vector2.ZERO
var feed: Array[String] = []
var banner: String = ""
var banner_time: float = 0.0

func show_banner(text: String, seconds: float = 3.0) -> void:
	banner = text
	banner_time = seconds

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	banner_time = maxf(banner_time - delta, 0.0)
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
	# Town news, left.
	var y: float = 84.0
	for entry in feed:
		UiTheme.text(self, font, Vector2(26, y), entry, 16, Color(0.78, 0.75, 0.7, 0.9), HORIZONTAL_ALIGNMENT_LEFT, 560)
		y += 22.0
	# Prompt, bottom centre.
	if prompt != "":
		var width: float = font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var box := Rect2(clampf(prompt_position.x - width * 0.5 - 24, 8, maxf(8, size_px.x - width - 56)), maxf(8, prompt_position.y - 50), width + 48, 50)
		UiTheme.draw_panel(self, box, 0.9)
		UiTheme.text(self, font, Vector2(box.position.x + 24, box.position.y + 34), prompt, 24, UiTheme.TEXT)
	if gate_hint != "":
		var width: float = font.get_string_size(gate_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var box := Rect2(clampf(gate_hint_position.x - width * 0.5 - 20, 8, maxf(8, size_px.x - width - 48)), maxf(8, gate_hint_position.y - 46), width + 40, 46)
		UiTheme.draw_panel(self, box, 0.85)
		UiTheme.text(self, font, Vector2(box.position.x + 20, box.position.y + 31), gate_hint, 19, UiTheme.TEXT)
	if banner_time > 0.0:
		var alpha: float = clampf(banner_time, 0.0, 1.0)
		var lines: PackedStringArray = banner.split("\n")
		var band: float = 72.0 + 30.0 * (lines.size() - 1)
		draw_rect(Rect2(0, 100, size_px.x, band), Color(0, 0, 0, 0.4 * alpha))
		draw_rect(Rect2(size_px.x * 0.3, 100 + band - 2, size_px.x * 0.4, 2), Color(UiTheme.EMBER.r, UiTheme.EMBER.g, UiTheme.EMBER.b, 0.7 * alpha))
		UiTheme.text(self, font, Vector2(0, 148), lines[0], 36, Color(0.95, 0.8, 0.5, alpha), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)
		for i in range(1, lines.size()):
			UiTheme.text(self, font, Vector2(0, 148 + 30.0 * i), lines[i], 20, Color(0.85, 0.78, 0.65, alpha), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)

## Whether a screen point lies on one of the panels drawn here (nothing in town needs to block the mouse, so never).
func covers(_point: Vector2) -> bool:
	return false
