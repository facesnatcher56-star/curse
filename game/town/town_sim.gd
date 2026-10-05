class_name TownSim
extends RefCounted
## The town's inner life (see docs/zombasite-world-and-npcs.md, 3.2 to 3.6). Every few seconds each NPC picks an activity, weighted by
## their personality traits and mood; social activities act on another NPC, who reacts according to what their own traits like or
## dislike, and that moves their mood and what the two think of each other. Bad blood ends in brawls, a hired recruit who is
## wretched leaves, and now and then a town event happens. Everything is numbers in TownState; this only changes them.
##
## `barks` collects what NPCs say (the town scene shows them above heads); `history` is the same as plain text for tests and the board.

const ACTIVITY_TIME := 15.0     # seconds between rounds (Zombasite: 15 s per activity)
const EVENT_TIME := 150.0       # a town event about this often

## id -> base weight, whether it needs a partner, happiness change for the doer and the target, and the opinion change.
const ACTIVITIES := {
	"small_talk": {"w": 1.2, "social": true, "self": 1.0, "other": 1.0, "rel": 1.5},
	"gossip": {"w": 0.6, "social": true, "self": 1.5, "other": 0.0, "rel": 0.5},
	"argue": {"w": 0.5, "social": true, "self": -1.0, "other": -3.0, "rel": -6.0},
	"praise": {"w": 0.5, "social": true, "self": 0.5, "other": 3.0, "rel": 4.0},
	"joke": {"w": 0.7, "social": true, "self": 1.0, "other": 1.5, "rel": 1.0},
	"drink": {"w": 0.3, "social": false, "self": 2.0},
	"pray": {"w": 0.3, "social": false, "self": 1.5},
	"rest": {"w": 1.0, "social": false, "self": 0.5},
	"brood": {"w": 0.2, "social": false, "self": -2.0},
	"work": {"w": 1.0, "social": false, "self": 0.3},
}
const LIKED_BONUS := {"other": 2.0, "rel": 3.0}
const DISLIKED_PENALTY := {"other": -3.0, "rel": -4.0}
const BRAWL_BELOW := 20.0
const LEAVE_BELOW := -60.0

var rng := RandomNumberGenerator.new()
var barks: Array[Dictionary] = []    # {id, text, partner}: drained by the town scene
var history: Array[String] = []
var _clock: float = 0.0
var _event_clock: float = EVENT_TIME * 0.6

func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

## Advances town time. `delta` is real seconds.
func tick(delta: float) -> void:
	_clock += delta
	_event_clock -= delta
	while _clock >= ACTIVITY_TIME:
		_clock -= ACTIVITY_TIME
		run_round()
	if _event_clock <= 0.0:
		_event_clock = EVENT_TIME * rng.randf_range(0.7, 1.3)
		run_event()

## One round: every NPC in town does one thing.
func run_round() -> void:
	var ids: Array = TownState.present_ids()
	for i in range(ids.size() - 1, 0, -1):   # shuffled with this sim's own generator, so a seed gives the same town
		var j: int = rng.randi() % (i + 1)
		var held: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = held
	for id in ids:
		if bool(TownState.npcs[id]["left"]):
			continue
		_do_activity(id, ids)
	_settle(ids)

# --- Choosing and doing --------------------------------------------------------------------------------------------------

## The weight of each activity for this NPC right now: base, personality traits, then mood.
func activity_weights(id: String) -> Dictionary:
	var weights: Dictionary = {}
	var mood: float = TownState.happiness(id)
	for activity in ACTIVITIES:
		var w: float = float(ACTIVITIES[activity]["w"])
		for trait_id in TownState.traits_of(id):
			var t: TraitDef = TownDb.trait_def(trait_id)
			if t != null and t.weights.has(activity):
				w *= float(t.weights[activity])
		if mood < 0.0:
			w *= {"argue": 2.5, "brood": 3.0, "praise": 0.4, "joke": 0.5}.get(activity, 1.0)
		elif mood > 40.0:
			w *= {"argue": 0.3, "small_talk": 1.5, "praise": 1.5}.get(activity, 1.0)
		weights[activity] = w
	return weights

func _pick_activity(id: String) -> String:
	var weights: Dictionary = activity_weights(id)
	var total: float = 0.0
	for activity in weights:
		total += float(weights[activity])
	var roll: float = rng.randf() * total
	for activity in weights:
		roll -= float(weights[activity])
		if roll <= 0.0:
			return activity
	return "rest"

func _do_activity(id: String, ids: Array) -> void:
	var activity: String = _pick_activity(id)
	var spec: Dictionary = ACTIVITIES[activity]
	var partner: String = ""
	if bool(spec["social"]):
		partner = _pick_partner(id, ids)
		if partner == "":
			activity = "rest"
			spec = ACTIVITIES[activity]
	perform(id, activity, partner)

## Runs one activity (also used directly by tests): the doer's mood, and for a social one the target's reaction.
func perform(id: String, activity: String, partner: String = "") -> void:
	var spec: Dictionary = ACTIVITIES[activity]
	TownState.add_happiness(id, float(spec["self"]))
	var def: NpcDef = TownDb.npc(id)
	if partner == "":
		if activity in ["drink", "pray", "brood", "work"]:
			_say(id, _line(def, activity, ""), "")
		return
	var other: float = float(spec["other"])
	var rel: float = float(spec["rel"])
	var verdict: int = _reaction(partner, activity)
	if verdict > 0:
		other += float(LIKED_BONUS["other"])
		rel += float(LIKED_BONUS["rel"])
	elif verdict < 0:
		other += float(DISLIKED_PENALTY["other"])
		rel += float(DISLIKED_PENALTY["rel"])
	TownState.add_happiness(partner, other)
	TownState.add_relation(id, partner, rel)
	_say(id, _line(def, activity, partner), partner)
	if verdict != 0 or activity == "argue":
		var mood_text: String = "enjoys" if verdict > 0 else "resents"
		if activity == "argue":
			mood_text = "is wounded by"
		history.append("%s %s %s's %s." % [_name(partner), mood_text, _name(id), activity.replace("_", " ")])

## +1 if the target's traits like this kind of interaction, -1 if they dislike it, 0 otherwise.
func _reaction(target: String, activity: String) -> int:
	var score: int = 0
	for trait_id in TownState.traits_of(target):
		var t: TraitDef = TownDb.trait_def(trait_id)
		if t == null:
			continue
		if activity in t.likes:
			score += 1
		if activity in t.dislikes:
			score -= 1
	return clampi(score, -1, 1)

## Prefers someone they get on with, never someone who just left.
func _pick_partner(id: String, ids: Array) -> String:
	var total: float = 0.0
	var choices: Array = []
	for other in ids:
		if other == id or bool(TownState.npcs[other]["left"]):
			continue
		var w: float = 0.3 + TownState.relation(id, other) / 50.0
		choices.append([other, w])
		total += w
	if choices.is_empty():
		return ""
	var roll: float = rng.randf() * total
	for entry in choices:
		roll -= float(entry[1])
		if roll <= 0.0:
			return String(entry[0])
	return String((choices[0] as Array)[0])

## After a round: opinions drift back toward neutral, food worries, brawls and departures.
func _settle(ids: Array) -> void:
	for a in ids:
		for b in ids:
			if String(a) < String(b):
				var rel: float = TownState.relation(a, b)
				TownState.relations[TownState._pair(a, b)] = rel + clampf(50.0 - rel, -0.3, 0.3)
	for id in ids:
		TownState.add_happiness(id, 0.3)   # a roof and a wall
		if TownState.food <= 0:
			TownState.add_happiness(id, -3.0)
		elif TownState.rationing():
			TownState.add_happiness(id, -1.0)
	for a in ids:
		for b in ids:
			if String(a) < String(b) and TownState.relation(a, b) < BRAWL_BELOW and rng.randf() < 0.5:
				brawl(a, b)
	for id in ids:
		var def: NpcDef = TownDb.npc(id)
		if def != null and def.role == "recruit" and bool(TownState.npcs[id]["member"]) \
				and TownState.happiness(id) < LEAVE_BELOW:
			_leave(id)

func brawl(a: String, b: String) -> void:
	TownState.add_happiness(a, -8.0)
	TownState.add_happiness(b, -8.0)
	TownState.add_relation(a, b, 8.0)   # the air is cleared, a little
	history.append("%s and %s came to blows." % [_name(a), _name(b)])
	_say(a, _line(TownDb.npc(a), "brawl", b), b)
	_say(b, _line(TownDb.npc(b), "brawl", a), a)

func _leave(id: String) -> void:
	TownState.npcs[id]["left"] = true
	TownState.npcs[id]["member"] = false
	history.append("%s has left the clan." % _name(id))
	for other in TownState.present_ids():
		TownState.add_happiness(other, -3.0)
	_say(id, "I'm done with this place.", "")

# --- Events --------------------------------------------------------------------------------------------------------------

## A town event: sickness, a visitor with gold, or a rumour that sours two NPCs on each other.
func run_event() -> void:
	var ids: Array = TownState.present_ids()
	if ids.is_empty():
		return
	match rng.randi() % 3:
		0:
			var sick: String = ids[rng.randi() % ids.size()]
			TownState.add_happiness(sick, -12.0)
			history.append("%s has taken ill." % _name(sick))
			_say(sick, "I don't feel right.", "")
		1:
			TownState.vendor_gold += 40
			history.append("A traveller passed through and traded with Marlow.")
		2:
			if ids.size() >= 2:
				var a: String = ids[rng.randi() % ids.size()]
				var b: String = a
				while b == a:
					b = ids[rng.randi() % ids.size()]
				TownState.add_relation(a, b, -10.0)
				history.append("A rumour is going round about %s and %s." % [_name(a), _name(b)])
				_say(a, "Who has been talking about me?", b)

# --- Helpers -------------------------------------------------------------------------------------------------------------

## The price and reward effect of an NPC's mood: content merchants give a little, wretched ones charge more.
static func mood_price_mult(id: String) -> float:
	var h: float = TownState.happiness(id)
	if h > 40.0:
		return 0.9
	if h < -20.0:
		return 1.2
	return 1.0

func _name(id: String) -> String:
	var def: NpcDef = TownDb.npc(id)
	return def.display_name if def != null else id

func _line(def: NpcDef, key: String, _partner: String) -> String:
	if def == null or not def.lines.has(key):
		return {"brawl": "That's it!", "drink": "Another.", "pray": "Light, keep us.", "brood": "...", "work": "Back to it."}.get(key, "")
	var options: Array = def.lines[key]
	return String(options[rng.randi() % options.size()])

func _say(id: String, text: String, partner: String) -> void:
	if text != "":
		barks.append({"id": id, "text": text, "partner": partner})

## What an NPC says on a plain occasion ("greet", "idle", "return_ok", "return_dead", "hire").
func line_for(id: String, key: String) -> String:
	return _line(TownDb.npc(id), key, "")
