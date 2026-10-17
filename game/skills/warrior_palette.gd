class_name WarriorPalette
extends RefCounted
## The Warrior's effect colours, shared by every Warrior power: rage forged into steel. Blackened iron, blood crimson, ember orange and hot
## steel. Ranger powers keep their emerald accents, so the classes read apart without a name (docs/ART_DIRECTION.md, "Class palettes").

const IRON := Color(0.07, 0.06, 0.06)
const BLOOD := Color(0.36, 0.02, 0.03)
const CRIMSON := Color(0.78, 0.06, 0.05)
const EMBER := Color(1.0, 0.5, 0.1)
const HOT_STEEL := Color(1.0, 0.86, 0.66)
const DUST := Color(0.52, 0.47, 0.4)

## Crimson to molten orange as the rage builds (0 dull, 1 full).
static func rage(amount: float) -> Color:
	return CRIMSON.lerp(EMBER, clampf(amount, 0.0, 1.0))
