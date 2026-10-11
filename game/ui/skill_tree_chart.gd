extends Control
## Icon chart for the existing passive data. Owns layout and paths, not purchases.
signal inspect_node(id: String, power: bool, button: Button)
signal leave_node
signal raise_rank(id: String)
signal lower_rank(id: String)

const TIERS := [1, 5, 12, 24, 36]
const LANES := {
	"fortitude": 0, "critical_strike": 2, "barricade": 0, "overbear": 2,
	"toughness": 1, "alacrity": 3, "reinforced_armor": 0, "smite": 2,
	"fierce_renewal": 3, "rebuke": 0, "deadly_strike": 2,
	"critical_shot": 1, "dodge": 3, "biting_arrow": 0, "quick_draw": 1,
	"survival": 3, "far_shot": 0, "bleed": 1, "penetrate": 2,
	"cunning_renewal": 1, "mortal_wound": 0, "ricochet": 2,
	"brilliance": 0, "devastation": 2, "searing_flames": 2,
	"quickened_casting": 0, "ignite": 2, "arcane_fury": 0,
}
# Reuse Curse's worn icon language. These are thematic stand-ins, not imported DS2 art.
const ICONS := {
	"fortitude": "items/leather_jerkin", "critical_strike": "basic", "barricade": "items/kite_shield",
	"overbear": "items/greatsword", "toughness": "items/mail_hauberk", "alacrity": "cleave",
	"reinforced_armor": "items/plate_cuirass", "smite": "staggering_blow", "fierce_renewal": "war_cry",
	"rebuke": "provoke", "deadly_strike": "brutal_attack", "critical_shot": "take_aim", "dodge": "dodge",
	"biting_arrow": "throw", "quick_draw": "skewer", "survival": "potion", "far_shot": "take_aim",
	"bleed": "brutal_attack", "penetrate": "skewer", "cunning_renewal": "repulse",
	"mortal_wound": "staggering_blow", "ricochet": "throw", "brilliance": "items/talisman",
	"devastation": "detonation", "searing_flames": "fireball", "quickened_casting": "silence",
	"ignite": "flame_nexus", "arcane_fury": "earthshatter",
}
var tree: String = "melee"
var staged: Dictionary = {}
var points: Dictionary = {}
var links: Array[Dictionary] = []
## Passives a hovered power needs: id -> met. They pulse, green once met and red until then.
var _pulse: Dictionary = {}
var _pulse_time: float = 0.0

func _ready() -> void:
	set_process(false)
	custom_minimum_size = Vector2(560, 340)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_build()

static func icon_for(id: String) -> Texture2D:
	var path := "res://assets/icons/%s.png" % String(ICONS.get(id, id))
	if not ResourceLoader.exists(path):
		path = "res://assets/icons/power.png"
	return load(path) as Texture2D

static func style_icon_button(button: Button) -> void:
	# Text-button padding otherwise squeezes 48px icon tiles to a tiny sliver.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := UiTheme.get_theme().get_stylebox(state, "Button").duplicate() as StyleBox
		style.set_content_margin_all(4)
		button.add_theme_stylebox_override(state, style)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("h_separation", 0)

func _build() -> void:
	for def in PassiveDb.of_tree(tree):
		var rank := TownState.passive_rank(def.id, staged)
		var button := Button.new()
		button.name = def.id + "_plus"
		button.icon = icon_for(def.id)
		button.expand_icon = true
		style_icon_button(button)
		button.custom_minimum_size = Vector2(48, 48)
		button.size = Vector2(48, 48)
		button.focus_mode = Control.FOCUS_ALL
		button.set_meta("passive_id", def.id)
		button.self_modulate = Color.WHITE if rank > 0 or TownState.passive_blocker(def.id, staged) == "" else Color(0.60, 0.57, 0.53)
		button.pressed.connect(func() -> void: raise_rank.emit(def.id))
		button.mouse_entered.connect(func() -> void: inspect_node.emit(def.id, false, button))
		button.focus_entered.connect(func() -> void: inspect_node.emit(def.id, false, button))
		button.mouse_exited.connect(func() -> void: leave_node.emit())
		button.focus_exited.connect(func() -> void: leave_node.emit())
		add_child(button)
		var badge := ItemTile._label(str(rank), 14, UiTheme.ACCENT if staged.has(def.id) else UiTheme.TEXT)
		badge.position = Vector2(35, 32)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_constant_override("outline_size", 4)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		button.add_child(badge)
		if int(staged.get(def.id, 0)) > 0:
			var minus := UiTheme.button("-", 22)
			minus.name = def.id + "_minus"
			minus.custom_minimum_size = Vector2(22, 22)
			minus.size = Vector2(22, 22)
			minus.position = Vector2(-10, 28)
			minus.pressed.connect(func() -> void: lower_rank.emit(def.id))
			button.add_child(minus)
	_layout()

## Pulses these passives (id -> met) until called again with an empty dictionary.
func set_pulse(needed: Dictionary) -> void:
	_pulse = needed.duplicate()
	_pulse_time = 0.0
	set_process(not _pulse.is_empty())
	queue_redraw()

func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()

func _layout() -> void:
	points.clear()
	links.clear()
	for def in PassiveDb.of_tree(tree):
		var tier := TIERS.find(def.class_level)
		var lane := int(LANES.get(def.id, 1))
		var point := Vector2(105 + lane * (size.x - 180) / 3.0, 38 + tier * 65)
		points[def.id] = point
		get_node(def.id + "_plus").position = point - Vector2(24, 24)
	for def in PassiveDb.of_tree(tree):
		for required in def.prereqs:
			if points.has(required):
				links.append({"from": String(required), "to": def.id,
					"met": TownState.passive_rank(String(required), staged) >= int(def.prereqs[required])})
	queue_redraw()

func _draw() -> void:
	for i in TIERS.size():
		var y: float = 38 + i * 65
		draw_line(Vector2(64, y), Vector2(size.x - 18, y), Color(0.34, 0.28, 0.20, 0.25))
		UiTheme.text(self, UiTheme.heading_font(), Vector2(8, y + 5), "L%d" % TIERS[i], 13, UiTheme.TEXT_DIM)
	for link in links:
		var a: Vector2 = points[link["from"]] + Vector2(0, 25)
		var b: Vector2 = points[link["to"]] - Vector2(0, 25)
		var color := Color(0.68, 0.51, 0.27, 0.9) if link["met"] else Color(0.31, 0.28, 0.23)
		var middle := (a.y + b.y) * 0.5
		var path := PackedVector2Array([a, Vector2(a.x, middle), Vector2(b.x, middle), b])
		if b.y - a.y > 25:
			# A skipped tier must not run through another skill and imply a false prerequisite.
			var channel := a.x + (38.0 if a.x < size.x * 0.5 else -38.0)
			path = PackedVector2Array([a, a + Vector2(0, 7), Vector2(channel, a.y + 7),
				Vector2(channel, b.y - 7), Vector2(b.x, b.y - 7), b])
		draw_polyline(path, color, 2, true)
		draw_colored_polygon(PackedVector2Array([b, b + Vector2(-4, -6), b + Vector2(4, -6)]), color)
	# A hovered power's requirements: a breathing ring round each needed passive.
	for id in _pulse:
		if not points.has(id):
			continue
		var ring: Color = Color(0.47, 0.86, 0.46) if _pulse[id] else Color(0.93, 0.30, 0.24)
		var beat: float = 0.5 + 0.5 * sin(_pulse_time * 5.0)
		ring.a = 0.45 + 0.55 * beat
		var grow: float = 2.0 + 4.0 * beat
		draw_rect(Rect2(points[id] - Vector2(24 + grow, 24 + grow), Vector2(48 + grow * 2.0, 48 + grow * 2.0)), ring, false, 3.0)
