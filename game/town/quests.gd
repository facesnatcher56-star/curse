class_name Quests
extends RefCounted
## The quests and events of the world (see QuestDef, and docs/zombasite-world-and-npcs.md section 5 for where the shape comes from).
## New ones turn up on their own as time passes and as days pass; each is an instance in `TownState.quests`:
##   {uid, id, state: "active" | "ready" | "done" | "failed", days_left (-1: none), progress, data}
## A quest is measured as it happens out on the road (`report_kill`, `report_unique_killed`, `report_fetch_found`), becomes "ready" and is
## handed in to its giver (`claim`). A matter is a decision in town (`resolve_choice`). A world event changes the road for a few days.
## Every ending (done or failed) can start more (the def's `links`), so one thing leads to another. Pure rules, no scene: the town and
## the road only call in and show the result, which is also what the self-test drives.

const MAX_POSTED := 4                       # quests (not matters) waiting at once
const MAX_MATTERS := 2
const QUEST_SECONDS := Vector2(180.0, 300.0)   # how long between new quests (Zombasite's own pacing)
const MATTER_SECONDS := Vector2(120.0, 195.0)  # ... and between matters
const FETCH_DROP_CHANCE := 0.12

static var rng := RandomNumberGenerator.new()
static var news: Array[String] = []         # one line each time something happens, for the town to show
## The self-test turns the clocks off so quests do not turn up in the middle of unrelated checks; the quest checks turn them back on.
static var clocks_in_tests: bool = false

# --- Lookup ------------------------------------------------------------------------------------------------------------------------

static func def_of(inst: Dictionary) -> QuestDef:
	return TownDb.quest(String(inst.get("id", "")))

static func live() -> Array:
	var out: Array = []
	for inst in TownState.quests:
		if String(inst["state"]) in ["active", "ready"]:
			out.append(inst)
	return out

static func find(uid: int) -> Dictionary:
	for inst in TownState.quests:
		if int(inst["uid"]) == uid:
			return inst
	return {}

static func has_live(id: String) -> bool:
	for inst in live():
		if String(inst["id"]) == id:
			return true
	return false

static func ready_for(giver: String) -> Array:
	var out: Array = []
	for inst in TownState.quests:
		if String(inst["state"]) == "ready" and def_of(inst).giver == giver:
			out.append(inst)
	return out

static func waiting_for(giver: String) -> Array:
	var out: Array = []
	for inst in live():
		var def: QuestDef = def_of(inst)
		if def.giver == giver and def.kind != "world":
			out.append(inst)
	return out

## Something happened: it is shown once (the banner) and kept in the Chronicle.
static func tell(line: String, kind: String = "quest") -> void:
	news.append(line)
	Chronicle.add(kind, line)

static func pop_news() -> Array[String]:
	var out: Array[String] = news.duplicate()
	news.clear()
	return out

static func _present(id: String) -> bool:
	return id == "" or (TownState.npcs.has(id) and not bool(TownState.npcs[id]["left"]))

# --- Posting -------------------------------------------------------------------------------------------------------------------------

## Whether a quest could turn up now: the giver is in town, it is not already up, and the hero has done enough.
static func eligible(def: QuestDef, from_chain: bool = false) -> bool:
	if has_live(def.id) or not _present(def.giver):
		return false
	if from_chain:
		return true
	return def.weight > 0.0 and TownState.jobs_done >= def.min_jobs

## Puts a quest up (it does not check eligibility). Returns the new instance.
static func post(id: String) -> Dictionary:
	var def: QuestDef = TownDb.quest(id)
	if def == null:
		return {}
	TownState.quest_uid += 1
	var inst: Dictionary = {"uid": TownState.quest_uid, "id": id, "state": "active", "progress": 0, "data": {},
		"days_left": def.days if def.days > 0 else -1, "posted_day": TownState.day}
	match def.kind:
		"slay_unique":
			inst["data"] = {"spawned": false, "name": def.unique_name}
		"fetch":
			inst["data"] = {"kills": 0, "dropped": false}
		"matter":
			var others: Array = []
			for npc in TownState.present_ids():
				if npc != def.giver:
					others.append(npc)
			inst["data"] = {"victim": _pick(TownState.present_ids()), "suspect": _pick(others)}
		"world":
			var mod: Dictionary = def.world_mod.duplicate()
			mod["id"] = def.id
			mod["days_left"] = int(mod.get("days", 3))
			TownState.world_mods.append(mod)
			inst["days_left"] = int(mod["days_left"])
			inst["data"] = {"applied": false}
	TownState.quests.append(inst)
	if def.kind == "world":
		tell("%s: %s" % [def.title, def.text] if def.text != "" else def.title, "event")
	else:
		tell("New: %s" % title_of(inst))
	_fire(def, "start")
	return inst

static func _pick(options: Array) -> String:
	return String(options[rng.randi() % options.size()]) if not options.is_empty() else ""

## The next one to turn up, picked by weight from those that could. `kinds` limits what may be picked ("quest" or "matter"/"world").
static func roll_new(kind_group: String) -> Dictionary:
	var candidates: Array = []
	var total: float = 0.0
	for id in TownDb.sorted_ids(TownDb.quests()):
		var def: QuestDef = TownDb.quest(id)
		var is_quest: bool = def.kind in ["kill_group", "slay_unique", "fetch"]
		if (kind_group == "quest") != is_quest or not eligible(def):
			continue
		candidates.append(def)
		total += def.weight
	if candidates.is_empty():
		return {}
	var roll: float = rng.randf() * total
	for def in candidates:
		roll -= (def as QuestDef).weight
		if roll <= 0.0:
			return post((def as QuestDef).id)
	return post((candidates[0] as QuestDef).id)

static func posted_count() -> int:
	var n: int = 0
	for inst in live():
		if def_of(inst).kind in ["kill_group", "slay_unique", "fetch"]:
			n += 1
	return n

static func matter_count() -> int:
	var n: int = 0
	for inst in live():
		if def_of(inst).kind == "matter":
			n += 1
	return n

## Time passes in town (real seconds): when a clock runs out, something new may turn up. Returns what was posted.
static func tick(delta: float) -> Array[Dictionary]:
	var posted: Array[Dictionary] = []
	if OS.get_cmdline_user_args().has("--selftest") and not clocks_in_tests:
		return posted
	var clock: Dictionary = TownState.quest_clock
	clock["quest"] = float(clock.get("quest", 120.0)) - delta
	clock["matter"] = float(clock.get("matter", 90.0)) - delta
	if float(clock["quest"]) <= 0.0:
		clock["quest"] = rng.randf_range(QUEST_SECONDS.x, QUEST_SECONDS.y)
		if posted_count() < MAX_POSTED:
			var made: Dictionary = roll_new("quest")
			if not made.is_empty():
				posted.append(made)
	if float(clock["matter"]) <= 0.0:
		clock["matter"] = rng.randf_range(MATTER_SECONDS.x, MATTER_SECONDS.y)
		if matter_count() < MAX_MATTERS:
			var made2: Dictionary = roll_new("matter")
			if not made2.is_empty():
				posted.append(made2)
	return posted

## A day passes (the hero has come back from the road): deadlines move closer, what ran out is failed (a world event just ends), and the
## board is never left empty.
static func on_day() -> void:
	TownState.day += 1
	for inst in live():
		var left: int = int(inst["days_left"])
		if left < 0:
			continue
		left -= 1
		inst["days_left"] = left
		if left > 0:
			continue
		var def: QuestDef = def_of(inst)
		if def.kind == "world":
			inst["state"] = "done"
			tell("Over: %s" % title_of(inst), "event")
		elif String(inst["state"]) == "active":
			fail(inst)
	var kept: Array = []
	for mod in TownState.world_mods:
		# What a world event does to the town each day it runs: moods and food.
		var mood: float = float(mod.get("happy_per_day", 0.0))
		if mood != 0.0:
			for id in TownState.present_ids():
				TownState.add_happiness(id, mood)
		var bread: int = int(mod.get("food_per_day", 0))
		if bread != 0:
			TownState.food = maxi(TownState.food + bread, 0)
		mod["days_left"] = int(mod["days_left"]) - 1
		if int(mod["days_left"]) > 0:
			kept.append(mod)
	TownState.world_mods = kept
	Monsters.on_day()
	if posted_count() < 2:
		roll_new("quest")

# --- Measuring (called as things happen on the road) -------------------------------------------------------------------------------

## A monster of this kind died (not a named one). Returns {"changed": [instances that moved], "drops": [fetch instances whose item drops now]}.
static func report_kill(enemy_id: String) -> Dictionary:
	var changed: Array = []
	var drops: Array = []
	for inst in live():
		var def: QuestDef = def_of(inst)
		if String(inst["state"]) != "active":
			continue
		if def.kind == "kill_group" and (def.target == "" or def.target == enemy_id):
			inst["progress"] = int(inst["progress"]) + 1
			if int(inst["progress"]) >= def.count:
				inst["state"] = "ready"
				tell("Ready to hand in: %s" % title_of(inst))
			changed.append(inst)
		elif def.kind == "fetch" and def.target == enemy_id and not bool(inst["data"]["dropped"]):
			var data: Dictionary = inst["data"]
			data["kills"] = int(data["kills"]) + 1
			if int(data["kills"]) >= def.count or rng.randf() < FETCH_DROP_CHANCE:
				data["dropped"] = true
				drops.append(inst)
			changed.append(inst)
	return {"changed": changed, "drops": drops}

## The item is lying on the road again (it was dropped but the hero was dragged home, or it was left behind).
static func report_fetch_lost(uid: int) -> void:
	var inst: Dictionary = find(uid)
	if not inst.is_empty() and String(inst["state"]) == "active":
		inst["data"]["dropped"] = false

static func report_fetch_found(uid: int) -> bool:
	var inst: Dictionary = find(uid)
	if inst.is_empty() or String(inst["state"]) != "active":
		return false
	inst["state"] = "ready"
	tell("Found: %s" % def_of(inst).item_name)
	return true

static func report_unique_killed(uid: int) -> bool:
	var inst: Dictionary = find(uid)
	if inst.is_empty() or String(inst["state"]) != "active":
		return false
	inst["state"] = "ready"
	tell("Ready to hand in: %s" % title_of(inst))
	return true

# --- Endings -----------------------------------------------------------------------------------------------------------------------

## Handing a ready quest in: its reward is paid, it is done, and it may lead to something else. Returns {"ok", "text", "lines"}.
static func claim(uid: int) -> Dictionary:
	var inst: Dictionary = find(uid)
	if inst.is_empty() or String(inst["state"]) != "ready":
		return {"ok": false, "text": "", "lines": []}
	var def: QuestDef = def_of(inst)
	var lines: Array[String] = apply_bundle(def.reward, inst)
	_finish(inst, "done")
	_fire(def, "complete")
	return {"ok": true, "text": text_of(inst, "thanks"), "lines": lines}

static func fail(inst: Dictionary) -> Array[String]:
	var def: QuestDef = def_of(inst)
	var lines: Array[String] = apply_bundle(def.penalty, inst)
	_finish(inst, "failed")
	tell("Failed: %s" % title_of(inst))
	_fire(def, "fail")
	return lines

static func _finish(inst: Dictionary, state: String) -> void:
	inst["state"] = state
	TownState.quest_history.append({"id": inst["id"], "state": state, "day": TownState.day})
	while TownState.quest_history.size() > 30:
		TownState.quest_history.pop_front()
	TownState.quests.erase(inst)

## Picking one of a matter's choices. Returns {"ok": false, "text": why} when it cannot be afforded; otherwise {"ok", "success", "text", "lines"}.
static func resolve_choice(uid: int, index: int) -> Dictionary:
	var inst: Dictionary = find(uid)
	if inst.is_empty():
		return {"ok": false, "text": ""}
	var def: QuestDef = def_of(inst)
	if def.kind != "matter" or index < 0 or index >= def.choices.size():
		return {"ok": false, "text": ""}
	var choice: Dictionary = def.choices[index]
	var cost: Dictionary = choice.get("cost", {})
	if TownState.gold < int(cost.get("gold", 0)) or TownState.food < int(cost.get("food", 0)) or TownState.potions < int(cost.get("potions", 0)):
		return {"ok": false, "text": "You cannot afford that."}
	TownState.gold -= int(cost.get("gold", 0))
	TownState.food -= int(cost.get("food", 0))
	TownState.potions -= int(cost.get("potions", 0))
	var outcome: String = String(choice.get("outcome", "solve"))
	var success: bool = outcome == "solve" or (outcome == "gamble" and rng.randf() < float(choice.get("chance", 0.5)))
	var lines: Array[String]
	if success:
		lines = apply_bundle(choice.get("reward", def.reward), inst)
		_finish(inst, "done")
		_fire(def, "complete")
	else:
		lines = apply_bundle(choice.get("penalty", def.penalty), inst)
		_finish(inst, "failed")
		_fire(def, "fail")
	return {"ok": true, "success": success, "text": String(choice.get("result", "")) + "  " + text_of(inst, "thanks" if success else "fail_text"), "lines": lines}

## Starts what a quest's ending leads to: each link has its own chance.
static func _fire(def: QuestDef, when: String) -> void:
	for link in def.links.get(when, []):
		if rng.randf() < float(link.get("chance", 1.0)):
			var next: QuestDef = TownDb.quest(String(link["quest"]))
			if next != null and eligible(next, true):
				post(next.id)

# --- Pay and penalty ------------------------------------------------------------------------------------------------------------------

## Applies {gold, food, potions, item, happy, relation} (negative numbers cost). Returns a line for each thing that happened.
static func apply_bundle(bundle: Dictionary, inst: Dictionary = {}) -> Array[String]:
	var lines: Array[String] = []
	var gold: int = int(bundle.get("gold", 0))
	if gold != 0:
		var paid: int = gold if gold > 0 else -mini(-gold, TownState.gold)
		TownState.gold += paid
		lines.append("%+d gold" % paid)
	var food: int = int(bundle.get("food", 0))
	if food != 0:
		var moved: int = food if food > 0 else -mini(-food, TownState.food)
		TownState.food += moved
		lines.append("%+d food" % moved)
	var xp: int = int(bundle.get("xp", 0))   # the quest's own XP, named by whoever wrote it (never worked out from the gold)
	if xp > 0:
		TownState.add_hero_xp(xp)
		lines.append("%d XP" % xp)
	var potions: int = int(bundle.get("potions", 0))
	if potions != 0:
		var delta: int = potions if potions > 0 else -mini(-potions, TownState.potions)
		TownState.potions += delta
		lines.append("%+d potion%s" % [delta, "" if absi(delta) == 1 else "s"])
	if bundle.has("item"):
		var none: Array[String] = []
		var item: Dictionary = Items.roll_drop(Items.tier_for_source(float(bundle.get("threat", WorldThreat.QUEST_REWARD_THREAT))), 1.0 if int(bundle["item"]) >= 1 else 0.0, none)   # a reward names its own source threat
		TownState.stash_item(item)
		lines.append("an item in the stash (%s)" % String(item.get("name", "?")))
	var happy: Dictionary = bundle.get("happy", {})
	for who in happy:
		var amount: float = float(happy[who])
		for npc in _targets(String(who), inst):
			TownState.add_happiness(npc, amount)
	if not happy.is_empty():
		lines.append("moods shift")
	for rel in bundle.get("relation", []):
		TownState.add_relation(String(rel[0]), String(rel[1]), float(rel[2]))
	return lines

static func _targets(who: String, inst: Dictionary) -> Array:
	if who == "all":
		return TownState.present_ids()
	if who.begins_with("{"):
		who = String(inst.get("data", {}).get(who.trim_prefix("{").trim_suffix("}"), ""))
	return [who] if who != "" and TownState.npcs.has(who) else []

# --- Words -----------------------------------------------------------------------------------------------------------------------------

static func title_of(inst: Dictionary) -> String:
	return def_of(inst).title

## A text field of the quest ("text", "thanks", "fail_text") with {victim} and {suspect} filled in with townspeople's names.
static func text_of(inst: Dictionary, field: String = "text") -> String:
	var def: QuestDef = def_of(inst)
	var out: String = String(def.get(field))
	for token in ["victim", "suspect"]:
		out = out.replace("{%s}" % token, _name(String(inst.get("data", {}).get(token, ""))))
	return out

static func choice_label(inst: Dictionary, index: int) -> String:
	var label: String = String(def_of(inst).choices[index]["label"])
	return label.replace("{suspect}", _name(String(inst.get("data", {}).get("suspect", ""))))

static func _name(npc_id: String) -> String:
	var def: NpcDef = TownDb.npc(npc_id)
	return def.display_name if def != null else "someone"

## "3 / 8" style progress, and what is left, for lists and the tracker.
static func progress_text(inst: Dictionary) -> String:
	var def: QuestDef = def_of(inst)
	if String(inst["state"]) == "ready":
		return "done: hand it in"
	match def.kind:
		"kill_group":
			return "%d / %d %s" % [int(inst["progress"]), def.count, _plural(def.target)]
		"slay_unique":
			return "find and kill %s" % def.unique_name
		"fetch":
			return "find the %s (%s)" % [def.item_name, "it dropped: pick it up" if bool(inst["data"].get("dropped", false)) else "somewhere on the road"]
		"matter":
			return "needs a decision"
		"world":
			return "%d day%s left" % [int(inst["days_left"]), "" if int(inst["days_left"]) == 1 else "s"]
	return ""

static func _plural(enemy_id: String) -> String:
	var def: EnemyDef = EnemyDb.all().get(enemy_id)
	var name: String = def.display_name.to_lower() if def != null else (enemy_id if enemy_id != "" else "monster")
	return name if name.ends_with("s") else name + "s"

## One line each for the tracker: "Thin the Ghouls: 3 / 8 ghouls (4 days)".
static func tracker_lines() -> Array[String]:
	var out: Array[String] = []
	for inst in live():
		var def: QuestDef = def_of(inst)
		if def.kind == "matter":
			continue
		var days: String = "" if int(inst["days_left"]) < 0 else " (%d day%s)" % [int(inst["days_left"]), "" if int(inst["days_left"]) == 1 else "s"]
		out.append("%s: %s%s" % [def.title, progress_text(inst), days if def.kind != "world" else ""])
	return out

# --- World effects ------------------------------------------------------------------------------------------------------------------------

## The product of one multiplier ("gold_mult", "drop_mult", "health_mult") over every world event that is running.
static func world_mult(field: String) -> float:
	var product: float = 1.0
	for mod in TownState.world_mods:
		product *= float(mod.get(field, 1.0))
	return product
