class_name MapAutoTally
extends RefCounted
## Dev-only counters for the map-mode autoplay (`--mapmode-auto`): how often each item trait / legendary effect actually fired, how much damage
## each member and power dealt, and what hurt the party. The hooks in the game code call `note` / `dealt` / `hurt`, which return at once unless
## the autoplay switched `enabled` on, so a player's game is unchanged. Read by MapAutoReport.

static var enabled: bool = false
static var counts: Dictionary = {}       # key -> {"n": fires, "amount": summed amount}
static var dealt_by: Dictionary = {}     # "member/skill" -> damage dealt (before armour, after mark bonus)
static var hurt_by: Dictionary = {}      # "kind" or "kind*" (champion) -> damage the party took from it, since the last take_hurt()
static var hurt_total: Dictionary = {}   # the same, over the whole run

static func reset() -> void:
	counts.clear()
	dealt_by.clear()
	hurt_by.clear()
	hurt_total.clear()

## One firing of an effect (`amount`: the damage or charge it added, when that is known).
static func note(key: String, amount: float = 0.0) -> void:
	if not enabled:
		return
	var row: Dictionary = counts.get(key, {"n": 0, "amount": 0.0})
	row["n"] = int(row["n"]) + 1
	row["amount"] = float(row["amount"]) + amount
	counts[key] = row

static func n(key: String) -> int:
	return int((counts.get(key, {}) as Dictionary).get("n", 0))

static func amount(key: String) -> float:
	return float((counts.get(key, {}) as Dictionary).get("amount", 0.0))

## A hit a party member landed (Actor.receive -> MapModeTraits.modify_hit).
static func dealt(member_id: String, skill_id: String, damage: float) -> void:
	if enabled:
		var key: String = "%s/%s" % [member_id, skill_id]
		dealt_by[key] = float(dealt_by.get(key, 0.0)) + damage

## A blow a party member took (Player._on_hurt -> MapModeTraits.on_hurt).
static func hurt(result: Dictionary) -> void:
	if not enabled:
		return
	var src: Variant = result.get("source")
	var key: String = "unknown"
	if src is Enemy:
		key = String((src as Enemy).variant) + ("*" if (src as Enemy).champion != null else "")
	var dmg: float = float(result.get("damage", 0.0))
	hurt_by[key] = float(hurt_by.get(key, 0.0)) + dmg
	hurt_total[key] = float(hurt_total.get(key, 0.0)) + dmg

## What hurt the party since the last call.
static func take_hurt() -> Dictionary:
	var out: Dictionary = hurt_by.duplicate()
	hurt_by.clear()
	return out
