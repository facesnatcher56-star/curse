class_name CryptForecourtEncounter
extends RefCounted
## Authored encounter beat on Crypt Road: The Ruined Mortuary / Ossuary Forecourt.
## Located at z = -146..-164 on Crypt Road (centered around z = -154), forming the final exterior
## transition immediately before the sealed crypt gate facade at z = -166.
##
## Environmental Storytelling:
##   Before the dark curse overran the valley, this forecourt served as the solemn preparation ground
##   where bodies brought from the road and graveyard underwent final mortuary rites before burial
##   in the catacombs. When the crypt was sealed, the station was abandoned in panic.
##   On the western flank stands a ruined mortuary shelter with a stone embalming bier, unsealed burial
##   shrouds, breakable supply barrels, and fallen attendants. On the eastern flank, an ossuary retaining
##   wall lines weathered memorial niches and stacked bone relics. Monumental gate pillars and breached
##   iron boundary railings frame the entrance, while sacrificial braziers and fallen crypt wardens flank
##   the grand stone portal steps.
##
## Tactical Features:
##   - Direct approach lane (centered along x = -1.5..+1.5, z = -146..-164) permanently clear and open
##     for uninterrupted navigation to the crypt portal.
##   - Ruined mortuary shelter on the western verge providing close-quarters cover and flank infiltration.
##   - Ossuary wall and pillars on the eastern verge offering high cover against ranged line of sight.
##   - Final exterior resistance encounter:
##     * Group 27: Crypt Portal Vanguard (elite CENTER_ELITE_ID + 2 placed zombies = 7 enemies).
##     * Group 28: Ossuary Sentry & Scavengers (spitter lookout + 1 placed ghoul = 4 enemies).
##     * Group 29: Mortuary Shelter Feeder & Scavengers (bloater + 1 placed ghoul = 4 enemies).
##   - Total forecourt enemies: 15 (raising Crypt Road monster count from 231 to 246, safely within the [170, 280] limit).

## Exposed single elite enemy slot constant for the center vanguard group (Group 27).
## Set to an existing enemy id ("brute") for independent lane execution.
## Integration step may later swap this single constant to "warden".
const CENTER_ELITE_ID: String = "warden"

const GROUP_CENTER: int = 27
const GROUP_EAST: int = 28
const GROUP_WEST: int = 29

const CENTER_Z := -154.0
const BOUNDS_Z_MIN := -164.0
const BOUNDS_Z_MAX := -146.0
const BOUNDS_X_MIN := -18.0
const BOUNDS_X_MAX := 18.0

## Places the monumental gateposts, mortuary shelter, ossuary wall, biers, dressing, and lighting.
static func build(road: CryptRoad, _arena: Arena) -> void:
	_build_approach_silhouettes(road)
	_build_mortuary_shelter(road)
	_build_ossuary_wall(road)
	_build_portal_terrace(road)
	_build_flank_corridors(road)

## Populates the crypt forecourt encounter groups and attaches the staged climax controller.
## All enemies are placed at z <= -151 so they are > 300 m from player start (z = 150).
static func spawn_encounters(road: CryptRoad, director: RunDirector) -> void:
	# Group 27: Crypt Portal Vanguard (Center & Crypt Gate Threshold, z = -158..-162).
	# 1 elite (CENTER_ELITE_ID, single copy) presiding over the sealed crypt steps + 2 placed zombies (pallbearer wardens,
	# 3 pack copies each = 6 zombies). Total = 7 enemies.
	# Mode "": holding ground at the sacred sealed entrance.
	road._group(GROUP_CENTER, "", [
		[CENTER_ELITE_ID, 0.0, -161.0],
		["zombie", -2.4, -158.8],
		["zombie", 2.4, -158.8]
	], Vector2(0.0, -159.5), 3.5)

	# Group 28: Ossuary Sentry & Scavengers (Eastern Ossuary Wall & Niches, z = -151..-155).
	# 1 spitter lookout (single copy) stationed behind low stone wall cover + 1 placed ghoul (3 pack copies = 3 ghouls).
	# Total = 4 enemies.
	road._group(GROUP_EAST, "wander", [
		["spitter", 7.8, -154.5],
		["ghoul", 9.5, -152.0]
	], Vector2(8.5, -153.5), 3.5, Vector2.ZERO, [
		Vector2(7.5, -155.0),
		Vector2(9.5, -152.0),
		Vector2(6.5, -153.0)
	])

	# Group 29: Mortuary Shelter Feeder & Scavengers (Western Mortuary Shelter & Bier, z = -151..-156).
	# 1 bloater (single copy) corrupted by embalming fluid + 1 placed ghoul (3 pack copies = 3 ghouls).
	# Total = 4 enemies.
	road._group(GROUP_WEST, "wander", [
		["bloater", -9.0, -154.5],
		["ghoul", -7.5, -152.0]
	], Vector2(-8.5, -153.5), 3.5, Vector2.ZERO, [
		Vector2(-7.0, -152.5),
		Vector2(-10.0, -155.0),
		Vector2(-8.0, -156.5)
	])

	# Attach and initialize the staged encounter climax controller
	var climax := CryptForecourtClimax.new()
	climax.name = "CryptForecourtClimax"
	road.add_child(climax)
	climax.setup(road, director)

## Returns the staged climax controller attached to the CryptRoad instance.
static func get_climax(road: CryptRoad) -> CryptForecourtClimax:
	if road == null:
		return null
	return road.get_node_or_null("CryptForecourtClimax") as CryptForecourtClimax


## Forecourt entrance threshold markers and silhouettes visible when approaching North along the avenue (z = -146..-149).
static func _build_approach_silhouettes(road: CryptRoad) -> void:
	# Monumental flanking gateposts framing the forecourt entrance.
	road._prop("ruined_pillar", -4.8, -147.0, 0.2, 4.2, true, false, 1.0)
	road._prop("ruined_pillar", 4.8, -147.0, -0.15, 4.0, true, false, 1.0)

	# Breached iron boundary fence sections splayed outwards.
	road._prop("crypt/iron_fence", -6.8, -147.5, 0.4, 1.8, true, false, 0.8)
	road._prop("crypt/iron_fence", 6.8, -147.5, -0.35, 1.8, true, false, 0.8)

	# Shattered iron burial lantern post on the east approach shoulder.
	road._prop("lamp_post", 4.2, -148.5, -0.5, 3.6, true, false, 0.8)

	# Slumped crypt guardian casualty sprawled at the forecourt entrance threshold.
	road._prop("crypt/corpse", -3.2, -148.0, 1.2, 0.5, false, false, 0.0)

	# Scattered ritual bones and broken offering relics.
	road._prop("bones", 2.5, -147.8, 0.4, 0.35, false, false, 0.0)

	# Weathered boundary stone rubble.
	road._prop("rubble", -5.2, -148.2, 0.8, 0.9, true, false, 0.5)

## The ruined mortuary preparation shelter on the western flank (x = -7.0..-15.0, z = -150.0..-158.0).
static func _build_mortuary_shelter(road: CryptRoad) -> void:
	# North and west sheltering walls of the mortuary shed.
	road._prop("ruined_wall", -11.5, -151.0, 0.0, 2.8, true, false, 1.1)
	road._prop("ruined_wall", -14.5, -154.5, PI * 0.5, 2.8, true, false, 1.1)

	# Architectural framing pillars.
	road._prop("ruined_pillar", -8.2, -152.0, 0.1, 3.8, true, false, 1.0)
	road._prop("ruined_pillar", -8.2, -157.0, -0.2, 3.5, true, false, 1.0)

	# Stone embalming bier / mortuary slab (using flat grave slab model).
	road._prop("gravestone", -11.0, -154.5, PI * 0.5, 0.38, true, false, 0.0)

	# Fallen embalmer / attendant casualties.
	road._prop("crypt/corpse", -10.2, -154.0, 2.2, 0.5, false, false, 0.0)
	road._prop("crypt/corpse", -12.8, -155.5, -0.8, 0.5, false, false, 0.0)

	# Embalming fluid barrels and preparation supplies in the rear shelter corners.
	road._prop("barrel", -13.5, -156.0, 0.4, 1.0, true, false, 0.5)
	road._prop("barrel", -13.2, -152.5, 1.2, 0.95, true, false, 0.5)

	# Shattered timber beams from the collapsed shelter roof.
	road._prop("town/wood_pile", -12.5, -156.5, 0.3, 1.15, true, false, 0.8)

	# Abandoned mortuary burial chest.
	road._prop("stash_chest", -13.5, -153.5, -0.6, 0.95, true, false, 0.6)

	# Ceremonial mortuary brazier casting warm amber-red glow over the embalming station.
	var brazier: Node3D = road._prop("brazier", -8.0, -156.5, 0.0, 1.4, true, true, 0.8)
	road._light(brazier, Color(1.0, 0.48, 0.18), 1.6, 7.5, 1.25)

	# Scattered bone remnants near the bier.
	road._prop("bones", -10.5, -152.5, 0.6, 0.35, false, false, 0.0)

## The ossuary retaining wall and memorial bone niches on the eastern flank (x = 6.5..15.0, z = -150.0..-158.0).
static func _build_ossuary_wall(road: CryptRoad) -> void:
	# East ossuary boundary and niche walls along the outer perimeter.
	road._prop("ruined_wall", 13.5, -151.0, 0.05, 2.8, true, false, 1.1)
	road._prop("ruined_wall", 14.5, -155.5, PI * 0.5, 2.8, true, false, 1.1)

	# Framing columns along the ossuary front.
	road._prop("ruined_pillar", 7.8, -151.5, 0.0, 3.8, true, false, 1.0)
	road._prop("ruined_pillar", 7.8, -156.5, 0.2, 3.6, true, false, 1.0)

	# Upright memorial stone slabs embedded in ossuary niches.
	road._prop("gravestone", 13.0, -153.0, 0.1, 0.35, true, false, 0.0)
	road._prop("gravestone", 13.0, -156.0, -0.15, 0.35, true, false, 0.0)

	# Piles of ancestral skull and bone relics in the niches.
	road._prop("bones", 11.5, -153.5, 0.3, 0.42, false, false, 0.0)
	road._prop("bones", 12.0, -155.0, -0.5, 0.42, false, false, 0.0)

	# Lime / embalming barrel near the niche line.
	road._prop("barrel", 12.0, -156.5, 0.6, 1.0, true, false, 0.5)

	# Collapsed ashlar stone rubble along the wall base (non-colliding ambient detail).
	road._prop("rubble", 11.0, -152.0, 0.4, 0.85, false, false, 0.0)

	# Slumped ossuary guard casualty.
	road._prop("crypt/corpse", 9.8, -155.0, -1.5, 0.5, false, false, 0.0)

	# Ossuary vigil brazier casting solemn pale amber firelight near the south pillar.
	var brazier: Node3D = road._prop("brazier", 7.5, -156.5, 0.0, 1.4, true, true, 0.8)
	road._light(brazier, Color(0.95, 0.55, 0.22), 1.5, 7.0, 1.25)

## The central forecourt plaza and crypt portal transition terrace (z = -153.0..-164.0).
static func _build_portal_terrace(road: CryptRoad) -> void:
	# Subtle non-colliding pavement debris marking the edges of the central approach aisle.
	road._prop("rubble", -2.8, -153.5, 0.5, 0.65, false, false, 0.0)
	road._prop("rubble", 2.8, -153.5, -0.4, 0.65, false, false, 0.0)

	# Flanking stone boundary blocks before the crypt steps.
	road._prop("rubble", -3.2, -159.0, 0.8, 0.85, true, false, 0.5)
	road._prop("rubble", 3.2, -159.0, -0.6, 0.85, true, false, 0.5)

	# Broken funeral bier off the central aisle.
	road._prop("crypt/shrine", -3.2, -156.5, 0.1, 2.2, true, false, 1.0)
	road._prop("crypt/corpse", -2.2, -156.0, 1.8, 0.5, false, false, 0.0)
	road._prop("bones", -2.0, -157.0, 0.2, 0.35, false, false, 0.0)

	# Fallen elite wardens at the foot of the crypt portal steps.
	road._prop("crypt/corpse", -1.8, -162.0, 0.4, 0.5, false, false, 0.0)
	road._prop("crypt/corpse", 1.8, -162.2, -0.9, 0.5, false, false, 0.0)

	# Ceremonial burial braziers on the forecourt terrace flanking the crypt portal steps.
	var left_brazier: Node3D = road._prop("brazier", -4.5, -161.0, 0.0, 1.5, true, true, 0.8)
	road._light(left_brazier, Color(1.0, 0.5, 0.18), 1.8, 8.0, 1.4)
	var right_brazier: Node3D = road._prop("brazier", 4.5, -161.0, 0.0, 1.5, true, true, 0.8)
	road._light(right_brazier, Color(1.0, 0.5, 0.18), 1.8, 8.0, 1.4)

	# Gnarled dead trees framing the outer forecourt terrace boundary.
	road._prop("dead_tree", -17.0, -157.0, 0.4, 6.5, true, false, 1.5)
	road._prop("dead_tree", 17.0, -157.0, -0.3, 6.5, true, false, 1.5)

## Tactical flank cover corridors (Western mortuary shelter & Eastern ossuary colonnade).
static func _build_flank_corridors(road: CryptRoad) -> void:
	# Waist-high cover boulder screening the western mortuary approach against central line of sight.
	road._prop("rubble", -7.5, -149.5, 0.3, 0.9, true, false, 0.6)

	# Waist-high cover boulder on the eastern ossuary flank.
	road._prop("rubble", 7.5, -149.5, -0.4, 0.9, true, false, 0.6)
