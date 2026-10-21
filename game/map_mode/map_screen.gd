class_name MapModeScreen
extends RefCounted
## Map mode (issue #87): the Cutter stays on screen. After a dash and through a fight he must project INSIDE the part of the screen the HUD leaves
## free, not under the party portraits (top left), the target banner (top), the hotbar or the minimap (bottom). ONE safe area (safe_rect) and the
## helpers that use it: the dash formation clamps his landing spot (clamp_spot), his firing positions are refused when they are off screen
## (BowAttack._spot_good), and MapMode checks him once a second during a fight and walks him back (guard_goal). Nothing runs outside map mode.
## Every number is here.

const PORTRAIT_STRIP := 252.0   # canvas units: the left strip the Hero and Cutter cards use (MapModeOverlay.PARTY_CARDS_WIDTH)
const MARGIN := 16.0            # clear space kept from the screen's edges and from every HUD piece
const BANNER_CLEAR := 116.0     # canvas units from the top: the target banner (4 + 68) and its affix chips row, plus a little air
const BODY_HEIGHT := 1.8        # m: the head must be inside too, not only the feet
const GUARD_EVERY := 0.05       # s between the checks of the guard (one projection each)
const GUARD_TRIGGER_INSET := 45.0   # canvas units: the guard acts when he gets this close to the edge, before he is over it
const GUARD_HOLD := 2.5         # s the guard's goal is followed, instead of any firing-position goal, at most
const GUARD_ARRIVE := 0.8       # m: the guard's goal counts as reached
const GUARD_MIN_MOVE := 1.6     # m: a goal nearer than this to where he stands is not worth interrupting a shot for
const SEARCH_STEP := 0.75       # m between rings of candidate spots round the preferred one
const SEARCH_RINGS := 20
const SEARCH_ANGLES := 16
const CLAMP_INSET := 70.0       # canvas units: a clamped spot lies this far inside the area, so walking short of it by a step still counts as on screen
const ARRIVAL_INSET := 90.0     # canvas units: the landing spot lies this far inside, since the warrior walks on into the fight and the camera follows him
const ENEMY_CLEAR := 2.0        # m: a clamped spot keeps this far from any awake enemy (a body in the way is what holds him off screen)
const MIN_GAP := 2.0            # m: a clamped spot is never nearer the warrior than this
const MAX_GAP := 14.0           # m
const FIRE_RINGS: Array[float] = [12.0, 10.5, 9.0]   # map mode's preferred shooting ranges (the default game's are 10-15 m): closer, so he stays in frame

## False restores the old behaviour in map mode (for before/after measurements and screenshots). The default game never asks.
static var enabled: bool = true

## The screen area free of the HUD, in canvas units (the same units unproject_position and the HUD's rect helpers use): clear of the party
## portraits on the left, the target banner on top and the hotbar (and, in the old HUD, the vessels) below. The minimap is a corner piece, kept out
## by blocked_rects, so it does not cost the whole bottom edge.
static func safe_rect(size_px: Vector2, hud: Hud = null) -> Rect2:
	var bottom: float = size_px.y - MARGIN
	if hud != null:
		bottom = minf(bottom, hud.hotbar_rect(size_px).position.y - MARGIN)
		if not hud.use_ds2_ui:
			bottom = minf(bottom, minf(Hud.orb_rect(size_px, false).position.y, Hud.orb_rect(size_px, true).position.y) - MARGIN)
	var left: float = PORTRAIT_STRIP + MARGIN
	var right: float = size_px.x - MARGIN
	return Rect2(Vector2(left, BANNER_CLEAR), Vector2(maxf(right - left, 64.0), maxf(bottom - BANNER_CLEAR, 64.0)))

## HUD pieces inside the safe rectangle that still need keeping clear: the minimap.
static func blocked_rects(size_px: Vector2, hud: Hud = null) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var ds2: bool = hud == null or hud.use_ds2_ui
	out.append(Hud.minimap_rect(size_px, ds2).grow(MARGIN))
	return out

## The safe area for `anchor`'s viewport (and the HUD found beside the map mode, if any).
static func current_rect(anchor: Node) -> Rect2:
	var vp: Viewport = anchor.get_viewport()
	var hud: Hud = MapMode.current.hud if MapMode.current != null else null
	return safe_rect(vp.get_visible_rect().size, hud)

static func current_blocked(anchor: Node) -> Array[Rect2]:
	var hud: Hud = MapMode.current.hud if MapMode.current != null else null
	return blocked_rects(anchor.get_viewport().get_visible_rect().size, hud)

## `inside` against the HUD as it is now, through the viewport's current camera.
static func inside_now(body: Node3D, at: Vector3, shift: Vector3 = Vector3.ZERO, inset: float = 0.0) -> bool:
	at.y = body.global_position.y   # a navmesh point floats above the floor: judge every spot at the height the body's feet stand at
	return inside(body.get_viewport().get_camera_3d(), at, current_rect(body), shift, current_blocked(body), inset)

## Whether a ground point `at` (a standing body) projects inside `rect` through `camera`, feet and head. `shift` is how far the camera will move from
## where it is now (it follows the warrior): a point is judged as it will look then.
static func inside(camera: Camera3D, at: Vector3, rect: Rect2, shift: Vector3 = Vector3.ZERO, blocked: Array[Rect2] = [], inset: float = 0.0) -> bool:
	if camera == null:
		return true
	rect = rect.grow(-inset)
	for height in [0.0, BODY_HEIGHT]:
		var p: Vector3 = at - shift + Vector3.UP * height
		if camera.is_position_behind(p):
			return false
		var screen: Vector2 = camera.unproject_position(p)
		if not rect.has_point(screen):
			return false
		for box in blocked:
			if box.grow(inset).has_point(screen):
				return false
	return true

## Whether `body`'s firing position `spot` is on screen as the camera is now (map mode only; elsewhere always true).
static func spot_visible(body: Node3D, spot: Vector3) -> bool:
	if not MapMode.active or not enabled:
		return true
	return inside_now(body, spot, Vector3.ZERO, CLAMP_INSET)

## The camera's move from now to when it is centred on `warrior_at`.
static func camera_shift(body: Node3D, warrior_at: Vector3) -> Vector3:
	var rig := body.get_tree().get_first_node_in_group("camera_rig") as Node3D
	if rig == null:
		return Vector3.ZERO
	var shift: Vector3 = warrior_at - rig.global_position
	shift.y = 0.0
	return shift

## `preferred` if it is inside the safe area, else the navmesh spot nearest to it that is (never nearer the warrior than MIN_GAP, never farther
## than MAX_GAP). Returns `preferred` when nothing inside is found (the floor allows nothing better).
static func clamp_spot(body: Node3D, preferred: Vector3, warrior_at: Vector3, inset: float = CLAMP_INSET) -> Vector3:
	var camera: Camera3D = body.get_viewport().get_camera_3d()
	if camera == null or not enabled:
		return preferred
	var shift: Vector3 = camera_shift(body, warrior_at)
	if inside_now(body, preferred, shift, inset):
		return preferred
	# A comfortable inset first; when the floor offers nothing that deep inside (a narrow corridor), settle for less, down to the bare edge.
	for use in [inset, inset * 0.5, 0.0]:
		var found: Vector3 = _nearest_inside(body, preferred, warrior_at, shift, use)
		if found.is_finite():
			return found
	return preferred

static func _nearest_inside(body: Node3D, preferred: Vector3, warrior_at: Vector3, shift: Vector3, inset: float) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_gap: float = INF
	for ring in range(1, SEARCH_RINGS + 1):
		for k in SEARCH_ANGLES:
			var angle: float = TAU * float(k) / SEARCH_ANGLES
			var raw: Vector3 = preferred + Vector3(cos(angle), 0.0, sin(angle)) * (ring * SEARCH_STEP)
			var spot: Vector3 = Nav.snap(body, raw)
			var from_warrior: float = Vector2(spot.x - warrior_at.x, spot.z - warrior_at.z).length()
			if from_warrior < MIN_GAP or from_warrior > MAX_GAP or not inside_now(body, spot, shift, inset) or _enemy_near(body, spot):
				continue
			var gap: float = Vector2(spot.x - preferred.x, spot.z - preferred.z).length()
			if gap < best_gap:
				best_gap = gap
				best = spot
		if best_gap < INF:
			break   # the rings grow outward: the first ring with a spot holds the nearest (within one step)
	return best

static func _enemy_near(body: Node3D, spot: Vector3) -> bool:
	for node in body.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and not e.dead and e.is_aggro() and Vector2(e.global_position.x - spot.x, e.global_position.z - spot.z).length() < ENEMY_CLEAR:
			return true
	return false

## During a fight: where the Cutter should go now, or Vector3.INF when he is on screen already (or there is nothing better).
static func guard_goal(body: Node3D, warrior_at: Vector3) -> Vector3:
	var camera: Camera3D = body.get_viewport().get_camera_3d()
	if camera == null or not enabled:
		return Vector3.INF
	if inside_now(body, body.global_position, Vector3.ZERO, GUARD_TRIGGER_INSET):
		return Vector3.INF
	var spot: Vector3 = clamp_spot(body, body.global_position, warrior_at)
	# A goal that is (nearly) where he already stands is no goal: following it cancels his shot for nothing, and it comes back every check,
	# so he never got a shot off (draw, cancel, draw, cancel: the glitching hands at the first fight).
	if spot.distance_to(body.global_position) <= GUARD_MIN_MOVE and inside_now(body, body.global_position):
		return Vector3.INF   # (a body that is really over the edge is pulled in however short the step)
	if inside_now(body, spot, Vector3.ZERO, GUARD_TRIGGER_INSET):
		return spot
	return Vector3.INF
