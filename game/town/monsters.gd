class_name Monsters
extends RefCounted
## What the monsters do on their own (docs/zombasite-world-and-npcs.md: named monsters, nemeses, plots). A few monsters on the road are
## named and keep growing: each day that passes they gain strength; one that kills the hero becomes a nemesis (stronger still, with a
## title). A grown monster starts plots: it gathers a raid, raises an altar, raises a horde or sends a scout, and the days tick down to the
## plot's end unless the hero kills it first. Each is a dictionary in `TownState.monsters`:
##   {uid, kind, name, level, kills, age, nemesis, spawned, dist (metres from the gate), lane, spotted_day, plot: {} | {type, days_left, total}}
## Everything that happens is told to the Chronicle, to the banner (through Quests.news) and as gossip a townsperson says. Pure rules, no
## scene: the town puts the monsters, their marks and the plot signs out on the road (TownScene.populate_monsters) and the self-test drives it.

const MAX_ALIVE := 2
const RISE_CHANCE := 0.55         # per day, while fewer than MAX_ALIVE live on the road
const EVOLVE_PER_DAY := 0.3       # levels a named monster gains for every day that passes
const PLOT_CHANCE := 0.45         # per day, once it has grown enough and has no plot going
const START_LEVEL := 2.0
const PLOT_MIN_LEVEL := 2.3

const FIRST := ["Gorran", "Mawl", "Skarn", "Vethik", "Oddrun", "Hesk", "Brannoch", "Ulmar", "Tessk", "Drog"]
const EPITHETS := {
	"ghoul": ["Gnawing", "Hollow", "Lean"], "brute": ["Breaker", "Heavy", "Unbowed"], "spitter": ["Weeping", "Vile", "Sour"],
	"priest": ["Pale", "Hymnless", "Gaunt"], "bloater": ["Swollen", "Slow", "Brimming"], "zombie": ["Patient", "Mudded", "Unburied"],
}
const KIND_POOL := ["ghoul", "ghoul", "brute", "spitter", "priest", "bloater"]

## How each plot runs: how many days it takes, how likely it is to be picked and what is told when it starts.
const PLOTS := {
	"raid": {"days": 3, "weight": 3.0, "start": "%s is gathering a raiding party. Kill it before they reach the gate."},
	"altar": {"days": 4, "weight": 2.0, "start": "%s is raising a dread altar out on the road. Kill it before the altar is done."},
	"uprising": {"days": 4, "weight": 2.0, "start": "%s is calling the dead out of the ground. Kill it before they rise."},
	"scout": {"days": 2, "weight": 2.0, "start": "%s has sent a scout toward the walls. It will be here soon."},
}

const TAUNTS := {
	"kill": ["Another one for the pile.", "You are slow. I am patient.", "Stay down, hearth-keeper.", "Tell your people I am coming."],
	"spot": ["You again.", "I remember the taste of you.", "Come closer. I am hungry.", "The road is mine now."],
	"grow": ["I am more than I was.", "Every night I am stronger.", "You cannot hold the road."],
}

const GOSSIP := {
	"rise": ["Something new is out on the road. A big one.", "The carters say a named thing is walking the road now."],
	"grow": ["It's grown again. You can hear it from the wall.", "They say it's twice the size it was."],
	"raid": ["It's gathering a war party. We will not hold the gate alone.", "Raiders. The wall will not stop that many."],
	"raid_hit": ["They hit the gate in the night. We lost food and nerve.", "I never want to see that again."],
	"altar": ["There is an altar going up out there. The dead are bolder for it.", "Smoke over the road. That altar is rising."],
	"uprising": ["The ground is moving out there. They are coming up.", "A whole hillside of them, they say."],
	"scout": ["Something is watching the walls.", "I saw eyes in the trees. Do not go out alone."],
	"slain": ["It's dead. I never thought I would say it.", "That one will not trouble the road again."],
	"nemesis": ["It killed you and it is not hiding it. It has a name now.", "It has your scent. It will want another go."],
}

static var rng := RandomNumberGenerator.new()
static var gossip: Array[Dictionary] = []   # {who: [npc ids], text}, said once by someone in town
## The self-test keeps the monsters out of the old checks (they would rise and plot in the middle of unrelated days); the checks for them turn this on.
static var in_tests: bool = false

static func _off() -> bool:
	return OS.get_cmdline_user_args().has("--selftest") and not in_tests

# --- Lookup ---------------------------------------------------------------------------------------------------------------------

static func alive() -> Array:
	return TownState.monsters.duplicate()

static func find(uid: int) -> Dictionary:
	for mon in TownState.monsters:
		if int(mon["uid"]) == uid:
			return mon
	return {}

## "Gorran the Hollow", or once it has killed the hero "Gorran the Hollow, Slayer of 2".
static func title_of(mon: Dictionary) -> String:
	var kills: int = int(mon.get("kills", 0))
	return "%s%s" % [mon["name"], ", Slayer of %d" % kills if kills > 0 else ""]

static func tag_of(mon: Dictionary) -> String:
	return "%s  (level %d)" % [title_of(mon), int(floor(float(mon["level"])))]

# --- Telling --------------------------------------------------------------------------------------------------------------------

static func _tell(text: String, topic: String = "", who: Array = []) -> void:
	Quests.tell(text, "monster")
	if topic != "":
		gossip.append({"who": who if not who.is_empty() else ["hale", "marlow", "maren", "dorn"], "text": String(GOSSIP[topic][rng.randi() % (GOSSIP[topic] as Array).size()])})

static func taunt(kind: String) -> String:
	var lines: Array = TAUNTS[kind]
	return String(lines[rng.randi() % lines.size()])

# --- Rising ---------------------------------------------------------------------------------------------------------------------

static func _make(kind: String, level: float, dist: float) -> Dictionary:
	TownState.monster_uid += 1
	var epithets: Array = EPITHETS.get(kind, EPITHETS["zombie"])
	var name: String = "%s the %s" % [FIRST[rng.randi() % FIRST.size()], epithets[rng.randi() % epithets.size()]]
	for other in TownState.monsters:   # no two share a name
		if String(other["name"]) == name:
			name += " the Younger"
	var mon: Dictionary = {"uid": TownState.monster_uid, "kind": kind, "name": name, "level": level, "kills": 0, "age": 0, "nemesis": false,
		"spawned": false, "dist": dist, "lane": rng.randf_range(-4.0, 4.0), "spotted_day": -1, "plot": {}, "fired": ""}
	TownState.monsters.append(mon)
	return mon

## A new named monster turns up on the road.
static func rise() -> Dictionary:
	var kind: String = String(KIND_POOL[rng.randi() % KIND_POOL.size()])
	var dist: float = rng.randf_range(50.0, 250.0)
	var mon: Dictionary = _make(kind, START_LEVEL, dist)
	var zone: ZoneDef = TownDb.zone_at(dist)
	_tell("%s has been seen in %s. A bounty is posted." % [mon["name"], zone.display_name if zone != null else "the wild"], "rise")
	return mon

## A monster that killed the hero without being named is named now (it keeps its body: `spawned` stays true, the town marks it).
static func promote(kind: String, dist: float) -> Dictionary:
	var mon: Dictionary = _make(kind, START_LEVEL + 0.5, dist)
	mon["spawned"] = true
	mon["kills"] = 1
	mon["nemesis"] = true
	_tell("A %s that killed you has taken a name: %s." % [kind, mon["name"]], "nemesis")
	return mon

# --- Days -----------------------------------------------------------------------------------------------------------------------

## A day passes (the hero is back from the road): the named ones grow, their plots move on and sometimes a new one rises.
static func on_day() -> void:
	if _off():
		return
	for mon in alive():
		mon["age"] = int(mon["age"]) + 1
		var before: int = int(floor(float(mon["level"])))
		mon["level"] = float(mon["level"]) + EVOLVE_PER_DAY
		if int(floor(float(mon["level"]))) > before:
			_tell("%s has grown stronger (level %d)." % [mon["name"], int(floor(float(mon["level"])))], "grow")
		if (mon["plot"] as Dictionary).is_empty():
			if float(mon["level"]) >= PLOT_MIN_LEVEL and rng.randf() < PLOT_CHANCE:
				_start_plot(mon)
		else:
			_tick_plot(mon)
	if TownState.monsters.size() < MAX_ALIVE and rng.randf() < RISE_CHANCE:
		rise()

static func _start_plot(mon: Dictionary) -> void:
	var total: float = 0.0
	for id in PLOTS:
		total += float(PLOTS[id]["weight"])
	var roll: float = rng.randf() * total
	var chosen: String = "raid"
	for id in PLOTS:
		roll -= float(PLOTS[id]["weight"])
		if roll <= 0.0:
			chosen = String(id)
			break
	var days: int = int(PLOTS[chosen]["days"])
	mon["plot"] = {"type": chosen, "days_left": days, "total": days}
	_tell(String(PLOTS[chosen]["start"]) % mon["name"], chosen if chosen != "raid" else "raid")

static func _tick_plot(mon: Dictionary) -> void:
	var plot: Dictionary = mon["plot"]
	plot["days_left"] = int(plot["days_left"]) - 1
	if int(plot["days_left"]) > 0:
		return
	_fire(mon, String(plot["type"]))
	mon["plot"] = {}

## A plot comes to its end: what it does to the town or the road.
static func _fire(mon: Dictionary, type: String) -> void:
	var level: float = float(mon["level"])
	match type:
		"raid":
			var food_lost: int = mini(TownState.food, 2 + int(level / 2.0))
			var gold_lost: int = mini(TownState.gold, int(TownState.gold * 0.2) + 5)
			TownState.food -= food_lost
			TownState.gold -= gold_lost
			for id in TownState.present_ids():
				TownState.add_happiness(id, -3.0)
			_tell("%s's raiders hit the gate in the night: -%d food, -%d gold, and the clan is shaken." % [mon["name"], food_lost, gold_lost], "raid_hit", ["hale", "marlow"])
		"altar":
			TownState.world_mods.append({"id": "altar", "label": "Dread Altar", "monster": int(mon["uid"]), "health_mult": 1.2, "speed_mult": 1.04,
				"days_left": 99, "applied": false})
			mon["fired"] = "altar"
			_tell("%s has finished the altar. The dead are harder until it is broken." % mon["name"], "altar")
		"uprising":
			TownState.world_mods.append({"id": "uprising", "label": "The Dead Rise", "monster": int(mon["uid"]), "count_mult": 1.3, "days_left": 3})
			mon["fired"] = "uprising"
			_tell("%s has raised a horde on the road." % mon["name"], "uprising")
		"scout":
			var ids: Array = TownState.present_ids()
			var gold_lost: int = mini(TownState.gold, int(TownState.gold * 0.1) + 3)
			TownState.gold -= gold_lost
			if not ids.is_empty():
				var who: String = String(ids[rng.randi() % ids.size()])
				TownState.add_happiness(who, -12.0)
				var def: NpcDef = TownDb.npc(who)
				_tell("%s's scout slipped in: %s was roughed up and %d gold went missing." % [mon["name"], def.display_name if def != null else "someone", gold_lost], "scout")

# --- Meeting the hero -----------------------------------------------------------------------------------------------------------

## A named monster killed the hero: it becomes a nemesis, stronger, with a title. Returns its line.
static func hero_fell(uid: int) -> String:
	var mon: Dictionary = find(uid)
	if mon.is_empty():
		return ""
	mon["kills"] = int(mon["kills"]) + 1
	mon["level"] = float(mon["level"]) + 0.5
	var first: bool = not bool(mon["nemesis"])
	mon["nemesis"] = true
	_tell("%s killed you%s." % [mon["name"], " and is now your nemesis" if first else " again"], "nemesis" if first else "")
	return "%s: \"%s\"" % [mon["name"], taunt("kill")]

## The hero meets a named monster for the first time today: it speaks once a day. Returns the line, or "".
static func spot(uid: int) -> String:
	var mon: Dictionary = find(uid)
	if mon.is_empty() or int(mon["spotted_day"]) == TownState.day:
		return ""
	mon["spotted_day"] = TownState.day
	return "%s: \"%s\"" % [mon["name"], taunt("spot")]

## The hero killed it: the bounty is paid, its plot dies with it, and anything it built comes down. Returns {name, gold, items}.
static func killed(uid: int) -> Dictionary:
	var mon: Dictionary = find(uid)
	if mon.is_empty():
		return {}
	var gold: int = 30 + int(20.0 * float(mon["level"])) + (40 if bool(mon["nemesis"]) else 0)
	var plot: Dictionary = mon["plot"]
	var xp: int = HeroProgression.named_xp(float(mon["level"]), int(mon.get("kills", 0)), not plot.is_empty())   # its own level and history, never the hero's
	var kept: Array = []
	var broke: bool = false
	for mod in TownState.world_mods:
		if int(mod.get("monster", -1)) == uid:
			broke = true
		else:
			kept.append(mod)
	TownState.world_mods = kept
	TownState.monsters.erase(mon)
	TownState.gold += gold
	var tail: String = ""
	if not plot.is_empty():
		tail = " Its %s dies with it." % String(plot["type"])
	elif broke:
		tail = " What it built comes down."
	_tell("%s is dead. The bounty is paid: %d gold.%s" % [title_of(mon), gold, tail], "slain")
	return {"name": mon["name"], "gold": gold, "items": 2 if bool(mon["nemesis"]) else 1, "xp": xp}

# --- Showing --------------------------------------------------------------------------------------------------------------------

## How far along a plot is, 0..1.
static func plot_progress(mon: Dictionary) -> float:
	var plot: Dictionary = mon["plot"]
	if plot.is_empty():
		return 0.0
	return 1.0 - float(plot["days_left"]) / float(plot["total"])

static func plot_name(type: String) -> String:
	return {"raid": "a raid", "altar": "a dread altar", "uprising": "an uprising", "scout": "a scout"}.get(type, type)

## One card per named monster and per standing world effect that came from one: {title, sub, frac, tint}, for the HUD and the Chronicle page.
static func cards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mon in TownState.monsters:
		var plot: Dictionary = mon["plot"]
		var sub: String = "level %d, wandering the road" % int(floor(float(mon["level"])))
		var frac: float = -1.0
		if not plot.is_empty():
			var days: int = int(plot["days_left"])
			sub = "plotting %s: %d day%s" % [plot_name(String(plot["type"])), days, "" if days == 1 else "s"]
			frac = plot_progress(mon)
		out.append({"title": title_of(mon), "sub": sub, "frac": frac, "tint": Color(0.9, 0.2, 0.15) if bool(mon["nemesis"]) else Color(1.0, 0.55, 0.2)})
	for mod in TownState.world_mods:
		if String(mod.get("label", "")) != "":
			var left: int = int(mod["days_left"])
			out.append({"title": String(mod["label"]), "sub": "until its maker dies" if left > 10 else "%d day%s left" % [left, "" if left == 1 else "s"],
				"frac": -1.0, "tint": Color(0.75, 0.4, 0.9)})
	return out
