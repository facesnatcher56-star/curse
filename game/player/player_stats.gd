class_name PlayerStats
extends RefCounted
## Run stats and gear: mana/stamina/potions, cooldowns, equipment, regeneration and damage numbers.

var p: Player

func _init(player: Player) -> void:
	p = player
	ult_charge = ult_cost("earthshatter")   # a run starts with the ultimate ready

## One-line damage summary for tooltips (the blow before the target's armour).
func skill_damage_text(id: String) -> String:
	var skill: Dictionary = SkillDb.all()[id]
	match String(skill["kind"]):
		"melee":
			var r: Vector2 = weapon_range(float(skill["mult"]))
			return ("Damage %d-%d per hit" if id == "basic" else "Damage %d-%d") % [int(r.x), int(r.y)]
		"projectile":
			var spell: Vector2 = spell_range()
			return "Fire damage %d-%d" % [int(spell.x), int(spell.y)]
		"throw":
			var thrown: Vector2 = weapon_range(float(skill["mult"]), true)
			return "Damage up to %d-%d" % [int(thrown.x), int(thrown.y)]
		"charge":
			var impale: Vector2 = weapon_range(1.5)
			var kick: Vector2 = weapon_range(1.8)
			return "Impale %d-%d, then %d-%d per kick" % [int(impale.x), int(impale.y), int(kick.x), int(kick.y)]
		"leap":
			var chop: Vector2 = weapon_range(p.leap.LEAP_CHOP_MULT)
			var slam: Vector2 = weapon_range(p.leap.LEAP_SLAM_MULT)
			return "Chop %d-%d, slam %d-%d (crit)" % [int(chop.x), int(chop.y), int(slam.x), int(slam.y)]
		"earthshatter":
			var shatter: Vector2 = weapon_range(p.earthshatter.MULT)
			return "Damage %d-%d, thrown %d m up" % [int(shatter.x * p.earthshatter.MIN_FALLOFF), int(shatter.y),
				int(pow(p.earthshatter.LAUNCH_LIFT, 2.0) / 40.0)]
		"buff":
			if id == "brutal_attack":
				var brutal: Vector2 = weapon_range(brutal_mult())
				return "Empowered hit %d-%d" % [int(brutal.x), int(brutal.y)]
			elif id == "take_aim":
				var cutter := _cutter()
				return "Cutter's arrow deals ~%d" % int((cutter.arrow_damage() if cutter != null else 10.0) * ArcherCompanion.take_aim_mult())
		"potion":
			return "Heals 60"
	return ""

# --- Attributes, life and mana (Dungeon Siege II, see HeroAttributes) ---------------------------------------------------------------
## STR, DEX, INT from the hero's class skill levels (TownState.class_xp). Refreshed whenever his XP changes (`refresh`).
var attributes: Vector3 = HeroAttributes.START
var strength: float:
	get: return attributes.x
var dexterity: float:
	get: return attributes.y
var intelligence: float:
	get: return attributes.z

## Works STR / DEX / INT out again from the saved class XP and the gear, and with them the hero's maximum life and mana (keeping the share
## he has left of each), his armour, resistance, block and added fire. His character level becomes his combat level.
func refresh() -> void:
	gear = gear_totals()
	attributes = HeroAttributes.attributes(HeroAttributes.levels_from_xp(TownState.class_xp)) \
		+ Vector3(gear_stat("str"), gear_stat("dex"), gear_stat("int"))
	var life_share: float = p.health / maxf(p.max_health, 1.0)
	var mana_share: float = mana / maxf(max_mana, 1.0)
	p.max_health = (HeroAttributes.max_life(attributes) + gear_stat("life")) * (1.0 + passive("fortitude") / 100.0)
	max_mana = (HeroAttributes.max_mana(attributes) + gear_stat("mana")) * (1.0 + passive("brilliance") / 100.0)
	p.health = clampf(p.max_health * life_share, 0.0, p.max_health) if not p.dead else p.health
	mana = max_mana * mana_share
	p.level = TownState.hero_level
	p.armor = total_armor()
	p.fire_resist = (gear_stat("fire_resist") + passive("survival")) / 100.0
	p.block_chance = (gear_stat("block") + passive("barricade")) / 100.0 if equipment.has(Items.Slot.SHIELD) else 0.0
	p.added_fire = gear_stat("fire_added")
	p.crit_chance = passive("critical_strike") / 100.0
	p.crit_mult = passive("deadly_strike") / 100.0 if TownState.passive_rank("deadly_strike") > 0 else 2.0
	p.toughness = passive("toughness") / 100.0
	p.dodge_chance = passive("dodge") / 100.0

## A DS2 passive's effect at the hero's rank in it (PassiveDef.value; 0 when he has none).
func passive(id: String) -> float:
	var def: PassiveDef = PassiveDb.get_def(id)
	return def.value(TownState.passive_rank(id)) if def != null else 0.0

# --- What the gear adds (DS2 modifiers, uniques and set bonuses) ------------------------------------------------------------------------
## Everything worn adds up to this: stat (AffixDb.STAT_NAMES) -> value. Worked out by `refresh`.
var gear: Dictionary = {}

func gear_stat(stat: String) -> float:
	return float(gear.get(stat, 0.0))

## The modifiers of every worn piece, plus each set's bonus for the pieces of it worn.
func gear_totals() -> Dictionary:
	var out: Dictionary = {}
	var set_pieces: Dictionary = {}
	for place in equipment:
		var item: Dictionary = equipment[place]
		var mods: Dictionary = Items.mods_of(item)
		for stat in mods:
			out[stat] = float(out.get(stat, 0.0)) + float(mods[stat])
		var u: UniqueDef = UniqueDb.get_unique(String(item.get("unique", "")))
		if u != null and u.set_id != "":
			set_pieces[u.set_id] = int(set_pieces.get(u.set_id, 0)) + 1
	for set_id in set_pieces:
		var set_def: SetDef = UniqueDb.get_set(set_id)
		if set_def != null:
			var bonus: Dictionary = set_def.bonus_for(int(set_pieces[set_id]))
			for stat in bonus:
				out[stat] = float(out.get(stat, 0.0)) + float(bonus[stat])
	return out

## DS2's armour: the worn pieces' armour plus flat armour modifiers, then x (1 + armour %). Heroes have none of their own.
## Barricade raises the shield's own armour (+20 to +120%), Reinforced Armor all of it (DS2 section 3).
func total_armor() -> float:
	var armor: float = base_armor
	for place in equipment:
		var piece: float = float((equipment[place] as Dictionary)["stats"].get("armor", 0.0))
		var barricade: int = TownState.passive_rank("barricade")
		if place == Items.Slot.SHIELD and barricade > 0:
			piece *= 1.0 + (20.0 + 100.0 * float(barricade - 1) / 19.0) / 100.0
		armor += piece
	var provoke: float = p.powers.provoke_armor_pct if p.powers != null else 0.0   # DS2's Provoke, while it holds
	return (armor + gear_stat("armor")) * (1.0 + passive("reinforced_armor") / 100.0) * (1.0 + (gear_stat("armor_pct") + provoke) / 100.0)

## A skill's mana: its data's, except Fireball, a DS2 spell whose cost grows with INT (82 at INT 100, 164 at 200: 0.82 x INT).
func mana_cost(id: String) -> float:
	if id == "fireball":
		return roundf(SPELL_MANA_PER_INT * intelligence)
	return float(SkillDb.all()[id]["mana"])

## DS2's Fireball (the reference's table): about 53 at INT 100 and 105 at INT 200, fitted as `1 + 0.52 x INT`, rolled 0.75 to 1.25.
const SPELL_BASE := 1.0
const SPELL_PER_INT := 0.52
const SPELL_MANA_PER_INT := 0.82

func spell_range() -> Vector2:
	var average: float = (SPELL_BASE + SPELL_PER_INT * intelligence) * (1.0 + (gear_stat("spell_pct") + passive("devastation")) / 100.0) \
		* (1.0 + passive("searing_flames") / 100.0)
	return Vector2(average * 0.75, average * 1.25)

func spell_damage() -> float:
	var r: Vector2 = spell_range()
	return randf_range(r.x, r.y)

var max_mana: float = 55.0
var mana: float = 55.0
## Stamina is OFF as a resource (owner's first playtest: it served no purpose yet and only felt bad). With this false nothing spends it, nothing is
## gated on it, and the HUD shows no bar. The numbers below stay so turning it back on is this one line.
const STAMINA_ON := false
var max_stamina: float = 100.0
var stamina: float = 100.0
const MAX_POTIONS := 6
var potions: int = 3
var run_speed: float = 5.0
var cooldowns: Dictionary = {}
## True while the weapon is out of his hand (Weapon Throw): the weapon slot cannot be changed until it is back, so he never owns two.
var weapon_locked: bool = false
# Equipment (see items.gd)
var equipment: Dictionary = {}  # Items.Slot -> item Dictionary
var bag: Array[Dictionary] = []   # found this run, not worn; goes to the town stash when the run ends
const MAX_BAG := 12
var base_armor: float = 0.0   # DS2: a hero's armour is all his gear's
## The ultimate charges from damage the hero deals; `ult_cost()` is how much a skill needs (0 for ordinary skills).
var ult_charge: float = 0.0   # starts full (set in _init)
const BRUTAL_COMBAT_SECONDS := 21.0
var brutal_reload_required: float = 0.0
var brutal_reload_remaining: float = 0.0

func brutal_active_members() -> int:
	var members: int = 1
	if p != null and p.is_inside_tree():
		for node in p.get_tree().get_nodes_in_group("companions"):
			if node is Actor and is_instance_valid(node) and not (node as Actor).dead:
				members += 1
	return members

## Dungeon Siege II's fast-power baseline, copied directly: secondsOfCombat × (6 + 1.5L) × (1 + .022L) × active group members.
func power_recharge_damage(seconds_of_combat: float) -> float:
	var level: float = maxf(float(TownState.hero_level), 1.0)
	return seconds_of_combat * (6.0 + 1.5 * level) * (1.0 + 0.022 * level) * brutal_active_members() / (1.0 + gear_stat("recharge") / 100.0)

## Brutal Attack is a melee power: Fierce Renewal speeds its recharge.
func brutal_recharge_damage() -> float:
	return power_recharge_damage(BRUTAL_COMBAT_SECONDS) / (1.0 + passive("fierce_renewal") / 100.0)

## Brutal Attack's weapon-damage multiplier at the hero's rank (DS2: 1500 + 25 x Melee % at rank 1, to 2000 + 60 x Melee % at rank 3).
func brutal_mult() -> float:
	return maxf(PowerDb.hero_value("brutal_attack", "damage_pct"), 1500.0) / 100.0

func spend_brutal_attack() -> void:
	brutal_reload_required = brutal_recharge_damage()
	brutal_reload_remaining = brutal_reload_required

func _cutter() -> ArcherCompanion:
	if p != null and p.is_inside_tree():
		for node in p.get_tree().get_nodes_in_group("companions"):
			if node is ArcherCompanion and is_instance_valid(node):
				return node as ArcherCompanion
	return null

func ult_cost(id: String) -> float:
	if PowerController.LIVE.has(id):
		return p.powers.required(id) if p.powers != null else 1.0
	if id == "brutal_attack":
		return brutal_reload_required if brutal_reload_required > 0.0 else brutal_recharge_damage()
	if id == "take_aim":
		var cutter := _cutter()
		if cutter != null:
			return cutter.take_aim_reload_required if cutter.take_aim_reload_required > 0.0 else power_recharge_damage(ArcherCompanion.TAKE_AIM_COMBAT_SECONDS)
		return power_recharge_damage(ArcherCompanion.TAKE_AIM_COMBAT_SECONDS)
	return float(SkillDb.all()[id].get("charge", 0.0))

func ult_fraction(id: String) -> float:
	if PowerController.LIVE.has(id):
		return p.powers.fraction(id) if p.powers != null else 1.0
	var cost: float = ult_cost(id)
	if id == "brutal_attack":
		return 1.0 if brutal_reload_remaining <= 0.0 else clampf(1.0 - brutal_reload_remaining / maxf(cost, 0.001), 0.0, 1.0)
	if id == "take_aim":
		var cutter := _cutter()
		if cutter == null:
			return 0.0
		return 1.0 if cutter.take_aim_reload_remaining <= 0.0 else clampf(1.0 - cutter.take_aim_reload_remaining / maxf(cost, 0.001), 0.0, 1.0)
	return clampf(ult_charge / cost, 0.0, 1.0) if cost > 0.0 else 1.0

func gain_brutal_charge(damage: float) -> void:
	brutal_reload_remaining = maxf(brutal_reload_remaining - maxf(damage, 0.0), 0.0)

func gain_ult_charge(damage: float) -> void:
	ult_charge = minf(ult_charge + damage, MAX_ULT_CHARGE)

const MAX_ULT_CHARGE := 650.0

func can_use(id: String) -> bool:
	if PowerController.LIVE.has(id):
		return p.powers != null and p.powers.ready(id)
	var skill: Dictionary = SkillDb.all()[id]
	if id == "brutal_attack":
		return brutal_reload_remaining <= 0.0 and PowerDb.hero_rank("brutal_attack") > 0
	if id == "take_aim":
		var cutter := _cutter()
		return cutter != null and not cutter.dead and cutter.take_aim_reload_remaining <= 0.0
	if ult_cost(id) > 0.0 and ult_fraction(id) < 1.0:
		return false
	return float(cooldowns.get(id, 0.0)) <= 0.0 and mana >= mana_cost(id)

func use_potion() -> bool:
	if potions <= 0:
		p._say("No potions left")
		return false
	if float(cooldowns.get("potion", 0.0)) > 0.0:
		p._say("Potion not ready")
		return false
	if p.health >= p.max_health:
		p._say("Already at full health")
		return false
	potions -= 1
	cooldowns["potion"] = float(SkillDb.all()["potion"]["cd"])
	p.health = minf(p.health + 60.0, p.max_health)
	Fx.text_at(p, p.global_position + Vector3(0, 2.4, 0), "+60", Color(0.4, 1.0, 0.4), 56)
	return true

## The wielded weapon's own blow (its base's DS2 curve at its item level, ItemDef.stats_at) plus the gear's minimum and maximum melee
## damage. Bare hands are a level 1 one-handed blow.
func weapon_base_range() -> Vector2:
	var item: Variant = equipment.get(Items.Slot.WEAPON)
	var low: float = float((item as Dictionary)["stats"].get("min", 3.105)) if item != null else 3.105
	var high: float = float((item as Dictionary)["stats"].get("max", 5.175)) if item != null else 5.175
	return Vector2(low + gear_stat("melee_min"), maxf(high + gear_stat("melee_max"), low + gear_stat("melee_min")))

## DS2's hero blow: the weapon plus 0.2 x STR (DEX for a thrown weapon), 0.75 of that on the low roll and 1.25 on the high, then x (1 +
## melee damage %), times `mult` (the skill's multiplier, DS2's power damage multiplier). CURSE CHOICE: the hero's thrown blade is his
## melee weapon, so it keeps the melee modifiers.
func weapon_range(mult: float, thrown: bool = false) -> Vector2:
	var base: Vector2 = weapon_base_range()
	var bonus: float = 0.2 * maxf(dexterity if thrown else strength, 10.0)
	var overbear: float = passive("overbear") if _two_handed(equipment.get(Items.Slot.WEAPON, {})) else 0.0
	return Vector2(base.x + 0.75 * bonus, base.y + 1.25 * bonus) * (1.0 + gear_stat("melee_pct") / 100.0) * (1.0 + overbear / 100.0) * mult

func weapon_damage(mult: float, thrown: bool = false) -> float:
	var r: Vector2 = weapon_range(mult, thrown)
	return randf_range(r.x, r.y)

# --- Equipment -----------------------------------------------------------------

func _stat(slot: int, key: String, fallback: float) -> float:
	var item: Variant = equipment.get(slot)
	if item == null:
		return fallback
	return float((item as Dictionary)["stats"].get(key, fallback))

func weapon_stat(key: String, fallback: float) -> float:
	return _stat(Items.Slot.WEAPON, key, fallback)

## One entry of the wielded weapon's profile (ItemDef.profile), `fallback` when it has none or nothing is wielded.
func weapon_profile(key: String, fallback: Variant = 0.0) -> Variant:
	var item: Variant = equipment.get(Items.Slot.WEAPON)
	if item == null:
		return fallback
	var def: ItemDef = ItemDb.get_def(String((item as Dictionary).get("def", "")))
	return def.profile.get(key, fallback) if def != null else fallback

func armor_stat(key: String, fallback: float) -> float:
	return _stat(Items.Slot.ARMOR, key, fallback)

## Attack speed: the weapon's own.
func attack_speed() -> float:
	return weapon_stat("speed", 1.0)

## How fast a skill plays out: a spell by Quickened Casting, everything else by the weapon and Alacrity (DS2: melee speed).
func skill_speed(id: String) -> float:
	if String(SkillDb.all()[id].get("kind", "")) == "projectile":
		return 1.0 + passive("quickened_casting") / 100.0
	return attack_speed() * (1.0 + passive("alacrity") / 100.0)

## Puts `item` on. Returns what came off to make room (the piece in its place, and a shield for a two-handed weapon or a two-handed weapon
## for a shield), or null when it cannot be worn: the weapon is out in the world, or the hero does not meet its requirement (DS2: class
## skill at least item level - 2). A ring goes on a free hand, else replaces the first ring.
func equip(item: Dictionary, announce: bool = true) -> Variant:
	if weapon_locked and int(item["slot"]) == Items.Slot.WEAPON:
		p._say("Recall your weapon first")
		return null
	if not Items.hero_can_wear(item):
		if announce:
			p._say(Items.requirement_text(item))
		return null
	var off: Array[Dictionary] = []
	var place: int = place_for(item)
	if equipment.has(place):
		off.append(equipment[place])
	var conflict: int = _hand_conflict(item)
	if conflict >= 0 and equipment.has(conflict):
		if conflict == Items.Slot.WEAPON and weapon_locked:
			p._say("Recall your weapon first")
			return null
		off.append(equipment[conflict])
		equipment.erase(conflict)
	equipment[place] = item
	refresh()
	if place == Items.Slot.WEAPON or conflict == Items.Slot.WEAPON:
		p.refresh_weapon_model()
	return off

## Where `item` would go: its slot, or for a ring the free hand (the first when both are full).
func place_for(item: Dictionary) -> int:
	var places: Array[int] = Items.places(int(item["slot"]))
	for place in places:
		if not equipment.has(place):
			return place
	return places[0]

## The place a two-handed weapon and a shield fight over: -1 when there is none.
func _hand_conflict(item: Dictionary) -> int:
	var slot: int = int(item["slot"])
	if slot == Items.Slot.WEAPON and _two_handed(item):
		return Items.Slot.SHIELD
	if slot == Items.Slot.SHIELD and equipment.has(Items.Slot.WEAPON) and _two_handed(equipment[Items.Slot.WEAPON]):
		return Items.Slot.WEAPON
	return -1

static func _two_handed(item: Dictionary) -> bool:
	var def: ItemDef = ItemDb.get_def(String(item.get("def", "")))
	return def != null and bool(def.profile.get("two_handed", false))

## Puts back what was worn at `place` (a save, the town's record), with no requirement check: what he had on stays on.
func wear(place: int, item: Dictionary) -> void:
	equipment[place] = item
	refresh()
	if place == Items.Slot.WEAPON:
		p.refresh_weapon_model()

## Takes off what is worn at `place` (returns it, or null).
func unequip(place: int) -> Variant:
	if not equipment.has(place) or (place == Items.Slot.WEAPON and weapon_locked):
		return null
	var item: Dictionary = equipment[place]
	equipment.erase(place)
	refresh()
	if place == Items.Slot.WEAPON:
		p.refresh_weapon_model()
	return item

## Whether `item` would be put on at once when picked up: only into an empty place, if he may wear it and it pushes nothing off. Rarity
## never decides it, because a rarer piece may not fit the build; everything else goes to the bag and the player chooses.
func takes_empty_slot(item: Dictionary) -> bool:
	return not equipment.has(place_for(item)) and Items.hero_can_wear(item) \
		and (_hand_conflict(item) < 0 or not equipment.has(_hand_conflict(item)))

## Picks a dropped item up: an empty slot is filled at once, anything else goes to the bag.
func pickup(item: Dictionary) -> String:
	var color: Color = Items.RARITY_COLORS[int(item["rarity"])]
	var text: String
	if takes_empty_slot(item) and equip(item, false) != null:
		text = "Equipped %s" % item["name"]
	else:
		add_to_bag(item)
		text = "Found %s (bag)" % item["name"]
	# (no "Equipped X" / "Found X (bag)" line: the item name floating over the hero is enough; `text` is still returned for callers and tests)
	Fx.text_at(p, p.global_position + Vector3(0, 2.6, 0), String(item["name"]), color, 40)
	return text

func add_to_bag(item: Dictionary) -> void:
	bag.append(item)
	while bag.size() > MAX_BAG:
		var worst: int = 0
		for i in bag.size():
			if int(bag[i]["rarity"]) < int(bag[worst]["rarity"]):
				worst = i
		bag.remove_at(worst)

func heal(amount: float) -> void:
	p.health = minf(p.health + amount, p.max_health)
	Fx.text_at(p, p.global_position + Vector3(0, 2.4, 0), "+%d" % int(amount), Color(0.4, 1.0, 0.4), 40)

func collect_orbs() -> void:
	for node in p.get_tree().get_nodes_in_group("orbs"):
		var orb := node as Node3D
		if orb != null and orb.global_position.distance_to(p.global_position + Vector3(0, 0.6, 0)) < 1.3:
			if bool(orb.get("is_potion")):
				potions = mini(potions + 1, MAX_POTIONS)
				Fx.text_at(p, p.global_position + Vector3(0, 2.4, 0), "+1 potion", Color(1.0, 0.45, 0.4), 40)
			else:
				heal(HealthOrb.HEAL)
			orb.queue_free()

## Seconds left in which stamina recovers at its normal rate whatever the fight is doing (Bloody Recovery, after a physical kill).
var stamina_free_time: float = 0.0

## DS2 regeneration: about 1% of the maximum a second, life and mana alike.
func regen(delta: float) -> void:
	var in_combat: bool = p.combat_timer > 0.0
	p.health = minf(p.health + p.max_health * HeroAttributes.REGEN_PER_SECOND * (1.0 + gear_stat("life_regen") / 100.0) * delta, p.max_health)
	mana = minf(mana + max_mana * HeroAttributes.REGEN_PER_SECOND * (1.0 + gear_stat("mana_regen") / 100.0) * delta, max_mana)
	stamina_free_time = maxf(stamina_free_time - delta, 0.0)
	if not in_combat or p.velocity.length() < 0.5 or stamina_free_time > 0.0:
		stamina = minf(stamina + 14.0 * delta, max_stamina)

func cooldown_fraction(id: String) -> float:
	var total: float = float(SkillDb.all()[id]["cd"])
	if total <= 0.0:
		return 0.0
	return clampf(float(cooldowns.get(id, 0.0)) / total, 0.0, 1.0)
