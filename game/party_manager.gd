class_name PartyManager
extends RefCounted
## One party, common member data, and live control routing. No combat formulas live here.

signal active_member_changed(previous_id: String, member_id: String)
signal controller_active_changed(controller_id: String, previous_id: String, member_id: String)
const MAX_MEMBERS := 6

static var instance: PartyManager
var members: Dictionary = {}
var bodies: Dictionary = {}
var backpack: Array[Dictionary] = []
## Controller IDs are runtime input authorities, not persistent character owners.
var local_controller_id: String = "local"
var subgroups: Dictionary = {"local": ["hero", "cutter"]}
var active_by_controller: Dictionary = {"local": "hero"}
var active_id: String:
	get: return String(active_by_controller.get(local_controller_id, ""))
	set(value): active_by_controller[local_controller_id] = value
var gold: int:
	get: return TownState.gold
	set(value): TownState.gold = value
var food: int:
	get: return TownState.food
	set(value): TownState.food = value
var potions: int:
	get: return TownState.potions
	set(value): TownState.potions = value
var mana_potions: int:
	get: return TownState.mana_potions
	set(value): TownState.mana_potions = value

static func current() -> PartyManager:
	if instance == null:
		instance = PartyManager.new()
	return instance

func member(member_id: String = "hero") -> CharacterState:
	if not members.has(member_id):
		if members.size() >= MAX_MEMBERS:
			push_error("Party capacity exceeded")
			return null
		members[member_id] = CharacterState.new(member_id)
	return members[member_id]

func add_member(record: CharacterState) -> bool:
	if record == null or record.id == "" or members.has(record.id) or members.size() >= MAX_MEMBERS: return false
	members[record.id] = record
	return true

func reset(clear_bodies: bool = false) -> void:
	members.clear()
	if clear_bodies: bodies.clear()
	else:
		for id in bodies.keys():
			if not is_instance_valid(bodies[id]): bodies.erase(id)
	backpack.clear()
	local_controller_id = "local"
	subgroups = {"local": ["hero", "cutter"]}
	active_by_controller = {"local": "hero"}
	active_id = "hero"
	member("hero")
	member("cutter")

func active_body(controller_id: String = "") -> Player:
	if controller_id == "": controller_id = local_controller_id
	var body: Variant = bodies.get(active_by_controller.get(controller_id, ""))
	return body as Player if is_instance_valid(body) else null

func living() -> Array[Player]:
	var result: Array[Player] = []
	for body in bodies.values():
		if is_instance_valid(body) and not body.dead: result.append(body)
	return result

## Owner-approved Curse rule, NOT verified DS2 aggregation: living deployed party average.
func loot_bonuses() -> Dictionary:
	var result := {"magic_find": 0.0, "gold_find": 0.0}
	var deployed := living()
	for body in deployed:
		result.magic_find += body.stats.magic_find()
		result.gold_find += body.stats.gear_stat("gold_find")
	if not deployed.is_empty():
		result.magic_find /= deployed.size()
		result.gold_find /= deployed.size()
	return result

func controller_for(member_id: String) -> Dictionary:
	for controller_id in subgroups:
		if member_id in subgroups[controller_id]:
			return {"controller_id": controller_id, "kind": "human" if active_by_controller.get(controller_id, "") == member_id else "ai"}
	return {"controller_id": "", "kind": "ai"}

## Validates the future 1x6 / 2x3 / 3x2 allocation without creating network controllers.
func assign_subgroups(groups: Dictionary) -> bool:
	if groups.is_empty() or groups.size() > 3: return false
	var maximum: int = MAX_MEMBERS / groups.size()
	var used: Array = []
	for controller_id in groups:
		if not groups[controller_id] is Array or groups[controller_id].size() > maximum: return false
		for id in groups[controller_id]:
			if not members.has(id) or id in used: return false
			used.append(id)
	subgroups = groups.duplicate(true)
	for controller_id in active_by_controller.keys():
		if not subgroups.has(controller_id): active_by_controller.erase(controller_id)
	for controller_id in subgroups:
		if active_by_controller.get(controller_id, "") not in subgroups[controller_id]:
			active_by_controller[controller_id] = subgroups[controller_id][0] if not subgroups[controller_id].is_empty() else ""
	return true

func select(member_id: String, controller_id: String = "") -> bool:
	if controller_id == "": controller_id = local_controller_id
	if member_id not in subgroups.get(controller_id, []): return false
	var body: Variant = bodies.get(member_id)
	if not is_instance_valid(body) or body.dead or active_by_controller.get(controller_id, "") == member_id: return false
	var old: String = String(active_by_controller.get(controller_id, ""))
	var previous := active_body(controller_id)
	if previous != null: previous.release_control()
	active_by_controller[controller_id] = member_id
	body.receive_control()
	controller_active_changed.emit(controller_id, old, member_id)
	if controller_id == local_controller_id: active_member_changed.emit(old, member_id)
	return true

func cycle(controller_id: String = "") -> void:
	if controller_id == "": controller_id = local_controller_id
	var group: Array = subgroups.get(controller_id, [])
	if group.is_empty(): return
	var index := group.find(active_by_controller.get(controller_id, ""))
	for offset in range(1, group.size() + 1):
		if select(String(group[(index + offset) % group.size()]), controller_id): return

func to_dict() -> Dictionary:
	for body in bodies.values():
		if is_instance_valid(body): body.capture_state()
	var saved: Dictionary = {}
	for member_id in members: saved[member_id] = member(member_id).to_dict()
	var bag: Array = []
	for item in backpack:
		var entry := Items.to_save(item)
		if item.has("bag_cell"):
			var cell: Vector2i = item.bag_cell
			entry["bag_cell"] = [cell.x, cell.y]
		entry["bag_rotated"] = bool(item.get("bag_rotated", false))
		bag.append(entry)
	return {"members": saved, "active_id": active_id, "backpack": bag,
		"subgroups": subgroups.duplicate(true), "active_by_controller": active_by_controller.duplicate(true)}

func load_data(data: Dictionary) -> void:
	reset()
	members.clear()
	for member_id in data.get("members", {}):
		if members.size() >= MAX_MEMBERS: break
		members[String(member_id)] = CharacterState.from_dict(String(member_id), data["members"][member_id])
	if members.is_empty(): member("hero")
	subgroups = {"local": members.keys()}
	active_by_controller = {"local": String(data.get("active_id", members.keys()[0]))}
	if active_id not in members: active_id = String(members.keys()[0])
	var groups: Dictionary = data.get("subgroups", subgroups)
	if assign_subgroups(groups):
		for controller_id in data.get("active_by_controller", {}):
			var selected: String = String(data["active_by_controller"][controller_id])
			if selected in subgroups.get(controller_id, []): active_by_controller[controller_id] = selected
	for entry in data.get("backpack", []):
		var item := Items.from_save(entry)
		if item.is_empty(): continue
		var cell: Array = entry.get("bag_cell", [])
		if cell.size() == 2: item["bag_cell"] = Vector2i(int(cell[0]), int(cell[1]))
		item["bag_rotated"] = bool(entry.get("bag_rotated", false))
		backpack.append(item)
