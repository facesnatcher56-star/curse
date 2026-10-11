class_name MonsterScaling
extends RefCounted
## Dungeon Siege II's monster numbers by level (docs/ds2-combat-and-loot.md section 9): life, damage per hit and armour for a monster of
## level L, its tier (EnemyDef.tier) and its role (EnemyDef.role). Pure rules; Enemy applies them when it spawns or its level changes.

## Tier: life multiplier, and damage per hit `(a L + b)(1 + 0.04 L)`.
const TIERS := {
	"trivial": {"life": 0.25, "a": 1.0, "b": 4.0},
	"weak": {"life": 2.0 / 3.0, "a": 1.4, "b": 5.33},
	"normal": {"life": 1.0, "a": 2.12, "b": 8.0},
	"strong": {"life": 5.0 / 3.0, "a": 3.0, "b": 11.5},
	"miniboss": {"life": 11.0 / 3.0, "a": 4.7, "b": 17.8},
}

## Role: life and damage per hit multipliers (rogue and tank variants; ranged and magic monsters are frailer).
const ROLES := {
	"": {"life": 1.0, "damage": 1.0},
	"rogue": {"life": 0.8, "damage": 0.85},
	"tank": {"life": 1.25, "damage": 1.2},
	"ranged": {"life": 0.8, "damage": 1.0},
	"magic": {"life": 0.6, "damage": 1.0},
}

## Literal (a, b) per-hit coefficients from actor_evil_{melee,ranged,magic}.gas.
## DS2 defines melee rogue/tank variants only for normal and strong. Other combinations
## (Curse's weak ghoul, for example) keep the explicitly approximate role multiplier above.
const ROLE_DAMAGE := {
	"rogue": {"normal": Vector2(1.8, 6.67), "strong": Vector2(2.5, 9.5)},
	"tank": {"normal": Vector2(2.54, 9.6), "strong": Vector2(3.6, 13.7)},
	"ranged": {"trivial": Vector2(0.85, 3.2), "weak": Vector2(1.13, 4.3), "normal": Vector2(1.7, 6.4),
		"strong": Vector2(2.4, 9.1), "miniboss": Vector2(3.8, 14.2)},
	"magic": {"trivial": Vector2(1, 4), "weak": Vector2(1.4, 5.3), "normal": Vector2(2.1, 8),
		"strong": Vector2(3, 11.5), "miniboss": Vector2(4.7, 17.8)},
}

static func life(level: int, tier: String, role: String = "") -> float:
	var l: float = float(maxi(level, 1))
	return (9.0 * l + 18.0) * (1.0 + 0.12 * l) * float(_tier(tier)["life"]) * float(_role(role)["life"])

## Average damage per hit; a blow rolls 0.75 to 1.25 of it.
static func damage(level: int, tier: String, role: String = "") -> float:
	var l: float = float(maxi(level, 1))
	if ROLE_DAMAGE.has(role) and ROLE_DAMAGE[role].has(tier):
		var coefficients: Vector2 = ROLE_DAMAGE[role][tier]
		return (coefficients.x * l + coefficients.y) * (1.0 + 0.04 * l)
	var t: Dictionary = _tier(tier)
	return (float(t["a"]) * l + float(t["b"])) * (1.0 + 0.04 * l) * float(_role(role)["damage"])

static func armor(level: int) -> float:
	var l: float = float(maxi(level, 1))
	return 1.333 * (8.0 + 2.0 * l) * (1.0 + 0.004 * l)

static func _tier(tier: String) -> Dictionary:
	return TIERS.get(tier, TIERS["normal"])

static func _role(role: String) -> Dictionary:
	return ROLES.get(role, ROLES[""])
