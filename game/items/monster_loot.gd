class_name MonsterLoot
extends RefCounted
## Literal common monster oneof weights from installed DS2 pcontent_macros.gas.
## Gold/potions/gear are alternatives, not independent extra chances.
const TABLES := {
	"weak": [0.7385, 0.12, 0.02, 0.04, 0.024],
	"normal": [0.6625, 0.12, 0.03, 0.06, 0.035],
	"strong": [0.515, 0.14, 0.04, 0.08, 0.048],
}

static func roll(level: int, tier: String, mf: float = 0.0, mult: float = 1.0) -> Dictionary:
	var out := {"gold": 0, "health": 0, "mana": 0, "item": {}}
	if tier == "miniboss":
		out.item = Items.roll_reward(level, Items.MINIBOSS, mf)
		return out # Miniboss gold/potion integration is tracked separately; road has none.
	var key := "weak" if tier == "trivial" else tier
	var weights: Array = TABLES.get(key, TABLES.normal).duplicate()
	var equipment: Dictionary = Items.DROPS.get(key, Items.DROPS.normal)
	for kind in ["item", "rare", "unique", "set"]: weights.append(equipment[kind])
	for i in range(5, 9): weights[i] = float(weights[i]) * mult * (1.0 + maxf(mf, 0.0) / 100.0 if i >= 6 else 1.0)
	var total := 0.0
	for weight in weights: total += float(weight)
	var pick := randf() * total
	var selected := 0
	for i in weights.size():
		pick -= float(weights[i])
		if pick < 0.0:
			selected = i
			break
	if selected in [1, 2]:
		var l := float(maxi(level, 1))
		var curve := (0.1 * l * l + 2.6 * l + 1.0) if key == "weak" else ((0.267 * l * l + 6.9 * l + 2.67) if key == "strong" else (0.2 * l * l + 5.2 * l + 2.0))
		out.gold = maxi(1, int(round(curve * randf_range(0.375, 0.625) if selected == 2 else curve * randf_range(0.093, 0.156))))
	elif selected == 3: out.health = 1
	elif selected == 4: out.mana = 1
	elif selected >= 5:
		var kind: String = ["item", "rare", "unique", "set"][selected - 5]
		var window: Vector2i = Items.DROPS.get(key, Items.DROPS.normal).window
		if kind == "rare": window = Vector2i(-5, 1) if key == "weak" else (Vector2i(-3, 2) if key == "strong" else Vector2i(-4, 2))
		var rarity_window := window if kind == "rare" else Vector2i.ZERO
		if kind in ["unique", "set"]: rarity_window = Vector2i(-40 if kind == "unique" else -50, 2 if key == "weak" else 3)
		out.item = Items.item_of_kind(kind, level, window, rarity_window)
	return out
