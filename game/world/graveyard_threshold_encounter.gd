class_name GraveyardThresholdEncounter
extends RefCounted
## Authored encounter beat on Crypt Road: The Broken Funeral Procession / Graveyard Threshold.
## Located at z = 89..73 on Crypt Road (centered around z = 81), distinct from the Burned Pilgrim Camp
## (z = 108..92) and directly introducing the ancient graveyard (z = 94..45) and ruined cottage.
##
## Environmental Storytelling:
##   Before the road was completely lost to the dark curse, a solemn funeral procession or burial
##   detail attempted to convey their dead to the ancient graveyard. Caught in the open just outside
##   the iron threshold gates, the procession was overrun. The funeral hearse wagon was tipped and
##   desecrated, burial caskets spilled, pallbearers and mourners slaughtered, and shallow fresh
##   graves begun outside the consecrated grounds left abandoned with disturbed markers as the dead rose.
##
## Tactical Features:
##   - Direct road passage (centered x = -0.5..+2.0, z = 89..73) permanently open and clear for navigation.
##   - Broken funeral hearse wagon and spilled burial casket on the eastern verge providing heavy cover.
##   - Shallow disturbed burial trench with toppled grave markers and churned soil on the western verge.
##   - Mourning shrine with warm candle light and fallen mourners marking the threshold.
##   - Western cemetery detour trail weaving behind toppled grave slabs and iron gateposts for ranged cover.
##   - Compact escalation encounter: hearse pack (risen pallbearer zombies + scavenger ghoul),
##     cemetery threshold lookout (watchful spitter + grave zombie), and flank prowler ghoul.

const CENTER_Z := 81.0
const BOUNDS_Z_MIN := 73.0
const BOUNDS_Z_MAX := 89.0
const BOUNDS_X_MIN := -16.0
const BOUNDS_X_MAX := 14.0

## Places the funeral procession landmark, broken hearse, disturbed graves, mourning shrine, and props.
static func build(road: CryptRoad, arena: Arena) -> void:
	_build_approach_silhouettes(road)
	_build_broken_hearse(road)
	_build_disturbed_graves(road)
	_build_mourning_shrine(road)
	_build_flank_corridors(road)

## Populates the graveyard threshold encounter groups.
## All enemies are placed at z <= 85 so they are >= 65 m from player start (z = 150).
static func spawn_encounters(road: CryptRoad, director: RunDirector) -> void:
	# Group 24: Risen Pallbearers & Hearse Pack (Eastern Road Verge & Broken Wagon).
	# 2 placed zombies (pallbearers, 3 pack copies = 6 zombies) + 1 placed ghoul (3 pack copies = 3 ghouls) = 9 enemies.
	# Mode "wander": picking through the shattered casket and spilled wagon cargo.
	road._group(24, "wander", [
		["zombie", 3.2, 82.5],
		["zombie", 5.0, 84.0],
		["ghoul", 4.2, 81.2]
	], Vector2(4.0, 82.5), 3.5, Vector2.ZERO, [
		Vector2(3.0, 84.5),
		Vector2(5.5, 82.0),
		Vector2(3.8, 80.5)
	])

	# Group 25: Cemetery Threshold Lookout (Western Verge & Disturbed Trench).
	# 1 spitter lookout (1 copy) stationed at z = 83.5 behind grave marker cover + 1 zombie gravedigger (3 pack copies = 3 zombies) = 4 enemies.
	# Placed at z = 83.5 (> 80.0) so it does not interfere with cottage spitter test checks in dev_harness.
	road._group(25, "", [
		["spitter", -6.2, 83.5],
		["zombie", -4.5, 82.0]
	], Vector2(-5.5, 83.0), 3.0)

	# Group 26: Graveyard Flank Prowler (Threshold Shrine & Cemetery Trail).
	# 1 placed ghoul (3 pack copies = 3 ghouls) stalking the western detour route.
	road._group(26, "wander", [
		["ghoul", -5.5, 76.5]
	], Vector2(-5.0, 76.5), 3.5, Vector2.ZERO, [
		Vector2(-4.0, 78.5),
		Vector2(-6.5, 75.0)
	])

## Silhouettes and markers visible when approaching north along the road from z = 92..87.
static func _build_approach_silhouettes(road: CryptRoad) -> void:
	# Shattered iron mourning lantern post on the east verge.
	road._prop("lamp_post", 4.2, 88.5, 0.35, 3.6, true, false, 0.8)
	# Roadside stone rubble milestone framing the approach.
	road._prop("rubble", -2.8, 88.0, 0.75, 0.8, false, false, 0.0)
	# Fallen escort casualty sprawled on the road verge.
	road._prop("crypt/corpse", 2.2, 87.0, 1.8, 0.5, false, false, 0.0)
	# Scattered funeral bones.
	road._prop("bones", 1.0, 88.5, 0.4, 0.35, false, false, 0.0)

## The broken funeral hearse wagon and spilled burial casket on the eastern verge (x = 2.8..8.0, z = 85.5..80.5).
static func _build_broken_hearse(road: CryptRoad) -> void:
	# Primary funeral hearse wagon tilted off the road verge.
	road._prop("wrecked_cart", 4.4, 83.2, 0.82, 1.9, true, false, 1.3)
	# Spilled burial chest / iron-banded casket thrown from the cart bed.
	road._prop("stash_chest", 6.0, 84.0, -0.4, 0.95, true, false, 0.6)
	# Heavy stone grave slab tilted against the hearse wreckage.
	road._prop("gravestone", 3.2, 84.6, 1.15, 0.35, true, false, 0.0)
	# Overturned funeral brazier casting low ember glow.
	var brazier: Node3D = road._prop("brazier", 5.2, 81.8, 0.0, 1.35, true, true, 0.8)
	road._light(brazier, Color(1.0, 0.52, 0.2), 1.6, 7.5, 1.25)
	# Pallbearer casualties collapsed near the hearse wheels.
	road._prop("crypt/corpse", 3.6, 82.2, 2.1, 0.5, false, false, 0.0)
	road._prop("crypt/corpse", 5.5, 81.2, -0.75, 0.5, false, false, 0.0)
	# Destructible funeral barrels (burial oils and embalming supplies).
	road._prop("barrel", 2.8, 81.6, 0.5, 1.0, true, false, 0.5)
	road._prop("barrel", 6.4, 82.8, 1.7, 0.95, true, false, 0.5)
	# Shattered timber beams from the cart.
	road._prop("town/wood_pile", 7.0, 84.8, 0.3, 1.15, true, false, 0.9)
	# Dead tree anchoring the eastern verge.
	road._prop("dead_tree", 9.8, 82.0, 0.2, 6.0, true, false, 1.5)

## Disturbed shallow graves and toppled markers outside consecrated ground (x = -3.2..-8.5, z = 85.0..79.0).
static func _build_disturbed_graves(road: CryptRoad) -> void:
	# Tilted headstones and grave slabs sinking into disturbed dirt.
	road._prop("gravestone", -4.5, 83.8, PI + 0.3, 0.32, true, false, 0.0)
	road._prop("gravestone", -6.2, 82.4, PI - 0.25, 0.35, true, false, 0.0)
	road._prop("gravestone", -5.0, 80.5, 0.45, 0.3, true, false, 0.0)
	# Churned soil and stone rubble mounds from the shallow burial pits.
	road._prop("rubble", -3.8, 84.4, 0.6, 0.7, false, false, 0.0)
	road._prop("rubble", -5.8, 81.5, 1.35, 0.85, true, false, 0.5)
	# Slumped gravedigger / unburied corpse in the shallow pit.
	road._prop("crypt/corpse", -5.2, 82.8, 1.5, 0.5, false, false, 0.0)
	# Scattered bone fragments from the disturbed earth.
	road._prop("bones", -3.6, 82.0, 0.8, 0.35, false, false, 0.0)
	road._prop("bones", -6.8, 83.5, -0.5, 0.35, false, false, 0.0)
	# Embalming / lime barrel near the pit.
	road._prop("barrel", -3.2, 80.6, 0.3, 0.95, true, false, 0.5)

## Wayside mourning shrine and threshold boundary markers (x = -2.5..-10.5, z = 78.5..74.0).
static func _build_mourning_shrine(road: CryptRoad) -> void:
	# Wayside mourning shrine where final rites and prayers were spoken.
	var shrine: Node3D = road._prop("crypt/shrine", -3.5, 76.5, 0.2, 2.4, true, false, 1.2)
	road._light(shrine, Color(1.0, 0.65, 0.3), 1.4, 6.0, 1.3)
	# Slumped mourner casualty at the shrine foot.
	road._prop("crypt/corpse", -2.4, 75.8, 2.8, 0.5, false, false, 0.0)
	# Offerings and bone relics beside the altar.
	road._prop("bones", -1.8, 76.8, 0.3, 0.35, false, false, 0.0)
	# Cemetery boundary gate pillar and iron railings framing the threshold into the ancient graveyard.
	road._prop("ruined_pillar", -8.2, 78.5, 0.0, 3.4, true, false, 1.0)
	road._prop("crypt/iron_fence", -10.2, 77.0, PI * 0.45, 1.8, true, false, 1.0)
	# Low collapsed masonry rubble near the gatepost.
	road._prop("rubble", -7.5, 75.5, -0.6, 0.9, true, false, 0.6)
	# Ancient cypress / dead tree overhanging the threshold.
	road._prop("dead_tree", -12.5, 78.0, 0.7, 6.2, true, false, 1.5)

## Flank trails and cover angles (Western cemetery detour & Eastern hearse shoulder).
static func _build_flank_corridors(road: CryptRoad) -> void:
	# Tactical waist-high boulder on the western trail providing cover against spitter line of sight.
	road._prop("rubble", -7.8, 82.0, 0.4, 0.85, true, false, 0.6)
	# Eastern verge screening rubble near the cottage approach.
	road._prop("rubble", 7.8, 77.5, 0.85, 0.9, true, false, 0.6)
