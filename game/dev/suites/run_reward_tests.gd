extends DevSuite
## Self-test: what a run leaves on the ground when it ends (RunDirector.settle_ground_rewards). Uncollected gear goes to the town stash,
## gold and mana potions are credited, health potions fill the pack, and a dead hero loses what lies on the ground. Nothing is saved:
## the town state is not written (TownState.persist is off), and _end_run (the scene change) is not run here.

func _test_run_rewards() -> void:
	TownState.persist = false
	TownState.reset()
	for node in get_tree().get_nodes_in_group("orbs"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	await get_tree().process_frame
	var director := RunDirector.new()
	add_child(director)
	var gear_name: String = String(Items.starting_gear()[0]["name"])
	var stash_before: int = TownState.stash.size()
	var gold_before: int = TownState.gold
	var drops: Array[LootDrop] = []
	for i in 3:
		var drop := LootDrop.create(Items.starting_gear()[0].duplicate(true))
		director.add_child(drop)
		drops.append(drop)
	# Orbs lie far from the live hero (the menu scene has one): his own pickup would take them during the frame waits.
	var gold_orb := _orb_far_away(40, false, false)
	var potion := _orb_far_away(0, true, false)
	TownState.potions = 2
	await get_tree().process_frame

	# Successful completion (and an abandoned run takes the same path): ground gear to the stash, gold and a potion to the hero, once.
	var summary: String = director.settle_ground_rewards(false)
	expect("uncollected gear reaches the stash (three drops, three stash items)", TownState.stash.size() == stash_before + 3
		and String(TownState.stash.back()["name"]) == gear_name)
	expect("gold on the ground is credited once", TownState.gold == gold_before + 40)
	expect("a health potion on the ground fills the pack", TownState.potions == 3)
	expect("the summary says what was sent and collected (%s)" % summary, summary.contains("3 items sent to stash")
		and summary.contains("40 gold collected") and summary.contains("1 potion collected"))
	var handed_over: bool = true
	for drop in drops:
		handed_over = handed_over and (not is_instance_valid(drop) or drop.is_queued_for_deletion())
	expect("every ground reward is handed over (drops and orbs freed)", handed_over and (not is_instance_valid(gold_orb) or gold_orb.is_queued_for_deletion())
		and (not is_instance_valid(potion) or potion.is_queued_for_deletion()))
	await get_tree().process_frame

	# Repeated transitions: a second settle finds nothing and changes nothing (no duplication).
	var stash_mid: int = TownState.stash.size()
	var gold_mid: int = TownState.gold
	var again: String = director.settle_ground_rewards(false)
	expect("a repeated transition duplicates nothing", TownState.stash.size() == stash_mid and TownState.gold == gold_mid
		and TownState.potions == 3 and again == "")

	# A full pack: the potion over the maximum is reported as left behind, never hidden.
	TownState.potions = PlayerStats.MAX_POTIONS
	var spare := _orb_far_away(0, true, false)
	await get_tree().process_frame
	var full_summary: String = director.settle_ground_rewards(false)
	expect("a potion with a full pack stays at the maximum and is reported (%s)" % full_summary,
		TownState.potions == PlayerStats.MAX_POTIONS and full_summary.contains("1 potion left behind (pack full)"))

	# A dead hero: uncollected ground gear, gold and potions are lost, and nothing reaches the stash or the purse.
	TownState.potions = 2
	var lost_stash: int = TownState.stash.size()
	var lost_gold: int = TownState.gold
	var death_drop := LootDrop.create(Items.starting_gear()[0].duplicate(true))
	director.add_child(death_drop)
	var death_orb := _orb_far_away(25, false, false)
	var death_potion := _orb_far_away(0, true, false)
	await get_tree().process_frame
	var death_summary: String = director.settle_ground_rewards(true)
	expect("death: the stash and the purse are untouched and the pack keeps its potions", TownState.stash.size() == lost_stash
		and TownState.gold == lost_gold and TownState.potions == 2)
	expect("death: uncollected ground rewards are lost and the summary says so (%s)" % death_summary,
		death_drop.is_queued_for_deletion() and death_orb.is_queued_for_deletion() and death_potion.is_queued_for_deletion()
		and death_summary.begins_with("Lost on the ground"))

	# Stash overflow: the stash has no size limit in code, so every deposit is kept (nothing is refused or deleted).
	var deposited: int = 0
	for i in 60:
		TownState.stash_item(Items.starting_gear()[0].duplicate(true))
		deposited += 1
	expect("the stash keeps every deposit (no silent overflow loss)", TownState.stash.size() == lost_stash + deposited)

	TownState.reset()
	director.queue_free()
	await get_tree().process_frame

## Quest items and the run's ground rewards in world mode: a fetch item stays reachable through death, return, leaving and a reload, and
## each reward is handed over once. Uses the real quest storage (TownState.quests) and the real settle path; the town scene itself is not run.
func _test_quest_and_world_rewards() -> void:
	TownState.persist = false
	TownState.reset()
	for node in get_tree().get_nodes_in_group("orbs"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("quest_pickups"):
		node.queue_free()
	await get_tree().process_frame
	var def: QuestDef = TownDb.quest("lost_satchel")
	var count_before: int = def.count
	def.count = 10   # a kill count the target would not reach: only the last-of-kind rule can drop it
	var satchel: Dictionary = Quests.post("lost_satchel")
	var uid: int = int(satchel["uid"])
	var drop: Dictionary = Quests.report_kill(def.target, true)
	expect("the last monster of a fetch target always drops the wanted item (non-respawning target)", (drop["drops"] as Array).has(satchel)
		and bool(satchel["data"]["dropped"]))
	Quests.set_drop_spot(satchel, Vector3(12.0, 0.0, -7.0))
	expect("the item is not dropped twice by the same target", (Quests.report_kill(def.target, true)["drops"] as Array).is_empty())
	# A scene reload: the pickup is gone but the quest keeps the item and its spot (existing quest storage, saved with the town).
	var saved: Dictionary = TownState.to_dict()
	TownState.reset()
	TownState.from_dict(saved)
	var restored: Dictionary = Quests.find(uid)
	expect("the dropped item and its spot survive a save and load", not restored.is_empty() and bool(restored["data"]["dropped"]) and restored["data"].has("at"))
	var spots: Array = Quests.fetch_to_respawn([])
	expect("an item with no pickup on the road comes back at its stored spot", spots.size() == 1 and (spots[0]["at"] as Vector3).is_equal_approx(Vector3(12.0, 0.0, -7.0)))
	expect("an item that already has a pickup is not put back twice", Quests.fetch_to_respawn([uid]).is_empty())
	# Death, return and leaving: none of them removes the quest item, and the ground rewards follow the policy once each.
	var director := RunDirector.new()
	add_child(director)
	var dead_drop := LootDrop.create(Items.starting_gear()[0].duplicate(true))
	director.add_child(dead_drop)
	await get_tree().process_frame
	var stash_before: int = TownState.stash.size()
	var lost: String = director.settle_ground_rewards(true)
	expect("a death loses the uncollected ground gear and says so (%s)" % lost, TownState.stash.size() == stash_before and lost.begins_with("Lost"))
	expect("a death leaves the quest item where it is", not Quests.find(uid).is_empty() and bool(Quests.find(uid)["data"]["dropped"]))
	var kept_drop := LootDrop.create(Items.starting_gear()[0].duplicate(true))
	director.add_child(kept_drop)
	await get_tree().process_frame
	var kept: String = director.settle_ground_rewards(false)
	expect("a return or leaving recovers the ground gear once (%s)" % kept, TownState.stash.size() == stash_before + 1 and kept.contains("sent to stash"))
	var again: String = director.settle_ground_rewards(false)
	expect("repeated transitions duplicate nothing", again == "" and TownState.stash.size() == stash_before + 1)
	expect("the quest item is still reachable after every transition", not Quests.fetch_to_respawn([]).is_empty())
	director.queue_free()
	def.count = count_before
	TownState.reset()
	await get_tree().process_frame

## A reward orb far from the hero: gold (or a potion, or mana when neither is set), added to the suite so it is in the orbs group.
func _orb_far_away(gold: int, potion: bool, mana: bool) -> HealthOrb:
	var orb := HealthOrb.new()
	orb.gold_amount = gold
	orb.is_potion = potion
	orb.is_mana = mana
	add_child(orb)
	orb.global_position = Vector3(900.0, 0.0, 900.0)
	return orb
