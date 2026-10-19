class_name MapModeOverlay
extends Control
## Map mode's full-screen node map (issue #79). The dungeon is a graph: every node is an ICON ONLY (skull = pack, crowned skull = champion,
## a cluster = swarm, chest, shrine, boss), sized by the group's strength, joined by drawn corridors. The text label appears only for the
## hovered or controller-focused node, in a tooltip that stays on screen.
##
## Marker rows given to open()/set_markers(): {"id", "pos": Vector3, "kind", "state", "strength", "label"}. `state` is "cleared", "reachable"
## (bright, clickable, has a tooltip) or "beyond" (a dim icon: no tooltip, not clickable); hidden nodes are simply not passed. A row without
## a state counts as reachable, which is what the flat Crypt map uses. Links (set_links) switch the overlay to the graph view: the graph's own
## bounding box is fitted to the whole panel. Without links it shows the terrain, as before.
## The panel leaves the hotbar, both vessels and the top-left party panel uncovered. While open it swallows all mouse and pad input.

signal selected(id: int)
signal closed()

const TOP_INSET := 110.0          # keeps the top-left party panel readable
const MARGIN := 16.0
const ICON_PAD := 34.0            # room between the graph's outermost icon and the panel edge
const ICON_GAP := 6.0             # clear space kept between any two icons
const GRAPH_STRETCH := 4.0         # the graph may be stretched this much along the panel's longer side to fill it
const MIN_ICON_SCALE := 0.45
const HIT_EXTRA := 4.0
const STICK_THRESHOLD := 0.6
const FOCUS_CONE := 1.22          # rad (70 deg): a focus move only goes to nodes this close to the pushed direction
const REPEAT_FIRST := 0.35
const REPEAT_NEXT := 0.16
const TIP_MAX_WIDTH := 380.0
const COMBAT_KINDS := ["group", "pack", "swarm", "champion", "boss"]
const KIND_COLOR := {
	"group": Color(0.86, 0.20, 0.16), "pack": Color(0.86, 0.20, 0.16), "swarm": Color(0.90, 0.38, 0.18),
	"champion": Color(0.95, 0.72, 0.22), "boss": Color(0.95, 0.30, 0.20),
	"loot": Color(0.95, 0.80, 0.30), "chest": Color(0.84, 0.64, 0.30), "shrine": Color(0.45, 0.78, 0.95),
	"exit": Color(0.55, 0.78, 0.95), "start": Color(0.70, 0.85, 0.70),
}

var map_data: MinimapMap
## Developer/test hook: lay the overlay out for this screen size instead of the viewport's.
var screen_override: Vector2 = Vector2.ZERO

var _open: bool = false
var _can_close: bool = true
var _markers: Array = []
var _links: Array = []
var _frame: Rect2 = Rect2()
var _hero: Vector3 = Vector3.ZERO
var _hover: int = -1
var _focus: int = -1
var _focus_shown: bool = false   # the controller focus (ring and tooltip) shows once the pad or keys are used; the mouse hides it
var _stick_active: bool = false
var _stick_timer: float = 0.0
var _layout: Dictionary = {}      # id -> {"at": Vector2, "r": float}
var _xf: Transform2D = Transform2D()
var _layout_dirty: bool = true

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

# ---- fitting ----------------------------------------------------------------------------------------------------------------------------

## Terrain view: world (x, z) metres -> panel pixels, the whole map fitted into `panel`, aspect kept, centred, north up (no yaw).
static func fit_transform(map: MinimapMap, panel: Rect2) -> Transform2D:
	if map == null or map.cols <= 0 or map.rows <= 0:
		return Transform2D(0.0, panel.get_center())
	return fit_bounds(Rect2(map.origin, Vector2(map.cols, map.rows) * MinimapMap.CELL), panel)

## World (x, z) -> panel pixels with `bounds` fitted to `panel`, aspect kept, centred. A long north-south place is turned a quarter so it fills
## a wide screen.
## `stretch` > 1 lets the picture use the panel's other dimension too, by stretching one axis up to that factor more than the other (a schematic
## graph can be; the terrain cannot).
static func fit_bounds(bounds: Rect2, panel: Rect2, stretch: float = 1.0) -> Transform2D:
	var world := Vector2(maxf(bounds.size.x, 8.0), maxf(bounds.size.y, 8.0))
	var c: Vector2 = bounds.get_center()
	if world.y > world.x * 1.3 and panel.size.x > panel.size.y:
		var sa: Vector2 = _axis_scales(Vector2(world.y, world.x), panel.size, stretch)   # world z runs across the screen, world x up it
		return Transform2D(Vector2(0.0, -sa.y), Vector2(sa.x, 0.0), panel.get_center() - Vector2(c.y * sa.x, -c.x * sa.y))
	var s: Vector2 = _axis_scales(world, panel.size, stretch)
	return Transform2D(Vector2(s.x, 0.0), Vector2(0.0, s.y), panel.get_center() - c * s)

static func _axis_scales(world: Vector2, panel: Vector2, stretch: float) -> Vector2:
	var sx: float = panel.x / world.x
	var sy: float = panel.y / world.y
	var low: float = minf(sx, sy)
	return Vector2(minf(sx, low * stretch), minf(sy, low * stretch))

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

func is_graph_view() -> bool:
	return not _links.is_empty()

# ---- public API -------------------------------------------------------------------------------------------------------------------------

func open(markers: Array, hero_pos: Vector3, can_close: bool) -> void:
	_markers = markers.duplicate()
	_hero = hero_pos
	_can_close = can_close
	_hover = -1
	_focus = -1
	_focus_shown = Gamepad.active
	_stick_active = false
	_open = true
	_fit_to_screen()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_layout_dirty = true
	_focus = _initial_focus()
	queue_redraw()

func set_markers(markers: Array) -> void:
	_markers = markers.duplicate()
	_layout_dirty = true
	if _hover >= 0 and not _clickable(_hover):
		_hover = -1
	if _focus < 0 or not _clickable(_focus):
		_focus = _initial_focus()
	queue_redraw()

## Corridor rows {"a", "b", "pts": Array of Vector3 or Vector2 world points}. A non-empty list switches to the graph view.
func set_links(links: Array) -> void:
	_links = links.duplicate()
	_layout_dirty = true
	queue_redraw()

## Fixes the world rectangle (x, z) the graph view fits to, so the picture does not jump as nodes appear. Empty = fit what is shown.
func set_frame(world_rect: Rect2) -> void:
	_frame = world_rect
	_layout_dirty = true

func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_hover = -1

func is_open() -> bool:
	return _open

## The hovered node (mouse), else the controller-focused one (once the pad or keys moved it); -1 if none.
func focused_id() -> int:
	if _hover >= 0:
		return _hover
	return _focus if _focus_shown and _clickable(_focus) else -1

## Where a node's icon centre is on screen (-1, -1 if it is not shown).
func marker_screen_pos(id: int) -> Vector2:
	_ensure_layout()
	return (_layout[id]["at"] as Vector2) if _layout.has(id) else Vector2(-1, -1)

## The square the node's icon occupies on screen.
func icon_rect(id: int) -> Rect2:
	_ensure_layout()
	if not _layout.has(id):
		return Rect2()
	var at: Vector2 = _layout[id]["at"]
	var r: float = _layout[id]["r"]
	return Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0)

## The tooltip text for the hovered or focused node ("" when it has none: nothing focused, or a dim "beyond" icon).
func tooltip_text() -> String:
	var id: int = focused_id()
	var i: int = _find(id)
	return String(_markers[i].get("label", "")) if i >= 0 else ""

## The tooltip's screen rectangle (Rect2() when none is shown).
func tooltip_rect() -> Rect2:
	var text: String = tooltip_text()
	if text == "":
		return Rect2()
	return _tip_rect(text, focused_id())

func panel_inner_rect() -> Rect2:
	return panel_rect().grow(-ICON_PAD)

## Cycles controller focus by `step` through the clickable nodes (ordered by angle around their centre).
func select_next(step: int) -> void:
	var ids: Array = _sorted_ids()
	if ids.is_empty():
		return
	var at: int = ids.find(_focus)
	_focus = int(ids[posmod((0 if at < 0 else at) + step, ids.size())]) if at >= 0 else int(ids[0])
	_hover = -1
	_focus_shown = true
	queue_redraw()

## Moves the controller focus to the neighbouring clickable node best in line with `dir` (screen direction). Stays put when none is that way.
func move_focus(dir: Vector2) -> void:
	_ensure_layout()
	_focus_shown = true
	if dir.length() < 0.1 or not _layout.has(_focus):
		if not _clickable(_focus):
			_focus = _initial_focus()
		return
	var from: Vector2 = _layout[_focus]["at"]
	var best: int = -1
	var best_score: float = INF
	for m in _markers:
		var id: int = int(m["id"])
		if id == _focus or not _clickable(id):
			continue
		var v: Vector2 = (_layout[id]["at"] as Vector2) - from
		var ang: float = absf(v.angle_to(dir))
		if ang > FOCUS_CONE:
			continue
		var score: float = v.length() * (1.0 + ang * 1.5)
		if score < best_score:
			best_score = score
			best = id
	if best >= 0:
		_focus = best
		_hover = -1
		queue_redraw()

func choose_focused() -> void:
	var id: int = focused_id()
	if id >= 0 and _clickable(id):
		selected.emit(id)

# ---- input ------------------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		var h: int = _hit((event as InputEventMouseMotion).position)
		_focus_shown = false
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
		if _focus_shown or _hover >= 0:
			choose_focused()
		else:
			_focus_shown = true
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		move_focus(Vector2.RIGHT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		move_focus(Vector2.LEFT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		move_focus(Vector2.DOWN)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		move_focus(Vector2.UP)
		get_viewport().set_input_as_handled()

## The Hud is not sized to the screen, so the overlay takes the viewport's size itself.
func _fit_to_screen() -> void:
	var screen: Vector2 = screen_override if screen_override != Vector2.ZERO else get_viewport_rect().size
	if size != screen or position != Vector2.ZERO:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		position = Vector2.ZERO
		size = screen
		_layout_dirty = true
		queue_redraw()

## Left stick: edge-triggered, then repeating while held, in the direction pushed.
func _process(delta: float) -> void:
	_fit_to_screen()
	var v: Vector2 = Gamepad.move_vector()
	if v.length() < STICK_THRESHOLD:
		_stick_active = false
		return
	if not _stick_active:
		_stick_active = true
		_stick_timer = REPEAT_FIRST
		move_focus(v)
		return
	_stick_timer -= delta
	if _stick_timer <= 0.0:
		_stick_timer = REPEAT_NEXT
		move_focus(v)

# ---- geometry ---------------------------------------------------------------------------------------------------------------------------

func _find(id: int) -> int:
	for i in _markers.size():
		if int(_markers[i]["id"]) == id:
			return i
	return -1

func _state(m: Dictionary) -> String:
	return String(m.get("state", "reachable"))

func _clickable(id: int) -> bool:
	var i: int = _find(id)
	return i >= 0 and _state(_markers[i]) != "beyond"

func _initial_focus() -> int:
	var best: int = -1
	var best_d: float = INF
	for pass_reachable in [true, false]:
		for m in _markers:
			var id: int = int(m["id"])
			if not _clickable(id) or (pass_reachable and _state(m) != "reachable"):
				continue
			var p: Vector3 = m["pos"]
			var d: float = Vector2(p.x - _hero.x, p.z - _hero.z).length()
			if d < best_d:
				best_d = d
				best = id
		if best >= 0:
			break
	return best

func _radius_of(m: Dictionary) -> float:
	var kind: String = String(m.get("kind", "group"))
	if kind in COMBAT_KINDS:
		var r: float = 11.0 + 2.6 * sqrt(maxf(float(m.get("strength", 1)), 1.0))
		if kind == "swarm":
			r *= 1.2
		if kind == "boss":
			r = maxf(r, 20.0)
		return clampf(r, 12.0, 26.0)
	return 9.0 if kind == "loot" else 11.0

func _world_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for m in _markers:
		pts.append(Vector2((m["pos"] as Vector3).x, (m["pos"] as Vector3).z))
	for l in _links:
		for p in l["pts"]:
			pts.append(Vector2(p.x, p.y) if p is Vector2 else Vector2(p.x, p.z))
	return pts

func _compute_layout() -> void:
	_layout.clear()
	var panel: Rect2 = panel_rect()
	if is_graph_view():
		var bounds: Rect2 = _frame
		if bounds.size == Vector2.ZERO:
			var pts: Array[Vector2] = _world_points()
			bounds = Rect2(pts[0], Vector2.ZERO) if not pts.is_empty() else Rect2(Vector2.ZERO, Vector2(8, 8))
			for p in pts:
				bounds = bounds.expand(p)
		_xf = fit_bounds(bounds, panel_inner_rect(), GRAPH_STRETCH)
	else:
		_xf = fit_transform(map_data, panel)
	var scale: float = 1.0
	for m in _markers:
		var p: Vector3 = m["pos"]
		_layout[int(m["id"])] = {"at": _xf * Vector2(p.x, p.z), "r": _radius_of(m)}
	# Icons never overlap: where the screen is too small for the graph, they shrink together instead.
	var ids: Array = _layout.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = _layout[ids[i]]
			var b: Dictionary = _layout[ids[j]]
			var need: float = float(a["r"]) + float(b["r"]) + ICON_GAP
			var have: float = (a["at"] as Vector2).distance_to(b["at"])
			if have < need:
				scale = minf(scale, have / need)
	scale = clampf(scale, MIN_ICON_SCALE, 1.0)
	for id in _layout:
		_layout[id]["r"] = float(_layout[id]["r"]) * scale
	_layout_dirty = false

func _ensure_layout() -> void:
	if _layout_dirty:
		_compute_layout()

func _hit(at: Vector2) -> int:
	_ensure_layout()
	var best: int = -1
	var best_d: float = INF
	for m in _markers:
		var id: int = int(m["id"])
		if not _clickable(id):
			continue
		var d: float = (_layout[id]["at"] as Vector2).distance_to(at)
		if d <= float(_layout[id]["r"]) + HIT_EXTRA and d < best_d:
			best_d = d
			best = id
	return best

func _sorted_ids() -> Array:
	var clickable: Array = []
	for m in _markers:
		if _clickable(int(m["id"])):
			clickable.append(m)
	if clickable.is_empty():
		return []
	var c := Vector2.ZERO
	for m in clickable:
		c += Vector2((m["pos"] as Vector3).x, (m["pos"] as Vector3).z)
	c /= float(clickable.size())
	var keyed: Array = []
	for m in clickable:
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
	_ensure_layout()
	var panel: Rect2 = panel_rect()
	UiTheme.draw_panel(self, panel.grow(6.0), 0.94)
	draw_rect(panel, Color(0.03, 0.025, 0.022, 0.96))
	var graph: bool = is_graph_view()
	if not graph and map_data != null:
		map_data.draw(self, _xf)
		_draw_hero(_xf * Vector2(_hero.x, _hero.z))
	if graph:
		_draw_links()
	var active: int = focused_id()
	# Dim icons first, then the lit ones, then the focused one on top.
	for pass_state in ["beyond", "cleared", "reachable"]:
		for m in _markers:
			if _state(m) == pass_state and int(m["id"]) != active:
				_draw_icon(m, false)
	var ai: int = _find(active)
	if ai >= 0:
		_draw_icon(_markers[ai], true)
	if graph:
		_draw_you_are_here()
	var tip: String = tooltip_text()
	if tip != "":
		_draw_tooltip(tip, active)
	var help: String = "Click a lit node to dash there" if graph else "Click a group to dash there"
	if Gamepad.active:
		help = "Stick: move between nodes      A  dash there" + ("      B  close" if _can_close else "")
	UiTheme.text(self, UiTheme.heading_font(), Vector2(panel.position.x, panel.end.y + 22.0), help, 14, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x)

func _link_world(l: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in l["pts"]:
		out.append(_xf * (Vector2(p.x, p.y) if p is Vector2 else Vector2(p.x, p.z)))
	return out

func _draw_links() -> void:
	var state: Dictionary = {}
	for m in _markers:
		state[int(m["id"])] = _state(m)
	for l in _links:
		var a: String = String(state.get(int(l["a"]), "hidden"))
		var b: String = String(state.get(int(l["b"]), "hidden"))
		if a == "hidden" or b == "hidden" or (a == "beyond" and b == "beyond"):
			continue
		var pts: PackedVector2Array = _link_world(l)
		if pts.size() < 2:
			continue
		var lit: bool = a != "beyond" and b != "beyond"
		var done: bool = a == "cleared" and b == "cleared"
		var core: Color = Color(0.78, 0.62, 0.34) if done else (Color(0.62, 0.50, 0.32) if lit else Color(0.34, 0.30, 0.27, 0.7))
		draw_polyline(pts, Color(0, 0, 0, 0.8), 8.0, true)
		draw_polyline(pts, core.darkened(0.45), 5.0, true)
		draw_polyline(pts, core, 2.0, true)

func _draw_you_are_here() -> void:
	var best: int = -1
	var best_d: float = INF
	for m in _markers:
		if _state(m) != "cleared":
			continue
		var p: Vector3 = m["pos"]
		var d: float = Vector2(p.x - _hero.x, p.z - _hero.z).length()
		if d < best_d:
			best_d = d
			best = int(m["id"])
	if best < 0:
		return
	var at: Vector2 = (_layout[best]["at"] as Vector2) - Vector2(0.0, float(_layout[best]["r"]) + 10.0)
	var pts := PackedVector2Array([at + Vector2(-7, -7), at + Vector2(7, -7), at + Vector2(0, 5)])
	draw_colored_polygon(pts, Color.WHITE)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color.BLACK, 1.5)

func _draw_hero(at: Vector2) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -9), at + Vector2(7, 7), at + Vector2(0, 3), at + Vector2(-7, 7)])
	draw_colored_polygon(pts, Color.WHITE)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.BLACK, 1.5)

## A tooltip beside the node (right, else left), kept inside the screen. Title line, then the details.
func _tip_rect(text: String, id: int) -> Rect2:
	var lines: PackedStringArray = text.split("\n")
	var head: Font = UiTheme.heading_font()
	var body: Font = ThemeDB.fallback_font
	var box: StyleBoxTexture = UiTheme.tooltip_box()
	var w: float = 0.0
	var h: float = 0.0
	for i in lines.size():
		var f: Font = head if i == 0 else body
		var fs: int = 15 if i == 0 else 14
		w = maxf(w, f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		h += float(fs) + 5.0
	w = minf(w, TIP_MAX_WIDTH) + box.get_minimum_size().x
	h += box.get_minimum_size().y - 5.0
	_ensure_layout()
	var at: Vector2 = _layout[id]["at"] if _layout.has(id) else Vector2.ZERO
	var r: float = _layout[id]["r"] if _layout.has(id) else 10.0
	var x: float = at.x + r + 10.0
	if x + w > size.x - 6.0:
		x = at.x - r - 10.0 - w
	var rect := Rect2(Vector2(x, at.y - h * 0.5), Vector2(w, h))
	rect.position.x = clampf(rect.position.x, 6.0, maxf(size.x - w - 6.0, 6.0))
	rect.position.y = clampf(rect.position.y, 6.0, maxf(size.y - h - 6.0, 6.0))
	return rect

func _draw_tooltip(text: String, id: int) -> void:
	var rect: Rect2 = _tip_rect(text, id)
	draw_style_box(UiTheme.tooltip_box(), rect)
	var lines: PackedStringArray = text.split("\n")
	var y: float = rect.position.y + UiTheme.tooltip_box().get_offset().y - 2.0
	for i in lines.size():
		var fs: int = 15 if i == 0 else 14
		y += float(fs)
		var col: Color = UiTheme.ACCENT if i == 0 else UiTheme.TEXT
		if lines[i].begins_with("Requires") or lines[i].begins_with("Cleared"):
			col = UiTheme.TEXT_DIM
		UiTheme.text(self, UiTheme.heading_font() if i == 0 else ThemeDB.fallback_font, Vector2(rect.position.x + UiTheme.tooltip_box().get_offset().x, y), lines[i], fs, col, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - UiTheme.tooltip_box().get_minimum_size().x)
		y += 5.0

func _draw_icon(m: Dictionary, on: bool) -> void:
	var id: int = int(m["id"])
	var at: Vector2 = _layout[id]["at"]
	var r: float = _layout[id]["r"]
	var kind: String = String(m.get("kind", "group"))
	var st: String = _state(m)
	var col: Color = KIND_COLOR.get(kind, Color.WHITE)
	var edge := Color(0.05, 0.03, 0.03)
	match st:
		"cleared":
			col = col.lerp(Color(0.5, 0.5, 0.5), 0.55)
			col.a = 0.8
			edge.a = 0.8
		"beyond":
			col = col.lerp(Color(0.45, 0.45, 0.5), 0.7)
			col.a = 0.42
			edge.a = 0.42
	if on:
		draw_arc(at, r + 5.0, 0.0, TAU, 40, Color(1, 0.95, 0.7), 3.0)
		draw_circle(at, r + 3.0, Color(1, 0.95, 0.7, 0.14))
	elif st == "reachable":
		draw_circle(at, r + 2.5, Color(0.0, 0.0, 0.0, 0.35))
	match kind:
		"group", "pack":
			_skull(at, r, col, edge, false)
		"champion":
			_skull(at, r, col, edge, true)
		"swarm":
			_skull(at + Vector2(-r * 0.42, r * 0.22), r * 0.62, col.darkened(0.2), edge, false)
			_skull(at + Vector2(r * 0.42, r * 0.22), r * 0.62, col.darkened(0.2), edge, false)
			_skull(at + Vector2(0, -r * 0.1), r * 0.8, col, edge, false)
		"boss":
			var horn := PackedVector2Array([at + Vector2(-r * 0.55, -r * 0.35), at + Vector2(-r * 0.95, -r * 0.95), at + Vector2(-r * 0.15, -r * 0.7)])
			draw_colored_polygon(horn, col.lightened(0.3))
			horn = PackedVector2Array([at + Vector2(r * 0.55, -r * 0.35), at + Vector2(r * 0.95, -r * 0.95), at + Vector2(r * 0.15, -r * 0.7)])
			draw_colored_polygon(horn, col.lightened(0.3))
			_skull(at + Vector2(0, r * 0.08), r * 0.9, col, edge, true)
		"chest":
			var box := Rect2(at + Vector2(-r * 0.7, -r * 0.5), Vector2(r * 1.4, r))
			draw_rect(box, col)
			draw_rect(box, edge, false, 1.5)
			draw_line(at + Vector2(-r * 0.7, -r * 0.1), at + Vector2(r * 0.7, -r * 0.1), edge, 1.5)
			draw_rect(Rect2(at + Vector2(-r * 0.15, -r * 0.2), Vector2(r * 0.3, r * 0.4)), edge)
		"shrine":
			draw_rect(Rect2(at + Vector2(-r * 0.6, r * 0.3), Vector2(r * 1.2, r * 0.45)), col.darkened(0.35))
			draw_rect(Rect2(at + Vector2(-r * 0.3, -r * 0.1), Vector2(r * 0.6, r * 0.45)), col.darkened(0.2))
			var flame := PackedVector2Array([at + Vector2(0, -r * 0.95), at + Vector2(r * 0.4, -r * 0.3), at + Vector2(0, -r * 0.05), at + Vector2(-r * 0.4, -r * 0.3)])
			draw_colored_polygon(flame, col.lightened(0.25))
			draw_polyline(PackedVector2Array([flame[0], flame[1], flame[2], flame[3], flame[0]]), edge, 1.5)
		"start", "exit":
			draw_rect(Rect2(at + Vector2(-r * 0.6, -r * 0.2), Vector2(r * 1.2, r * 0.95)), col)
			draw_arc(at + Vector2(0, -r * 0.2), r * 0.6, PI, TAU, 16, col, 2.0)
			draw_rect(Rect2(at + Vector2(-r * 0.28, r * 0.1), Vector2(r * 0.56, r * 0.65)), edge)
			draw_arc(at + Vector2(0, r * 0.1), r * 0.28, PI, TAU, 10, edge, 2.0)
		"loot":
			var d := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.78, 0), at + Vector2(0, r), at + Vector2(-r * 0.78, 0)])
			draw_colored_polygon(d, col)
			draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), edge, 1.5)
		_:
			draw_circle(at, r * 0.6, col)
	if st == "cleared" and kind in COMBAT_KINDS + ["chest", "shrine"]:
		var tick := PackedVector2Array([at + Vector2(r * 0.25, r * 0.55), at + Vector2(r * 0.55, r * 0.85), at + Vector2(r * 1.05, r * 0.2)])
		draw_polyline(tick, Color(0.1, 0.1, 0.1), 5.0)
		draw_polyline(tick, Color(0.45, 0.9, 0.45), 2.5)

## A skull filling a circle of radius `r` around `at`; the crowned one (a champion) wears a gold crown on top.
func _skull(at: Vector2, r: float, col: Color, edge: Color, crowned: bool) -> void:
	var u: float = r / (1.3 if crowned else 1.0)
	var head_c: Vector2 = at + Vector2(0, -u * (0.08 if not crowned else -0.12))
	draw_circle(head_c, u * 0.82, edge)
	draw_circle(head_c, u * 0.7, col)
	var jaw := Rect2(head_c + Vector2(-u * 0.38, u * 0.35), Vector2(u * 0.76, u * 0.5))
	draw_rect(jaw.grow(u * 0.1), edge)
	draw_rect(jaw, col)
	var eye_col := Color(edge.r, edge.g, edge.b, edge.a)
	draw_circle(head_c + Vector2(-u * 0.27, -u * 0.05), u * 0.2, eye_col)
	draw_circle(head_c + Vector2(u * 0.27, -u * 0.05), u * 0.2, eye_col)
	draw_line(head_c + Vector2(-u * 0.18, u * 0.55), head_c + Vector2(-u * 0.18, u * 0.8), eye_col, 1.2)
	draw_line(head_c + Vector2(0, u * 0.55), head_c + Vector2(0, u * 0.8), eye_col, 1.2)
	draw_line(head_c + Vector2(u * 0.18, u * 0.55), head_c + Vector2(u * 0.18, u * 0.8), eye_col, 1.2)
	if crowned:
		var base: float = -u * 0.55
		var crown := PackedVector2Array([
			head_c + Vector2(-u * 0.55, base), head_c + Vector2(-u * 0.6, base - u * 0.6), head_c + Vector2(-u * 0.3, base - u * 0.25),
			head_c + Vector2(0, base - u * 0.72), head_c + Vector2(u * 0.3, base - u * 0.25), head_c + Vector2(u * 0.6, base - u * 0.6),
			head_c + Vector2(u * 0.55, base)])
		var gold := Color(1.0, 0.82, 0.25, col.a)
		draw_colored_polygon(crown, gold)
		var outline := crown.duplicate()
		outline.append(crown[0])
		draw_polyline(outline, edge, 1.4)
