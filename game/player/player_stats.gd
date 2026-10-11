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
				var brutal: Vector2 = weapon_range(SkillController.BRUTAL_MULT)
				return "Empowered hit %d-%d" % [int(brutal.x), int(brutal.y)]
			elif id == "take_aim":
				var cutter := _cutter()
				return "Cutter's arrow deals ~%d" % int((cutter.arrow_damage() if cutter != null else 10.0) * ArcherCompanion.TAKE_AIM_MULT)
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

## Works STR / DEX / INT out again from the saved class XP, and with them the hero's maximum life and mana (keeping the share he has
## left of each). His character level becomes his combat level.
func refresh() -> void:
	attributes = HeroAttributes.attributes(HeroAttributes.levels_from_xp(TownState.class_xp))
	var life_share: float = p.health / maxf(p.max_health, 1.0)
	var mana_share: float = mana / maxf(max_mana, 1.0)
	p.max_health = HeroAttributes.max_life(attributes)
	max_mana = HeroAttributes.max_mana(attributes)
	p.health = clampf(p.max_health * life_share, 0.0, p.max_health) if not p.dead else p.health
	mana = max_mana * mana_share
	p.level = TownState.hero_level

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
	var average: float = SPELL_BASE + SPELL_PER_INT * intelligence
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
	return seconds_of_combat * (6.0 + 1.5 * level) * (1.0 + 0.022 * level) * brutal_active_members()

func brutal_recharge_damage() -> float:
	return power_recharge_damage(BRUTAL_COMBAT_SECONDS)

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
	if id == "brutal_attack":
		return brutal_reload_required if brutal_reload_required > 0.0 else brutal_recharge_damage()
	if id == "take_aim":
		var cutter := _cutter()
		if cutter != null:
			return cutter.take_aim_reload_required if cutter.take_aim_reload_required > 0.0 else power_recharge_damage(ArcherCompanion.TAKE_AIM_COMBAT_SECONDS)
		return power_recharge_damage(ArcherCompanion.TAKE_AIM_COMBAT_SECONDS)
	return float(SkillDb.all()[id].get("charge", 0.0))

func ult_fraction(id: String) -> float:
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
	var skill: Dictionary = SkillDb.all()[id]
	if id == "brutal_attack":
		return brutal_reload_remaining <= 0.0
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

## The wielded weapon's own blow (DS2 one-handed: `3.4 + 0.74 x item level` on average, rolled 0.75 to 1.25), scaled by its base's damage.
## CURSE CHOICE until DS2 item levels arrive: the item's tier stands in for its item level.
func weapon_base_range() -> Vector2:
	var item: Variant = equipment.get(Items.Slot.WEAPON)
	var item_level: float = float((item as Dictionary).get("tier", 1)) if item != null else 1.0
	var average: float = (3.4 + 0.74 * item_level) * weapon_stat("damage", 1.0)
	return Vector2(average * 0.75, average * 1.25)

## DS2's hero blow: the weapon plus 0.2 x STR (DEX for a thrown weapon), 0.75 of that on the low roll and 1.25 on the high, times `mult`
## (the skill's multiplier, DS2's power damage multiplier).
func weapon_range(mult: float, thrown: bool = false) -> Vector2:
	var base: Vector2 = weapon_base_range()
	var bonus: float = 0.2 * maxf(dexterity if thrown else strength, 10.0)
	return Vector2(base.x + 0.75 * bonus, base.y + 1.25 * bonus) * mult

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

func equip(item: Dictionary, announce: bool = true) -> void:
	if weapon_locked and int(item["slot"]) == Items.Slot.WEAPON:
		p._say("Recall your weapon first")
		return
	equipment[int(item["slot"])] = item
	p.armor = base_armor + armor_stat("armor", 0.0)
	if int(item["slot"]) == Items.Slot.WEAPON:
		p.refresh_weapon_model()
	# (no "Equipped X" line any more: the gear panel and the hero's weapon show it)
	if announce:
		pass

## Whether `item` would be put on at once when picked up: only into an empty slot. Rarity never decides it, because a rarer piece may
## not fit the build; everything else goes to the bag and the player chooses.
func takes_empty_slot(item: Dictionary) -> bool:
	return equipment.get(int(item["slot"])) == null

## Picks a dropped item up: an empty slot is filled at once, anything else goes to the bag.
func pickup(item: Dictionary) -> String:
	var color: Color = Items.RARITY_COLORS[int(item["rarity"])]
	var text: String
	if takes_empty_slot(item):
		equip(item, false)
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
	p.health = minf(p.health + p.max_health * HeroAttributes.REGEN_PER_SECOND * delta, p.max_health)
	mana = minf(mana + max_mana * HeroAttributes.REGEN_PER_SECOND * delta, max_mana)
	stamina_free_time = maxf(stamina_free_time - delta, 0.0)
	if not in_combat or p.velocity.length() < 0.5 or stamina_free_time > 0.0:
		stamina = minf(stamina + 14.0 * delta, max_stamina)

func cooldown_fraction(id: String) -> float:
	var total: float = float(SkillDb.all()[id]["cd"])
	if total <= 0.0:
		return 0.0
	return clampf(float(cooldowns.get(id, 0.0)) / total, 0.0, 1.0)
