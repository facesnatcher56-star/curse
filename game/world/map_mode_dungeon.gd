class_name MapModeDungeon
extends CryptDungeon
## The dedicated map-mode dungeon (`-- --mapmode`): a graph of rooms joined by corridors, built with the Crypt's GridMap kit and loader. The scene is
## `game/world/dungeons/map_mode_01.tscn`; the plan and the data contract for the node-map UI are in MapModeLayout; how to edit and rebake it is in
## docs/MAP_MODE_DUNGEON.md. This class only names it, captures which group / chest / shrine belongs to which node, and makes the two champion packs
## deterministic.
##
##   node_groups  node id -> Enemy.group_id of the node's pack (combat nodes)
##   node_chests  node id -> Chest
##   node_shrines node id -> Shrine (call use_shrine())

const MAP_SCENE := "res://game/world/dungeons/map_mode_01.tscn"

var node_groups: Dictionary = {}
var node_chests: Dictionary = {}
var node_shrines: Dictionary = {}
var _marker_nodes: Array[int] = []        # the node id of each enemy marker, in the order spawn_encounters walks them
var _marker_champions: Array[Dictionary] = []


static func make_arena() -> Arena:
	var a := Arena.new()
	a.half_x = MapModeLayout.half_x()
	a.half_z = MapModeLayout.half_z()
	a.scatter = false
	return a


func scene_path() -> String:
	return MAP_SCENE


func zone_title() -> String:
	return "The Sunken Way"


func banner_text(_job: Dictionary) -> String:
	return "The Sunken Way\nPick Your Road"


func start_position() -> Vector3:
	if level != null and level.has_node("PlayerStart"):
		return (level.get_node("PlayerStart") as Node3D).global_position
	var start: Vector2 = MapModeLayout.world(MapModeLayout.START_CELL.x, MapModeLayout.START_CELL.y)
	return Vector3(start.x, 0.0, start.y)


## The enemies' level on the way in: stage 0..7 to a level the party can hold at that point (the swarm is the weakest kind, level 1).
const STAGE_LEVELS: Array[int] = [1, 1, 2, 2, 3, 3, 4, 5]

func level_for_node(node_id: int, stage: int) -> int:
	for n in MapModeLayout.nodes():
		if int(n["id"]) == node_id and String(n["kind"]) == "swarm":
			return 1
	return STAGE_LEVELS[clampi(stage, 0, STAGE_LEVELS.size() - 1)]

## The markers are still in the scene and the chests already stand under this node: remember which node is which.
func _scene_read() -> void:
	_marker_nodes.clear()
	_marker_champions.clear()
	for marker in level.get_node("EnemyGroups").get_children():
		if marker is DungeonEnemyGroup:   # the same filter read_groups uses, so the order matches `groups`
			_marker_nodes.append(_node_id(marker))
			_marker_champions.append(marker.get_meta(MapModeLayout.CHAMPION_META, {}) as Dictionary)
	for chest in get_children():
		if chest is Chest and String(chest.name).begins_with("Node"):
			node_chests[_node_id(chest)] = chest
	if level.has_node("Shrines"):
		for marker in level.get_node("Shrines").get_children():
			var shrine := Shrine.new()
			shrine.name = "Shrine%d" % _node_id(marker)
			add_child(shrine)
			shrine.position = (marker as Node3D).position
			node_shrines[_node_id(marker)] = shrine


static func _node_id(node: Node) -> int:
	return int(String(node.name).trim_prefix("Node"))


## Spawns the packs as TestDungeon does, then records each node's group id and gives the two champion packs their champion: the roll is switched off
## while they spawn (so no other pack gets one by chance) and the champions are attached to the kinds the plan names.
func spawn_encounters(for_director: RunDirector) -> void:
	var first_id: int = _enemy_group_id
	for i in _marker_nodes.size():   # levels follow the way in, not the XP the hero would earn clearing every room (a route can skip rooms)
		groups[i]["fixed_level"] = level_for_node(_marker_nodes[i], int(groups[i]["area"]))
	var chance: float = Champion.chance_override
	Champion.chance_override = 0.0
	super.spawn_encounters(for_director)
	Champion.chance_override = chance
	for i in _marker_nodes.size():
		var gid: int = first_id + 1 + i   # TestDungeon.spawn_encounters hands out ids in marker order
		node_groups[_marker_nodes[i]] = gid
		var plan: Dictionary = _marker_champions[i]
		if plan.is_empty():
			continue
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e != null and e.group_id == gid and not e.dead and e.champion == null and e.def != null and e.def.id == String(plan["kind"]):
				Champion.attach(e, String(plan["affix"]))
				break
