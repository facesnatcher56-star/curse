class_name WorldThreat
extends RefCounted
## How dangerous the connected world is, kept apart from everything else called "level":
##   Hero Level (`TownState.hero_level`) is how developed the hero is. It never scales the world.
##   World threat (here) is how dangerous a place or a monster is. One scale: an enemy spawned at threat T has `Enemy.level_scale = T`
##   and the DS2 monster level `monster_level(T)`, which sets its life, damage and armour. Ordinary monsters get their zone's `base_threat`; a quest's unique monster has its own
##   `QuestDef.unique_level` (the same scale, absolute); a named monster (see Monsters) grows its own `level`, applied by MonsterMark.
##   Item level is DS2's: a drop's level window is around its SOURCE's monster level (a monster's own, or `monster_level` of the threat
##   where a prop or reward lies), never the hero's. Rarity comes from the source's tier (Items.roll_drop) and the hero's magic find.
## Nothing here reads TownState: the world is no harder because the hero is stronger or has finished more quests.

## What a zone-less spot counts as (the road's own start).
const FALLBACK_THREAT := 1.0

## Placeholders until merchants and quest item rewards get their own progression (see Items.roll_choices, Quests): an explicit source
## threat and rarity chance, not a hidden count of jobs done. 1.5 is the deepest stretch of the road today (monster level 4).
const MERCHANT_THREAT := 1.5
const MERCHANT_RARE_CHANCE := 0.4
const QUEST_REWARD_THREAT := 1.5

## The Dungeon Siege II monster level of a threat. Threat stays the world's one danger dial (zones, quest monsters, named monsters
## growing); this is the only place it becomes a DS2 level, which sets a monster's life, damage, armour and XP (see Enemy) and the
## level gap in combat. CURSE CHOICE: the road's first stretch (threat 1.25) is level 1, as DS2 opens, and every point of threat is
## 12 levels: the road runs 1 (Road In) to 4 (the Crypt Approach), and a named monster grown to threat 3.4 is level 27.
const LEVEL_ONE_THREAT := 1.25
const LEVELS_PER_THREAT := 12.0

static func monster_level(threat: float) -> int:
	return maxi(1 + int(round((threat - LEVEL_ONE_THREAT) * LEVELS_PER_THREAT)), 1)

## The threat of the authored stretch that covers a distance (metres) out from the town gate.
static func for_distance(distance: float) -> float:
	var zone: ZoneDef = TownDb.zone_at(distance)
	return zone.base_threat if zone != null else FALLBACK_THREAT
