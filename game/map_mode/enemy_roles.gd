class_name EnemyRoles
extends RefCounted
## Map-mode enemy roles (issue #81): who each kind of enemy goes for, and where the Cutter lands. ONE table (ROLES) holds every rule and number.
## Nothing here runs unless `MapMode.active`: Enemy asks `retarget` only behind that flag, so the default game's "closest living party member,
## sticky until it dies" targeting is untouched. There is no threat system yet (real threat-from-damage comes later); a role is a fixed rule.
##
## Rules:
##   closest        today's rule (the sticky nearest member). The role returns "no opinion" and Enemy keeps its own target.
##   flanker        the Cutter (the member farthest back), and the route to her goes AROUND the other members (route_goal).
##   ranged_hitter  whoever last hit it from range (within `memory` s); otherwise closest.
##   top_damage     whoever dealt it the most damage in the last `window` s, re-checked every `recheck` s; otherwise closest.
## `special_*` (the Warden): closest, but every `special_every` s its next attack goes for the farthest member for `special_window` s.
## Provoke overrides every role while it holds (Enemy.provoked_until_ms, set by the power).
## A champion keeps its kind's `variant`, so it follows its kind's rule.

const ROLES := {
	"zombie": {"rule": "closest"},                                        # the frontline
	"ghoul": {"rule": "flanker", "clear": 2.4, "side": 3.4},              # dives the Cutter; `clear`: how close to its line a member counts as in the way
	"rock_thrower": {"rule": "ranged_hitter", "memory": 6.0},
	"brute": {"rule": "top_damage", "window": 5.0, "recheck": 2.0},
	"warden": {"rule": "closest", "special_every": 10.0, "special_window": 5.0},
}
const DEFAULT_ROLE := {"rule": "closest"}   # every kind not listed (spitter, bloater, priest ...)

## Dash formation: on arrival the warrior stands at the group's edge and the Cutter this far behind him, on the side away from the group.
const BACK_MIN := 8.0
const BACK_MAX := 10.0
const BACK := 9.0
## A hit from at least this far away counts as "from range" for the rock thrower's rule.
const RANGED_HIT_MIN := 4.0
const CUTTER_ID := "cutter"

## False restores the old targeting inside map mode (for before/after measurements). The default game never asks.
static var enabled: bool = true

class State extends RefCounted:
	var hits: Array = []        # [time, source Actor, amount, from_range]
	var next_recheck: float = 0.0
	var next_special: float = -1.0
	var special_until: float = -1.0

static func role_of(e: Enemy) -> Dictionary:
	return ROLES.get(e.variant, DEFAULT_ROLE)

static func rule_of(e: Enemy) -> String:
	return String(role_of(e).get("rule", "closest"))

static func state_of(e: Enemy) -> State:
	if not e.has_meta("role_state"):
		e.set_meta("role_state", State.new())
	return e.get_meta("role_state") as State

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Records a blow the enemy took, for the rules that look at who hit it (rock thrower, brute). Map mode only; called from Enemy.receive.
static func note_hit(e: Enemy, result: Dictionary, source_pos: Vector3, now: float = -1.0) -> void:
	var source: Actor = result.get("source") as Actor
	if source == null or not (source is Player):
		return
	var t: float = _now() if now < 0.0 else now
	var st: State = state_of(e)
	var gap: float = Vector2(source_pos.x - e.global_position.x, source_pos.z - e.global_position.z).length()
	st.hits.append([t, source, float(result.get("damage", 0.0)), gap >= RANGED_HIT_MIN])
	while st.hits.size() > 40:
		st.hits.pop_front()

## The member farthest back: the Cutter while she lives, otherwise whoever is farthest from `from`.
static func cutter_of(members: Array, from: Vector3) -> Player:
	var farthest: Player = null
	var far_gap: float = -1.0
	for m in members:
		var p := m as Player
		if p == null or p.dead:
			continue
		if p.member_id == CUTTER_ID:
			return p
		var gap: float = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
		if gap > far_gap:
			far_gap = gap
			farthest = p
	return farthest

static func farthest_of(members: Array, from: Vector3) -> Player:
	var best: Player = null
	var far_gap: float = -1.0
	for m in members:
		var p := m as Player
		if p == null or p.dead:
			continue
		var gap: float = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
		if gap > far_gap:
			far_gap = gap
			best = p
	return best

## The member `e` should go for now, or null for "keep the current target" (Enemy's own sticky closest). Pure apart from the enemy's history.
static func choose(e: Enemy, members: Array, now: float) -> Actor:
	var role: Dictionary = role_of(e)
	var st: State = state_of(e)
	var chosen: Actor = null
	match String(role.get("rule", "closest")):
		"flanker":
			chosen = cutter_of(members, e.global_position)
		"ranged_hitter":
			var memory: float = float(role.get("memory", 6.0))
			for i in range(st.hits.size() - 1, -1, -1):
				var h: Array = st.hits[i]
				if now - float(h[0]) > memory:
					break
				var who: Actor = h[1] as Actor
				if bool(h[3]) and is_instance_valid(who) and not who.dead and members.has(who):
					chosen = who
					break
		"top_damage":
			if now >= st.next_recheck:
				st.next_recheck = now + float(role.get("recheck", 2.0))
				var window: float = float(role.get("window", 5.0))
				var totals: Dictionary = {}
				for h: Array in st.hits:
					if now - float(h[0]) <= window and is_instance_valid(h[1]) and not (h[1] as Actor).dead and members.has(h[1]):
						totals[h[1]] = float(totals.get(h[1], 0.0)) + float(h[2])
				var best: float = 0.0
				for who in totals:
					if float(totals[who]) > best:
						best = float(totals[who])
						chosen = who
	if role.has("special_every"):
		if st.next_special < 0.0:
			st.next_special = now + float(role["special_every"])
		if now >= st.next_special:
			st.next_special = now + float(role["special_every"])
			st.special_until = now + float(role.get("special_window", 5.0))
		if now < st.special_until:
			return farthest_of(members, e.global_position)
		if st.special_until > 0.0:
			st.special_until = -1.0
			return closest_of(members, e.global_position)   # the telegraphed strike is over: back to the nearest
	return chosen

static func closest_of(members: Array, from: Vector3) -> Player:
	var best: Player = null
	var near: float = INF
	for m in members:
		var p := m as Player
		if p == null or p.dead:
			continue
		var gap: float = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
		if gap < near:
			near = gap
			best = p
	return best

## Called by Enemy every physics frame in map mode (never in the default game).
static func retarget(e: Enemy) -> void:
	if not enabled or e.dead:
		return
	if Time.get_ticks_msec() < e.provoked_until_ms:
		return   # Provoke holds: it overrides every role
	var pick: Actor = choose(e, PartyManager.current().living(), _now())
	if pick != null and pick != e.target:
		e.target = pick

## True when `e` is awake and going for the Cutter: the readability marker (a red line) is drawn for it.
static func targets_cutter(e: Enemy) -> bool:
	var p := e.target as Player
	return p != null and p.member_id == CUTTER_ID and not p.dead and not e.dead and e.is_aggro()

## For a flanker: the next point to head for on the way to `goal`, going AROUND any other party member standing on the straight line.
## Everything else (and the default game) gets `goal` back unchanged.
static func route_goal(e: Enemy, goal: Vector3) -> Vector3:
	if not MapMode.active or not enabled or rule_of(e) != "flanker":
		return goal
	var role: Dictionary = role_of(e)
	var a := Vector2(e.global_position.x, e.global_position.z)
	var b := Vector2(goal.x, goal.z)
	var ab: Vector2 = b - a
	var length: float = ab.length()
	if length < 0.5:
		return goal
	var dir: Vector2 = ab / length
	for m in PartyManager.current().living():
		if m == e.target:
			continue
		var c := Vector2(m.global_position.x, m.global_position.z)
		var along: float = (c - a).dot(dir)
		if along < 0.0 or along > length:
			continue
		var off: float = (c - a).cross(dir)   # signed side of the line the member stands on
		if absf(off) > float(role.get("clear", 2.4)):
			continue
		var perp := Vector2(-dir.y, dir.x)
		# Pass on the side the line already leans to; dead centre, on the enemy's own side (its random orbit direction).
		var sign_side: float = signf(off) if absf(off) > 0.05 else e._orbit_dir
		var via: Vector2 = c + perp * sign_side * float(role.get("side", 3.4))
		return Nav.snap(e, Vector3(via.x, goal.y, via.y))
	return goal

# --- Dash formation -------------------------------------------------------------------------------------------------------------------

## Where the Cutter lands: BACK_MIN..BACK_MAX m behind the warrior's `hero_spot`, on the side away from the group (`away` points from the group out
## to the party). `route_spot` is the corridor point that far back (or a zero vector when the route is too short); it is used when it fits, else
## a point straight back. Whatever is chosen is snapped onto the navmesh and kept inside the band when the floor allows (largest first).
static func cutter_spot(body: Node3D, hero_spot: Vector3, away: Vector3, route_spot: Vector3 = Vector3.INF) -> Vector3:
	var flat_away := Vector3(away.x, 0.0, away.z)
	flat_away = flat_away.normalized() if flat_away.length() > 0.05 else Vector3.BACK
	var candidates: Array[Vector3] = []
	if route_spot.is_finite():
		candidates.append(route_spot)
	for back in [BACK, BACK - 1.0, BACK + 1.0, BACK_MIN]:
		for turn in [0.0, 0.5, -0.5, 1.0, -1.0]:
			candidates.append(hero_spot + flat_away.rotated(Vector3.UP, turn) * back)
	var best: Vector3 = hero_spot
	var best_gap: float = -1.0
	for c in candidates:
		var spot: Vector3 = Nav.snap(body, c)
		var gap: float = Vector2(spot.x - hero_spot.x, spot.z - hero_spot.z).length()
		if gap >= BACK_MIN and gap <= BACK_MAX:
			return spot
		if gap <= BACK_MAX and gap > best_gap:
			best_gap = gap
			best = spot
	return best
