class_name EnemyRoles
extends RefCounted
## Enemy targeting (issue #109): MMO-style THREAT, in the normal game and in map mode alike. Every number lives in this file.
## An enemy nobody has any threat on yet falls back to Enemy's own "closest living party member, sticky until it dies".
##
## Rules:
##   Each enemy has a threat table (party member -> threat) and goes for the member with the most.
##   Damage is 1 threat per point (basic attacks, powers and procs alike); a TANK member's threat (damage, healing) is multiplied (WARRIOR_THREAT_MULT).
##   Healing: the HEALER (who cast it or drank the potion) gets HEAL_THREAT per point healed, split evenly across every enemy that already has a
##   party member in its threat table.
##   Taking aggro (WoW): a member takes an enemy from its current holder only above TAKE_MELEE (110%) of the holder's threat when he stands within
##   MELEE_HIT_MAX of the enemy, above TAKE_RANGED (130%) otherwise. A member nobody has threat on yet is simply the top.
##   Pulls: the first member to come within a group's aggro range, or to hit any of it (or the one closest to it when the fight starts), gets
##   PULL_THREAT on EVERY enemy of that group.
##   Provoke is a taunt (`taunt`): the tank's threat becomes the top plus TAUNT_BONUS (110%) and Enemy.provoked_until_ms locks the enemy on him.
##   A dead member's threat is wiped from every table. No decay, no threat display.
## The Warden's special (`ROLES["warden"]`): every `special_every` s its next attack goes for the farthest member for `special_window` s. It
## overrides the table only for that window.
## Nothing here knows how many members the party has, or their ids: who is a tank is `is_tank` (TANK_MEMBERS), the one place that names a member.

## The kinds with a special; every other kind just follows threat.
const ROLES := {
	"warden": {"special_every": 10.0, "special_window": 5.0},
}
const DEFAULT_ROLE := {}

## Threat numbers.
const WARRIOR_THREAT_MULT := 2.0   # a tank's damage and healing threat are multiplied by this
const HEAL_THREAT := 0.5           # per point healed, split across the enemies in combat
const PULL_THREAT := 10.0          # each enemy of a group the first member pulls
const TAKE_MELEE := 1.1            # 110% of the holder's threat, for a challenger within MELEE_HIT_MAX of the enemy
const TAKE_RANGED := 1.3           # 130% for one farther away
const TAUNT_BONUS := 1.1           # Provoke: the top threat times this
## Who holds the TANK flag (member ids; the only member names in the threat code).
const TANK_MEMBERS: Array[String] = ["hero"]
## A challenger this close (flat metres) to the enemy counts as in melee range.
const MELEE_HIT_MAX := 3.5

## Dash formation: on arrival the warrior stands at the group's edge and the Cutter this far behind him, on the side away from the group.
const BACK_MIN := 8.0
const BACK_MAX := 10.0
const BACK := 9.0
const CUTTER_ID := "cutter"

## False restores the old closest-member targeting (for before/after measurements).
static var enabled: bool = true

class State extends RefCounted:
	var threat: Dictionary = {}   # Player -> float
	var pulled: bool = false      # a member has already pulled it (the first one gets the pull threat; later ones do not)
	var next_special: float = -1.0
	var special_until: float = -1.0

static func role_of(e: Enemy) -> Dictionary:
	return ROLES.get(e.variant, DEFAULT_ROLE)

static func state_of(e: Enemy) -> State:
	if not e.has_meta("role_state"):
		e.set_meta("role_state", State.new())
	return e.get_meta("role_state") as State

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

static func is_tank(p: Actor) -> bool:
	var pl := p as Player
	return pl != null and TANK_MEMBERS.has(pl.member_id)

static func threat_of(e: Enemy, member: Actor) -> float:
	return float(state_of(e).threat.get(member, 0.0))

## Adds `amount` of threat for `member` on `e` (a tank's is multiplied).
static func add_threat(e: Enemy, member: Actor, amount: float) -> void:
	if amount <= 0.0 or member == null:
		return
	var st: State = state_of(e)
	st.threat[member] = float(st.threat.get(member, 0.0)) + amount * (WARRIOR_THREAT_MULT if is_tank(member) else 1.0)

## `member` pulls `e` and every enemy of its group that has not been pulled yet: PULL_THREAT on each, whole group at once.
static func pull(e: Enemy, member: Actor) -> void:
	if member == null or not e.is_inside_tree():
		return
	var mates: Array = [e]
	if e.group_id >= 0:
		for node in e.get_tree().get_nodes_in_group("enemies"):
			var mate := node as Enemy
			if mate != null and mate != e and mate.group_id == e.group_id:
				mates.append(mate)
	for m: Enemy in mates:
		var st: State = state_of(m)
		if m.dead or st.pulled:
			continue
		st.pulled = true
		st.threat[member] = float(st.threat.get(member, 0.0)) + PULL_THREAT

## Enemy._physics_process: `e` has just noticed the party. The closest member within its aggro range is the one who came into it.
static func note_noticed(e: Enemy) -> void:
	if not enabled:
		return
	var inside: Array = PartyManager.current().living().filter(func(p: Player) -> bool: return e.flat_distance_to(p) <= e.aggro_range)
	pull(e, closest_of(inside, e.global_position))

## MapMode: the fight starts and the group wakes together. The member closest to it (the warrior arrives first in the dash) pulls all of it.
static func pull_group(enemies: Array, members: Array) -> void:
	if enemies.is_empty():
		return
	var sum := Vector3.ZERO
	for e in enemies:
		sum += (e as Enemy).global_position
	var puller: Player = closest_of(members, sum / float(enemies.size()))
	for e in enemies:
		pull(e as Enemy, puller)

## A blow `e` took (Enemy.receive): the first member to hit the group pulls it, and every point is threat for the one who dealt it.
static func note_hit(e: Enemy, result: Dictionary, _source_pos: Vector3 = Vector3.ZERO, _now_s: float = -1.0) -> void:
	var source: Player = result.get("source") as Player
	if source == null:
		return
	pull(e, source)
	if int(result.get("outcome", Combat.Outcome.HIT)) >= Combat.Outcome.HIT:
		add_threat(e, source, float(result.get("damage", 0.0)))

## True when a living party member is in `e`'s threat table (it is in combat with the party, not merely awake elsewhere).
static func has_party_threat(e: Enemy) -> bool:
	if not e.has_meta("role_state"):
		return false
	for who in state_of(e).threat:
		if is_instance_valid(who) and who is Player and not (who as Actor).dead:
			return true
	return false

## Life restored to `healer` or by him (a heal, a potion, life steal): HEAL_THREAT per point, split evenly across every enemy that already has a
## party member in its threat table (an awake group nobody has pulled gets none).
static func note_heal(healer: Actor, amount: float) -> void:
	if not enabled or amount <= 0.0 or healer == null or not healer.is_inside_tree():
		return
	var engaged: Array[Enemy] = []
	for node in healer.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and not e.dead and has_party_threat(e):
			engaged.append(e)
	for e in engaged:
		add_threat(e, healer, amount * HEAL_THREAT / float(engaged.size()))

## Provoke hit `e`: the taunter's threat becomes the top plus TAUNT_BONUS (at least a pull). The lock itself is Enemy.provoked_until_ms.
static func taunt(e: Enemy, taunter: Actor) -> void:
	if not enabled:
		return
	var st: State = state_of(e)
	var top: float = 0.0
	for who in st.threat:
		if who != taunter:
			top = maxf(top, float(st.threat[who]))
	st.pulled = true
	st.threat[taunter] = maxf(maxf(float(st.threat.get(taunter, 0.0)), top * TAUNT_BONUS), PULL_THREAT)

## Removes a member from every table (he died).
static func wipe(member: Actor) -> void:
	if not is_instance_valid(member) or not member.is_inside_tree():
		return
	for node in member.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and e.has_meta("role_state"):
			state_of(e).threat.erase(member)

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

## The member with the most threat on `e`, unless the holder keeps it by the 110% / 130% rule; null when nobody has any.
static func _by_threat(e: Enemy, st: State, members: Array) -> Actor:
	var best: Actor = null
	var best_threat: float = 0.0
	for m in members:
		var p := m as Player
		if p == null or p.dead:
			continue
		var t: float = float(st.threat.get(p, 0.0))
		if t > best_threat:
			best_threat = t
			best = p
	if best == null:
		return null
	var holder: Actor = e.target if (e.target != null and members.has(e.target) and not e.target.dead) else null
	if holder == null or holder == best:
		return best
	var held: float = float(st.threat.get(holder, 0.0))
	if held <= 0.0:
		return best
	var melee: bool = e.flat_distance_to(best) <= MELEE_HIT_MAX
	return best if best_threat > held * (TAKE_MELEE if melee else TAKE_RANGED) else holder

## The member `e` should go for now, or null for "keep the current target" (Enemy's own sticky closest). Pure apart from the enemy's own table.
static func choose(e: Enemy, members: Array, now: float) -> Actor:
	var role: Dictionary = role_of(e)
	var st: State = state_of(e)
	for who in st.threat.keys():
		if not is_instance_valid(who) or (who as Actor).dead:
			st.threat.erase(who)   # a dead member's threat is wiped
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
			var after: Actor = _by_threat(e, st, members)   # the telegraphed strike is over: back to the table (the nearest when it is empty)
			return after if after != null else closest_of(members, e.global_position)
	return _by_threat(e, st, members)

## Called by Enemy every physics frame.
static func retarget(e: Enemy) -> void:
	if not enabled or e.dead:
		return
	if Time.get_ticks_msec() < e.provoked_until_ms:
		return   # Provoke holds: it locks the enemy on the taunter
	var pick: Actor = choose(e, PartyManager.current().living(), _now())
	if pick != null and pick != e.target:
		e.target = pick

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
