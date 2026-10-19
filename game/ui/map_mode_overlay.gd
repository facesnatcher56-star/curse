class_name MapModeOverlay
extends Control
## Map mode's full-screen map (issue #79, step 1): the whole terrain, north up, with a pickable marker for every live enemy group, loot pile,
## chest and exit. Click a marker (or move the controller focus and press A) and `selected(id)` fires; the coordinator decides what happens.
## The panel leaves the hotbar, both vessels and the top-left party panel uncovered. While open it swallows all mouse and pad input.

signal selected(id: int)
signal closed()

const HIT_RADIUS := 18.0
const MARGIN := 16.0
const TOP_INSET := 110.0          # keeps the top-left party panel readable
const STICK_THRESHOLD := 0.6
const REPEAT_FIRST := 0.35
const REPEAT_NEXT := 0.16
const KIND_COLOR := {
	"group": Color(0.86, 0.20, 0.16),
	"loot": Color(0.95, 0.80, 0.30),
	"chest": Color(0.84, 0.64, 0.30),
	"exit": Color(0.55, 0.78, 0.95),
}

var map_data: MinimapMap

var _open: bool = false
var _can_close: bool = true
var _markers: Array = []
var _hero: Vector3 = Vector3.ZERO
var _hover: int = -1
var _focus: int = -1
var _stick_dir: int = 0
var _stick_timer: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

## World (x, z) metres -> panel pixels: the whole map fitted into `panel`, aspect kept, centred, north up (no yaw).
static func fit_transform(map: MinimapMap, panel: Rect2) -> Transform2D:
	if map == null or map.cols <= 0 or map.rows <= 0:
		return Transform2D(0.0, panel.get_center())
	var world := Vector2(map.cols, map.rows) * MinimapMap.CELL
	if world.y > world.x * 1.3 and panel.size.x > panel.size.y:   # a long north-south place (the Crypt) is turned a quarter so it fills the wide screen
		var rs: float = minf(panel.size.x / world.y, panel.size.y / world.x)
		var c: Vector2 = map.origin + world * 0.5
		return Transform2D(Vector2(0.0, -rs), Vector2(rs, 0.0), panel.get_center() - Vector2(c.y, -c.x) * rs)
	var s: float = minf(panel.size.x / world.x, panel.size.y / world.y)
	var offset: Vector2 = panel.get_center() - (map.origin + world * 0.5) * s
	return Transform2D(Vector2(s, 0.0), Vector2(0.0, s), offset)

func open(markers: Array, hero_pos: Vector3, can_close: bool) -> void:
	_markers = markers.duplicate()
	_hero = hero_pos
	_can_close = can_close
	_hover = -1
	_focus = -1
	_stick_dir = 0
	_open = true
	_fit_to_screen()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	if not _markers.is_empty():
		_focus = int(_sorted_ids()[0])
	queue_redraw()

func set_markers(markers: Array) -> void:
	_markers = markers.duplicate()
	if _hover >= 0 and _find(_hover) < 0:
		_hover = -1
	if _focus < 0 or _find(_focus) < 0:
		_focus = -1 if _markers.is_empty() else int(_sorted_ids()[0])
	queue_redraw()

func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_hover = -1

func is_open() -> bool:
	return _open

## The hovered marker (mouse), else the controller-focused one; -1 if none.
func focused_id() -> int:
	if _hover >= 0:
		return _hover
	return _focus if _find(_focus) >= 0 else -1

func marker_screen_pos(id: int) -> Vector2:
	var i: int = _find(id)
	if i < 0 or map_data == null:
		return Vector2(-1, -1)
	var p: Vector3 = _markers[i]["pos"]
	return _to_screen(Vector2(p.x, p.z))

## Cycles controller focus by `step` through the markers ordered by angle around their centre (stable: ties break on id).
func select_next(step: int) -> void:
	var ids: Array = _sorted_ids()
	if ids.is_empty():
		return
	var at: int = ids.find(_focus)
	_focus = int(ids[posmod((0 if at < 0 else at) + step, ids.size())]) if at >= 0 else int(ids[0])
	_hover = -1
	queue_redraw()

func choose_focused() -> void:
	var id: int = focused_id()
	if id >= 0:
		selected.emit(id)

# ---- input ------------------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		var h: int = _hit((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var h: int = _hit(mb.position)
			if h >= 0:
				selected.emit(h)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _can_close:
			closed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		choose_focused()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		select_next(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		select_next(-1)
		get_viewport().set_input_as_handled()

## Left stick: edge-triggered, then repeating while held (right/down = next, left/up = previous).
## The Hud is not sized to the screen, so the overlay takes the viewport's size itself.
func _fit_to_screen() -> void:
	var screen: Vector2 = get_viewport_rect().size
	if size != screen or position != Vector2.ZERO:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		position = Vector2.ZERO
		size = screen
		queue_redraw()

func _process(delta: float) -> void:
	_fit_to_screen()
	var v: Vector2 = Gamepad.move_vector()
	var dir: int = 0
	if absf(v.x) > STICK_THRESHOLD or absf(v.y) > STICK_THRESHOLD:
		var m: float = v.x if absf(v.x) >= absf(v.y) else v.y
		dir = 1 if m > 0.0 else -1
	if dir == 0:
		_stick_dir = 0
		return
	if dir != _stick_dir:
		_stick_dir = dir
		_stick_timer = REPEAT_FIRST
		select_next(dir)
		return
	_stick_timer -= delta
	if _stick_timer <= 0.0:
		_stick_timer = REPEAT_NEXT
		select_next(dir)

# ---- geometry ---------------------------------------------------------------------------------------------------------------------------

## The map panel: the screen less a margin, clear of the hotbar, both vessels and the party panel.
func panel_rect() -> Rect2:
	var s: Vector2 = size
	var bottom: float = s.y - MARGIN
	var orb_top: float = minf(Hud.orb_rect(s, false).position.y, Hud.orb_rect(s, true).position.y)
	bottom = minf(bottom, orb_top - 8.0)
	var hud := get_parent() as Hud
	if hud != null:
		bottom = minf(bottom, hud.hotbar_rect(s).position.y - 8.0)
	bottom -= 26.0   # the help line sits under the panel
	return Rect2(Vector2(MARGIN, TOP_INSET), Vector2(s.x - MARGIN * 2.0, maxf(bottom - TOP_INSET, 64.0)))

func _to_screen(world_xz: Vector2) -> Vector2:
	return fit_transform(map_data, panel_rect()) * world_xz

func _find(id: int) -> int:
	for i in _markers.size():
		if int(_markers[i]["id"]) == id:
			return i
	return -1

func _hit(at: Vector2) -> int:
	var best: int = -1
	var best_d: float = HIT_RADIUS
	for m in _markers:
		var p: Vector3 = m["pos"]
		var d: float = _to_screen(Vector2(p.x, p.z)).distance_to(at)
		if d <= best_d:
			best_d = d
			best = int(m["id"])
	return best

func _sorted_ids() -> Array:
	if _markers.is_empty():
		return []
	var c := Vector2.ZERO
	for m in _markers:
		c += Vector2((m["pos"] as Vector3).x, (m["pos"] as Vector3).z)
	c /= float(_markers.size())
	var keyed: Array = []
	for m in _markers:
		var p := Vector2((m["pos"] as Vector3).x, (m["pos"] as Vector3).z)
		keyed.append([snappedf((p - c).angle(), 0.0001), int(m["id"])])
	keyed.sort()
	var out: Array = []
	for k in keyed:
		out.append(k[1])
	return out

# ---- drawing ----------------------------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if not _open:
		return
	var panel: Rect2 = panel_rect()
	UiTheme.draw_panel(self, panel.grow(6.0), 0.94)
	draw_rect(panel, Color(0.03, 0.025, 0.022, 0.96))
	if map_data != null:
		var xf: Transform2D = fit_transform(map_data, panel)
		map_data.draw(self, xf)
		_draw_hero(xf * Vector2(_hero.x, _hero.z))
	var font: Font = UiTheme.heading_font()
	var active: int = focused_id()
	var placed: Array[Rect2] = []
	var plates: Array = []
	for m in _markers:
		var p: Vector3 = m["pos"]
		var at: Vector2 = fit_transform(map_data, panel) * Vector2(p.x, p.z)
		var id: int = int(m["id"])
		_draw_icon(String(m["kind"]), at, id == active)
		var rect: Rect2 = _label_rect(font, String(m["label"]), at, panel, placed)
		placed.append(rect)
		plates.append([rect, String(m["label"]), id == active])
	for plate in plates:
		if not plate[2]:
			_draw_plate(font, plate[0], plate[1], false)
	for plate in plates:
		if plate[2]:
			_draw_plate(font, plate[0], plate[1], true)
	var help: String = "Click a group to dash there"
	if Gamepad.active:
		help += "      A select" + ("  B close" if _can_close else "")
	UiTheme.text(self, font, Vector2(panel.position.x, panel.end.y + 22.0), help, 14, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x)

## A label rect beside the marker (right, else left), pushed down past labels already placed, then clamped inside the panel.
func _label_rect(font: Font, label: String, at: Vector2, panel: Rect2, placed: Array[Rect2]) -> Rect2:
	var sz: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13) + Vector2(12.0, 8.0)
	var x: float = at.x + 14.0
	if x + sz.x > panel.end.x:
		x = at.x - 14.0 - sz.x
	var r := Rect2(Vector2(x, at.y - sz.y * 0.5), sz)
	for _pass in 12:
		var moved: bool = false
		for o in placed:
			if r.intersects(o):
				r.position.y = o.end.y + 2.0
				moved = true
		if not moved:
			break
	r.position.x = clampf(r.position.x, panel.position.x + 2.0, maxf(panel.end.x - sz.x - 2.0, panel.position.x + 2.0))
	r.position.y = clampf(r.position.y, panel.position.y + 2.0, maxf(panel.end.y - sz.y - 2.0, panel.position.y + 2.0))
	return r

func _draw_plate(font: Font, r: Rect2, label: String, on: bool) -> void:
	draw_rect(r, Color(0.05, 0.04, 0.035, 0.94 if on else 0.78))
	draw_rect(r, UiTheme.ACCENT if on else UiTheme.BORDER, false, 2.0 if on else 1.0)
	UiTheme.text(self, font, r.position + Vector2(6.0, r.size.y - 7.0), label, 13, UiTheme.ACCENT if on else UiTheme.TEXT)

func _draw_hero(at: Vector2) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -9), at + Vector2(7, 7), at + Vector2(0, 3), at + Vector2(-7, 7)])
	draw_colored_polygon(pts, Color.WHITE)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.BLACK, 1.5)

func _draw_icon(kind: String, at: Vector2, on: bool) -> void:
	var col: Color = KIND_COLOR.get(kind, Color.WHITE)
	if on:
		draw_arc(at, HIT_RADIUS, 0.0, TAU, 40, Color(1, 0.95, 0.7), 3.0)
		draw_circle(at, HIT_RADIUS - 2.0, Color(1, 0.95, 0.7, 0.12))
	var edge := Color(0.05, 0.03, 0.03)
	match kind:
		"group":
			draw_circle(at, 9.0, edge)
			draw_circle(at, 7.5, col)
			draw_line(at + Vector2(-4, -4), at + Vector2(4, 4), Color.WHITE, 1.8)   # crossed blades
			draw_line(at + Vector2(4, -4), at + Vector2(-4, 4), Color.WHITE, 1.8)
		"loot":
			var d := PackedVector2Array([at + Vector2(0, -9), at + Vector2(7, 0), at + Vector2(0, 9), at + Vector2(-7, 0)])
			draw_colored_polygon(d, col)
			draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), edge, 1.5)
		"chest":
			var box := Rect2(at + Vector2(-7, -5), Vector2(14, 10))
			draw_rect(box, col)
			draw_rect(box, edge, false, 1.5)
			draw_line(at + Vector2(-7, -1), at + Vector2(7, -1), edge, 1.5)
			draw_rect(Rect2(at + Vector2(-1.5, -2), Vector2(3, 4)), edge)
		"exit":
			draw_rect(Rect2(at + Vector2(-7, -2), Vector2(14, 11)), col)
			draw_arc(at + Vector2(0, -2), 7.0, PI, TAU, 16, col, 2.0)
			draw_rect(Rect2(at + Vector2(-3, 1), Vector2(6, 8)), edge)
			draw_arc(at + Vector2(0, 1), 3.0, PI, TAU, 10, edge, 2.0)
		_:
			draw_circle(at, 6.0, col)
