class_name MapModeLegendaries
extends RefCounted
## The first power legendaries of map mode (issue #82): existing bases that rewrite one power. Every effect is gated on `MapMode.active` and on the
## item being worn by the member who casts (Hero's Amulet: either member), so the default game is unchanged. All numbers and texts live in DEFS.
## They are not in UniqueDb's drop pool (the default game never rolls them): UniqueDb.get_unique falls back to `def()` so an item built from one
## names itself, saves and loads; the first champion of a run drops one (`first_champion_drop`), and chests may hand them out via `random_item`.

## id -> {name, base (ItemDef id), level, text (tooltip line), numbers, mods}. `unique` marks the existing level-5 unique that is given a power.
const DEFS := {
	"gravecaller_maul": {"name": "Gravecaller Maul", "base": "axe_2h", "level": 6,
		"text": "Whirling Strike pulls enemies in first",
		"numbers": {"pull_reach": 6.0, "pull_gap": 1.2}, "mods": {"melee_pct": 12.0}},
	"headsmans_due": {"name": "Headsman's Due", "base": "longsword", "level": 5,
		"text": "A Brutal Attack kill jumps to the nearest enemy and hits again (up to 3 times)",
		"numbers": {"max_jumps": 3, "jump_range": 8.0}, "mods": {"melee_pct": 10.0}},
	"executioners_sight": {"name": "Executioner's Sight", "base": "short_bow", "level": 5,
		"text": "Take Aim on an Opening always crits and refunds half its charge",
		"numbers": {"refund": 0.5}, "mods": {"ranged_pct": 10.0}},
	"splitbow": {"name": "Splitbow", "base": "short_bow", "level": 5,
		"text": "Thunderous Shot fires 3 bolts in a cone",
		"numbers": {"bolts": 3, "cone_degrees": 30.0}, "mods": {"ranged_pct": 8.0}},
	"heros_amulet": {"name": "Hero's Amulet", "unique": true,
		"text": "When one party member uses a power, the other gains 25% charge",
		"numbers": {"charge_share": 0.25}},
}
## The pool the first champion draws from.
const FIRST_CHAMPION_POOL: Array[String] = ["gravecaller_maul", "headsmans_due", "executioners_sight", "splitbow", "heros_amulet"]
## A power used twice within this many seconds by the same member counts once for Hero's Amulet (Take Aim announces itself when it is drawn and when it is armed).
const AMULET_DEBOUNCE := 0.5
## The legendary drop's beam colour, and a sound that already exists (the war cry shout).
const BEAM_COLOR := Color(1.0, 0.62, 0.16)
const DROP_SOUND := "war_cry_cast"

static var first_champion_dropped: bool = false
static var _defs: Dictionary = {}   # id -> UniqueDef
static var _amulet_stamp: Dictionary = {}   # member id + power -> seconds

## A new map-mode run: the first champion drops a legendary again.
static func reset_run() -> void:
	first_champion_dropped = false
	_amulet_stamp.clear()

static func number(id: String, key: String) -> float:
	return float((DEFS.get(id, {}).get("numbers", {}) as Dictionary).get(key, 0.0))

## The UniqueDef of a legendary (built once); Hero's Amulet is the existing unique.
static func def(id: String) -> UniqueDef:
	if not DEFS.has(id):
		return null
	var row: Dictionary = DEFS[id]
	if bool(row.get("unique", false)):
		return UniqueDb.uniques().get(id) as UniqueDef
	if not _defs.has(id):
		var u := UniqueDef.new()
		u.id = id
		u.display_name = String(row["name"])
		u.base = String(row["base"])
		u.level = int(row["level"])
		u.mods = (row.get("mods", {}) as Dictionary).duplicate()
		_defs[id] = u
	return _defs[id]

static func item(id: String) -> Dictionary:
	var u: UniqueDef = def(id)
	return Items.unique(u) if u != null else {}

static func random_item() -> Dictionary:
	return item(FIRST_CHAMPION_POOL[randi() % FIRST_CHAMPION_POOL.size()])

## Which legendary an item is ("" for anything else).
static func id_of(it: Dictionary) -> String:
	var id: String = String(it.get("unique", ""))
	return id if DEFS.has(id) else ""

## The tooltip line of a legendary, shown in map mode only ("" otherwise).
static func tooltip_line(it: Dictionary) -> String:
	var id: String = id_of(it)
	return "Legendary: %s" % String(DEFS[id]["text"]) if id != "" and MapMode.active else ""

## The shared gate: map mode is on and `who` wears the legendary (Hero's Amulet: it counts when either member wears it).
static func active_for(who: Player, id: String) -> bool:
	if not MapMode.active or who == null or not DEFS.has(id):
		return false
	if id == "heros_amulet":
		for body in PartyManager.current().bodies.values():
			if is_instance_valid(body) and _worn(body, Items.Slot.AMULET, id):
				return true
		return false
	return _worn(who, Items.Slot.WEAPON, id)

static func _worn(body: Player, slot: int, id: String) -> bool:
	if body.stats == null:
		return false
	var worn: Variant = body.stats.equipment.get(slot)
	return worn is Dictionary and String((worn as Dictionary).get("unique", "")) == id

# --- Hero's Amulet -----------------------------------------------------------------------------------------------------------------

## Player.power_activated: the other living member gains the amulet's share of every power's charge.
static func on_power_used(_member_id: String, power_id: String, user: Player) -> void:
	if not active_for(user, "heros_amulet"):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var key: String = "%s/%s" % [user.member_id, power_id]
	if now - float(_amulet_stamp.get(key, -99.0)) < AMULET_DEBOUNCE:
		return
	_amulet_stamp[key] = now
	for body in PartyManager.current().living():
		if body != user:
			body.stats.refund_power_charge(number("heros_amulet", "charge_share"))

# --- Gravecaller Maul ----------------------------------------------------------------------------------------------------------------

## Pulls every enemy within the maul's reach in to just outside the hero, before Whirling Strike measures who it hits.
static func pull_in(p: Player) -> void:
	if not active_for(p, "gravecaller_maul"):
		return
	var gap: float = number("gravecaller_maul", "pull_gap")
	for e in p.powers.enemies_within(p.global_position, number("gravecaller_maul", "pull_reach")):
		var out: Vector3 = e.global_position - p.global_position
		out.y = 0.0
		if out.length() <= gap + e.body_radius:
			continue
		var dir: Vector3 = out.normalized() if out.length() > 0.05 else Vector3.FORWARD
		var spot: Vector3 = p.global_position + dir * (gap + e.body_radius)
		e.global_position = Vector3(spot.x, e.global_position.y, spot.z)

# --- Headsman's Due ------------------------------------------------------------------------------------------------------------------

## A Brutal Attack killed `first`: the blow jumps to the nearest living enemy and hits again, up to the legendary's jump count, each hit the same
## empowered blow. Returns how many jumps landed.
static func headsman_chain(p: Player, first: Actor, damage: float, multiplier: float, weight: float) -> int:
	if not active_for(p, "headsmans_due") or first == null or not first.dead:
		return 0
	var jumps: int = 0
	var from: Vector3 = first.global_position
	var last: Actor = first
	while jumps < int(number("headsmans_due", "max_jumps")):
		var next: Actor = null
		var best: float = number("headsmans_due", "jump_range")
		for node in p.get_tree().get_nodes_in_group("enemies"):
			var e := node as Actor
			if e == null or e.dead or e == last:
				continue
			var d: float = e.global_position.distance_to(from)
			if d < best:
				best = d
				next = e
		if next == null:
			break
		var result: Dictionary = Combat.resolve(p, next, damage, Combat.DamageType.PHYSICAL, false, weight, false, false, multiplier)
		result["skill_id"] = "brutal_attack"
		result["finisher"] = false
		var dir: Vector3 = next.global_position - from
		dir.y = 0.0
		SkillFx.brutal_impact(p, next.global_position, dir, PowerDb.hero_rank("brutal_attack", p.member_id))
		from = next.global_position
		next.receive(result, p.global_position)
		jumps += 1
		last = next
		if not next.dead:
			break   # the chain only continues through kills
	return jumps

# --- Executioner's Sight -------------------------------------------------------------------------------------------------------------

## Whether the Take Aim shot loosed at `target` is the legendary's: the bow is worn and the target stands open.
static func sight_applies(p: Player, target: Actor) -> bool:
	return active_for(p, "executioners_sight") and target != null and p.openings.is_open_on(target)

# --- Splitbow ------------------------------------------------------------------------------------------------------------------------

## The directions Thunderous Shot's bolts fly in: just `dir`, or the legendary's fan of bolts centred on it.
static func bolt_directions(p: Player, dir: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = [dir]
	if not active_for(p, "splitbow"):
		return out
	var n: int = int(number("splitbow", "bolts"))
	var cone: float = deg_to_rad(number("splitbow", "cone_degrees"))
	out.clear()
	for i in n:
		var t: float = (float(i) / float(n - 1) - 0.5) * cone if n > 1 else 0.0
		out.append(dir.rotated(Vector3.UP, t))
	return out

# --- The first champion --------------------------------------------------------------------------------------------------------------

## The legendary the first champion of this map-mode run drops (an item, or {} for every later champion and outside map mode).
static func first_champion_drop() -> Dictionary:
	if not MapMode.active or first_champion_dropped:
		return {}
	first_champion_dropped = true
	return random_item()

## Whether a ground drop gets the legendary beam and sound (map mode only).
static func beam_for(it: Dictionary) -> bool:
	return MapMode.active and id_of(it) != ""
