class_name WaystationEncounter
extends RefCounted
## Authored encounter beat on Crypt Road: the Hearthward Waystation / Ruined Tollpost.
## Located at z = 142..118 on Crypt Road, bridging Last Hearth's gate and the ruined road content.
##
## Features:
##   - Ruined stone tollhouse on the east flank with an ember brazier and fallen watchman storytelling.
##   - Breached central road barricade (palisades, wrecked cart, barrels) creating a direct frontal funnel.
##   - Clear western flank bypass ditch offering line-of-sight cover against the tollhouse sentry.
##   - Balanced combat encounter: barricade defenders, tollhouse spitter lookout, and a flank roamer.

const CENTER_Z := 127.0
const BOUNDS_Z_MIN := 118.0
const BOUNDS_Z_MAX := 142.0
const BOUNDS_X_MIN := -18.0
const BOUNDS_X_MAX := 18.0

## Places the waystation architectural props, barricades, dressing, and lighting.
static func build(road: CryptRoad, arena: Arena) -> void:
	_build_approach_silhouettes(road)
	_build_tollhouse(road)
	_build_road_barricade(road)
	_build_flank_lane(road)

## Populates the waystation encounter groups.
## All enemies are placed at z <= 132 so they are > 18 m from the player start (z = 150).
static func spawn_encounters(road: CryptRoad, director: RunDirector) -> void:
	# Group 1: Barricade defenders holding the breached road gate.
	# 1 ghoul scavenger (3 pack copies) and 1 watchman zombie (3 pack copies) = 6 monsters.
	road._group(1, "wander", [
		["ghoul", 1.8, 126.2],
		["zombie", 3.8, 127.8]
	], Vector2(2.5, 127.0), 3.5, Vector2.ZERO, [
		Vector2(1.5, 129.5),
		Vector2(3.5, 125.5),
		Vector2(0.8, 126.0)
	])

	# Group 20: Tollhouse interior sentry and lookout.
	# 1 spitter lookout (1 copy) covering the frontal approach + 1 interior zombie (3 pack copies) = 4 monsters.
	road._group(20, "", [
		["spitter", 9.5, 128.0],
		["zombie", 12.5, 125.5]
	], Vector2(11.0, 127.0), 2.5)

	# Group 21: Western flank roamer stalking the ditch bypass.
	# 1 ghoul prowler (3 pack copies) = 3 monsters.
	road._group(21, "wander", [
		["ghoul", -10.0, 127.0]
	], Vector2(-10.0, 127.0), 4.0, Vector2.ZERO, [
		Vector2(-9.5, 133.0),
		Vector2(-10.5, 122.0)
	])

## Roadside approach silhouettes and early visual cues visible from z = 150.
static func _build_approach_silhouettes(road: CryptRoad) -> void:
	# Shattered roadside lamp post marking the former maintained boundary.
	road._prop("lamp_post", 6.0, 138.0, 0.2, 3.8, true, false, 0.8)
	# Heavy stone milestone / trail marker on the west verge.
	road._prop("rubble", -2.8, 139.5, 0.5, 1.1, true, false, 0.8)
	# Abandoned supply barrel fallen off a wagon near the approach.
	road._prop("barrel", 1.2, 141.0, 0.3, 0.95, true, false, 0.5)

## The ruined stone tollhouse on the east flank (x = 6..16, z = 122..134).
static func _build_tollhouse(road: CryptRoad) -> void:
	# North and East walls: sturdy defensive masonry that survived collapse.
	road._prop("ruined_wall", 10.5, 122.5, 0.0, 2.7, true, false, 1.8)
	road._prop("ruined_wall", 15.0, 127.0, PI * 0.5, 2.8, true, false, 1.8)
	# South wall of the main hall.
	road._prop("ruined_wall", 11.5, 132.5, 0.0, 2.5, true, false, 1.8)

	# Front western threshold facing the road: two ruined pillars framing a wide breach.
	road._prop("ruined_pillar", 6.8, 123.5, 0.1, 3.8, true, false, 1.2)
	road._prop("ruined_pillar", 7.2, 131.5, -0.2, 3.5, true, false, 1.2)
	# Low collapsed masonry at the threshold providing partial visual debris.
	road._prop("rubble", 7.0, 128.5, 1.2, 0.65, false, false, 0.0)

	# Interior storytelling and atmospheric props:
	# 1. Smouldering brazier casting low warm amber light and deep shadows.
	var brazier: Node3D = road._prop("brazier", 11.0, 124.2, 0.0, 1.4, true, true, 0.8)
	road._light(brazier, Color(1.0, 0.55, 0.2), 1.8, 7.5, 1.3)

	# 2. Slumped road watchman corpse against the back wall.
	road._prop("crypt/corpse", 13.2, 129.5, 0.8, 0.5, false, false, 0.0)

	# 3. Weathered toll bulletin board listing long-ignored road taxes and bounties.
	road._prop("bulletin_board", 14.2, 124.8, -0.35, 2.2, true, false, 0.8)

	# 4. Old iron-banded toll chest forced open and looted.
	road._prop("stash_chest", 12.8, 130.8, 0.45, 1.0, true, false, 0.6)

	# 5. Breakable supply barrels tucked in the corner.
	road._prop("barrel", 13.8, 123.2, 1.1, 1.0, true, false, 0.5)
	road._prop("barrel", 14.4, 127.8, -0.6, 1.0, true, false, 0.5)

	# 6. Horse water trough outside the south wall for passing wayfarers.
	road._prop("town/water_trough", 8.0, 134.5, -0.25, 1.1, true, false, 0.8)

## Central road barricade (z = 126..130) with a readable 2.5 m breached passage.
static func _build_road_barricade(road: CryptRoad) -> void:
	# East barricade wing: heavy palisade reinforced with an overturned baggage cart.
	road._prop("palisade", 3.4, 128.5, -0.15, 2.4, true, false, 1.2)
	road._prop("wrecked_cart", 3.2, 126.2, 1.85, 1.8, true, false, 1.2)
	road._prop("barrel", 2.5, 130.2, 0.4, 1.0, true, false, 0.5)

	# Breached road passage: clear walkable lane centered around x = 0.0..1.5 at z = 127.5.
	# Splintered debris and a fallen casualty tell the story of the breach.
	road._prop("rubble", 1.8, 128.5, 0.7, 0.55, false, false, 0.0)
	road._prop("crypt/corpse", -0.2, 126.8, 2.1, 0.5, false, false, 0.0)

	# West barricade wing: palisade and reinforcing timber wood pile.
	road._prop("palisade", -3.5, 127.5, 0.1, 2.4, true, false, 1.4)
	road._prop("barrel", -2.2, 129.0, 1.3, 1.0, true, false, 0.5)
	road._prop("town/wood_pile", -5.2, 128.5, 0.35, 1.3, true, false, 1.1)

## Western flank bypass lane (x = -8..-16, z = 120..136).
static func _build_flank_lane(road: CryptRoad) -> void:
	# Outer palisade segment anchoring the western edge of the ditch trail.
	road._prop("palisade", -13.5, 128.0, -0.2, 2.3, true, false, 1.4)
	# Weathered iron boundary fence section running north-south on the far verge.
	road._prop("crypt/iron_fence", -16.0, 126.0, PI * 0.5, 1.8, true, false, 1.2)
	# Old boundary trees framing the flank path.
	road._prop("dead_tree", -18.5, 132.0, 0.0, 6.2, true, false, 1.5)
	road._prop("dead_tree", -17.5, 122.0, 0.6, 5.8, true, false, 1.5)
	# Mossy fallen boulder providing partial cover along the flank trail.
	road._prop("rubble", -11.0, 131.0, -0.4, 0.85, true, false, 0.6)
