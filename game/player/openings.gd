class_name Openings
extends RefCounted
## The Opening passive (melee tree) and Shield Openings: a fatal flaw shows on an enemy, and striking it within the window plays a
## weapon-specific execution (SkillController.start_opening). Owned by the hero (`Player.openings`).
##
## Triggers: a melee hit that lands while the hero is in melee may mark a nearby enemy; a successful shield block may mark the attacker.
## One mark at a time, a short cooldown after each mark ends or is executed. The window is WINDOW seconds.
##
## Values are CURSE CHOICES, not DS2 data (DS2 has no Opening): the rank tables live in data/passives/opening.tres and are labelled as
## provisional in docs/ and the PR until the owner confirms them.

const WINDOW := 1.5            # seconds the mark stays executable
const COOLDOWN := 4.0          # seconds before another mark may appear, after a mark ends or is executed
const MELEE_REACH := 2.8       # a nearby enemy for a melee hit is within this of the hero's edge (sword range plus a step)
const INVULNERABLE := 0.5      # seconds the hero cannot be hurt while an execution starts
const EXECUTION_STUN_RADIUS := 2.5
const BURN_SECONDS := 3.0      # Openings ignite: the burn that an execution leaves
const GROUND_LIFT := 0.08   # the ring sits just above the floor so it is not lost in the tiles

## Weapon profile key ("opening" in data/items) -> the execution. `clip` is an existing knight2 clip (V1 reuses them); `strike`, `end` and
## `start` are in clip seconds, `time` is the blow's length in seconds before the weapon's speed, `weight` is the stagger, `lunge` the step in.
const STYLES := {
	"stab": {"clip": "atk_thrust", "start": 0.0, "strike": 0.57, "end": 1.1, "time": 1.0, "weight": 1.1, "lunge": 0.8, "range": 2.8, "mult": 1.0},
	"chop": {"clip": "atk_finisher", "start": 0.0, "strike": 0.77, "end": 1.6, "time": 1.45, "weight": 1.7, "lunge": 0.9, "range": 2.6, "mult": 1.0},
	"crush": {"clip": "power", "start": 0.78, "strike": 1.23, "end": 1.72, "time": 1.08, "weight": 2.15, "lunge": 0.85, "range": 2.5, "mult": 1.0,
		"stun": 1.5},
	"backstab": {"clip": "atk_thrust", "start": 0.0, "strike": 0.57, "end": 1.1, "time": 0.75, "weight": 0.9, "lunge": 1.0, "range": 2.6, "mult": 1.0},
	"impale": {"clip": "atk2_thrust", "start": 0.0, "strike": 0.57, "end": 1.1, "time": 1.0, "weight": 1.4, "lunge": 0.8, "range": 3.0, "mult": 1.0},
	# The Gravecutter's own execution (data/uniques/gravecutter.tres): a wide cleave that staggers the crowd around its target. Provisional.
	"grave_cleave": {"clip": "atk_slash_r", "start": 0.0, "strike": 0.38, "end": 0.75, "time": 0.9, "weight": 1.5, "lunge": 0.6, "range": 2.6,
		"mult": 1.0, "stun": 0.6},
	"bash": {"clip": "stomp", "start": 0.0, "strike": 0.5, "end": 1.0, "time": 0.9, "weight": 1.6, "lunge": 0.6, "range": 2.4, "mult": 1.0,
		"stun": 1.0},
}
## The shield's execution overrides the weapon's (open question to the owner: a sword and shield gets the bash).
const SHIELD_STYLE := "bash"

var p: Player
var mark_target: Actor = null
var mark_left: float = 0.0
## What made the open mark: "melee" (a melee hit or a power use) or "block" (a successful shield block). Picks the execution.
var mark_kind: String = ""
var cooldown: float = 0.0
var _ring: MeshInstance3D
var _ring_pulse: float = 0.0
## Counters the self test reads.
var marks_made: int = 0
var executions: int = 0
var marks_expired: int = 0

func _init(player: Player) -> void:
	p = player

## The passive's rank on this hero (0 when not bought, or when the hero has no Melee-tree access).
func rank() -> int:
	return TownState.effective_passive_rank("opening", p.member_id)

## Opening chance in percent per melee hit, or per successful shield block: the passive's rank table plus any worn +Opening chance.
func spot_chance() -> float:
	var r: int = rank()
	if r <= 0:
		return 0.0
	return PassiveDb.get_def("opening").extra_value("spot", r) + p.stats.gear_stat("opening")

func shield_chance() -> float:
	var r: int = rank()
	if r <= 0:
		return 0.0
	return PassiveDb.get_def("opening").extra_value("shield", r) + p.stats.gear_stat("opening")

## Extra damage on an execution, in percent on top of its guaranteed critical.
func damage_bonus() -> float:
	return PassiveDb.get_def("opening").extra_value("damage", maxi(rank(), 1))

## Extra item drop chance on the executed enemy, in percent.
func drop_bonus() -> float:
	return PassiveDb.get_def("opening").extra_value("drop", maxi(rank(), 1))

## Power charge restored by an execution, in percent of each power's bar: the one flat Curse rule (PlayerStats.OPENING_REFILL), not the
## DS2 passive's rank-scaled "charge" value, so the refund is never counted twice.
func charge_refund() -> float:
	return PlayerStats.OPENING_REFILL * 100.0

## The execution for the hero's wielded weapon (a melee-triggered Opening). Empty when there is none. A shield never overrides it: only a
## mark made by a successful block (mark_kind "block") plays the shield bash, see style_for_kind.
func style_id() -> String:
	if p.stats.is_ranged():
		return ""   # Openings are a melee passive
	var weapon: Variant = p.stats.equipment.get(Items.Slot.WEAPON)
	if weapon is Dictionary:
		var unique: UniqueDef = UniqueDb.get_unique(String((weapon as Dictionary).get("unique", "")))
		if unique != null and unique.opening_style != "":
			return unique.opening_style   # a unique weapon's own execution
	return String(p.stats.weapon_profile("opening", ""))

## The execution a mark plays: a block-triggered mark plays the shield bash (a shield must be worn), any other mark the weapon's own.
func style_for_kind(kind: String) -> String:
	if kind == "block":
		return SHIELD_STYLE if p.stats.equipment.has(Items.Slot.SHIELD) else ""
	return style_id()

func style() -> Dictionary:
	var id: String = style_for_kind(mark_kind)
	return (STYLES[id] as Dictionary).duplicate() if STYLES.has(id) else {}

## Called after a basic melee blow the hero lands on `target` (a hit, not a miss, block or secondary effect). A power rolls once per use
## through `on_power_use` instead, not once per enemy it hits.
func on_melee_hit(target: Actor) -> void:
	if mark_target != null or cooldown > 0.0 or rank() <= 0 or style_id() == "":
		return
	if randf() * 100.0 >= spot_chance():
		return
	var nearby: Actor = _nearest_enemy_in_reach(target)
	if nearby != null:
		_mark(nearby, "melee")

## Called once when the hero uses a melee power (Whirling Strike, Staggering Blow, and so on): one roll for the whole use, not per enemy.
func on_power_use() -> void:
	if mark_target != null or cooldown > 0.0 or rank() <= 0 or style_id() == "":
		return
	if randf() * 100.0 >= spot_chance():
		return
	var nearby: Actor = _nearest_enemy_in_reach(null)
	if nearby != null:
		_mark(nearby, "melee")

## Called when the hero blocks a blow on his shield. Only a successful block gets this roll.
func on_block(attacker: Actor) -> void:
	if mark_target != null or cooldown > 0.0 or rank() <= 0 or not is_instance_valid(attacker) or attacker.dead:
		return
	if not attacker.is_in_group("enemies"):
		return
	if randf() * 100.0 >= shield_chance():
		return
	_mark(attacker, "block")

func _nearest_enemy_in_reach(first: Actor) -> Actor:
	var best: Actor = null
	var best_d: float = INF
	for node in p.get_tree().get_nodes_in_group("enemies"):
		var e := node as Actor
		if e == null or e.dead or not is_instance_valid(e) or e.is_in_group("player"):
			continue
		var d: float = p.flat_distance_to(e) - e.body_radius
		if d <= MELEE_REACH and d < best_d:
			best = e
			best_d = d
	if best == null and is_instance_valid(first) and not first.dead:
		best = first
	return best

func _mark(enemy: Actor, kind: String) -> void:
	clear_mark(false)
	mark_target = enemy
	mark_kind = kind
	mark_left = WINDOW
	marks_made += 1
	_ring = _make_ring(enemy)
	Sfx.sample(enemy, "sword_hit", -4.0, 1.8)   # cue: a bright ring off the blade (see docs: a dedicated recording is pending)
	Fx.text_at(enemy, enemy.global_position + Vector3(0, 2.6, 0), "OPENING", Color(1.0, 0.85, 0.35), 34, 0.9)

func _make_ring(enemy: Actor) -> MeshInstance3D:
	# A glowing band on the ground under the enemy (a torus, so the body does not hide it).
	var ring := MeshInstance3D.new()
	var band := TorusMesh.new()
	var radius: float = maxf(enemy.body_radius, 0.5) * 1.5
	band.inner_radius = radius * 0.82
	band.outer_radius = radius
	band.rings = 32
	band.ring_segments = 12
	ring.mesh = band
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.3, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position = Vector3(0, GROUND_LIFT, 0)
	enemy.add_child(ring)
	return ring

## Ends the current mark. `cool` starts the cooldown (an expired or executed mark does; a replaced one does not).
func clear_mark(cool: bool = true) -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	mark_target = null
	mark_left = 0.0
	mark_kind = ""
	if cool:
		cooldown = COOLDOWN

func is_open_on(target: Actor) -> bool:
	return mark_target != null and target == mark_target and mark_left > 0.0 and is_instance_valid(target) and not target.dead

## Frame update: counts the window down, pulses the mark and runs the cooldown.
func tick(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	if mark_target == null:
		return
	if not is_instance_valid(mark_target) or mark_target.dead:
		clear_mark(false)
		return
	mark_left -= delta
	if mark_left <= 0.0:
		marks_expired += 1
		clear_mark(true)
		return
	_ring_pulse += delta
	if is_instance_valid(_ring):
		var pulse: float = 1.0 + 0.08 * sin(_ring_pulse * 9.0)
		_ring.scale = Vector3(pulse, 1.0, pulse)

## The hero's basic attack reached the marked enemy: start the execution and spend the mark. Returns true when it took the attack.
func try_execute(target: Actor) -> bool:
	if not is_open_on(target):
		return false
	var s: Dictionary = style()
	if s.is_empty():
		return false
	clear_mark(false)
	cooldown = COOLDOWN
	executions += 1
	p.skills.start_opening(target, s)
	return true

## Payoff of a landed execution: the drop chance and power charge, gear ignite and heal, and the stun of a crushing blow. A champion
## hook: a champion takes the crit and loses its affix (Lane G), it is never instantly killed.
func on_executed(target: Actor, result: Dictionary, s: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	if int(result.get("outcome", 0)) in [Combat.Outcome.MISS, Combat.Outcome.BLOCK]:
		return
	target.set_meta("opening_drop_mult", 1.0 + drop_bonus() / 100.0)
	p.stats.refund_power_charge(charge_refund() / 100.0)
	var heal_pct: float = p.stats.gear_stat("openings_heal")
	if heal_pct > 0.0:
		p.stats.heal(p.max_health * heal_pct / 100.0)
	var ignite: float = p.stats.gear_stat("openings_ignite")
	if ignite > 0.0 and target.has_method("apply_burn"):
		target.apply_burn(maxf(p.stats.weapon_damage(1.0), 1.0) * ignite / 100.0, BURN_SECONDS, true, p, "opening", result.get("origin", {}))
	var stun: float = float(s.get("stun", 0.0))
	if stun > 0.0:
		for node in p.get_tree().get_nodes_in_group("enemies"):
			var e := node as Actor
			if e != null and e != target and not e.dead and is_instance_valid(e) and e.global_position.distance_to(target.global_position) <= EXECUTION_STUN_RADIUS:
				e._gain_stun(stun)
	_champion_break(target)

## Champion hook (Lane G): a champion's defining affix breaks here. Lane G is not merged, so nothing happens yet.
func _champion_break(_target: Actor) -> void:
	pass
