class_name TownHud
extends Control
## What the town screen shows outside the panels: gold and food, the job you have taken, what the hero is near ("E  Talk to Marlow"),
## and a short feed of what has been happening in town.

var prompt: String = ""
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
	# Resources, top left.
	var line: String = "Gold %d      Food %d%s      Potions %d" % [TownState.gold, TownState.food,
		" (rationing)" if TownState.rationing() else "", TownState.potions]
	UiTheme.draw_panel(self, Rect2(14, 14, 470, 44), 0.8)
	UiTheme.text(self, font, Vector2(30, 43), line, 20, UiTheme.BRONZE_LIGHT.lightened(0.25))
	# The job taken, top right.
	if not TownState.job.is_empty():
		var job: Dictionary = TownState.job
		var text: String = "Job: %s  (%s, %dg)" % [job["name"], JobObjective.describe(job), int(job["reward"])]
		UiTheme.draw_panel(self, Rect2(size_px.x - 484, 14, 470, 44), 0.8)
		UiTheme.text(self, font, Vector2(size_px.x - 468, 43), text, 18, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 440)
	# Town news, left.
	var y: float = 84.0
	for entry in feed:
		UiTheme.text(self, font, Vector2(26, y), entry, 16, Color(0.78, 0.75, 0.7, 0.9), HORIZONTAL_ALIGNMENT_LEFT, 560)
		y += 22.0
	# Prompt, bottom centre.
	if prompt != "":
		var width: float = font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var box := Rect2(size_px.x * 0.5 - width * 0.5 - 24, size_px.y - 124, width + 48, 50)
		UiTheme.draw_panel(self, box, 0.9)
		UiTheme.text(self, font, Vector2(box.position.x + 24, box.position.y + 34), prompt, 24, UiTheme.TEXT)
	if banner_time > 0.0:
		var alpha: float = clampf(banner_time, 0.0, 1.0)
		draw_rect(Rect2(0, 100, size_px.x, 72), Color(0, 0, 0, 0.4 * alpha))
		draw_rect(Rect2(size_px.x * 0.3, 170, size_px.x * 0.4, 2), Color(UiTheme.EMBER.r, UiTheme.EMBER.g, UiTheme.EMBER.b, 0.7 * alpha))
		UiTheme.text(self, font, Vector2(0, 148), banner, 36, Color(0.95, 0.8, 0.5, alpha), HORIZONTAL_ALIGNMENT_CENTER, size_px.x)

## Whether a screen point lies on one of the panels drawn here (nothing in town needs to block the mouse, so never).
func covers(_point: Vector2) -> bool:
	return false
