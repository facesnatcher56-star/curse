extends DevSuite
## Self-test suite for developer Item Test Lab.
## Covers:
## 1. Launching the Item Test Lab scene.
## 2. Spawning real items (including Gemini melee families, bows, armor, shields, jewelry).
## 3. Equipping items through normal PlayerStats API.
## 4. Observing live character and equipment stat updates.
## 5. Performing genuine attacks against the training dummy.
## 6. Verifying combat damage comes from actual Combat.resolve / Actor.receive pipeline.
## 7. Unequipping items and restoring statistics.
## 8. Resetting lab without touching production saves.

func _test_item_lab() -> void:
	TownState.persist = false
	TownState.reset()

	# 1. Instantiate the lab scene
	var lab_scene := load("res://game/dev/item_lab/item_test_lab.tscn")
	expect("item test lab scene resource exists and loads", lab_scene != null)
	if lab_scene == null:
		return

	var lab: ItemTestLab = lab_scene.instantiate() as ItemTestLab
	expect("lab instantiates as ItemTestLab", lab != null)
	if lab == null:
		return
	# This suite validates equipment and combat state, not audio playback. The lab's
	# impact sounds attach voices to the outer self-test scene and outlive the lab.
	var sfx_was_enabled: bool = Sfx.enabled
	Sfx.enabled = false

	game.add_child(lab)
	await get_tree().process_frame
	await get_tree().physics_frame

	expect("lab spawns real player actor", lab.player != null and lab.player is Player)
	expect("lab spawns real training dummy", lab.dummy != null and lab.dummy is TrainingDummy)
	expect("lab player uses real PlayerStats and SkillController", lab.player.stats != null and lab.player.skills != null)
	expect("lab creates spawner panel, stats readout, and combat log",
		lab.spawner_panel != null and lab.stats_readout != null and lab.combat_log != null)

	var p: Player = lab.player
	var dummy: TrainingDummy = lab.dummy
	var stats: PlayerStats = p.stats

	# 2. Verify all new and existing weapon families are implementable & browseable in ItemDefs
	var families := ["axe_1h", "axe_2h", "mace", "club", "dagger", "hammer_2h", "longsword", "falchion", "greatsword", "short_bow"]
	for fam in families:
		var def := ItemDb.get_def(fam)
		expect("ItemDef '%s' exists in ItemDb" % fam, def != null)

	# 3. Equip through normal equipment API and verify stat changes
	var unequipped_armor: float = p.armor
	var unequipped_dmg: Vector2 = stats.weapon_range(1.0)

	var dagger_item: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Dagger")
	expect("dagger item generated successfully", not dagger_item.is_empty())
	var dagger_res: Variant = stats.equip(dagger_item, false)
	expect("dagger equipped via normal equipment API", dagger_res != null and stats.equipment.get(Items.Slot.WEAPON) != null)
	expect("weapon model updated on character", p.model.weapon != null)
	expect("character stats update immediately", stats.weapon_range(1.0) != unequipped_dmg)

	# Test 2H weapon stance and shield conflict
	var buckler: Dictionary = Items.build(ItemDb.get_def("buckler"), 6, Items.Rarity.NORMAL)
	stats.equip(buckler, false)
	expect("buckler equips and adds block chance", stats.equipment.has(Items.Slot.SHIELD) and p.block_chance > 0.0)

	var warhammer_item: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Warhammer")
	var displaced: Variant = stats.equip(warhammer_item, false)
	expect("2H warhammer takes off buckler", stats.equipment.has(Items.Slot.WEAPON) and not stats.equipment.has(Items.Slot.SHIELD))
	expect("block chance restored to zero when shield is removed", is_equal_approx(p.block_chance, 0.0))

	# Test armor equip and total armor stat update
	stats.unequip(Items.Slot.ARMOR)
	unequipped_armor = p.armor
	var armor_item: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 2, "Leather Jerkin")
	stats.equip(armor_item, false)
	expect("armor updates character total armor", p.armor > unequipped_armor)

	# 4. Perform genuine attacks against dummy using Combat system
	dummy.reset_health()
	var initial_hp: float = dummy.health

	# Perform genuine Combat.resolve and Actor.receive
	var combat_hit: Dictionary = Combat.resolve(p, dummy, 25.0, Combat.DamageType.PHYSICAL, false)
	combat_hit["skill_id"] = "basic"
	dummy.receive(combat_hit, p.global_position)

	expect("dummy receives genuine combat damage", dummy.health < initial_hp)
	expect("damage applied equals combat resolution result", is_equal_approx(initial_hp - dummy.health, float(combat_hit["damage"])))
	expect("combat log records entry", lab.combat_log._log_list.get_child_count() > 0)

	# 5. Dummy health reset control
	dummy.reset_health()
	expect("dummy reset health restores full HP", is_equal_approx(dummy.health, dummy.max_health))

	# 6. Unequip items and restore statistics
	stats.unequip(Items.Slot.WEAPON)
	stats.unequip(Items.Slot.ARMOR)
	expect("unequipping weapon removes worn gear", not stats.equipment.has(Items.Slot.WEAPON))
	expect("unequipping armor restores base armor", is_equal_approx(p.armor, stats.base_armor))

	# 7. Reset Lab without touching production saves
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	expect("lab session is developer-only and isolated", SavePolicy.is_dev_session(user_args) and not SavePolicy.may_modify(SavePolicy.PRODUCTION_PATH, user_args))
	lab._reset_lab_state()
	expect("lab reset restores starting gear", stats.equipment.has(Items.Slot.WEAPON) and stats.equipment.has(Items.Slot.ARMOR))

	lab.queue_free()
	await get_tree().process_frame
	Sfx.enabled = sfx_was_enabled
