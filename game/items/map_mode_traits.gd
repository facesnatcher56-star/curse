class_name MapModeTraits
extends RefCounted
## Item traits (issue #82; the normal game too since #112): every level 1-5 base carries a built-in trait, plus the drop gaps (Battle Axe and
## Buckler from item level 3) and extra magic/rare modifiers. They act in every mode; the few that need a map-mode event (a dash, a fight start
## or a room clear: on_dash_arrived, on_fight_start, on_room_clear) are called by MapMode only; the dash ones also fire at the end of a roll
## (on_roll_end, owner 2026-10-21). All the numbers are in TABLE and AFFIXES.
##
## A trait is active while the item is worn by any party member; an effect that needs "the equipped member" uses that member.

## base id -> {id, text, numbers}. `text` is the tooltip line: {key} is replaced by that number (whole numbers print without a decimal).
const TABLE := {
	"club": {"id": "club_opening", "text": "Autos: +{opening}% Opening chance", "numbers": {"opening": 8.0}},
	"dagger": {"id": "dagger_swift", "text": "Fastest autos (+{speed}% attack speed); autos always crit an enemy with an open Opening",
		"numbers": {"speed": 20.0}},
	"falchion": {"id": "falchion_cleave", "text": "Cleave: every {every} autos also hit one extra enemy for {mult}% damage",
		"numbers": {"every": 3.0, "mult": 75.0, "reach": 3.0}},
	"longsword": {"id": "longsword_charge", "text": "+{charge}% power charge from auto-attack damage", "numbers": {"charge": 10.0}},
	"axe_1h": {"id": "axe_bleed", "text": "Autos cause bleed ({pct}% of the hit a second for {secs} s)", "numbers": {"pct": 25.0, "secs": 3.0}},
	"mace": {"id": "mace_shred", "text": "Autos strip {step}% armour per hit, stacking to {cap}% for {secs} s",
		"numbers": {"step": 3.0, "cap": 15.0, "secs": 4.0}},
	"short_bow": {"id": "bow_mark", "text": "Autos mark the target for {secs} s: the rest of the party deals +{pct}% to marked enemies",
		"numbers": {"secs": 6.0, "pct": 15.0}},
	"leather_jerkin": {"id": "jerkin_shield", "text": "A shield absorbs the first {pct}% of your max life in damage; it refills out of combat", "numbers": {"pct": 20.0}},
	"apprentice_robe": {"id": "robe_recharge", "text": "Powers charge {recharge}% faster", "numbers": {"recharge": 10.0}},
	"mail_hauberk": {"id": "hauberk_taken", "text": "Damage taken also charges your powers ({pct}% of it)", "numbers": {"pct": 50.0}},
	"leather_cap": {"id": "cap_telegraph", "text": "Enemy wind-up telegraphs show {lead} s earlier", "numbers": {"lead": 0.5}},
	"iron_helm": {"id": "helm_stun", "text": "-{pct}% stun duration when hit", "numbers": {"pct": 25.0}},
	"woven_hood": {"id": "hood_power", "text": "+{power}% power damage for {secs} s after a dash or a roll", "numbers": {"power": 15.0, "secs": 3.0}},
	"leather_gloves": {"id": "gloves_speed", "text": "+{speed}% auto-attack speed", "numbers": {"speed": 10.0}},
	"iron_gauntlets": {"id": "gauntlets_execute", "text": "Opening executions hit {pct}% harder", "numbers": {"pct": 25.0}},
	"studded_gloves": {"id": "studded_champions", "text": "+{opening}% Opening chance against champions", "numbers": {"opening": 15.0}},
	"leather_boots": {"id": "boots_burst", "text": "+{speed}% attack speed for {secs} s after a dash or a roll", "numbers": {"speed": 30.0, "secs": 3.0}},
	"iron_greaves": {"id": "greaves_knock", "text": "A dash or a roll knocks back enemies where you land", "numbers": {"knock": 3.0, "radius": 7.0, "stun": 0.5}},
	"signet": {"id": "signet_share", "text": "When you use a power, the other party members gain {charge}% charge", "numbers": {"charge": 10.0}},
	"charm": {"id": "charm_kills", "text": "Kills refill {charge}% of your power charge", "numbers": {"charge": 5.0}},
}

## The tooltip colour of the trait line (distinct from the stat lines).
const LINE_COLOR := Color(0.62, 0.84, 0.95)

## Map-mode drop gaps: base id -> the item level it is offered from (the default game offers it from its own first level).
const EXTRA_DROPS := {"axe_2h": 3, "buckler": 3}

## Extra magic/rare modifiers in the map-mode pool only: {id, family, stat, title, position, level, value, ceiling, slots}. `level` is the
## modifier level (it rolls on an item whose window allows it); the value rolls between `value` and `ceiling`.
const AFFIXES: Array[Dictionary] = [
	{"id": "mm_opening_1", "family": "opening", "stat": "opening", "title": "of Foresight", "position": "suffix", "level": 1, "value": 3.0, "ceiling": 6.0, "slots": ["weapon", "gloves", "helm"]},
	{"id": "mm_opening_2", "family": "opening", "stat": "opening", "title": "of Foresight", "position": "suffix", "level": 10, "value": 6.0, "ceiling": 10.0, "slots": ["weapon", "gloves", "helm"]},
	{"id": "mm_charge_kill_1", "family": "mm_charge_kill", "stat": "charge_on_kill", "title": "Bloodied", "position": "prefix", "level": 1, "value": 2.0, "ceiling": 4.0, "slots": ["ring", "amulet", "helm", "body"]},
	{"id": "mm_charge_kill_2", "family": "mm_charge_kill", "stat": "charge_on_kill", "title": "Bloodied", "position": "prefix", "level": 10, "value": 4.0, "ceiling": 7.0, "slots": ["ring", "amulet", "helm", "body"]},
	{"id": "mm_marked_1", "family": "mm_marked", "stat": "marked_damage", "title": "Hunter's", "position": "prefix", "level": 1, "value": 5.0, "ceiling": 10.0, "slots": ["weapon", "ring", "amulet", "gloves"]},
	{"id": "mm_marked_2", "family": "mm_marked", "stat": "marked_damage", "title": "Hunter's", "position": "prefix", "level": 10, "value": 10.0, "ceiling": 18.0, "slots": ["weapon", "ring", "amulet", "gloves"]},
	{"id": "mm_gale_1", "family": "mm_gale", "stat": "party_speed", "title": "of the Gale", "position": "suffix", "level": 1, "value": 8.0, "ceiling": 15.0, "slots": ["boots", "body"]},
	{"id": "mm_gale_2", "family": "mm_gale", "stat": "party_speed", "title": "of the Gale", "position": "suffix", "level": 10, "value": 15.0, "ceiling": 25.0, "slots": ["boots", "body"]},
	{"id": "mm_auto_1", "family": "mm_auto", "stat": "auto_speed", "title": "Quick", "position": "prefix", "level": 1, "value": 4.0, "ceiling": 8.0, "slots": ["weapon", "gloves", "boots"]},
	{"id": "mm_auto_2", "family": "mm_auto", "stat": "auto_speed", "title": "Quick", "position": "prefix", "level": 10, "value": 8.0, "ceiling": 14.0, "slots": ["weapon", "gloves", "boots"]},
]
## The stats the modifiers above add that the base game does not know (name on the card; all are percentages).
const NEW_STAT_NAMES := {"charge_on_kill": "Power charge on kill", "marked_damage": "Damage to marked enemies", "party_speed": "Party movement speed", "auto_speed": "Auto-attack speed"}

## "of the Gale" (issue #112): every member's Party movement speed adds up and speeds up the whole party, to at most this many percent.
const PARTY_SPEED_CAP := 30.0
## The Jerkin's pool refills once the party has been out of combat (no awake enemy going for a member) this many seconds (issue #112).
const SHIELD_REFILL_CALM := 5.0

## The skill ids that are "autos" (the basic melee blow, the Cutter's and a bow's arrow).
const AUTO_IDS: Array[String] = ["basic", "companion_arrow"]
const MARK_META := "mm_marked"

static var time_override: float = -1.0       # tests set the clock
static var _affix_defs: Dictionary = {}      # id -> AffixDef (built on first use)
static var _state: Dictionary = {}           # body instance id -> {power_until, burst_until, autos, shield}

static func now() -> float:
	return time_override if time_override >= 0.0 else Time.get_ticks_msec() / 1000.0

static func reset() -> void:
	_state.clear()
	time_override = -1.0

# --- The table -----------------------------------------------------------------------------------------------------------------------

static func trait_of(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	return TABLE.get(String((item as Dictionary).get("def", "")), {}) as Dictionary

## The tooltip line of a trait ("" when the item has none).
static func line_for(base_id: String) -> String:
	var entry: Dictionary = TABLE.get(base_id, {}) as Dictionary
	if entry.is_empty():
		return ""
	var text: String = String(entry["text"])
	var numbers: Dictionary = entry["numbers"]
	for key in numbers:
		var v: float = float(numbers[key])
		text = text.replace("{%s}" % key, str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v))
	return text

## The shared tooltip hook (Items.rows): the item's trait line.
static func rows_for(item: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not trait_of(item).is_empty():
		out.append({"text": line_for(String(item.get("def", ""))), "key": "", "color": LINE_COLOR})
	return out

## One number of the trait `id`, summed over the pieces that body wears. 0 when the body wears none.
static func value(body: Variant, trait_id: String, key: String) -> float:
	if body == null or not is_instance_valid(body) or not body is Player:
		return 0.0
	var total: float = 0.0
	for item in (body as Player).stats.equipment.values():
		var entry: Dictionary = trait_of(item)
		if not entry.is_empty() and String(entry["id"]) == trait_id:
			total += float((entry["numbers"] as Dictionary).get(key, 1.0))
	return total

static func has(body: Variant, trait_id: String) -> bool:
	if body == null or not is_instance_valid(body) or not body is Player:
		return false
	for item in (body as Player).stats.equipment.values():
		var entry: Dictionary = trait_of(item)
		if not entry.is_empty() and String(entry["id"]) == trait_id:
			return true
	return false

static func gear(body: Player, stat: String) -> float:
	return body.stats.gear_stat(stat) if body != null and is_instance_valid(body) else 0.0

static func _living() -> Array[Player]:
	return PartyManager.current().living()

static func _st(body: Player) -> Dictionary:
	var id: int = body.get_instance_id()
	if not _state.has(id):
		_state[id] = {"power_until": -1.0, "burst_until": -1.0, "autos": 0, "shield": 0.0, "calm": 0.0}
	return _state[id]

static func is_auto(result: Dictionary) -> bool:
	return AUTO_IDS.has(String(result.get("skill_id", ""))) and not bool(result.get("secondary", false))

# --- Stat hooks (queried live, never cached) ---------------------------------------------------------------------------------------

## Auto-attack speed multiplier (PlayerStats.attack_speed).
static func speed_mult(body: Player) -> float:
	var pct: float = value(body, "dagger_swift", "speed") + value(body, "gloves_speed", "speed") + gear(body, "auto_speed")
	if now() < float(_st(body)["burst_until"]):
		pct += value(body, "boots_burst", "speed")
	return 1.0 + pct / 100.0

## Walking speed multiplier of every party member (PlayerMovement._travel_speed): the members' Party movement speed, added up and capped.
static func party_speed_mult() -> float:
	var pct: float = 0.0
	for body in _living():
		pct += gear(body, "party_speed")
	return 1.0 + minf(pct, PARTY_SPEED_CAP) / 100.0

## Power recharge in percent (PlayerStats.power_recharge_damage).
static func recharge_bonus(body: Player) -> float:
	return value(body, "robe_recharge", "recharge")

## Power damage in percent (PlayerStats.power_damage_mult): the Woven Hood after a dash.
static func power_damage_bonus(body: Player) -> float:
	if now() < float(_st(body)["power_until"]):
		MapAutoTally.note("hood_power_query")
		return value(body, "hood_power", "power")
	return 0.0

## Stun duration multiplier on the hero (Player._gain_stun).
static func stun_mult(body: Player) -> float:
	if value(body, "helm_stun", "pct") > 0.0:
		MapAutoTally.note("helm_stun_hit")
	return maxf(1.0 - value(body, "helm_stun", "pct") / 100.0, 0.1)

## Opening chance in percent on top of the passive's (Openings.spot_chance), and against one target (Openings.on_melee_hit).
static func opening_bonus(body: Player) -> float:
	return value(body, "club_opening", "opening")

static func opening_bonus_vs(body: Player, target: Actor) -> float:
	if target is Enemy and (target as Enemy).champion != null:
		if value(body, "studded_champions", "opening") > 0.0:
			MapAutoTally.note("studded_champion_roll")
		return value(body, "studded_champions", "opening")
	return 0.0

## An Opening execution's extra damage in percent (Openings.damage_bonus).
static func execution_bonus(body: Player) -> float:
	if value(body, "gauntlets_execute", "pct") > 0.0:
		MapAutoTally.note("gauntlets_execution")
	return value(body, "gauntlets_execute", "pct")

# --- Charge helpers --------------------------------------------------------------------------------------------------------------

## Damage-equivalent charge for one member's powers only.
static func charge_member(body: Player, amount: float) -> void:
	if amount <= 0.0 or not is_instance_valid(body):
		return
	body.stats.gain_brutal_charge(amount)
	body.powers.gain(amount)
	if body.bow != null:
		body.bow.reload_remaining = maxf(body.bow.reload_remaining - amount, 0.0)

# --- Event hooks -------------------------------------------------------------------------------------------------------------------

## Pre-damage hook (Actor.receive): marked enemies take more, and a Dagger's auto crits an open Opening.
static func modify_hit(target: Actor, result: Dictionary) -> Dictionary:
	var source: Variant = result.get("source")
	if not source is Player or int(result.get("outcome", 0)) < Combat.Outcome.HIT or float(result.get("damage", 0.0)) <= 0.0:
		return result
	var body: Player = source as Player
	MapAutoTally.dealt(body.member_id, String(result.get("skill_id", "?")), float(result.get("damage", 0.0)))   # (dev autoplay counters; inert otherwise)
	var pct: float = 0.0
	if target.has_meta(MARK_META):
		var mark: Dictionary = target.get_meta(MARK_META)
		if now() < float(mark["until"]):
			pct += gear(body, "marked_damage")
			if gear(body, "marked_damage") > 0.0:
				MapAutoTally.note("affix_marked_damage", float(result["damage"]) * gear(body, "marked_damage") / 100.0)
			if String(mark["by"]) != body.member_id and body.member_id == "hero":   # the bonus is the warrior's only (owner decision)
				pct += float(mark["pct"])
				MapAutoTally.note("bow_mark_bonus", float(result["damage"]) * float(mark["pct"]) / 100.0)
			elif String(mark["by"]) != body.member_id:
				MapAutoTally.note("bow_mark_denied_to_cutter")   # the Cutter hit a mark the hero made: no bonus (warrior only)
	if pct > 0.0:
		result["damage"] = float(result["damage"]) * (1.0 + pct / 100.0)
	if is_auto(result) and int(result["outcome"]) == Combat.Outcome.HIT and has(body, "dagger_swift") and _open_on(target):
		result["outcome"] = Combat.Outcome.CRITICAL
		MapAutoTally.note("dagger_open_crit")
		result["damage"] = float(result["damage"]) * body.crit_mult
	return result

static func _open_on(target: Actor) -> bool:
	for member in _living():
		if member.openings != null and member.openings.is_open_on(target):
			return true
	return false

## After a landed blow (Player.on_dealt_hit): the auto-attack traits.
static func on_dealt_hit(body: Player, target: Actor, result: Dictionary) -> void:
	if not is_instance_valid(target) or not is_auto(result):
		return
	if int(result.get("outcome", 0)) < Combat.Outcome.HIT:
		return
	var damage: float = float(result.get("damage", 0.0))
	# Longsword: a share of the auto's damage charges every power again.
	var share: float = value(body, "longsword_charge", "charge")
	if share > 0.0:
		body.on_party_damage(damage * share / 100.0, "basic")
		MapAutoTally.note("longsword_charge", damage * share / 100.0)
	# War Axe: bleed (Actor.bleed_time / bleed_dps, the existing damage over time).
	if has(body, "axe_bleed") and not target.dead:
		target.bleed_time = maxf(target.bleed_time, value(body, "axe_bleed", "secs"))
		target.bleed_dps = maxf(target.bleed_dps, damage * value(body, "axe_bleed", "pct") / 100.0)
		MapAutoTally.note("axe_bleed_applied", damage * value(body, "axe_bleed", "pct") / 100.0 * value(body, "axe_bleed", "secs"))
	# Mace: armour shred, stacking up to a cap.
	if has(body, "mace_shred") and not target.dead:
		var cap: float = value(body, "mace_shred", "cap") / 100.0
		target.armor_shred = maxf(target.armor_shred, minf(target.armor_shred + value(body, "mace_shred", "step") / 100.0, cap))
		target.armor_shred_time = maxf(target.armor_shred_time, value(body, "mace_shred", "secs"))
		MapAutoTally.note("mace_shred_applied")
	# Short Bow: the auto marks its target.
	if has(body, "bow_mark") and not target.dead:
		target.set_meta(MARK_META, {"until": now() + value(body, "bow_mark", "secs"), "by": body.member_id, "pct": value(body, "bow_mark", "pct")})
		MapAutoTally.note("bow_mark_applied")
	# Falchion: every Nth auto cleaves to one more enemy.
	if has(body, "falchion_cleave"):
		var st: Dictionary = _st(body)
		st["autos"] = int(st["autos"]) + 1
		if int(st["autos"]) >= int(value(body, "falchion_cleave", "every")):
			st["autos"] = 0
			_cleave(body, target)

static func _cleave(body: Player, first: Actor) -> void:
	var best: Actor = null
	var best_d: float = value(body, "falchion_cleave", "reach")
	for node in body.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e == first or e.dead or e.is_queued_for_deletion() or e.is_in_group("player"):
			continue
		var d: float = first.global_position.distance_to(e.global_position) - e.body_radius
		if d <= best_d:
			best = e
			best_d = d
	if best == null:
		return
	var swing: float = body.stats.weapon_damage(1.0) * value(body, "falchion_cleave", "mult") / 100.0
	var result: Dictionary = Combat.resolve(body, best, swing, Combat.DamageType.PHYSICAL, true, 0.6)
	result["skill_id"] = "cleave"
	result["secondary"] = true
	MapAutoTally.note("falchion_cleave", swing)
	best.receive(result, body.global_position)

## The wearer took a hit (Player._on_hurt): Mail Hauberk turns it into charge.
static func on_hurt(body: Player, result: Dictionary) -> void:
	MapAutoTally.hurt(result)
	var pct: float = value(body, "hauberk_taken", "pct")
	if pct > 0.0:
		MapAutoTally.note("hauberk_charge", float(result.get("damage", 0.0)) * pct / 100.0)
		charge_member(body, float(result.get("damage", 0.0)) * pct / 100.0)

## A party kill (Player.on_enemy_killed): Charm and the "charge on kill" modifier refill the wearer's powers.
static func on_kill() -> void:
	for body in _living():
		var share: float = value(body, "charm_kills", "charge") + gear(body, "charge_on_kill")
		if share > 0.0:
			body.stats.refund_power_charge(share / 100.0)
			MapAutoTally.note("charm_or_kill_charge", share)

## A member used a power (Player.power_activated): Signet gives the others charge.
static func on_power(member_id: String, _power_id: String) -> void:
	var share: float = 0.0
	for body in _living():
		if body.member_id == member_id:   # only the wearer's own power use shares charge (owner decision)
			share = value(body, "signet_share", "charge")
	if share <= 0.0:
		return
	for body in _living():
		if body.member_id != member_id:
			body.stats.refund_power_charge(share / 100.0)
			MapAutoTally.note("signet_share", share)

## A fight begins (MapMode._arrive, group visit): the Jerkin's shield fills for each living wearer (a fresh pool every fight).
static func on_fight_start(m: MapMode) -> void:
	if not MapMode.active:
		return
	for body in [m.hero, m.companion]:
		if body == null or not is_instance_valid(body):
			continue
		_st(body)["shield"] = 0.0 if body.dead else body.max_health * value(body, "jerkin_shield", "pct") / 100.0
		if float(_st(body)["shield"]) > 0.0:
			MapAutoTally.note("jerkin_shield_up", float(_st(body)["shield"]))

## A room is cleared (MapMode._begin_collect after a fight): the shields are gone.
static func on_room_clear(m: MapMode) -> void:
	if not MapMode.active:
		return
	for body in [m.hero, m.companion]:
		if body == null or not is_instance_valid(body):
			continue
		_st(body)["shield"] = 0.0

## Every physics frame of a living member (Player): once the party has been out of combat SHIELD_REFILL_CALM s, the Jerkin's pool is full again.
static func tick(body: Player, delta: float) -> void:
	var pool: float = body.max_health * value(body, "jerkin_shield", "pct") / 100.0
	if pool <= 0.0:
		return
	var st: Dictionary = _st(body)
	st["calm"] = 0.0 if in_combat(body) else float(st["calm"]) + delta
	if float(st["calm"]) >= SHIELD_REFILL_CALM and float(st["shield"]) < pool:
		st["shield"] = pool
		MapAutoTally.note("jerkin_shield_up", pool)

## In combat: an awake enemy is going for a living party member.
static func in_combat(body: Node) -> bool:
	for node in body.get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and not e.dead and e.is_aggro() and e.target is Player and not (e.target as Player).dead:
			return true
	return false

## Player._filter_incoming: the Jerkin's shield soaks damage (AoE and ticks included) until its pool is used up; it refills out of combat (tick).
static func absorb(body: Player, result: Dictionary) -> Dictionary:
	if int(result.get("outcome", 0)) < Combat.Outcome.HIT:
		return result
	var damage: float = float(result.get("damage", 0.0))
	var st: Dictionary = _st(body)
	var pool: float = float(st["shield"])
	if damage <= 0.0 or pool <= 0.0:
		return result
	var soaked: float = minf(damage, pool)
	st["shield"] = pool - soaked
	result["damage"] = damage - soaked
	result["shield_absorbed"] = soaked
	MapAutoTally.note("jerkin_shield_absorbed", soaked)
	if float(result["damage"]) <= 0.0:
		result["outcome"] = Combat.Outcome.BLOCK   # fully soaked: no recoil, like the guard
		result["guard"] = true
	if body.is_inside_tree() and body.get_tree().current_scene != null:
		Fx.ring(body, body.global_position, 1.2, Color(0.55, 0.8, 1.0))
	return result

## The party lands (MapMode._arrive): Woven Hood and Leather Boots start their timers, Iron Greaves knock enemies back.
static func on_dash_arrived(m: MapMode) -> void:
	if not MapMode.active:
		return
	for body in [m.hero, m.companion]:
		if body == null or not is_instance_valid(body) or body.dead:
			continue
		_landed(body)

## A member's dodge roll ends (PlayerMovement.tick_roll), in either mode: the same as a dash landing (owner, issue #112).
static func on_roll_end(body: Player) -> void:
	if body != null and is_instance_valid(body) and not body.dead:
		_landed(body)

## Woven Hood and Leather Boots start their timers, Iron Greaves knock enemies back.
static func _landed(body: Player) -> void:
	var st: Dictionary = _st(body)
	if has(body, "hood_power"):
		st["power_until"] = now() + value(body, "hood_power", "secs")
		MapAutoTally.note("hood_window")
	if has(body, "boots_burst"):
		st["burst_until"] = now() + value(body, "boots_burst", "secs")
		MapAutoTally.note("boots_window")
	if has(body, "greaves_knock"):
		_knock_back(body)

static func _knock_back(body: Player) -> void:
	var radius: float = value(body, "greaves_knock", "radius")
	var metres: float = value(body, "greaves_knock", "knock")
	var stun: float = value(body, "greaves_knock", "stun")
	for node in body.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or e.is_in_group("player") or not is_instance_valid(e):
			continue
		var away: Vector3 = e.global_position - body.global_position
		away.y = 0.0
		if away.length() > radius:
			continue
		e.knock += away.normalized() * sqrt(44.0 * metres)   # knock decays at 22 m/s^2: an impulse of v covers v^2 / 44 metres
		e._gain_stun(stun)
		MapAutoTally.note("greaves_knock")

## Leather Cap (MeleeBehavior): the enemy shows its telegraph `lead` seconds before it can swing again.
static func pre_telegraph(e: Enemy, cooldown: float, distance: float) -> bool:
	if cooldown <= 0.0 or distance > e.attack_range * 1.6:
		return false
	var lead: float = 0.0
	for body in _living():
		lead = maxf(lead, value(body, "cap_telegraph", "lead"))
	if lead > 0.0 and cooldown <= lead:
		e.telegraph(0.3)
		MapAutoTally.note("cap_telegraph")
		return true
	return false

# --- The drop gaps and the modifier pool (Items.pick_base, AffixDb) --------------------------------------------------------------

## The item levels a base is offered at: Battle Axe and Buckler also from level 3.
static func drop_levels(def: ItemDef) -> Array[int]:
	if not EXTRA_DROPS.has(def.id):
		return def.levels
	var out: Array[int] = [int(EXTRA_DROPS[def.id])]
	for level in def.levels:
		if level > int(EXTRA_DROPS[def.id]):
			out.append(level)
	return out

static func affix_def(id: String) -> AffixDef:
	_build_affixes()
	return _affix_defs.get(id) as AffixDef

## The extra modifiers that fit this item kind and modifier-level window (the same filter as AffixDb.eligible).
static func extra_affixes(kind: String, low: int, high: int, position: String) -> Array[AffixDef]:
	var out: Array[AffixDef] = []
	_build_affixes()
	for a in _affix_defs.values():
		var def := a as AffixDef
		if def.slots.has(kind) and def.level >= low and def.level <= high and (position == "" or def.position == position):
			out.append(def)
	return out

static func _build_affixes() -> void:
	if not _affix_defs.is_empty():
		return
	for row in AFFIXES:
		var a := AffixDef.new()
		a.id = String(row["id"])
		a.family = String(row["family"])
		a.stat = String(row["stat"])
		a.title = String(row["title"])
		a.position = String(row["position"])
		a.tier = 1 if int(row["level"]) < 10 else 2
		a.level = int(row["level"])
		a.value = float(row["value"])
		a.max_value = float(row["value"])
		a.value_ceiling = float(row["ceiling"])
		a.percent = true
		var slots: Array[String] = []
		for s in row["slots"]:
			slots.append(String(s))
		a.slots = slots
		_affix_defs[a.id] = a
