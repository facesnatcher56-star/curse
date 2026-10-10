class_name WorldThreat
extends RefCounted
## How dangerous the connected world is, kept apart from everything else called "level":
##   Hero Level (`TownState.hero_level`) is how developed the hero is. It never scales the world.
##   World threat (here) is how dangerous a place or a monster is. One scale: an enemy spawned at threat T has `Enemy.level_scale = T`
##   (health x T, damage x (1 + 0.4 (T - 1))). Ordinary monsters get their zone's `base_threat`; a quest's unique monster has its own
##   `QuestDef.unique_level` (the same scale, absolute); a named monster (see Monsters) grows its own `level`, applied by MonsterMark.
##   Item tier is worked out from the SOURCE of a drop (`Items.tier_for_source`), never from the hero, jobs done or an arena wave. It is
##   a separate scale from threat (a provisional loot mapping that keeps the early road's loot as it was): the numbers do not match.
##   Rarity (a source's luck, EnemyDef.drop_luck) is separate again.
## Nothing here reads TownState: the world is no harder because the hero is stronger or has finished more quests.

## What a zone-less spot counts as (the road's own start).
const FALLBACK_THREAT := 1.0

## Placeholders until merchants and quest item rewards get their own progression (see Items.roll_choices, Quests): an explicit source
## threat and rarity chance, not a hidden count of jobs done. 1.5 is the deepest stretch of the road today (tier 2).
const MERCHANT_THREAT := 1.5
const MERCHANT_RARE_CHANCE := 0.4
const QUEST_REWARD_THREAT := 1.5

## The threat of the authored stretch that covers a distance (metres) out from the town gate.
static func for_distance(distance: float) -> float:
	var zone: ZoneDef = TownDb.zone_at(distance)
	return zone.base_threat if zone != null else FALLBACK_THREAT
