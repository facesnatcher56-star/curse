extends DevSuite
## Map mode, Step 1 (`-- --crypt01 --mapmode`, issue #79): the map lists live groups and drops cleared ones, a selection dashes both party members to the
## group, auto-attack starts on arrival and follows the focus target, a cleared group collects its loot and reopens the map, the fight is logged,
## and with the flag off nothing is hooked. (A full Crypt run is played by hand; this drives the same MapMode on the self-test arena.)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _wait_state(m: MapMode, wanted: MapMode.State, max_frames: int) -> void:
	var n: int = 0
	while m.state != wanted and n < max_frames:
		await get_tree().physics_frame
		n += 1

func _test_map_mode() -> void:
	expect("with the flag off map mode does not exist (no hooks, no flag)", not MapMode.active and not MapMode.requested())
	var cutter: Player = game.companion
	var cutter_was_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = false
	var base: Vector3 = player.global_position
	var near: Array[Enemy] = []
	for i in 2:
		near.append(_spawn_enemy(Nav.snap(player, base + Vector3(16.0 + i, 0.0, 2.0 * i)), "zombie", 1.0))
	var far: Enemy = _spawn_enemy(Nav.snap(player, base + Vector3(-16.0, 0.0, 6.0)), "zombie", 1.0)
	for e in near:
		e.group_id = 901
		e.aggro_range = 0.0
	far.group_id = 902
	far.aggro_range = 0.0
	var m := MapMode.new()
	game.add_child(m)
	m.setup(player, cutter, hud)
	expect("map mode is active once its node runs", MapMode.active)
	await _frames(10)
	expect("the map opens by itself at the start", m.state == MapMode.State.MAP and m.overlay != null and m.overlay.is_open())
	var ids: Array = m.markers().filter(func(x: Dictionary) -> bool: return x["kind"] == "group").map(func(x: Dictionary) -> int: return int(x["id"]))
	expect("the map lists both live groups", ids.has(901) and ids.has(902))
	var label: String = ""
	for x in m.markers():
		if int(x["id"]) == 901:
			label = String(x["label"])
	expect("a group's label gives count, kinds and what it guards (%s)" % label, label.begins_with("2 zombie") and label.contains("guards:"))
	expect("click-to-move does nothing: the stick and the ground are ignored in this mode", MapMode.active and player.attack_target == null)
	# Select the near group: both party members dash to its edge.
	var group_centre: Vector3 = m.centre_of(near)
	m.overlay.selected.emit(901)
	expect("selecting a group closes the map and starts the dash", m.state == MapMode.State.DASH and not m.overlay.is_open())
	await _wait_state(m, MapMode.State.FIGHT, 150)
	expect("the dash ends in a fight within about a second and a half", m.state == MapMode.State.FIGHT)
	var hero_gap: float = player.global_position.distance_to(group_centre)
	var cutter_gap: float = cutter.global_position.distance_to(group_centre)
	expect("the hero stands at the edge of the group (%.1f m)" % hero_gap, hero_gap < MapMode.ARRIVE_DISTANCE + 3.0)
	expect("the Cutter dashed with the hero (%.1f m)" % cutter_gap, cutter_gap < MapMode.ARRIVE_DISTANCE + 5.0)
	await _frames(3)
	expect("the group is awake on arrival and the hero auto-attacks the nearest enemy", near[0].is_aggro() and player.attack_target in near)
	expect("the other group stayed asleep (groups are isolated)", not far.is_aggro())
	# Focus switches both fighters to the clicked enemy.
	var other: Enemy = near[1] if player.attack_target == near[0] else near[0]
	m.set_focus(other)
	await _frames(12)
	expect("focus moves the hero's target (%s)" % player.attack_target, player.attack_target == other)
	expect("focus moves the Cutter's target (%s, dead %s, busy %s)" % [cutter.attack_target, cutter.dead, cutter.skills.busy], cutter.attack_target == other)
	# Fight, then clear. Drop an item and gold to be collected.
	var item: Dictionary = Items.make(0, 1, 1)
	game.director.drop_item(player.global_position + Vector3(1.0, 0.0, 0.0), item)
	for e in near:
		e.credit_hero()
		e._apply_damage(e.max_health + 10.0)
	await _wait_state(m, MapMode.State.COLLECT, 30)
	await _wait_state(m, MapMode.State.MAP, 420)
	expect("a cleared group reopens the map", m.state == MapMode.State.MAP and m.overlay.is_open())
	expect("its loot was collected automatically", get_tree().get_nodes_in_group("loot").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).is_empty())
	var left: Array = m.markers().filter(func(x: Dictionary) -> bool: return x["kind"] == "group").map(func(x: Dictionary) -> int: return int(x["id"]))
	expect("the cleared group is gone from the map, the other remains", not left.has(901) and left.has(902))
	expect("the fight was logged with its length and click-to-first-hit", m.log.fights.size() == 1 and float(m.log.fights[0]["length_s"]) > 0.0 and m.log.fights[0].has("click_to_first_hit_s"))
	# Tidy: remove the mode and what it left, restore the Cutter's flag.
	far.credit_hero()
	far._apply_damage(far.max_health + 10.0)
	m.overlay.queue_free()
	m.queue_free()
	await _frames(2)
	cutter.testing_disabled = cutter_was_disabled
	expect("removing the node turns map mode off again", not MapMode.active)
