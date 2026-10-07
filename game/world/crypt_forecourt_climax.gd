class_name CryptForecourtClimax
extends Node
## Staged encounter climax controller for the Crypt Forecourt on Crypt Road.
## Coordinates the final exterior encounter (Groups 27 Center, 28 East, 29 West)
## into a deliberate 3-stage escalation concluding with the forecourt clear beat.
##
## Staged Flow:
##   1. OPENING: Center Vanguard (Group 27) acts as opening pressure at the crypt portal steps.
##   2. FIRST_FLANK (Stage 1): First flank (Group 28 East Ossuary) joins after center vanguard
##      takes meaningful casualties or combat timer elapses.
##   3. SECOND_FLANK (Stage 2): Second flank (Group 29 West Mortuary) joins as combat escalates.
##   4. CLEARED: When all forecourt enemies are dead, emits "Forecourt secured — the sealed crypt waits."
##
## Rules:
##   - All enemies placed physically from the start; no mid-encounter invisible spawns.
##   - Direct approach and both flank routes remain permanently traversable.
##   - Clear state fires exactly once.

signal stage_changed(new_stage: Stage)
signal encounter_cleared()

enum Stage {
	DORMANT = 0,
	OPENING = 1,
	FIRST_FLANK = 2,
	SECOND_FLANK = 3,
	CLEARED = 4,
}

const GROUP_CENTER: int = 27
const GROUP_EAST: int = 28
const GROUP_WEST: int = 29

const FORECOURT_ENTRY_Z: float = -146.0
const CLEAR_BANNER_TEXT: String = "Forecourt secured — the sealed crypt waits."
const CLEAR_BANNER_DURATION: float = 4.0

const STAGE_1_FALLBACK_TIMER: float = 12.0
const STAGE_2_FALLBACK_TIMER: float = 10.0
const STAGE_1_CENTER_CASUALTY_THRESHOLD: int = 4  # <= 4 alive in center group triggers flank 1
const STAGE_2_CENTER_CASUALTY_THRESHOLD: int = 2  # <= 2 alive in center group triggers flank 2
const STAGE_2_TOTAL_CASUALTY_THRESHOLD: int = 6   # <= 6 total alive triggers flank 2

var current_stage: Stage = Stage.DORMANT
var auto_progress: bool = true

var road: CryptRoad
var director: RunDirector

var first_flank_group: int = GROUP_EAST
var second_flank_group: int = GROUP_WEST

var _center_enemies: Array[Enemy] = []
var _first_flank_enemies: Array[Enemy] = []
var _second_flank_enemies: Array[Enemy] = []
var _all_forecourt_enemies: Array[Enemy] = []

var _saved_aggro_ranges: Dictionary = {}
var _stage_timer: float = 0.0
var _cleared: bool = false
var _clear_event_fired_count: int = 0

func setup(p_road: CryptRoad, p_director: RunDirector) -> void:
	road = p_road
	director = p_director
	_collect_and_stage_enemies()

func _collect_and_stage_enemies() -> void:
	_center_enemies.clear()
	_first_flank_enemies.clear()
	_second_flank_enemies.clear()
	_all_forecourt_enemies.clear()
	_saved_aggro_ranges.clear()

	var nodes: Array = get_tree().get_nodes_in_group("enemies")
	for node in nodes:
		var e := node as Enemy
		if e == null:
			continue
		if e.group_id == GROUP_CENTER:
			_center_enemies.append(e)
			_all_forecourt_enemies.append(e)
			_saved_aggro_ranges[e] = e.aggro_range
			e.aggro_range = 0.0
			if not e.died.is_connected(_on_enemy_died):
				e.died.connect(_on_enemy_died)
		elif e.group_id == first_flank_group:
			_first_flank_enemies.append(e)
			_all_forecourt_enemies.append(e)
			_saved_aggro_ranges[e] = e.aggro_range
			e.aggro_range = 0.0
			if not e.died.is_connected(_on_enemy_died):
				e.died.connect(_on_enemy_died)
		elif e.group_id == second_flank_group:
			_second_flank_enemies.append(e)
			_all_forecourt_enemies.append(e)
			_saved_aggro_ranges[e] = e.aggro_range
			e.aggro_range = 0.0
			if not e.died.is_connected(_on_enemy_died):
				e.died.connect(_on_enemy_died)

func _physics_process(delta: float) -> void:
	if _cleared or not auto_progress:
		return

	var player: Player = _get_player()

	match current_stage:
		Stage.DORMANT:
			if player != null and player.global_position.z <= FORECOURT_ENTRY_Z:
				activate_opening()
			elif _has_any_aggro_or_damage(_center_enemies):
				activate_opening()
			elif _has_any_aggro_or_damage(_first_flank_enemies):
				activate_opening()
				trigger_stage_1()
			elif _has_any_aggro_or_damage(_second_flank_enemies):
				activate_opening()
				trigger_stage_2()

		Stage.OPENING:
			_stage_timer += delta
			var center_alive: int = get_alive_count(GROUP_CENTER)
			if center_alive <= STAGE_1_CENTER_CASUALTY_THRESHOLD or _stage_timer >= STAGE_1_FALLBACK_TIMER or _has_any_aggro_or_damage(_first_flank_enemies):
				trigger_stage_1()
			elif _has_any_aggro_or_damage(_second_flank_enemies):
				trigger_stage_2()

		Stage.FIRST_FLANK:
			_stage_timer += delta
			var center_alive: int = get_alive_count(GROUP_CENTER)
			var total_alive: int = get_total_alive_count()
			if center_alive <= STAGE_2_CENTER_CASUALTY_THRESHOLD or total_alive <= STAGE_2_TOTAL_CASUALTY_THRESHOLD or _stage_timer >= STAGE_2_FALLBACK_TIMER or _has_any_aggro_or_damage(_second_flank_enemies):
				trigger_stage_2()

		Stage.SECOND_FLANK:
			if get_total_alive_count() == 0:
				complete_encounter()

func activate_opening() -> void:
	if current_stage >= Stage.OPENING:
		return
	current_stage = Stage.OPENING
	_stage_timer = 0.0
	_wake_group_list(_center_enemies)
	stage_changed.emit(Stage.OPENING)

func trigger_stage_1() -> void:
	if current_stage < Stage.OPENING:
		activate_opening()
	if current_stage >= Stage.FIRST_FLANK:
		return
	current_stage = Stage.FIRST_FLANK
	_stage_timer = 0.0
	_wake_group_list(_first_flank_enemies)
	stage_changed.emit(Stage.FIRST_FLANK)

func trigger_stage_2() -> void:
	if current_stage < Stage.FIRST_FLANK:
		trigger_stage_1()
	if current_stage >= Stage.SECOND_FLANK:
		return
	current_stage = Stage.SECOND_FLANK
	_stage_timer = 0.0
	_wake_group_list(_second_flank_enemies)
	stage_changed.emit(Stage.SECOND_FLANK)

func complete_encounter() -> void:
	if _cleared:
		return
	if get_total_alive_count() > 0:
		return
	_cleared = true
	_clear_event_fired_count += 1
	current_stage = Stage.CLEARED
	stage_changed.emit(Stage.CLEARED)
	encounter_cleared.emit()
	if road != null and road.return_waystone != null:
		road.return_waystone.reveal()
	TownState.report_forecourt_cleared(CryptRoad.SITE_ID)
	if director != null and director.hud != null:
		director.hud.show_banner(CLEAR_BANNER_TEXT, CLEAR_BANNER_DURATION)
	set_physics_process(false)

func _wake_group_list(enemies: Array[Enemy]) -> void:
	# Restore stored aggro ranges first so mates alerting each other have proper perception.
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			if _saved_aggro_ranges.has(e):
				e.aggro_range = float(_saved_aggro_ranges[e])
	# Wake all living members.
	for e in enemies:
		if is_instance_valid(e) and not e.dead and not e.is_aggro():
			e.alert_delay = 0.0
			e.wake()

func _on_enemy_died(_enemy: Enemy) -> void:
	if _cleared:
		return
	if not auto_progress:
		return
	match current_stage:
		Stage.OPENING:
			if get_alive_count(GROUP_CENTER) <= STAGE_1_CENTER_CASUALTY_THRESHOLD:
				trigger_stage_1()
		Stage.FIRST_FLANK:
			if get_alive_count(GROUP_CENTER) <= STAGE_2_CENTER_CASUALTY_THRESHOLD or get_total_alive_count() <= STAGE_2_TOTAL_CASUALTY_THRESHOLD:
				trigger_stage_2()
		Stage.SECOND_FLANK:
			if get_total_alive_count() == 0:
				complete_encounter()

func _has_any_aggro_or_damage(enemies: Array[Enemy]) -> bool:
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			if e.is_aggro() or e.health < e.max_health:
				return true
	return false

func _get_player() -> Player:
	if director != null and director.player != null:
		return director.player
	var nodes: Array = get_tree().get_nodes_in_group("player")
	if not nodes.is_empty():
		return nodes[0] as Player
	return null

func get_alive_count(gid: int) -> int:
	var count: int = 0
	var list: Array[Enemy] = get_group_enemies(gid)
	for e in list:
		if is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion():
			count += 1
	return count

func get_total_alive_count() -> int:
	var count: int = 0
	for e in _all_forecourt_enemies:
		if is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion():
			count += 1
	return count

func get_total_count() -> int:
	return _all_forecourt_enemies.size()

func get_group_enemies(gid: int) -> Array[Enemy]:
	var result: Array[Enemy] = []
	match gid:
		GROUP_CENTER:
			result.append_array(_center_enemies)
		first_flank_group:
			result.append_array(_first_flank_enemies)
		second_flank_group:
			result.append_array(_second_flank_enemies)
	return result

func is_group_active(gid: int) -> bool:
	var list: Array[Enemy] = get_group_enemies(gid)
	var any_alive: bool = false
	for e in list:
		if is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion():
			any_alive = true
			if e.is_aggro():
				return true
	return false

func get_active_groups() -> Array[int]:
	var result: Array[int] = []
	if is_group_active(GROUP_CENTER):
		result.append(GROUP_CENTER)
	if is_group_active(first_flank_group):
		result.append(first_flank_group)
	if is_group_active(second_flank_group):
		result.append(second_flank_group)
	return result

func is_cleared() -> bool:
	return _cleared

func get_clear_event_fired_count() -> int:
	return _clear_event_fired_count
