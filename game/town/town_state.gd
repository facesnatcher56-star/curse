class_name TownState
extends RefCounted
## Everything about the town that outlives a run: gold, food, the hero's gear and stash, each townsperson's mood and how they feel
## about each other, the job board and the job being run. Static, so the town scene, the run and the menus all see the same
## thing; saved to user://town.json (the self-test turns saving off).

const SAVE_PATH := "user://town.json"
const MAX_STASH := 12
const LOW_FOOD := 3

static var persist: bool = true

static var gold: int = 40
static var food: int = 12
static var potions: int = 3
static var jobs_done: int = 0
static var vendor_gold: int = 150
static var gear: Dictionary = {}          # Items.Slot (int) -> item Dictionary, worn at the start of every run
static var stash: Array = []              # spare items
static var npcs: Dictionary = {}          # id -> {happiness: float, traits: [id], member: bool, left: bool}
static var relations: Dictionary = {}     # "a|b" (ids sorted) -> 0..100, 50 is neutral
static var board: Array = []              # job offers: {name, waves, modifiers: [id], reward}
static var job: Dictionary = {}           # the job being run (empty: a free arena run)
static var last_run: Dictionary = {}      # {kills, wave, completed, died, gold} of the run just finished
static var stock: Array = []              # the vendor's items for sale: {item, price}

const JOB_NAMES: Array[String] = ["the Crypt Road", "Marrow Fields", "the Drowned Chapel", "Ashen Hollow", "the Old Tannery",
	"Gallows Hill", "the Bone Orchard", "Saltgrave Bridge", "the Rotwood"]

# --- Setup ---------------------------------------------------------------------------------------------------------------

## A fresh town: starting gold and food, everyone at their starting mood, a first job board.
static func reset() -> void:
	gold = 40
	food = 12
	potions = 3
	jobs_done = 0
	vendor_gold = 150
	gear = {}
	stash = []
	npcs = {}
	relations = {}
	board = []
	job = {}
	last_run = {}
	stock = []
	ensure_npcs()
	roll_board()

## Makes sure every NpcDef has a state entry (new NPCs added to the data appear in old saves).
static func ensure_npcs() -> void:
	for id in TownDb.sorted_ids(TownDb.npcs()):
		if not npcs.has(id):
			var def: NpcDef = TownDb.npc(id)
			var traits: Array = []
			for t in def.traits:
				traits.append(t)
			npcs[id] = {"happiness": def.start_happiness, "traits": traits, "member": def.role != "recruit", "left": false}

static func start_if_needed() -> void:
	if npcs.is_empty():
		reset()
	ensure_npcs()
	if board.is_empty():
		roll_board()

# --- NPC mood and relations ----------------------------------------------------------------------------------------------

static func present_ids() -> Array:
	var ids: Array = []
	for id in TownDb.sorted_ids(TownDb.npcs()):
		if npcs.has(id) and not bool(npcs[id]["left"]):
			ids.append(id)
	return ids

## The clan: everyone who has joined (the townspeople who run the town count from the start).
static func member_ids() -> Array:
	var ids: Array = []
	for id in present_ids():
		if bool(npcs[id]["member"]):
			ids.append(id)
	return ids

static func happiness(id: String) -> float:
	return float(npcs[id]["happiness"]) if npcs.has(id) else 0.0

static func add_happiness(id: String, amount: float) -> void:
	if npcs.has(id):
		npcs[id]["happiness"] = clampf(float(npcs[id]["happiness"]) + amount, -100.0, 100.0)

static func traits_of(id: String) -> Array:
	return npcs[id]["traits"] if npcs.has(id) else []

static func _pair(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

static func relation(a: String, b: String) -> float:
	return float(relations.get(_pair(a, b), 50.0))

static func add_relation(a: String, b: String, amount: float) -> void:
	relations[_pair(a, b)] = clampf(relation(a, b) + amount, 0.0, 100.0)

## Short word for a mood or an opinion, as the player sees it.
static func mood_word(value: float) -> String:
	if value >= 50.0:
		return "Content"
	if value >= 10.0:
		return "Fine"
	if value >= -20.0:
		return "Uneasy"
	if value >= -60.0:
		return "Unhappy"
	return "Wretched"

static func opinion_word(value: float) -> String:
	if value < 20.0:
		return "Hates"
	if value < 45.0:
		return "Dislikes"
	if value <= 55.0:
		return "Neutral"
	if value <= 80.0:
		return "Likes"
	return "Close"

static func rationing() -> bool:
	return food <= LOW_FOOD

# --- Jobs ----------------------------------------------------------------------------------------------------------------

## Three offers, each with up to two modifiers (the way the data's `excludes` allows) and a reward that grows with them.
static func roll_board(rng: RandomNumberGenerator = null) -> void:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	board = []
	var names: Array[String] = JOB_NAMES.duplicate()
	var ids: Array = TownDb.sorted_ids(TownDb.modifiers())
	for i in 3:
		var waves: int = 2 + i + (1 if jobs_done >= 3 else 0)
		var chosen: Array[String] = []
		var wanted: int = [0, 1, 2][clampi(i + (1 if jobs_done >= 2 else 0), 0, 2)]
		var tries: int = 0
		while chosen.size() < wanted and tries < 30:
			tries += 1
			var id: String = ids[r.randi() % ids.size()]
			if chosen.has(id) or not _compatible(id, chosen):
				continue
			chosen.append(id)
		var place: String = names.pop_at(r.randi() % names.size())
		var mult: float = 1.0
		for id in chosen:
			mult *= TownDb.modifier(id).reward_mult
		board.append({"name": ("Clear " if i == 0 else "Hold ") + place, "waves": waves, "modifiers": chosen,
			"reward": int(round((35.0 + 25.0 * waves) * mult))})

static func _compatible(id: String, chosen: Array[String]) -> bool:
	var def: WaveModifierDef = TownDb.modifier(id)
	for other in chosen:
		if other in def.excludes or id in TownDb.modifier(other).excludes:
			return false
	return true

## Leaving through the gate: the job becomes the active one and the clan eats.
static func begin_job(offer: Dictionary) -> void:
	job = offer.duplicate(true)
	food = maxi(food - food_cost(), 0)
	for id in member_ids():
		if food <= 0:
			add_happiness(id, -3.0)
	save()

static func food_cost() -> int:
	return maxi(1, member_ids().size() - 1)

## Back from a run: pay out, update moods, restock, post new jobs. `result` = {kills, wave, completed, died}.
static func finish_run(result: Dictionary) -> void:
	var earned: int = int(result.get("kills", 0)) * 2
	if bool(result.get("completed", false)) and not job.is_empty():
		earned += int(job.get("reward", 0))
		jobs_done += 1
	gold += earned
	var summary: Dictionary = result.duplicate()
	summary["gold"] = earned
	last_run = summary
	for id in member_ids():
		var def: NpcDef = TownDb.npc(id)
		if def != null and def.clan_skill == "forager":
			food += 2
		add_happiness(id, 4.0 if bool(result.get("completed", false)) else (-4.0 if bool(result.get("died", false)) else 0.0))
	vendor_gold += 25
	stock = []   # the trader gets new stock
	job = {}
	roll_board()
	save()

## Takes the hero's gear at the end of a run. A worn item that gets replaced goes to the stash.
static func take_gear(equipment: Dictionary) -> void:
	for slot in equipment.keys():
		var item: Dictionary = (equipment[slot] as Dictionary).duplicate(true)
		var old: Variant = gear.get(int(slot))
		if old != null and (old as Dictionary).get("name") != item.get("name") and not _is_plain_starter(old as Dictionary):
			stash_item(old as Dictionary)
		gear[int(slot)] = item

static func _is_plain_starter(item: Dictionary) -> bool:
	return int(item.get("rarity", 0)) == Items.Rarity.COMMON and String(item.get("affix", "")) == ""

static func stash_item(item: Dictionary) -> void:
	stash.append(item)
	while stash.size() > MAX_STASH:
		stash.pop_front()

## What the vendor will pay for an item (and charge, before mood).
static func item_price(item: Dictionary) -> int:
	return [30, 80, 220][clampi(int(item.get("rarity", 0)), 0, 2)]

# --- Saving --------------------------------------------------------------------------------------------------------------

static func to_dict() -> Dictionary:
	return {"gold": gold, "food": food, "potions": potions, "jobs_done": jobs_done, "vendor_gold": vendor_gold, "gear": gear,
		"stash": stash, "npcs": npcs, "relations": relations, "board": board, "stock": stock}

static func from_dict(data: Dictionary) -> void:
	gold = int(data.get("gold", 40))
	food = int(data.get("food", 12))
	potions = int(data.get("potions", 3))
	jobs_done = int(data.get("jobs_done", 0))
	vendor_gold = int(data.get("vendor_gold", 150))
	gear = {}
	for key in (data.get("gear", {}) as Dictionary):
		gear[int(key)] = _fix_item(data["gear"][key])
	stash = []
	for item in data.get("stash", []):
		stash.append(_fix_item(item))
	npcs = data.get("npcs", {})
	relations = data.get("relations", {})
	board = data.get("board", [])
	stock = []
	for entry in data.get("stock", []):
		stock.append({"item": _fix_item(entry["item"]), "price": int(entry["price"])})
	job = {}
	last_run = {}

## JSON has no integers: bring slot/rarity back to ints.
static func _fix_item(item: Dictionary) -> Dictionary:
	item["slot"] = int(item["slot"])
	item["rarity"] = int(item["rarity"])
	return item

static func save() -> void:
	if not persist:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(to_dict()))

## Loads the saved town, or starts a new one when there is none (or it cannot be read).
static func load_or_start() -> void:
	if persist and FileAccess.file_exists(SAVE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if parsed is Dictionary:
			from_dict(parsed)
	start_if_needed()
