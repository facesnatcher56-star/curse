class_name CharacterState
extends RefCounted
## Persistent data shared by every playable member. Derived values use the existing DS2 rules.

var id: String = "hero"
## Persistent profile ownership never changes when another controller selects this character.
var owner_id: String = "local"
var xp: int = 0
var class_xp: Dictionary = {"melee": 0, "ranged": 0, "combat": 0, "nature": 0}
var passive_ranks: Dictionary = {}
var equipment: Dictionary = {}
var hotbar: Array[String] = []
var hotbar_alt: String = "basic"
var health: float = -1.0
var mana: float = -1.0
var power_state: Dictionary = {}

var level: int:
	get: return HeroProgression.level_for_xp(xp)
var attributes: Vector3:
	get: return HeroAttributes.attributes(HeroAttributes.levels_from_xp(class_xp))

func _init(member_id: String = "hero") -> void:
	id = member_id
	hotbar.assign(["", "", "", "", "", ""])

func main_class() -> String:
	var best := "melee"
	for tree in HeroAttributes.CLASSES:
		if int(class_xp.get(tree, 0)) > int(class_xp.get(best, 0)):
			best = tree
	return best

func to_dict() -> Dictionary:
	var worn: Dictionary = {}
	for slot in equipment:
		worn[str(slot)] = Items.to_save(equipment[slot])
	return {"id": id, "owner_id": owner_id, "xp": xp, "class_xp": class_xp.duplicate(true), "passive_ranks": passive_ranks.duplicate(true),
		"equipment": worn, "hotbar": hotbar.duplicate(), "hotbar_alt": hotbar_alt,
		"health": health, "mana": mana, "power_state": power_state.duplicate(true)}

static func from_dict(member_id: String, data: Dictionary) -> CharacterState:
	var member := CharacterState.new(member_id)
	member.owner_id = String(data.get("owner_id", "local"))
	member.xp = HeroProgression.sanitize_xp(data.get("xp", 0))
	for tree in HeroAttributes.CLASSES:
		member.class_xp[tree] = HeroProgression.sanitize_xp(data.get("class_xp", {}).get(tree, 0))
	for passive in data.get("passive_ranks", {}):
		if PassiveDb.get_def(String(passive)) != null:
			member.passive_ranks[String(passive)] = clampi(int(data["passive_ranks"][passive]), 0, PassiveDef.MAX_RANK)
	for slot in data.get("equipment", {}):
		var item: Dictionary = Items.from_save(data["equipment"][slot])
		if not item.is_empty(): member.equipment[int(slot)] = item
	if HotbarLayout.is_valid(data.get("hotbar", []), String(data.get("hotbar_alt", "basic"))):
		member.hotbar.assign(data["hotbar"])
		member.hotbar_alt = String(data["hotbar_alt"])
	member.health = float(data.get("health", -1.0))
	member.mana = float(data.get("mana", -1.0))
	member.power_state = data.get("power_state", {}).duplicate(true)
	return member
