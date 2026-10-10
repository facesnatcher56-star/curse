class_name PilgrimCampEncounter
extends RefCounted
## Authored encounter beat on Crypt Road: The Burned Pilgrim Camp.
## Located at z = 108..92 on Crypt Road, distinct from the Hearthward Waystation (z = 142..118)
## and preceding the ancient graveyard / ruined cottage (z = 94..45).
##
## Environmental Storytelling:
##   A desperate group of refugees and pilgrims fleeing Last Hearth with their baggage carts,
##   provisions, and family belongings made a hasty encampment beside the road. Overwhelmed
##   by the spreading blight, their camp was overrun, wagons burned, and supplies looted.
##
## Tactical Features:
##   - Direct road passage (centered x = -0.5..+2.2, z = 108..92) completely open for navigation.
##   - Burned baggage wagon and spilled crates on the eastern verge providing cover.
##   - Extinguished firepit with smouldering orange embers and huddled refugee casualties.
##   - Makeshift cloth shelter tents and drying racks on the western verge.
##   - Roadside wayside shrine with candle glow where pilgrims offered their final prayers.
##   - Western flank bypass trail through the tents/wood pile offering tactical flanking and line-of-sight cover.
##   - Balanced ambush encounter: feeding pack (zombies + ghoul), western flank ambushers (spitter + ghouls),
##     and eastern wagon scavenger.

const CENTER_Z := 100.0
const BOUNDS_Z_MIN := 92.0
const BOUNDS_Z_MAX := 108.0
const BOUNDS_X_MIN := -18.0
const BOUNDS_X_MAX := 18.0

## Places the pilgrim camp architecture, burned wagons, shelters, firepit, shrine, and atmospheric props.
static func build(road: CryptRoad, arena: Arena) -> void:
	_build_approach_silhouettes(road)
	_build_burned_wagons(road)
	_build_refugee_camp(road)
	_build_wayside_shrine(road)
	_build_flank_cover(road)

## Populates the pilgrim camp encounter groups.
## All enemies are placed at z <= 106 so they are >= 44 m from the player start (z = 150).
static func spawn_encounters(road: CryptRoad, director: RunDirector) -> void:
	# Group 2: The Feeding Pack (Center Firepit & Overturned Wagon).
	# Feeding on fallen refugees; distracted until the player enters aggro range.
	# 2 placed zombies (3 pack copies each = 6 zombies) + 1 placed ghoul (3 pack copies = 3 ghouls) = 9 enemies.
	# Mode "feed" satisfies Crypt Road feeding pack expectations (e.g. self-test feeder checks).
	road._group(2, "feed", [
		["zombie", -3.6, 101.2],
		["zombie", -5.2, 99.8],
		["ghoul", 3.8, 103.8]
	], Vector2(-3.0, 101.0), 3.5, Vector2(-4.5, 100.8))

	# Group 22: Western Flank Ambushers (Tents & Outer Woods).
	# 1 spitter lookout (1 copy) behind tent cover + 1 roaming ghoul (3 pack copies = 3 ghouls) = 4 enemies.
	road._group(22, "wander", [
		["spitter", -11.0, 98.0],
		["ghoul", -8.5, 95.5]
	], Vector2(-10.0, 97.0), 4.0, Vector2.ZERO, [
		Vector2(-10.5, 103.0),
		Vector2(-12.0, 97.0),
		Vector2(-8.0, 94.0)
	])

	# Group 23: Eastern Wagon Scavengers.
	# 1 placed zombie scavenger (3 pack copies = 3 zombies) picking through luggage debris.
	road._group(23, "wander", [
		["zombie", 7.8, 97.5]
	], Vector2(7.5, 98.0), 3.5, Vector2.ZERO, [
		Vector2(6.5, 101.0),
		Vector2(8.5, 96.0)
	])

## Silhouettes visible when approaching north along the road from z = 114..108.
static func _build_approach_silhouettes(road: CryptRoad) -> void:
	# Abandoned supply barrel fallen off a fleeing cart near the approach.
	road._prop("barrel", 1.8, 107.0, 0.4, 0.95, true, false, 0.5)
	# Low milestone rubble on the western verge marking distance from Last Hearth.
	road._prop("rubble", -3.8, 107.5, 0.8, 0.75, false, false, 0.0)
	# Fallen refugee casualty on the approach road verge.
	road._prop("crypt/corpse", -2.8, 106.0, 1.1, 0.5, false, false, 0.0)

## Overturned baggage carts and spilled cargo along the eastern verge (x = 3.5..12.0, z = 105..96).
static func _build_burned_wagons(road: CryptRoad) -> void:
	# Primary burned baggage wagon tilted on the road verge.
	road._prop("wrecked_cart", 4.8, 104.5, 0.65, 1.9, true, false, 1.3)
	# Spilled wooden cargo crates from the overturned cart.
	road._prop("town/crate_stack", 7.0, 105.0, -0.3, 1.25, true, false, 0.8)
	# Scattered supply barrels (destructible).
	road._prop("barrel", 3.5, 102.5, 0.8, 1.0, true, false, 0.5)
	road._prop("barrel", 6.2, 103.2, 2.1, 0.9, true, false, 0.5)
	# Refugee casualty beside the baggage cart.
	road._prop("crypt/corpse", 5.2, 103.0, 2.4, 0.5, false, false, 0.0)

	# Secondary supply cart on the eastern verge near the tree line.
	road._prop("wrecked_cart", 8.5, 97.0, 2.3, 1.75, true, false, 1.2)
	# Broken palisade stake line screening the eastern wood.
	road._prop("palisade", 11.0, 101.0, 0.2, 2.2, true, false, 1.2)
	# Dead tree anchoring the eastern verge.
	road._prop("dead_tree", 13.5, 104.0, 0.0, 5.8, true, false, 1.5)

## The refugee encampment on the western verge: firepit, cloth shelters, and civilian remains (x = -4.0..-14.0, z = 104..94).
static func _build_refugee_camp(road: CryptRoad) -> void:
	# Extinguished central campfire with smouldering embers.
	var firepit: Node3D = road._prop("brazier", -4.8, 100.8, 0.0, 1.3, true, true, 0.8)
	road._light(firepit, Color(1.0, 0.48, 0.18), 1.5, 7.0, 1.2)

	# Stone ring / rubble debris framing the firepit.
	road._prop("rubble", -3.8, 101.5, 1.2, 0.55, false, false, 0.0)
	# Refugee casualties huddled around the dying embers.
	road._prop("crypt/corpse", -5.8, 100.2, 0.5, 0.5, false, false, 0.0)
	road._prop("crypt/corpse", -4.2, 99.2, -1.2, 0.5, false, false, 0.0)

	# Firewood logs gathered for the night.
	road._prop("town/wood_pile", -6.8, 103.0, 0.4, 1.2, true, false, 1.0)

	# Makeshift refugee tent shelter (fabric canopy on timber posts).
	road._prop("market_stall", -9.2, 100.5, -0.25, 2.4, true, false, 1.4)
	# Casualty under the makeshift shelter.
	road._prop("crypt/corpse", -9.5, 99.2, 1.8, 0.5, false, false, 0.0)

	# Stacked refugee luggage and travel trunks.
	road._prop("town/crate_stack", -11.2, 102.5, 0.3, 1.3, true, false, 0.8)
	# Ransacked travel chest.
	road._prop("stash_chest", -8.5, 102.0, 0.7, 0.95, true, false, 0.6)
	# Breakable supply barrel near the shelter.
	road._prop("barrel", -6.5, 99.5, 1.4, 1.0, true, false, 0.5)

## Roadside wayside shrine where fleeing pilgrims made their final prayers (x = -2.5..-4.0, z = 95.5..94.0).
static func _build_wayside_shrine(road: CryptRoad) -> void:
	# Modest wooden/stone roadside shrine.
	var shrine: Node3D = road._prop("crypt/shrine", -3.2, 95.2, 0.15, 2.3, true, false, 1.2)
	road._light(shrine, Color(1.0, 0.68, 0.32), 1.3, 5.5, 1.4)

	# Praying pilgrim casualty slumped at the foot of the altar.
	road._prop("crypt/corpse", -2.2, 94.6, 3.0, 0.5, false, false, 0.0)
	# Scattered bone fragments near the shrine.
	road._prop("bones", -1.5, 95.8, 0.5, 0.35, false, false, 0.0)

## Western flank bypass trail and tactical cover line (x = -10.0..-16.0, z = 106..93).
static func _build_flank_cover(road: CryptRoad) -> void:
	# Tanned hide drying rack acting as a canvas windbreak / sightline cover.
	road._prop("town/drying_rack", -7.8, 97.5, 0.6, 1.7, true, false, 0.8)
	# Outer perimeter palisade stake section.
	road._prop("palisade", -14.5, 101.5, 0.1, 2.2, true, false, 1.2)
	# Border trees enclosing the western flank trail.
	road._prop("dead_tree", -16.5, 105.0, 0.0, 6.0, true, false, 1.5)
	road._prop("dead_tree", -15.5, 95.0, 0.5, 6.2, true, false, 1.5)
	# Fallen boulder / rubble providing tactical waist-high cover on the flank trail.
	road._prop("rubble", -11.5, 96.5, 0.4, 0.9, true, false, 0.7)
