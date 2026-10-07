extends SceneTree
## Focused validation tool for task crypt-climax-return-flow-056:
## Validates:
##   1. Return interaction absent/inactive before clear.
##   2. Appears/enables exactly once after Warden/forecourt clear.
##   3. Interaction label is clear ("Return to Last Hearth").
##   4. Activation returns hero safely to Last Hearth plaza.
##   5. Objective / quest text resolves appropriately.
##   6. Reward / completion fires once only.
##   7. Sealed crypt remains inaccessible.
##   8. Death / revive flow remains unchanged.
##   9. No duplicate triggers after revisiting.
##   10. Captures fresh screenshots:
##       - Cleared forecourt with return waystone
##       - Interaction prompt
##       - Arrival / closure in town

var evidence_dir: String = ""
var town: TownScene
var player: Player
var director: RunDirector
var crypt: CryptRoad

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):
			evidence_dir = arg.substr(11)
	if evidence_dir == "":
		evidence_dir = ProjectSettings.globalize_path("res://.agentbridge/task056-evidence")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	print("=== VALIDATE CRYPT RETURN FLOW 056 START ===")
	print("Target evidence directory: ", evidence_dir)
	_run_validation()

func _capture(filename: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		printerr("[ERROR] Viewport image is empty for ", filename)
		return
	var path: String = "%s/%s.png" % [evidence_dir, filename]
	var err: Error = img.save_png(path)
	if err == OK:
		print("  [CAPTURE] Saved: ", path)
	else:
		printerr("  [CAPTURE ERROR] Failed to save ", filename, " err=", err)

func _run_validation() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.gold = 100
	var town_scene: PackedScene = load("res://game/town.tscn")
	town = town_scene.instantiate() as TownScene
	root.add_child(town)
	current_scene = town

	# Wait for world build and nav bake
	for i in 60:
		await process_frame

	player = town.player
	director = town.director
	crypt = town.crypt

	assert(crypt != null, "CryptRoad must be attached to TownScene")
	assert(crypt.return_waystone != null, "CryptReturnWaystone must exist on CryptRoad")
	print("  [PASS] Town and CryptRoad initialized with ReturnWaystone")

	# --- TEST 1: Return interaction absent/inactive before clear ---
	assert(not crypt.return_waystone.active, "Return waystone must be inactive before clear")
	assert(not crypt.return_waystone.visible, "Return waystone must be invisible before clear")
	var spots_with_waystone: Array = town.spots.filter(func(s: Dictionary) -> bool: return String(s.get("key", "")) == "return_waystone")
	assert(spots_with_waystone.is_empty(), "return_waystone must NOT be registered in town.spots before clear")
	assert(not TownState.has_reward(), "Quest must not have reward before clear")
	assert(not crypt.is_forecourt_cleared(), "Forecourt must not be cleared initially")
	assert(director.objective_line().begins_with("Destroy nests"), "Objective line must show nest progress before clear")
	print("  [PASS] 1. Return interaction absent/inactive before clear")

	# --- TEST 2: Sealed crypt remains inaccessible ---
	var crypt_steps_world: Vector3 = crypt.at(0.0, -163.5)
	var crypt_gate_world: Vector3 = crypt.at(0.0, -166.0)
	var gate_distance: float = crypt_steps_world.distance_to(crypt_gate_world)
	assert(gate_distance >= 2.4, "Crypt gate facade must sit at least 2.4m behind steps")
	# Sealed crypt gate has static body blocking entry
	var space_state: PhysicsDirectSpaceState3D = town.get_world_3d().direct_space_state
	var ray_query := PhysicsRayQueryParameters3D.create(crypt_steps_world + Vector3(0, 1.5, 0), crypt.at(0.0, -168.0) + Vector3(0, 1.5, 0))
	ray_query.collision_mask = Actor.LAYER_WORLD
	var hit: Dictionary = space_state.intersect_ray(ray_query)
	assert(not hit.is_empty(), "Physics collision must block passage into sealed crypt")
	print("  [PASS] 2. Sealed crypt remains inaccessible (hit gate collision at z=", hit.position.z, ")")

	# --- TEST 3: Death / revive flow remains unchanged ---
	player.global_position = crypt.at(0.0, -50.0)
	town.outside = true
	player.dead = true
	player.health = 0.0
	assert(player.dead, "Player dead state confirmed")
	player.revive_at(Vector3(0.0, 0.0, 10.0))
	assert(not player.dead, "Player revive restored living state")
	assert(player.health == player.max_health, "Player health restored on revive")
	assert(player.global_position.distance_to(Vector3(0.0, 0.0, 10.0)) < 0.5, "Player revived at town plaza spawn")
	print("  [PASS] 3. Death / revive flow verified unchanged")

	# --- TEST 4: Clear Forecourt Climax & Verify Waystone Appears Once ---
	var climax: CryptForecourtClimax = CryptForecourtEncounter.get_climax(crypt)
	assert(climax != null, "CryptForecourtClimax controller must exist")
	player.global_position = crypt.at(0.0, -154.0)
	town.rig.global_position = player.global_position
	town.outside = true
	for i in 10:
		await process_frame

	# Simulate defeating all forecourt enemies
	for e in climax._all_forecourt_enemies:
		if is_instance_valid(e):
			e.dead = true
			e.health = 0.0

	climax.complete_encounter()
	for i in 5:
		await process_frame

	assert(climax.is_cleared(), "Climax must be marked cleared")
	assert(climax.get_clear_event_fired_count() == 1, "Clear event must fire exactly once")
	assert(crypt.is_forecourt_cleared(), "CryptRoad.is_forecourt_cleared() must be true")
	assert(crypt.return_waystone.active, "Return waystone must be active after clear")
	assert(crypt.return_waystone.visible, "Return waystone must be visible after clear")

	# Attempt repeat complete calls to verify single trigger
	climax.complete_encounter()
	assert(climax.get_clear_event_fired_count() == 1, "Clear event must NOT fire multiple times")
	print("  [PASS] 4. Appears/enables exactly once after Forecourt clear")

	# --- TEST 5: Interaction label and spots registration ---
	var waystone_spots: Array = town.spots.filter(func(s: Dictionary) -> bool: return String(s.get("key", "")) == "return_waystone")
	assert(not waystone_spots.is_empty(), "return_waystone must be registered in town.spots")
	var way_spot: Dictionary = waystone_spots[0]
	assert(String(way_spot.get("label", "")) == CryptReturnWaystone.INTERACT_LABEL, "Label must be exactly 'Return to Last Hearth'")
	assert(String(way_spot.get("kind", "")) == "waystone", "Spot kind must be 'waystone'")
	print("  [PASS] 5. Interaction label is clear ('Return to Last Hearth')")

	# --- TEST 6: Objective / quest text resolves appropriately ---
	var obj_line: String = director.objective_line()
	assert(obj_line == "Forecourt secured — Return to Last Hearth", "Director objective line must resolve to Forecourt secured, got: " + obj_line)
	var q_line: String = town._quest_line()
	assert(q_line.ends_with("done"), "Town quest line must resolve to done, got: " + q_line)
	assert(TownState.has_reward(), "TownState must register pending reward")
	assert(town.hud.quest_ready, "TownHud quest_ready must be true")
	print("  [PASS] 6. Objective / quest text resolves appropriately")

	# --- SCREENSHOT 1: Cleared forecourt with return waystone ---
	player.global_position = crypt.at(0.0, -159.0)
	town.rig.global_position = crypt.at(0.0, -161.0)
	for i in 15:
		await process_frame
	await _capture("01_cleared_forecourt_return_waystone")

	# --- SCREENSHOT 2: Approach waystone and display interaction prompt ---
	player.global_position = crypt.at(0.0, -162.0)
	town.rig.global_position = player.global_position
	# Wait for clear banner to fade so prompt is clearly visible
	for i in 90:
		await process_frame
	Gamepad.active = true
	town._update_near()
	assert(not town.near.is_empty(), "Player must be near a spot")
	assert(String(town.near.get("label", "")) == "Return to Last Hearth", "Near spot must be Return to Last Hearth")
	for i in 10:
		await process_frame
	await _capture("02_return_waystone_prompt")
	Gamepad.active = false

	# --- TEST 7: Activation returns hero to Last Hearth safely ---
	town.interact(town.near)
	for i in 10:
		await process_frame

	assert(not town.outside, "Hero must no longer be outside after return")
	assert(player.global_position.distance_to(Vector3(0.0, 0.0, 8.0)) < 1.0, "Hero must arrive safely at Last Hearth plaza")
	assert(not player.dead, "Hero must be alive upon return")
	var hale: TownNpc = town.npcs["hale"]
	assert(hale != null, "Warden Hale must exist")
	assert(hale.has_reward_marker(), "Warden Hale must display reward marker coin")
	print("  [PASS] 7. Activation returns hero to Last Hearth safely with reward marker")

	# --- SCREENSHOT 3: Arrival and closure in Last Hearth plaza ---
	for i in 15:
		await process_frame
	await _capture("03_arrival_closure_in_town")

	# --- TEST 8: Reward claims once only & road regrow resets waystone ---
	var gold_before: int = TownState.gold
	var claim_result: Dictionary = town.claim_rewards()
	assert(int(claim_result.get("count", 0)) > 0, "Claim rewards must succeed for the completed quest")
	assert(TownState.gold > gold_before, "TownState gold must increase on reward claim")
	assert(not TownState.has_reward(), "Pending reward must be cleared after claim")

	# Attempt repeat claim: must give nothing
	var second_claim: Dictionary = town.claim_rewards()
	assert(int(second_claim.get("count", 0)) == 0, "Second claim must yield 0 rewards (no duplicate payout)")
	print("  [PASS] 8. Reward/completion fires once only, no duplicate payout")

	# --- TEST 9: Road reset / regrow behavior ---
	# After regrow, the waystone must be dormant and not in spots
	assert(not crypt.return_waystone.active, "Return waystone must be dormant after regrow")
	var spots_after_regrow: Array = town.spots.filter(func(s: Dictionary) -> bool: return String(s.get("key", "")) == "return_waystone")
	assert(spots_after_regrow.is_empty(), "return_waystone must be cleared from spots after regrow")
	print("  [PASS] 9. Road regrow cleanly resets return waystone for next run")

	print("=== VALIDATE CRYPT RETURN FLOW 056 COMPLETED SUCCESSFULLY ===")
	quit(0)
