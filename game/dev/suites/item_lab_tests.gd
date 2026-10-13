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

## The Lab's panels stay inside the visible canvas at every supported window size, ultrawide included.
func _test_item_lab_layout() -> void:
	TownState.persist = false
	TownState.reset()
	var sfx_was_enabled: bool = Sfx.enabled
	Sfx.enabled = false
	var lab: ItemTestLab = (load("res://game/dev/item_lab/item_test_lab.tscn") as PackedScene).instantiate() as ItemTestLab
	game.add_child(lab)
	var window_was: Vector2i = get_window().size
	for ui_size in [0.5, 1.0, 1.5]:   # the supported interface-scale boundaries (GameSettings clamps ui_size to 0.5..1.5)
		for size in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440)]:
			get_window().size = size
			# GameSettings.apply_ui_scale does nothing headless, so apply its formula here.
			var fitted: float = maxf(minf(float(size.x) / 1280.0, float(size.y) / 720.0), 0.01)
			get_window().content_scale_factor = clampf(pow(fitted, -0.45) * ui_size, 0.3, 3.0)
			for i in 3:
				await get_tree().process_frame
			var visible: Rect2 = get_viewport().get_visible_rect()
			print("LAYOUT window=", get_window().size, " ui=", ui_size, " canvas=", visible.size, " fit=", lab.lab_ui_root.scale.x)
			var panels: Dictionary = {"spawner": lab.spawner_panel, "stats": lab.stats_readout, "log": lab.combat_log, "top bar": lab.spawner_panel.get_parent().get_child(0)}
			for name in panels:
				var panel: Control = panels[name]
				var rect: Rect2 = _lab_rect(panel)
				expect("%dx%d ui %.1f: the %s panel is inside the visible area (%s in %s)" % [size.x, size.y, ui_size, name, rect, visible], visible.grow(0.5).encloses(rect) and rect.size.x > 100.0)
			var top_bar: Rect2 = _lab_rect(lab.spawner_panel.get_parent().get_child(0) as Control)
			expect("%dx%d ui %.1f: the top bar does not overlap the docks" % [size.x, size.y, ui_size], top_bar.end.y <= _lab_rect(lab.spawner_panel).position.y + 0.5
				and top_bar.end.y <= _lab_rect(lab.stats_readout).position.y + 0.5)
			var right: Rect2 = _lab_rect(lab.stats_readout)
			var left: Rect2 = _lab_rect(lab.spawner_panel)
			expect("%dx%d ui %.1f: the left and right docks leave a central play area (%.0f wide)" % [size.x, size.y, ui_size, right.position.x - left.end.x], right.position.x - left.end.x >= 300.0)
			expect("%dx%d ui %.1f: the right dock is flush to the right edge" % [size.x, size.y, ui_size], absf(visible.end.x - right.end.x - ItemTestLab.LAB_MARGIN * lab.lab_ui_root.scale.x) < 1.5)
			expect("%dx%d ui %.1f: the right dock stays clear of the hotbar and minimap" % [size.x, size.y, ui_size], _lab_rect(lab.combat_log).end.y <= visible.end.y - ItemTestLab.LAB_BOTTOM_CLEARANCE * lab.lab_ui_root.scale.y + 1.0)
	get_window().content_scale_factor = 1.0
	get_window().size = window_was
	lab.queue_free()
	await get_tree().process_frame
	Sfx.enabled = sfx_was_enabled
	TownState.reset()

## Choosing from the Lab's real dropdowns never moves the hero; the next real ground click does.
func _test_item_lab_dropdowns() -> void:
	TownState.persist = false
	TownState.reset()
	var sfx_was_enabled: bool = Sfx.enabled
	Sfx.enabled = false
	var lab: ItemTestLab = (load("res://game/dev/item_lab/item_test_lab.tscn") as PackedScene).instantiate() as ItemTestLab
	game.add_child(lab)
	var window_was: Vector2i = get_window().size
	get_window().size = Vector2i(1920, 1080)
	Gamepad.active = false
	await get_tree().process_frame
	await get_tree().physics_frame
	var hero: Player = lab.player
	hero.cursor_override = hero.global_position + Vector3(3.0, 0.0, 3.0)
	var panel: LabSpawnerPanel = lab.spawner_panel
	var dropdowns: Array[OptionButton] = [panel._filter_option, panel._item_def_option, panel._level_option, panel._rarity_option, panel._affix_prefix_option]
	for dropdown in dropdowns:
		hero.movement.has_goal = false
		var center: Vector2 = dropdown.get_global_rect().get_center()
		_lab_pointer(center)
		await get_tree().process_frame
		var before: int = dropdown.selected
		_lab_button(center, true)
		await get_tree().physics_frame
		_lab_button(center, false)
		await get_tree().physics_frame
		var popup: PopupMenu = dropdown.get_popup()
		expect("%s: the dropdown opens without moving the hero" % dropdown.name, popup.visible and not hero.movement.has_goal)
		var entry: int = 1 if popup.item_count > 1 else 0
		var pick: Vector2 = Vector2(popup.position) + Vector2(popup.size.x * 0.5, 8.0 + (popup.size.y - 16.0) * (float(entry) + 0.5) / maxf(float(popup.item_count), 1.0))
		_lab_pointer(pick)
		await get_tree().process_frame
		_lab_button(pick, true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_lab_button(pick, false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		expect("%s: choosing an entry (%d -> %d) closes it and does not move the hero" % [dropdown.name, before, dropdown.selected], not popup.visible and not hero.movement.has_goal)
		# Reopen and dismiss over open terrain: not a move order either.
		_lab_pointer(center)
		await get_tree().process_frame
		_lab_button(center, true)
		await get_tree().physics_frame
		_lab_button(center, false)
		await get_tree().physics_frame
		var view: Vector2 = get_viewport().get_visible_rect().size
		var terrain := Vector2(view.x * 0.62, view.y * 0.45)   # open ground between the docks, above the HUD bars
		_lab_pointer(terrain)
		await get_tree().process_frame
		_lab_button(terrain, true)
		await get_tree().physics_frame
		_lab_button(terrain, false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		expect("%s: dismissing it over terrain does not move the hero" % dropdown.name, not popup.visible and not hero.movement.has_goal)
		# The very next ground click moves at once.
		_lab_button(terrain, true)
		await get_tree().physics_frame
		_lab_button(terrain, false)
		await get_tree().physics_frame
		expect("%s: the next genuine ground click moves the hero at once" % dropdown.name, hero.movement.has_goal and hero.click_mode == 0)
	# A genuine ground click still cancels an attack in progress.
	hero.movement.has_goal = false
	hero.attack_target = lab.dummy
	hero.skills.start_skill("basic", lab.dummy)
	var terrain_point := Vector2(get_viewport().get_visible_rect().size.x * 0.62, get_viewport().get_visible_rect().size.y * 0.45)
	_lab_pointer(terrain_point)
	await get_tree().process_frame
	_lab_button(terrain_point, true)
	await get_tree().physics_frame
	_lab_button(terrain_point, false)
	await get_tree().physics_frame
	expect("a ground click after the dropdowns still cancels the attack and moves", not hero.skills.busy and hero.movement.has_goal)
	hero.cursor_override = Vector3.INF
	get_window().size = window_was
	lab.queue_free()
	await get_tree().process_frame
	Sfx.enabled = sfx_was_enabled
	TownState.reset()

## Canvas coordinates (what Control rects use) to window pixels (what the operating system's events carry), through the content scale.
## A control's rectangle in canvas units, including the Lab overlay's own fit-to-canvas scale.
func _lab_rect(control: Control) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size)

func _lab_pixels(point: Vector2) -> Vector2:
	return get_window().get_final_transform() * point

func _lab_button(canvas_point: Vector2, pressed: bool) -> void:
	var point := _lab_pixels(canvas_point)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _lab_pointer(canvas_point: Vector2) -> void:
	var point := _lab_pixels(canvas_point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
