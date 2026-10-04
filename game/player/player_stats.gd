class_name PlayerStats
extends RefCounted
## Run stats and gear: mana/stamina/potions, cooldowns, equipment and its affixes, regeneration and damage numbers.

var p: Player

func _init(player: Player) -> void:
	p = player

## True when worn gear changes how this skill behaves (shown as a gold pip on its hotbar slot).
func skill_has_modifier(id: String) -> bool:
	for affix in SkillDb.modifier_affixes(id):
		if has_affix(affix):
			return true
	return false

## One-line damage summary for tooltips.
func skill_damage_text(id: String) -> String:
	var skill: Dictionary = SkillDb.all()[id]
	match String(skill["kind"]):
		"melee", "cleave":
			var factor: float = (1.0 + strength * 0.02) * weapon_stat("damage", 1.0) * float(skill["mult"])
			if id == "basic":
				return "Damage %d-%d per hit" % [int(weapon_min * factor), int(weapon_max * factor)]
			return "Damage %d-%d" % [int(weapon_min * factor), int(weapon_max * factor)]
		"projectile":
			return "Fire damage ~%d" % int(14.0 + strength * 0.4)
		"charge":
			var base: float = (1.0 + strength * 0.02) * weapon_stat("damage", 1.0)
			return "Impale %d-%d, then %d-%d per kick" % [int(weapon_min * base * 1.5), int(weapon_max * base * 1.5),
				int(weapon_min * base * 1.8), int(weapon_max * base * 1.8)]
		"leap":
			var factor: float = (1.0 + strength * 0.02) * weapon_stat("damage", 1.0)
			return "Chop %d-%d, slam %d-%d (crit)" % [int(weapon_min * factor * p.leap.LEAP_CHOP_MULT), int(weapon_max * factor * p.leap.LEAP_CHOP_MULT),
				int(weapon_min * factor * p.leap.LEAP_SLAM_MULT), int(weapon_max * factor * p.leap.LEAP_SLAM_MULT)]
		"earthshatter":
			var factor: float = (1.0 + strength * 0.02) * weapon_stat("damage", 1.0) * p.earthshatter.MULT
			return "Damage %d-%d, thrown %d m up" % [int(weapon_min * factor * p.earthshatter.MIN_FALLOFF), int(weapon_max * factor),
				int(pow(p.earthshatter.LAUNCH_LIFT, 2.0) / 40.0)]
		"potion":
			return "Heals 60"
	return ""

var max_mana: float = 80.0
var mana: float = 80.0
var max_stamina: float = 100.0
var stamina: float = 100.0
const MAX_POTIONS := 6
var potions: int = 3
var run_speed: float = 5.0
var strength: float = 15.0
var weapon_min: float = 6.0
var weapon_max: float = 11.0
var cooldowns: Dictionary = {}
# Equipment (see items.gd / item_effects.gd)
var equipment: Dictionary = {}  # Items.Slot -> item Dictionary
var base_armor: float = 15.0
var haste_time: float = 0.0
var riposte_time: float = 0.0
var ward_timer: float = 0.0
var aegis_hits: int = 0
## The ultimate charges from damage the hero deals; `ult_cost()` is how much a skill needs (0 for ordinary skills).
var ult_charge: float = 0.0

func ult_cost(id: String) -> float:
	return float(SkillDb.all()[id].get("charge", 0.0))

func ult_fraction(id: String) -> float:
	var cost: float = ult_cost(id)
	return clampf(ult_charge / cost, 0.0, 1.0) if cost > 0.0 else 1.0

func gain_ult_charge(damage: float) -> void:
	ult_charge = minf(ult_charge + damage, MAX_ULT_CHARGE)

const MAX_ULT_CHARGE := 650.0

func can_use(id: String) -> bool:
	var skill: Dictionary = SkillDb.all()[id]
	if ult_charge < ult_cost(id):
		return false
	return float(cooldowns.get(id, 0.0)) <= 0.0 and mana >= float(skill["mana"])

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
	Sfx.play(p, "potion", -4.0)
	Fx.text_at(p, p.global_position + Vector3(0, 2.4, 0), "+60", Color(0.4, 1.0, 0.4), 56)
	return true

func weapon_damage(mult: float) -> float:
	return randf_range(weapon_min, weapon_max) * (1.0 + strength * 0.02) * mult * weapon_stat("damage", 1.0)

# --- Equipment -----------------------------------------------------------------

func has_affix(id: String) -> bool:
	for item in equipment.values():
		if item["affix"] == id:
			return true
	return false

func _stat(slot: int, key: String, fallback: float) -> float:
	var item: Variant = equipment.get(slot)
	if item == null:
		return fallback
	return float((item as Dictionary)["stats"].get(key, fallback))

func weapon_stat(key: String, fallback: float) -> float:
	return _stat(Items.Slot.WEAPON, key, fallback)

func armor_stat(key: String, fallback: float) -> float:
	return _stat(Items.Slot.ARMOR, key, fallback)

## Attack speed: weapon base times a temporary haste bonus.
func attack_speed() -> float:
	return weapon_stat("speed", 1.0) * (1.0 + (ItemEffects.HASTE_BONUS if haste_time > 0.0 else 0.0))

func equip(item: Dictionary, announce: bool = true) -> void:
	equipment[int(item["slot"])] = item
	p.armor = base_armor + armor_stat("armor", 0.0)
	if announce:
		p._say("Equipped %s" % item["name"])

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

func regen(delta: float) -> void:
	var in_combat: bool = p.combat_timer > 0.0
	p.health = minf(p.health + 1.5 * (0.3 if in_combat else 1.0) * delta, p.max_health)
	mana = minf(mana + 3.0 * delta, max_mana)
	if not in_combat or p.velocity.length() < 0.5:
		stamina = minf(stamina + 14.0 * delta, max_stamina)

func cooldown_fraction(id: String) -> float:
	var total: float = float(SkillDb.all()[id]["cd"])
	if total <= 0.0:
		return 0.0
	return clampf(float(cooldowns.get(id, 0.0)) / total, 0.0, 1.0)
