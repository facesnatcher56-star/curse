class_name TownState
extends RefCounted
## Everything about the town that outlives a run: gold, food, the hero's gear and stash, each townsperson's mood and how they feel
## about each other, the job board and the job being run. Static, so the town scene, the run and the menus all see the same
## thing; saved to user://town.json in a normal game. Which file, and whether at all, is SavePolicy's decision: a developer session (any
## user arguments: the self-test, screenshots, diagnostics) never touches the production save unless it passes SavePolicy.REAL_SAVE_FLAG.

const SAVE_PATH := SavePolicy.PRODUCTION_PATH
## Bump this when a saved field changes shape or meaning, and add a step to `migrate`. A save with no version is version 0 (from before
## versions existed); a save newer than this build is never loaded or overwritten (it is copied aside, see `load_or_start`).
const SAVE_VERSION := 4
const MAX_STASH := 12
const LOW_FOOD := 3

static var persist: bool = SavePolicy.persists_by_default(OS.get_cmdline_user_args())

## The file this session reads and writes (the production save in a normal game, the developer-session file otherwise).
static func save_path() -> String:
	return SavePolicy.path_for(OS.get_cmdline_user_args())

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
static var job: Dictionary = {}           # the chosen job (empty: no gate travel)
static var last_run: Dictionary = {}      # {kills, wave, completed, died, gold} of the run just finished (abandoned: true if the game was closed mid-run)
## Saving is a conscious choice: the job taken and the last run's result are saved, but a run itself is not (no mid-run saves yet).
## `run_in_progress` is saved when the hero leaves the gate and cleared when the run ends, so a town that loads with it still set knows
## the game was closed mid-run: that run is abandoned (nothing earned or lost, the food already spent stays spent).
static var run_in_progress: bool = false
static var smith_gold: int = 120
static var smith_stock: Array = []        # the smith's weapons and armour for sale: {item, price}
static var stock: Array = []              # the vendor's items for sale: {item, price}
## Quests and events that have turned up (see Quests): {uid, id, state, days_left, progress, data}. `day` counts the returns from the road.
static var quests: Array = []
## Changes each time the road is corrupted afresh: it picks which conditions the road has and how its empty stretches are stocked.
static var road_seed: int = 0
## The self-test keeps the road plain (no random conditions) unless a check asks for them, so the old checks stay as they were.
static var road_conditions_in_tests: bool = false
static var quest_uid: int = 0
static var day: int = 1
static var world_mods: Array = []         # running world events: {id, days_left, gold_mult, drop_mult, health_mult}
static var quest_clock: Dictionary = {"quest": 120.0, "matter": 90.0}   # seconds until the next quest / matter may turn up
static var quest_history: Array = []      # the last few endings: {id, state, day}
static var monsters: Array = []           # the named monsters on the road (see Monsters)
static var monster_uid: int = 0
static var chronicle: Array = []          # what has happened: {day, kind, text} (see Chronicle)
## The hero's permanent progression (see HeroProgression). `hero_xp` is the total lifetime XP and the only authority: `hero_level` is
## always derived from it (here and on load), kept as a field so everything can simply read `TownState.hero_level`. Nothing else holds a level.
static var hero_xp: int = 0
static var hero_level: int = 1
## What the hero has BOUGHT with the points his level earns (see BuildDefs): the passive ids, and skill id -> chosen evolution id. The only
## things saved about the build: points are never stored, available = earned (from the level) - what these cost. Change them only through
## `buy_passive` / `select_evolution`; a load repairs anything unknown, repeated or unaffordable (it can never give points).
static var purchased_passives: Array[String] = []
static var skill_evolutions: Dictionary = {}
## Announces XP and level changes (see ProgressionEvents); the HUD listens, this never knows about any scene.
static var events := ProgressionEvents.new()

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
	quests = []
	road_seed = 0
	quest_uid = 0
	day = 1
	world_mods = []
	quest_clock = {"quest": 120.0, "matter": 90.0}
	quest_history = []
	monsters = []
	monster_uid = 0
	chronicle = []
	hero_xp = 0
	hero_level = 1
	purchased_passives = []
	skill_evolutions = {}
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

## The board is standing quests: whatever is posted is active, nothing has to be taken. There is one authored place in the world so far
## (the Crypt Road), so there is one quest. `job` mirrors it: the quest the HUD and the hero's surroundings are measuring.
static func roll_board(_rng: RandomNumberGenerator = null) -> void:
	road_seed += 1
	board = [crypt_road_offer()]
	job = (board[0] as Dictionary).duplicate(true)

## "Cleanse the Crypt Road": destroy its three corrupted nests; no waves, no timer (see JobObjective.DESTROY_NEST).
static func crypt_road_offer() -> Dictionary:
	var conditions: Array[String] = roll_road_conditions(road_seed)
	var mult: float = 1.0
	for id in conditions:
		mult *= TownDb.modifier(id).reward_mult
	return {"name": "Cleanse " + CRYPT_ROAD, "location": CRYPT_ROAD, "site": CryptRoad.SITE_ID, "objective": JobObjective.destroy_nest(3),
		"modifiers": conditions, "reward": int(round((150 + 20 * mini(jobs_done, 10)) * mult)), "xp": HeroProgression.STANDING_QUEST_XP}

## The conditions the road has this time (Zombasite gives about half of all levels one or two rules; see section 6 of the research doc):
## half the time none, otherwise one, and a third of those a second that does not clash with it. Always the same for the same seed.
static func roll_road_conditions(seed_value: int) -> Array[String]:
	var out: Array[String] = []
	if OS.get_cmdline_user_args().has("--selftest") and not road_conditions_in_tests:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = 9000 + seed_value * 31
	if rng.randf() >= 0.5:
		return out
	var ids: Array = TownDb.sorted_ids(TownDb.modifiers())
	out.append(String(ids[rng.randi() % ids.size()]))
	if rng.randf() < 0.33:
		for attempt in 10:
			var second: String = String(ids[rng.randi() % ids.size()])
			if not out.has(second) and _compatible(second, out):
				out.append(second)
				break
	return out

## Out in the world a quest's objective is measured as it happens (for the Crypt Road, nests destroyed: `stage`). When one is met it is
## marked `ready`; the keeper pays it out when the hero comes back (claim_ready). Returns true when a quest has just become ready.
static func report_progress(site: String, stage: int) -> bool:
	var became: bool = false
	for offer in board:
		if String(offer.get("site", "")) == site and not bool(offer.get("ready", false)) \
				and JobObjective.is_complete(offer, {"stage": stage}):
			offer["ready"] = true
			became = true
	if became:
		job = (board[0] as Dictionary).duplicate(true) if not board.is_empty() else {}
		save()
	return became

static func has_reward() -> bool:
	for offer in board:
		if bool(offer.get("ready", false)):
			return true
	return false

## The keeper pays every finished quest: gold, a better mood all round, fresh stock, and a new quest is posted in its place. Returns
## {"gold", "count", "names"} (count 0 when there was nothing to claim).
static func claim_ready() -> Dictionary:
	var gold_paid: int = 0
	var xp_paid: int = 0
	var names: Array[String] = []
	for offer in board.duplicate():
		if bool(offer.get("ready", false)):
			gold_paid += int(offer.get("reward", 0))
			xp_paid += int(offer.get("xp", 0))
			names.append(String(offer.get("name", "")))
			jobs_done += 1
			board.erase(offer)
	if names.is_empty():
		return {"gold": 0, "count": 0, "names": names, "xp": 0}
	gold += gold_paid
	for id in member_ids():
		var def: NpcDef = TownDb.npc(id)
		if def != null and def.clan_skill == "forager":
			food += 2
		add_happiness(id, 4.0)
	vendor_gold += 25
	smith_gold += 20
	stock = []   # the trader and the smith get new stock
	smith_stock = []
	roll_board()
	save()
	add_hero_xp(xp_paid)   # after the board is settled: the claim is done, so it can only be paid once
	return {"gold": gold_paid, "count": names.size(), "names": names, "xp": xp_paid}

## True while the hero is out beyond the town. The clan eats once per expedition, not every time the hero steps through the gate.
static var expedition: bool = false

static func begin_expedition() -> void:
	if expedition:
		return
	expedition = true
	var short: bool = food < food_cost()   # decided before eating: having exactly enough is not going hungry
	food = maxi(food - food_cost(), 0)
	if short:
		for id in member_ids():
			add_happiness(id, -3.0)
	save()

static func end_expedition() -> void:
	if expedition:
		Quests.on_day()   # a day has passed on the road: deadlines close in, events run down
	expedition = false

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

# --- Hero progression ----------------------------------------------------------------------------------------------------

## Gives the hero XP and announces it; the one door every XP reward goes through. Zero and negative amounts do nothing. XP past the level
## cap is not kept (there is no level 31). One award can cross several levels: that is one `hero_leveled` event, old level to new level.
## XP is in memory (and announced) at once. It is written to disk at once when `save_now` (quests, named monsters, nests, a level-up
## always), but the many small awards of ordinary kills pass false: they are written within XP_SAVE_DELAY_MS (see `flush_progression`)
## or at the next save, so a road full of zombies is not hundreds of file rewrites. A save writes the whole town (about a millisecond or
## two), which is fine now and then and wasteful per kill.
## Returns {xp_gained (what was actually kept), old_xp, new_xp, old_level, new_level, levels_gained}.
static func add_hero_xp(amount: int, save_now: bool = true) -> Dictionary:
	if amount <= 0:
		return _progress_result(hero_xp, hero_xp)
	var capped: int = mini(amount, HeroProgression.max_xp())   # nothing past the cap is kept: this also keeps the sum from overflowing
	return _set_hero_xp(hero_xp + capped, save_now)

const XP_SAVE_DELAY_MS := 8000
static var _xp_unsaved_ms: int = 0   # when the oldest XP not yet on disk was earned (0: all of it is saved)

## Writes XP waiting for the disk once it has waited long enough (or at once with `force`). Cheap when there is nothing to write: the
## world calls it every frame, and on leaving, quitting and coming home.
static func flush_progression(force: bool = false) -> void:
	if _xp_unsaved_ms != 0 and (force or Time.get_ticks_msec() - _xp_unsaved_ms >= XP_SAVE_DELAY_MS):
		save()

static func has_unsaved_xp() -> bool:
	return _xp_unsaved_ms != 0

## For `--level=N` and tests: puts the hero exactly at the start of a level (down as well as up).
static func dev_set_hero_level(level: int) -> Dictionary:
	return _set_hero_xp(HeroProgression.xp_for_level(level))

## Developer command line: `--level=N` puts the hero at the start of level N, then `--xp=N` grants N XP (so both together mean "level N plus
## N XP"). Not part of the game's own UI. Returns what was applied (tests read it).
static func apply_dev_progression(args: PackedStringArray) -> Array:
	var applied: Array = []
	for arg in args:
		if arg.begins_with("--level=") and arg.substr(8).is_valid_int():
			applied.append(dev_set_hero_level(arg.substr(8).to_int()))
	for arg in args:
		if arg.begins_with("--xp=") and arg.substr(5).is_valid_int():
			applied.append(add_hero_xp(arg.substr(5).to_int()))
	return applied

static func _set_hero_xp(total: int, save_now: bool = true) -> Dictionary:
	var old_xp: int = hero_xp
	var old_level: int = hero_level
	hero_xp = HeroProgression.sanitize_xp(total)
	hero_level = HeroProgression.level_for_xp(hero_xp)
	if hero_level < old_level:
		_repair_build()
	var result: Dictionary = _progress_result(old_xp, hero_xp)
	result["old_level"] = old_level
	result["levels_gained"] = maxi(hero_level - old_level, 0)
	var gained: Dictionary = HeroProgression.points_between(old_level, hero_level)
	result["passive_points_gained"] = int(gained["passive"])
	result["evolution_points_gained"] = int(gained["evolution"])
	if hero_xp != old_xp:
		if save_now or hero_level > old_level:
			save()
		elif _xp_unsaved_ms == 0:
			_xp_unsaved_ms = maxi(Time.get_ticks_msec(), 1)
		events.hero_xp_changed.emit(old_xp, hero_xp)
		if hero_level > old_level:
			var points: Dictionary = HeroProgression.points_between(old_level, hero_level)
			events.hero_leveled.emit(old_level, hero_level, hero_xp, int(points["passive"]), int(points["evolution"]))
	return result

static func _progress_result(old_xp: int, new_xp: int) -> Dictionary:
	var old_level: int = HeroProgression.level_for_xp(old_xp)
	var new_level: int = HeroProgression.level_for_xp(new_xp)
	var gained: Dictionary = HeroProgression.points_between(old_level, new_level)
	return {"xp_gained": maxi(new_xp - old_xp, 0), "old_xp": old_xp, "new_xp": new_xp, "old_level": old_level, "new_level": new_level,
		"levels_gained": maxi(new_level - old_level, 0), "passive_points_gained": int(gained["passive"]), "evolution_points_gained": int(gained["evolution"])}

## Points earned by the hero's level and not yet spent: earned (derived from the level) minus what the saved choices cost. Never negative.
static func passive_points_available() -> int:
	return maxi(HeroProgression.passive_points_for_level(hero_level) - purchased_passives.size() * BuildDefs.PASSIVE_COST, 0)

static func evolution_points_available() -> int:
	return maxi(HeroProgression.evolution_points_for_level(hero_level) - skill_evolutions.size() * BuildDefs.EVOLUTION_COST, 0)

# --- Build choices ------------------------------------------------------------------------------------------------------------------

static func has_passive(id: String) -> bool:
	return purchased_passives.has(id)

static func can_buy_passive(id: String) -> bool:
	return BuildDefs.is_passive(id) and not has_passive(id) and passive_points_available() >= BuildDefs.PASSIVE_COST

## Spends one Passive Point on a passive, once. Returns whether it was bought.
static func buy_passive(id: String) -> bool:
	if not can_buy_passive(id):
		return false
	purchased_passives.append(id)
	save()
	events.hero_build_changed.emit()
	return true

## The evolution chosen for a skill, or "" (the baseline skill).
static func selected_evolution(skill_id: String) -> String:
	return String(skill_evolutions.get(skill_id, ""))

static func can_select_evolution(skill_id: String, evolution_id: String) -> bool:
	return BuildDefs.is_evolution(skill_id, evolution_id) and not skill_evolutions.has(skill_id) 		and evolution_points_available() >= BuildDefs.EVOLUTION_COST

## Spends one Evolution Point on a skill's evolution. Permanent (there is no respec): a skill takes one, and the others are then closed.
static func select_evolution(skill_id: String, evolution_id: String) -> bool:
	if not can_select_evolution(skill_id, evolution_id):
		return false
	skill_evolutions[skill_id] = evolution_id
	save()
	events.hero_build_changed.emit()
	return true

## After the level changes (a developer command can lower it): choices the level no longer pays for are dropped, so points never go negative.
static func _repair_build() -> void:
	var clean: Dictionary = BuildDefs.sanitize(purchased_passives, skill_evolutions, HeroProgression.passive_points_for_level(hero_level),
		HeroProgression.evolution_points_for_level(hero_level))
	if (clean["passives"] as Array).size() != purchased_passives.size() or (clean["evolutions"] as Dictionary).size() != skill_evolutions.size():
		purchased_passives.assign(clean["passives"])
		skill_evolutions = clean["evolutions"]
		events.hero_build_changed.emit()

# --- Saving --------------------------------------------------------------------------------------------------------------

static func to_dict() -> Dictionary:
	return {"save_version": SAVE_VERSION, "gold": gold, "food": food, "potions": potions, "jobs_done": jobs_done,
		"vendor_gold": vendor_gold, "smith_gold": smith_gold, "smith_stock": _stock_to_save(smith_stock), "gear": _gear_to_save(),
		"stash": _items_to_save(stash), "npcs": npcs, "relations": relations, "board": board, "stock": _stock_to_save(stock), "job": job, "last_run": last_run, "run_in_progress": run_in_progress,
		"quests": quests, "road_seed": road_seed, "quest_uid": quest_uid, "day": day, "world_mods": world_mods, "quest_clock": quest_clock, "quest_history": quest_history,
		"monsters": monsters, "monster_uid": monster_uid, "chronicle": chronicle, "hero_level": hero_level, "hero_xp": hero_xp,
		"purchased_passives": purchased_passives.duplicate(), "skill_evolutions": skill_evolutions.duplicate()}

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
			3:   # the build arrives: a save from before it has bought nothing, and every point its level earned is free
				data["purchased_passives"] = []
				data["skill_evolutions"] = {}
			2:   # the hero's permanent level arrives: a save from before it starts at level 1 (nothing else says how far the hero has come)
				data["hero_xp"] = 0
				data["hero_level"] = 1
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
	var posted: Array = []
	for offer in board:
		if String(offer.get("site", "")) != "":   # only quests that exist in the world; the old wave jobs are gone from the board
			offer["xp"] = int(offer.get("xp", HeroProgression.STANDING_QUEST_XP))   # a quest posted before XP existed still pays it
			posted.append(offer)
	board = posted
	if board.is_empty():
		board = [crypt_road_offer()]
	stock = _stock_from_save(data.get("stock", []))
	last_run = data.get("last_run", {})
	quests = []
	for inst in data.get("quests", []):   # JSON has no integers: bring the counters back
		inst["uid"] = int(inst["uid"])
		inst["progress"] = int(inst.get("progress", 0))
		inst["days_left"] = int(inst.get("days_left", -1))
		for key in ["kills"]:
			if (inst.get("data", {}) as Dictionary).has(key):
				inst["data"][key] = int(inst["data"][key])
		if TownDb.quest(String(inst["id"])) != null:   # one whose definition was removed is dropped
			quests.append(inst)
	quest_uid = int(data.get("quest_uid", 0))
	road_seed = int(data.get("road_seed", 0))
	day = int(data.get("day", 1))
	world_mods = data.get("world_mods", [])
	for mod in world_mods:
		mod["days_left"] = int(mod.get("days_left", 1))
		if mod.has("monster"):
			mod["monster"] = int(mod["monster"])
	quest_clock = data.get("quest_clock", {"quest": 120.0, "matter": 90.0})
	quest_history = data.get("quest_history", [])
	monsters = []
	for mon in data.get("monsters", []):   # JSON has no integers
		mon["uid"] = int(mon["uid"])
		mon["kills"] = int(mon.get("kills", 0))
		mon["age"] = int(mon.get("age", 0))
		mon["spotted_day"] = int(mon.get("spotted_day", -1))
		mon["spawned"] = false   # the monsters of a road that has just loaded are put out afresh
		var plot: Dictionary = mon.get("plot", {})
		if not plot.is_empty():
			plot["days_left"] = int(plot["days_left"])
			plot["total"] = int(plot["total"])
		mon["plot"] = plot
		monsters.append(mon)
	monster_uid = int(data.get("monster_uid", 0))
	chronicle = []
	for entry in data.get("chronicle", []):
		entry["day"] = int(entry.get("day", 1))
		chronicle.append(entry)
	hero_xp = HeroProgression.sanitize_xp(data.get("hero_xp", 0))   # the XP decides; a saved level that disagrees with it is repaired
	hero_level = HeroProgression.level_for_xp(hero_xp)
	var clean: Dictionary = BuildDefs.sanitize(data.get("purchased_passives", []), data.get("skill_evolutions", {}),
		HeroProgression.passive_points_for_level(hero_level), HeroProgression.evolution_points_for_level(hero_level))
	purchased_passives.assign(clean["passives"])
	skill_evolutions = clean["evolutions"]
	events.hero_build_changed.emit()
	run_in_progress = false   # the world is not a run: nothing is "in progress" when the game is closed
	job =(board[0] as Dictionary).duplicate(true)   # the posted quest is the one measured; nothing has to be taken

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
	_xp_unsaved_ms = 0   # the whole town goes out, the hero's XP with it
	if not persist:
		return
	var path: String = save_path()
	if not SavePolicy.may_modify(path, OS.get_cmdline_user_args()):
		return
	SavePolicy.ensure_folder(path)
	var temp: String = path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	DirAccess.rename_absolute(temp, path)

## Loads the saved town, or starts a new one when there is none. A save that cannot be read, or that is from a newer build, is
## copied to user://town.json.<reason>.bak first so starting fresh never destroys it.
static func load_or_start() -> void:
	if persist and FileAccess.file_exists(save_path()):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
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
	var path: String = save_path()
	if SavePolicy.may_modify(path, OS.get_cmdline_user_args()):
		DirAccess.copy_absolute(path, "%s.%s.bak" % [path, reason])
