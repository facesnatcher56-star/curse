class_name Items
extends RefCounted
## Item data and reward generation. Design rule: base items are plain and fixed; the only variation
## is a behaviour (affix) that changes how you play. No random stat lines.
## Items are plain Dictionaries: {slot, rarity, name, base, stats, affix, flavor}.

enum Slot { WEAPON, ARMOR, TRINKET }
enum Rarity { COMMON, RARE, UNIQUE }

const SLOT_NAMES: Array[String] = ["Weapon", "Armor", "Trinket"]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Unique"]
const RARITY_COLORS: Array[Color] = [Color(0.82, 0.82, 0.82), Color(0.45, 0.72, 1.0), Color(1.0, 0.62, 0.18)]

## id -> title (rare item prefix), slot, description. Every one is a behaviour, not a number.
const AFFIXES := {
	# Weapon
	"cleaving": {"title": "Cleaving", "slot": Slot.WEAPON, "desc": "Your combo finisher also strikes everything in an arc in front of you."},
	"momentum": {"title": "Relentless", "slot": Slot.WEAPON, "desc": "Each kill makes you attack 30% faster for 3 seconds."},
	"chain": {"title": "Stormcalled", "slot": Slot.WEAPON, "desc": "25% of hits arc lightning to another nearby enemy."},
	"searing": {"title": "Searing", "slot": Slot.WEAPON, "desc": "Critical hits set the enemy on fire."},
	"executioner": {"title": "Executioner's", "slot": Slot.WEAPON, "desc": "Deal 60% more damage to enemies below 25% health."},
	"frostbite": {"title": "Frostbitten", "slot": Slot.WEAPON, "desc": "Hits slow enemies by 40% for 2 seconds."},
	# Armor
	"riposte": {"title": "Duelist's", "slot": Slot.ARMOR, "desc": "After a dodge roll, your next attack within 1.5 seconds always crits."},
	"shock_roll": {"title": "Thunderstep", "slot": Slot.ARMOR, "desc": "Starting a dodge roll blasts nearby enemies away and hurts them."},
	"warding": {"title": "Warded", "slot": Slot.ARMOR, "desc": "The first hit you take every 8 seconds is blocked completely."},
	"last_stand": {"title": "Stalwart", "slot": Slot.ARMOR, "desc": "Below 35% health, you take 30% less damage."},
	# Trinket
	"twin_flame": {"title": "Twin-Flame", "slot": Slot.TRINKET, "desc": "Fireball launches a second fireball at an angle."},
	"whirlpool": {"title": "Whirling", "slot": Slot.TRINKET, "desc": "Cleave first drags nearby enemies in toward you."},
	"windfall": {"title": "Fortunate", "slot": Slot.TRINKET, "desc": "15% of kills drop a health orb."},
	"quickening": {"title": "Quickened", "slot": Slot.TRINKET, "desc": "12% of kills reset all your skill cooldowns."},
	# Unique-only
	"gravewarden": {"title": "", "slot": Slot.WEAPON, "desc": "Power Strike sends a shockwave surging forward through every enemy in a line."},
	"aegis": {"title": "", "slot": Slot.ARMOR, "desc": "Every 4th hit you take is blocked and answered with a shockwave."},
	"ember": {"title": "", "slot": Slot.TRINKET, "desc": "Every kill erupts in a fiery explosion."},
}

## Plain base items. Weapons trade speed against damage; armor trades protection against mobility.
const BASES := {
	Slot.WEAPON: [
		{"name": "Falchion", "damage": 0.9, "speed": 1.18},
		{"name": "Longsword", "damage": 1.0, "speed": 1.0},
		{"name": "Greatsword", "damage": 1.35, "speed": 0.82},
	],
	Slot.ARMOR: [
		{"name": "Leather Jerkin", "armor": 15.0, "roll_cost": 0.8, "roll_speed": 1.1},
		{"name": "Mail Hauberk", "armor": 35.0, "roll_cost": 1.0, "roll_speed": 1.0},
		{"name": "Plate Cuirass", "armor": 60.0, "roll_cost": 1.4, "roll_speed": 0.9},
	],
	Slot.TRINKET: [
		{"name": "Charm"}, {"name": "Signet"}, {"name": "Talisman"},
	],
}

const UNIQUES := [
	{"name": "Gravewarden", "slot": Slot.WEAPON, "base": "Greatsword", "affix": "gravewarden",
		"flavor": "Pulled from a grave that was not empty."},
	{"name": "Aegis of the Fallen", "slot": Slot.ARMOR, "base": "Plate Cuirass", "affix": "aegis",
		"flavor": "Dented by every blow that missed you."},
	{"name": "Ember Signet", "slot": Slot.TRINKET, "base": "Signet", "affix": "ember",
		"flavor": "Still warm."},
]

static func starting_gear() -> Array[Dictionary]:
	return [make(Slot.WEAPON, Rarity.COMMON, 1, "", "Longsword"), make(Slot.ARMOR, Rarity.COMMON, 1, "", "Leather Jerkin")]

## Builds one item. `tier` scales the fixed numbers slowly with progress (no random variance).
static func make(slot: int, rarity: int, tier: int, affix: String = "", base_name: String = "") -> Dictionary:
	var bases: Array = BASES[slot]
	var base: Dictionary = bases[randi() % bases.size()]
	if base_name != "":
		for candidate in bases:
			if candidate["name"] == base_name:
				base = candidate
	var stats: Dictionary = {}
	match slot:
		Slot.WEAPON:
			stats = {"damage": float(base["damage"]) * (1.0 + 0.08 * (tier - 1)), "speed": float(base["speed"])}
		Slot.ARMOR:
			stats = {"armor": float(base["armor"]) + 6.0 * (tier - 1), "roll_cost": float(base["roll_cost"]),
				"roll_speed": float(base["roll_speed"])}
	var name: String = base["name"]
	if affix != "" and rarity == Rarity.RARE:
		name = "%s %s" % [AFFIXES[affix]["title"], name]
	return {"slot": slot, "rarity": rarity, "name": name, "base": base["name"], "stats": stats, "affix": affix, "flavor": ""}

static func make_unique(entry: Dictionary, tier: int) -> Dictionary:
	var item: Dictionary = make(entry["slot"], Rarity.UNIQUE, tier, entry["affix"], entry["base"])
	item["name"] = entry["name"]
	item["flavor"] = entry["flavor"]
	return item

## Three reward choices. Brutes guarantee at least rare; trinkets are always rare or better.
static func roll_choices(wave: int, brute_killed: bool, owned_uniques: Array[String]) -> Array[Dictionary]:
	var tier: int = 1 + wave / 3
	var choices: Array[Dictionary] = []
	var attempts: int = 0
	while choices.size() < 3 and attempts < 40:
		attempts += 1
		var slot: int = randi() % 3
		var roll: float = randf()
		var unique_chance: float = 0.20 if brute_killed else (0.08 if wave >= 4 else 0.04)
		var rare_chance: float = 1.0 if brute_killed else 0.55
		var rarity: int = Rarity.COMMON
		if roll < unique_chance:
			rarity = Rarity.UNIQUE
		elif roll < unique_chance + rare_chance:
			rarity = Rarity.RARE
		if slot == Slot.TRINKET and rarity == Rarity.COMMON:
			rarity = Rarity.RARE
		var item: Dictionary = {}
		if rarity == Rarity.UNIQUE:
			var pool: Array[Dictionary] = []
			for entry in UNIQUES:
				if entry["slot"] == slot and not (entry["name"] in owned_uniques):
					pool.append(entry)
			if pool.is_empty():
				rarity = Rarity.RARE
			else:
				item = make_unique(pool[randi() % pool.size()], tier)
		if rarity == Rarity.RARE:
			var ids: Array[String] = []
			for id in AFFIXES:
				if AFFIXES[id]["slot"] == slot and AFFIXES[id]["title"] != "":
					ids.append(id)
			item = make(slot, Rarity.RARE, tier, ids[randi() % ids.size()])
		elif rarity == Rarity.COMMON:
			item = make(slot, Rarity.COMMON, tier)
		# Avoid offering the exact same item twice.
		var duplicate: bool = false
		for existing in choices:
			if existing["name"] == item["name"]:
				duplicate = true
		if not duplicate:
			choices.append(item)
	return choices

## Text lines for a tooltip/card: stats first, then the behaviour.
static func lines(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var stats: Dictionary = item["stats"]
	match int(item["slot"]):
		Slot.WEAPON:
			out.append("Damage x%.2f    Speed x%.2f" % [stats["damage"], stats["speed"]])
		Slot.ARMOR:
			out.append("Armor %d    Roll cost x%.1f    Roll speed x%.1f" % [stats["armor"], stats["roll_cost"], stats["roll_speed"]])
		Slot.TRINKET:
			out.append("No stats. Only an effect.")
	if item["affix"] != "":
		out.append(AFFIXES[item["affix"]]["desc"])
	if item["flavor"] != "":
		out.append("\"%s\"" % item["flavor"])
	return out
