class_name TownState
extends RefCounted
## Everything about the town that outlives a run: gold, food, the hero's gear and stash, each townsperson's mood and how they feel
## about each other, the job board and the job being run. Static, so the town scene, the run and the menus all see the same
## thing; saved to user://town.json (the self-test turns saving off).

const SAVE_PATH := "user://town.json"
## Bump this when a saved field changes shape or meaning, and add a step to `migrate`. A save with no version is version 0 (from before
## versions existed); a save newer than this build is never loaded or overwritten (it is copied aside, see `load_or_start`).
const SAVE_VERSION := 2
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
static var board: Array = []              # job offers: {name, location, objective, modifiers: [id], reward} (see JobObjective)
static var job: Dictionary = {}           # the job being run (empty: a free arena run)
static var last_run: Dictionary = {}      # {kills, wave, completed, died, gold} of the run just finished (abandoned: true if the game was closed mid-run)
## Saving is a conscious choice: the job taken and the last run's result are saved, but a run itself is not (no mid-run saves yet).
## `run_in_progress` is saved when the hero leaves the gate and cleared when the run ends, so a town that loads with it still set knows
## the game was closed mid-run: that run is abandoned (nothing earned or lost, the food already spent stays spent).
static var run_in_progress: bool = false
static var smith_gold: int = 120
static var smith_stock: Array = []        # the smith's weapons and armour for sale: {item, price}
static var stock: Array = []              # the vendor's items for sale: {item, price}

## The one authored location so far (see CryptRoad): its job is always on the board, in the first slot. The other places are still the wave arena.
const CRYPT_ROAD := "the Crypt Road"
const JOB_NAMES: Array[String] = ["Marrow Fields", "the Drowned Chapel", "Ashen Hollow", "the Old Tannery",
	"Gallows Hill", "the Bone Orchard", "Saltgrave Bridge", "the Rotwood"]

# --- Setup ---------------------------------------------------------------------------------------------------------------

## A fresh town: starting gold and food, everyone at their starting mood, a first job board.
static func reset() -> void:
	gold = 40
	food = 12
	potions = 3
	jobs_done = 0
	vendor_gold = 150
	smith_gold = 120
	smith_stock = []
	gear = {}
	stash = []
	npcs = {}
	relations = {}
	board = []
	job = {}
	last_run = {}
	run_in_progress = false
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
		if i == 0:
			board.append(crypt_road_offer())
			continue
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
		board.append({"name": ("Clear " if i == 0 else "Hold ") + place, "location": place, "objective": JobObjective.clear_waves(waves), "modifiers": chosen,
			"reward": int(round((35.0 + 25.0 * waves) * mult))})

## "Cleanse the Crypt Road": destroy its three corrupted nests; no waves, no timer (see JobObjective.DESTROY_NEST).
static func crypt_road_offer() -> Dictionary:
	return {"name": "Cleanse " + CRYPT_ROAD, "location": CRYPT_ROAD, "site": CryptRoad.SITE_ID, "objective": JobObjective.destroy_nest(3),
		"modifiers": [], "reward": 150 + 20 * mini(jobs_done, 10)}

static func _compatible(id: String, chosen: Array[String]) -> bool:
	var def: RunModifierDef = TownDb.modifier(id)
	for other in chosen:
		if other in def.excludes or id in TownDb.modifier(other).excludes:
			return false
	return true

## Leaving through the gate: the job becomes the active one and the clan eats.
static func begin_job(offer: Dictionary) -> void:
	job = offer.duplicate(true)
	run_in_progress = true
	var short: bool = food < food_cost()   # decided before eating: having exactly enough is not going hungry
	food = maxi(food - food_cost(), 0)
	if short:
		for id in member_ids():
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
	run_in_progress = false
	vendor_gold += 25
	smith_gold += 20
	stock = []   # the trader gets new stock
	smith_stock = []   # and the smith
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
	return {"save_version": SAVE_VERSION, "gold": gold, "food": food, "potions": potions, "jobs_done": jobs_done,
		"vendor_gold": vendor_gold, "smith_gold": smith_gold, "smith_stock": _stock_to_save(smith_stock), "gear": _gear_to_save(),
		"stash": _items_to_save(stash), "npcs": npcs, "relations": relations, "board": board, "stock": _stock_to_save(stock), "job": job, "last_run": last_run, "run_in_progress": run_in_progress}

## Brings a loaded save up to SAVE_VERSION, one step at a time. Returns {} for a save from a newer build (do not touch it).
static func migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get("save_version", 0))
	if version > SAVE_VERSION:
		return {}
	while version < SAVE_VERSION:
		match version:
			0:   # before versions: boards held {waves}, no job or last run was saved
				var offers: Array = []
				for offer in data.get("board", []):
					offers.append(JobObjective.upgrade_legacy(offer))
				data["board"] = offers
				data["job"] = {}
				data["last_run"] = {}
				data["run_in_progress"] = false
			1:   # items were whole dictionaries: they become {def, tier, rarity, affix} (from_save reads both, this rewrites them)
				data["gear"] = _gear_to_save(_gear_from_save(data.get("gear", {})))
				data["stash"] = _items_to_save(_items_from_save(data.get("stash", [])))
				data["stock"] = _stock_to_save(_stock_from_save(data.get("stock", [])))
				data["smith_stock"] = _stock_to_save(_stock_from_save(data.get("smith_stock", [])))
		version += 1
		data["save_version"] = version
	return data

## Takes migrated data (see `migrate`); anything missing falls back to a starting value.
static func from_dict(data: Dictionary) -> void:
	gold = int(data.get("gold", 40))
	food = int(data.get("food", 12))
	potions = int(data.get("potions", 3))
	jobs_done = int(data.get("jobs_done", 0))
	vendor_gold = int(data.get("vendor_gold", 150))
	smith_gold = int(data.get("smith_gold", 120))
	smith_stock = _stock_from_save(data.get("smith_stock", []))
	gear = _gear_from_save(data.get("gear", {}))
	stash = _items_from_save(data.get("stash", []))
	npcs = data.get("npcs", {})
	relations = data.get("relations", {})
	board = []
	for offer in data.get("board", []):
		board.append(JobObjective.upgrade_legacy(offer))
	var has_site: bool = false
	for offer in board:
		has_site = has_site or String(offer.get("site", "")) == CryptRoad.SITE_ID
	if not board.is_empty() and not has_site:   # a board posted before the Crypt Road existed: its first offer becomes the Crypt Road job
		board[0] = crypt_road_offer()
	stock = _stock_from_save(data.get("stock", []))
	var saved_job: Dictionary = data.get("job", {})
	job = JobObjective.upgrade_legacy(saved_job) if not saved_job.is_empty() else {}
	last_run = data.get("last_run", {})
	run_in_progress = bool(data.get("run_in_progress", false))
	if run_in_progress:   # the game was closed during a run, and runs are not saved: it is over, with nothing earned
		run_in_progress = false
		job = {}
		last_run = {"kills": 0, "wave": 0, "completed": false, "died": false, "gold": 0, "abandoned": true}

## Items are saved as {def, tier, rarity, affix} (see Items.to_save) and built again on load; one whose base or affix no longer exists
## is dropped rather than breaking the save.
static func _items_to_save(items: Array) -> Array:
	var out: Array = []
	for item in items:
		out.append(Items.to_save(item))
	return out

static func _items_from_save(saved: Array) -> Array:
	var out: Array = []
	for entry in saved:
		var item: Dictionary = Items.from_save(entry)
		if not item.is_empty():
			out.append(item)
	return out

static func _gear_to_save(worn: Variant = null) -> Dictionary:
	var source: Dictionary = gear if worn == null else worn
	var out: Dictionary = {}
	for slot in source:
		out[str(slot)] = Items.to_save(source[slot])
	return out

static func _gear_from_save(saved: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in saved:
		var item: Dictionary = Items.from_save(saved[key])
		if not item.is_empty():
			out[int(item["slot"])] = item
	return out

static func _stock_to_save(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append({"item": Items.to_save(entry["item"]), "price": int(entry["price"])})
	return out

static func _stock_from_save(saved: Array) -> Array:
	var out: Array = []
	for entry in saved:
		var item: Dictionary = Items.from_save(entry["item"])
		if not item.is_empty():
			out.append({"item": item, "price": int(entry["price"])})
	return out

## Written to a temporary file and moved into place, so a crash while saving cannot leave half a save.
static func save() -> void:
	if not persist:
		return
	var temp: String = SAVE_PATH + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	DirAccess.rename_absolute(temp, SAVE_PATH)

## Loads the saved town, or starts a new one when there is none. A save that cannot be read, or that is from a newer build, is
## copied to user://town.json.<reason>.bak first so starting fresh never destroys it.
static func load_or_start() -> void:
	if persist and FileAccess.file_exists(SAVE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if parsed is Dictionary:
			var data: Dictionary = migrate(parsed)
			if data.is_empty():
				_back_up("newer")
			else:
				from_dict(data)
				if bool(last_run.get("abandoned", false)):
					save()   # the interrupted run is now settled: write that down so it is not found again
		else:
			_back_up("unreadable")
	start_if_needed()

static func _back_up(reason: String) -> void:
	DirAccess.copy_absolute(SAVE_PATH, "%s.%s.bak" % [SAVE_PATH, reason])
