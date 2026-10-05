class_name TownStage
extends RefCounted
## Acts out what TownSim decides, so the town's social life can be seen: someone who wants to gossip walks over to the other
## person and they face each other; an argument is had at arm's length and a brawl ends in a shove; drinking, praying and working
## happen at the inn door, the chapel door and the person's own station. The sim's numbers are unchanged and still apply at once;
## this only moves the people and decides when they speak. Scenes run one after another per person (nobody is in two at once).

## Where a solo activity is done comes from the town layout's Stations markers: "drink" (the inn door), "pray" (the chapel door) and
## "work_<role>" for each role (at the stall, the board, the stone, the anvil). A missing one falls back to the person's own place.
const SOCIAL := ["small_talk", "gossip", "argue", "praise", "joke", "brawl"]
const SOLO := ["drink", "pray", "work"]
const MEET_DISTANCE := 1.5      # how close two people stand to talk
const TALK_SECONDS := 4.5       # how long they stand there
const QUEUE_SECONDS := 20.0     # a scene that cannot start in this time is dropped

## Tests shrink every wait so a scene takes a moment.
static var time_scale: float = 1.0

var town: Node3D                      # the TownScene: its NPCs, the hero and the tree
var events: Array[String] = []        # "<scene> <who>": what has happened, for tests
var _queue: Array[Dictionary] = []

func _init(owner_scene: Node3D) -> void:
	town = owner_scene

## Takes a bark from the sim. Plain speech is said at once; anything with a place to go is queued as a scene.
func handle(bark: Dictionary) -> void:
	var npcs: Dictionary = town.npcs
	var id: String = bark["id"]
	if not npcs.has(id):
		return
	var activity: String = String(bark.get("activity", ""))
	var partner: String = String(bark.get("partner", ""))
	if activity == "brawl_reply":   # said by the one who was shoved, inside the brawl scene if it is still waiting
		for entry in _queue:
			if entry["kind"] == "brawl" and entry["id"] == partner and entry["partner"] == id:
				entry["reply"] = bark["text"]
				return
		_say(id, String(bark["text"]), partner)
		return
	var social: bool = partner != "" and npcs.has(partner) and activity in SOCIAL
	var solo: bool = activity in SOLO
	if not social and not solo:
		_say(id, String(bark["text"]), partner)
		return
	var kind: String = activity
	if social:
		kind = "brawl" if activity == "brawl" else "talk"
	_queue.append({"kind": kind, "activity": activity, "id": id, "partner": partner if social else "",
		"text": bark["text"], "reply": "", "waited": 0.0})

## Starts every queued scene whose people are free; drops the ones that have waited too long.
func update(delta: float) -> void:
	var i: int = 0
	while i < _queue.size():
		var entry: Dictionary = _queue[i]
		entry["waited"] = float(entry["waited"]) + delta
		if _free(entry):
			_queue.remove_at(i)
			_run(entry)
		elif float(entry["waited"]) > QUEUE_SECONDS:
			_queue.remove_at(i)
		else:
			i += 1

func _free(entry: Dictionary) -> bool:
	var npcs: Dictionary = town.npcs
	if (npcs[entry["id"]] as TownNpc).busy:
		return false
	return entry["partner"] == "" or not (npcs[entry["partner"]] as TownNpc).busy

func _run(entry: Dictionary) -> void:
	var npc: TownNpc = town.npcs[entry["id"]]
	var other: TownNpc = town.npcs[entry["partner"]] if entry["partner"] != "" else null
	npc.busy = true
	if other != null:
		other.busy = true
	match String(entry["kind"]):
		"talk":
			await _talk(npc, other, entry)
		"brawl":
			await _brawl(npc, other, entry)
		_:
			await _alone(npc, entry)
	await _go_home(npc)
	npc.busy = false
	if other != null:
		other.busy = false

# --- Scenes --------------------------------------------------------------------------------------------------------------

func _talk(npc: TownNpc, other: TownNpc, entry: Dictionary) -> void:
	await _approach(npc, other)
	events.append("%s %s" % [entry["activity"], entry["id"]])
	_say(entry["id"], String(entry["text"]), String(entry["partner"]))
	_face_each_other(npc, other)
	await _wait(TALK_SECONDS)

func _brawl(npc: TownNpc, other: TownNpc, entry: Dictionary) -> void:
	await _approach(npc, other)
	events.append("brawl %s" % entry["id"])
	_face_each_other(npc, other)
	_say(entry["id"], String(entry["text"]), String(entry["partner"]))
	await _wait(0.5)
	npc.shove(other.global_position)
	await _wait(0.12)
	other.recoil(npc.global_position)
	if String(entry["reply"]) != "":
		await _wait(0.4)
		_say(entry["partner"], String(entry["reply"]), String(entry["id"]))
	await _wait(2.5)

func _alone(npc: TownNpc, entry: Dictionary) -> void:
	var kind: String = String(entry["kind"])
	var spot: Vector3 = npc.home
	var station: String = "work_" + npc.def.role if kind == "work" else kind
	spot = town.stations.get(station, npc.home)
	npc.walk_to(spot)
	await npc.arrived
	events.append("%s %s" % [kind, entry["id"]])
	_say(entry["id"], String(entry["text"]), "")
	await _wait(TALK_SECONDS)

# --- Pieces --------------------------------------------------------------------------------------------------------------

func _approach(npc: TownNpc, other: TownNpc) -> void:
	var from_other: Vector3 = npc.global_position - other.global_position
	from_other.y = 0.0
	if from_other.length() <= MEET_DISTANCE + 0.5:
		return
	npc.walk_to(other.global_position + from_other.normalized() * MEET_DISTANCE)
	await npc.arrived

func _face_each_other(a: TownNpc, b: TownNpc) -> void:
	a.face_toward(b.global_position)
	b.face_toward(a.global_position)

func _go_home(npc: TownNpc) -> void:
	npc.walk_home()
	await npc.arrived
	npc.settle_at_home()

func _wait(seconds: float) -> void:
	await town.get_tree().create_timer(seconds / time_scale).timeout

## Speech is only shown when the hero is near enough to hear it.
func _say(id: String, text: String, partner: String) -> void:
	var npc: TownNpc = town.npcs.get(id)
	if npc == null or town.player.global_position.distance_to(npc.global_position) > town.BARK_RANGE:
		return
	npc.say(text)
	var other: TownNpc = town.npcs.get(partner) if partner != "" else null
	if other != null:
		npc.face_toward(other.global_position)
		other.face_toward(npc.global_position)
