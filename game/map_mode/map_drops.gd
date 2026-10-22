class_name MapDrops
extends RefCounted
## The drop model (issue #82; the normal game too since #112): every fight pays out, most groups guard a chest, enemy drops are a small bonus.
## With `ds2_tables` set (tests only) every entry point here hands back exactly DS2's own tables (MonsterLoot, Champion and Items are untouched;
## the selftest `mmdrops` compares them under a fixed seed).
##
## ALL NUMBERS ARE IN `T` BELOW. The functions are rules only. They use the global random stream (randf / randi), like Items does, so a test that
## calls seed() first rolls the same run again; only the guard of a group is a pure function of (run seed, node), because it is decided when the
## group spawns and shown on the node map before it is fought.

## Tests only: true hands back DS2's own tables (MonsterLoot.roll, Champion.loot, Items' windows) to compare against.
static var ds2_tables: bool = false
## The run's seed: the guard of every group follows from it. 0 until new_run() is called.
static var run_seed: int = 0

const T := {
	# --- enemies (per kill; alternatives, the rest is nothing) ---
	"enemy": {"gold": 0.35, "item": 0.05, "health": 0.07, "mana": 0.03},
	# what an enemy's own item is (a rare is DS2's lucky drop)
	"enemy_item": {"normal": 0.70, "magic1": 0.22, "magic2": 0.06, "rare": 0.02},
	# what a champion always drops on top: magic or better
	"champion_item": {"magic1": 0.48, "magic2": 0.45, "rare": 0.07},
	# --- guards ---
	# A group that is neither a champion's, a boss's nor a swarm's guards a chest with this chance; with the champions (always Gilded), the boss
	# (always a Hoard) and the side-branch chests (below) that is about 70% of the groups of the Sunken Way.
	"plain_chest_chance": 0.5,
	"iron_min_bodies": 8,          # a pack this big guards an Iron chest, a smaller one a Wooden chest
	"other_guards": {"shrine": 0.4, "gold": 0.35, "potions": 0.25},
	# The chest rooms of the dungeon (node ids); an unknown chest node is Iron. Cursed is the optional side branch with a real price.
	"chest_nodes": {5: "wooden", 12: "cursed"},
	"chest_node_default": "iron",
	"guards": {
		"wooden": {"title": "Wooden chest", "chest": true, "color": Color(0.66, 0.46, 0.26), "scale": 1.2},
		"iron": {"title": "Iron chest", "chest": true, "color": Color(0.58, 0.64, 0.74), "scale": 1.25},
		"gilded": {"title": "Gilded chest", "chest": true, "color": Color(1.0, 0.82, 0.3), "scale": 1.3},
		"cursed": {"title": "Cursed chest", "chest": true, "color": Color(0.66, 0.3, 0.88), "scale": 1.3},
		"hoard": {"title": "Boss hoard", "chest": true, "color": Color(1.0, 0.55, 0.2), "scale": 1.7},
		"shrine": {"title": "A shrine (a short blessing)", "chest": false, "color": Color(0.45, 0.78, 0.95)},
		"gold": {"title": "A pile of gold", "chest": false, "color": Color(0.95, 0.8, 0.3)},
		"potions": {"title": "A potion cache", "chest": false, "color": Color(0.9, 0.35, 0.35)},
	},
	# --- chest contents ---
	# count: [[items, weight]]. kinds: weights of the filler items (Items.item_of_kind kinds). min_magic: at least this many magic-or-better.
	# rares / legendaries: guaranteed number; rare_chance / legendary_chance: one more with that chance.
	"chests": {
		"wooden": {"count": [[1, 0.7], [2, 0.3]], "kinds": {"normal": 0.62, "magic1": 0.30, "magic2": 0.08}, "min_magic": 0,
			"rares": 0, "rare_chance": 0.0, "legendaries": 0, "legendary_chance": 0.0, "gold": [2.0, 4.0]},
		"iron": {"count": [[2, 0.7], [3, 0.3]], "kinds": {"normal": 0.35, "magic1": 0.45, "magic2": 0.20}, "min_magic": 1,
			"rares": 0, "rare_chance": 0.35, "legendaries": 0, "legendary_chance": 0.0, "gold": [4.0, 7.0]},
		"gilded": {"count": [[1, 0.8], [2, 0.2]], "kinds": {"magic1": 0.45, "magic2": 0.55}, "min_magic": 1,
			"rares": 1, "rare_chance": 0.0, "legendaries": 0, "legendary_chance": 0.05, "gold": [6.0, 10.0]},
		"cursed": {"count": [[2, 1.0]], "kinds": {"magic2": 1.0}, "min_magic": 1,
			"rares": 1, "rare_chance": 0.0, "legendaries": 1, "legendary_chance": 0.0, "gold": [6.0, 10.0]},
		"hoard": {"count": [[4, 0.6], [5, 0.4]], "kinds": {"normal": 0.40, "magic1": 0.32, "magic2": 0.28}, "min_magic": 2,
			"rares": 1, "rare_chance": 0.0, "legendaries": 1, "legendary_chance": 0.0, "gold": [12.0, 20.0]},
	},
	# --- the other guards ---
	"gold_pile": [10.0, 16.0],       # x the DS2 gold curve of the node's level
	"potion_cache": 3,               # health potions
	"shrine_buff": {"stat": "power_damage", "value": 30.0, "seconds": 90.0, "title": "Shrine's blessing"},
	# --- never empty-handed: a cleared node always leaves at least this ---
	"clear_gold": [3.0, 5.0],        # x the DS2 gold curve of the node's level, when nothing else dropped gold
	"clear_potion": 1,               # a health potion, when no item and no potion dropped
	# --- the summary card after a clear ---
	"summary_seconds": 180.0,   # the reward panel stays over the reopened map until Continue or the next node is picked (the map is usable at once); this is only its safety limit
	# --- party fit: this share of item rolls is forced onto a base the warrior or the Cutter can use ---
	"party_members": ["hero", "cutter"],
	"party_fit": 0.6,
	"party_fit_tries": 24,
	# --- upgrades feel like upgrades: a magic or rare item's modifiers come from the top of the modifier-level window around the item level
	# (DS2: magic -20..0, rare -25..+5; the modifier tiers are fixed values, so the higher the level, the bigger the number), and a modifier
	# that has a value range (magic find) rolls in its top part (the fraction of the range it may not go below) ---
	"mod_window": {1: Vector2i(-5, 0), 2: Vector2i(-6, 5)},   # Items.Rarity.MAGIC, RARE
	"value_floor": {1: 0.6, 2: 0.5},
}


static func enabled() -> bool:
	return not ds2_tables


## Starts a run: the guards of every group follow from `seed_value` (a random one when it is 0). `--mapseed=N` pins it for a developer.
static func new_run(seed_value: int = 0) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mapseed=") and seed_value == 0:
			seed_value = int(arg.substr(10))
	run_seed = seed_value if seed_value != 0 else maxi(randi(), 1)
	return run_seed


# --- Guards ---------------------------------------------------------------------------------------------------------------------------------

static func bodies_of(row: Dictionary) -> int:
	var total: int = 0
	for g in row.get("groups", []):
		total += int(g[1])
	return total


## What a node guards: {"guard": key of T.guards or "", "title", "chest": bool}. A pure function of the node and the run seed.
static func plan_for(row: Dictionary, seed_value: int = -1) -> Dictionary:
	var s: int = run_seed if seed_value < 0 else seed_value
	var id: int = int(row.get("id", 0))
	var kind: String = String(row.get("kind", "pack"))
	var guard: String = ""
	match kind:
		"start", "shrine":
			guard = ""
		"boss":
			guard = "hoard"
		"chest":
			guard = String((T.chest_nodes as Dictionary).get(id, T.chest_node_default))
		_:
			if kind == "champion" or String(row.get("champion", "")) != "":
				guard = "gilded"
			elif kind == "swarm":
				guard = "iron"   # a swarm is the biggest pack: it always pays
			else:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([s, id])
				if rng.randf() < float(T.plain_chest_chance):
					guard = "iron" if bodies_of(row) >= int(T.iron_min_bodies) else "wooden"
				else:
					guard = _pick(T.other_guards, rng.randf())
	var def: Dictionary = (T.guards as Dictionary).get(guard, {})
	return {"guard": guard, "title": String(def.get("title", "")), "chest": bool(def.get("chest", false))}


static func guard_color(guard: String) -> Color:
	return ((T.guards as Dictionary).get(guard, {}) as Dictionary).get("color", Color(0.8, 0.8, 0.8))


## "Wooden chest" -> the tooltip's line; the kinds that are not chests read "a shrine", "a pile of gold" ...
static func label_line(plan: Dictionary) -> String:
	return String(plan.get("title", ""))


# --- Enemies --------------------------------------------------------------------------------------------------------------------------------

## What a dead enemy leaves: the shape of MonsterLoot.roll ({gold, health, mana, item}). With map mode off this IS MonsterLoot.roll.
static func enemy_loot(level: int, tier: String, magic_find: float = 0.0, chance_mult: float = 1.0, gold_find: float = 0.0) -> Dictionary:
	if not enabled():
		return MonsterLoot.roll(level, tier, magic_find, chance_mult, gold_find)
	var out := {"gold": 0, "health": 0, "mana": 0, "item": {}}
	var key: String = "weak" if tier == "trivial" else (tier if tier in ["weak", "normal", "strong"] else "strong")
	var e: Dictionary = T.enemy
	var gold_p: float = float(e.gold)
	var health_p: float = float(e.health)
	var mana_p: float = float(e.mana)
	var item_p: float = float(e.item) * chance_mult
	var pick: float = randf()
	if pick < gold_p:
		out.gold = MonsterLoot.gold_amount(MonsterLoot.gold_curve(level, key) * randf_range(0.093, 0.156), gold_find)
	elif pick < gold_p + health_p:
		out.health = 1
	elif pick < gold_p + health_p + mana_p:
		out.mana = 1
	elif pick < gold_p + health_p + mana_p + item_p and tier != "miniboss":
		out.item = make_item(_pick(T.enemy_item, randf()), level, (Items.DROPS.get(key, Items.DROPS.normal) as Dictionary).window, magic_find)
	return out


## A champion's guaranteed item (map mode: magic or better). With map mode off this IS Champion.loot.
static func champion_loot(level: int, tier: String, magic_find: float = 0.0) -> Dictionary:
	if not enabled():
		return Champion.loot(level, tier, magic_find)
	var key: String = "weak" if tier == "trivial" else (tier if tier in ["weak", "normal", "strong"] else "normal")
	return make_item(_pick(T.champion_item, randf()), level, (Items.DROPS.get(key, Items.DROPS.normal) as Dictionary).window, magic_find)


# --- Items ----------------------------------------------------------------------------------------------------------------------------------

## True when the warrior or the Cutter can wear this item now (Items.hero_can_wear: class skill and item level against each member).
static func fits_party(item: Dictionary) -> bool:
	for member_id in T.party_members:
		if Items.hero_can_wear(item, String(member_id)):
			return true
	return false


## One item of `kind` (Items.item_of_kind's kinds, plus "legendary"). T.party_fit of the rolls are re-rolled until the base fits the party.
static func make_item(kind: String, level: int, window: Vector2i = Vector2i(-5, 1), magic_find: float = 0.0) -> Dictionary:
	var want_fit: bool = randf() < float(T.party_fit)
	var tries: int = int(T.party_fit_tries) if want_fit else 1
	var item: Dictionary = {}
	for i in tries:
		item = legendary_item(level) if kind == "legendary" else Items.item_of_kind(kind, level, window, Vector2i.ZERO, magic_find)
		if not want_fit or fits_party(item):
			break
	return item


## A legendary: the power legendaries of MapModeLegendaries when that table exists (called defensively: the file may not be merged yet), else the
## best unique that exists for the level, else a rare.
static func legendary_item(level: int) -> Dictionary:
	var path := "res://game/items/map_mode_legendaries.gd"
	if ResourceLoader.exists(path):
		var table: Object = load(path)
		if table != null:
			if table.has_method("random_item"):   # MapModeLegendaries: one of the five power legendaries
				var got: Variant = table.call("random_item")
				if got is Dictionary and not (got as Dictionary).is_empty():
					return got
	var item: Dictionary = Items.item_of_kind("unique", level, Vector2i(-5, 1), Vector2i(-60, 60))
	if int(item.get("rarity", 0)) < Items.Rarity.UNIQUE:
		item = Items.item_of_kind("set", level, Vector2i(-5, 1), Vector2i(-60, 60))
	return item


## The contents of a chest of this guard kind at `level`: an Array of items (see T.chests). Always the guaranteed pieces, then fillers, then the
## magic floor.
static func chest_items(guard: String, level: int, magic_find: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def: Dictionary = (T.chests as Dictionary).get(guard, {})
	if def.is_empty():
		return out
	var window: Vector2i = (Items.DROPS.normal as Dictionary).window
	var count: int = _pick_count(def.count, randf())
	var legendaries: int = int(def.legendaries) + (1 if randf() < float(def.legendary_chance) else 0)
	var rares: int = int(def.rares) + (1 if randf() < float(def.rare_chance) else 0)
	for i in legendaries:
		out.append(make_item("legendary", level, window, magic_find))
	for i in rares:
		out.append(make_item("rare", level, window, magic_find))
	while out.size() < count:
		out.append(make_item(_pick(def.kinds, randf()), level, window, magic_find))
	var magic: int = 0
	for item in out:
		magic += 1 if int(item["rarity"]) >= Items.Rarity.MAGIC else 0
	for i in out.size():
		if magic >= int(def.min_magic):
			break
		if int(out[i]["rarity"]) == Items.Rarity.NORMAL:
			out[i] = make_item("magic1", level, window, magic_find)
			magic += 1
	return out


## Gold a chest or a cleared node pays: `range` is a [low, high] multiple of the DS2 gold curve at `level`.
static func gold_for(level: int, range_x: Array, gold_find: float = 0.0) -> int:
	return MonsterLoot.gold_amount(MonsterLoot.gold_curve(level, "normal") * randf_range(float(range_x[0]), float(range_x[1])), gold_find)


# --- Shrine blessing --------------------------------------------------------------------------------------------------------------------------

## The shrine guard's temporary buff (T.shrine_buff) on every living party member, taken off again when its time is up.
static func bless(bodies: Array) -> void:
	var b: Dictionary = T.shrine_buff
	for body in bodies:
		var p := body as Player
		if p == null or not is_instance_valid(p) or p.dead:
			continue
		p.stats.temp_bonus = {String(b.stat): float(b.value)}
		p.stats.refresh()
		p.get_tree().create_timer(float(b.seconds)).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.stats.temp_bonus = {}
				p.stats.refresh())


# --- Modifier values ------------------------------------------------------------------------------------------------------------------------

## The modifier-level window a magic or rare item rolls its modifiers from (Items.roll_mods): `default` (DS2's) unless map mode narrows it to the top.
static func mod_window(rarity: int, default: Vector2i) -> Vector2i:
	if enabled() and (T.mod_window as Dictionary).has(rarity):
		return T.mod_window[rarity]
	return default


## A modifier's rolled value (Items.build). Map mode: a magic or rare item's value lies in the top part of its window. Otherwise exactly DS2's.
static func roll_value(affix: AffixDef, rarity: int) -> float:
	if enabled() and (T.value_floor as Dictionary).has(rarity):
		var low: float = lerpf(affix.value, affix.value_ceiling, float(T.value_floor[rarity]))
		return float(randi_range(int(ceilf(low)), int(affix.value_ceiling)))
	return float(randi_range(int(affix.value), int(affix.value_ceiling)))


# --- Counting -------------------------------------------------------------------------------------------------------------------------------

## "normal", "magic", "rare" or "legendary" (unique and set pieces).
static func tier_of(item: Dictionary) -> String:
	match int(item.get("rarity", 0)):
		Items.Rarity.MAGIC: return "magic"
		Items.Rarity.RARE: return "rare"
		Items.Rarity.UNIQUE, Items.Rarity.SET: return "legendary"
	return "normal"


static func count_tiers(items: Array) -> Dictionary:
	var out := {"normal": 0, "magic": 0, "rare": 0, "legendary": 0}
	for item in items:
		out[tier_of(item)] = int(out[tier_of(item)]) + 1
	return out


## "3 magic, 1 rare" for a fight-log line.
static func tiers_text(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in ["normal", "magic", "rare", "legendary"]:
		if int(counts.get(k, 0)) > 0:
			parts.append("%d %s" % [int(counts[k]), k])
	return ", ".join(parts) if not parts.is_empty() else "none"


# --- Helpers --------------------------------------------------------------------------------------------------------------------------------

static func _pick(weights: Dictionary, roll: float) -> String:
	var total: float = 0.0
	for k in weights:
		total += float(weights[k])
	var at: float = roll * total
	var last: String = ""
	for k in weights:
		last = String(k)
		at -= float(weights[k])
		if at < 0.0:
			return last
	return last


static func _pick_count(pairs: Array, roll: float) -> int:
	var total: float = 0.0
	for p in pairs:
		total += float(p[1])
	var at: float = roll * total
	for p in pairs:
		at -= float(p[1])
		if at < 0.0:
			return int(p[0])
	return int(pairs[pairs.size() - 1][0])
