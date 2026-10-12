extends SceneTree
## Isolated Phase 0 data regression. Never loads or writes the production save.
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	print("%s: %s" % ["PASS" if passed else "FAIL", label])
	if not passed: failures += 1

func run() -> void:
	TownState.persist = false
	TownState.reset()
	check("developer path cannot target production", SavePolicy.path_for(OS.get_cmdline_user_args()) == SavePolicy.DEV_PATH)
	var worn: Dictionary = {Items.Slot.WEAPON: Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow")}
	var legacy := {"save_version": 10, "hero_xp": HeroProgression.xp_for_level(8) + 17,
		"class_xp": {"melee": 900, "ranged": 300, "combat": 400, "nature": 0},
		"passive_ranks": {"critical_strike": 1}, "cutter_xp": HeroProgression.xp_for_level(6) + 13,
		"gear": TownState._gear_to_save(worn), "gold": 234, "stash": []}
	var migrated := TownState.migrate(legacy.duplicate(true))
	var fixture_path := SavePolicy.DEV_PATH.get_base_dir().path_join("party_v10_fixture.json")
	check("isolated fixture is permitted by SavePolicy", SavePolicy.may_modify(fixture_path, OS.get_cmdline_user_args()))
	SavePolicy.ensure_folder(fixture_path)
	var fixture := FileAccess.open(fixture_path, FileAccess.WRITE)
	fixture.store_string(JSON.stringify(legacy))
	fixture.close()
	var disk_fixture := JSON.parse_string(FileAccess.get_file_as_string(fixture_path)) as Dictionary
	check("isolated on-disk migration matches in-memory migration", JSON.parse_string(JSON.stringify(TownState.migrate(disk_fixture))) == JSON.parse_string(JSON.stringify(migrated)))
	check("migration is idempotent", TownState.migrate(migrated.duplicate(true)) == migrated)
	TownState.from_dict(migrated)
	var party := PartyManager.current()
	var hero := party.member("hero")
	var cutter := party.member("cutter")
	check("Hero XP and all class XP retained", hero.xp == legacy.hero_xp and hero.class_xp == legacy.class_xp)
	check("Hero purchases and points retained", hero.passive_ranks == legacy.passive_ranks and TownState.skill_points_left({}, "hero") == hero.level)
	check("Cutter independent XP and Ranged advancement retained", cutter.xp == legacy.cutter_xp and cutter.class_xp.ranged == legacy.cutter_xp)
	check("Cutter earned points use common rule", TownState.skill_points_left({}, "cutter") == cutter.level + 1)
	check("starter bow obeys ordinary requirements", Items.hero_can_wear(cutter.equipment[Items.Slot.WEAPON], "cutter"))
	check("no free Take Aim", PowerDb.hero_rank("take_aim", "cutter") == 0)
	check("legacy Hero hotbar retained", hero.hotbar == GameSettings.hotbar_slots and hero.hotbar_alt == GameSettings.hotbar_alt)
	check("Cutter hotbar independent", cutter.hotbar != hero.hotbar or cutter.hotbar == ["", "", "", "", "", ""])
	var before := hero.xp
	TownState.add_member_xp("cutter", 100, false, {"combat": 1.0})
	check("Cutter may learn Combat Magic without modifying Hero", hero.xp == before and cutter.class_xp.combat == 100)
	cutter.power_state = {"initialized": true, "bow": {"armed": true, "required": 300.0, "remaining": 75.0}}
	cutter.health = 35.0
	cutter.mana = 21.0
	cutter.hotbar[0] = "fireball"
	party.backpack.append(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow"))
	var saved := JSON.parse_string(JSON.stringify(TownState.to_dict())) as Dictionary
	TownState.from_dict(TownState.migrate(saved))
	check("independent character serialization", party.member("hero").xp == before and party.member("cutter").hotbar[0] == "fireball")
	check("vitals and power state round-trip", party.member("cutter").health == 35.0 and party.member("cutter").mana == 21.0 and party.member("cutter").power_state.bow.remaining == 75.0)
	check("shared bag is not duplicated", party.backpack.size() == 1 and TownState.gold == 234)
	for id in ["visitor_1", "visitor_2", "visitor_3", "visitor_4"]:
		var record := CharacterState.new(id)
		record.owner_id = "guest_profile"
		record.xp = 900
		check("additional member uses common state: " + id, party.add_member(record))
	check("six-member capacity enforced", not party.add_member(CharacterState.new("seventh")))
	check("two players may control three members each", party.assign_subgroups({"local": ["hero", "cutter", "visitor_1"], "guest": ["visitor_2", "visitor_3", "visitor_4"]}))
	check("ownership is independent of active controller", party.member("visitor_1").owner_id == "guest_profile" and party.controller_for("visitor_1").controller_id == "local")
	check("duplicate subgroup assignments are rejected", not party.assign_subgroups({"local": ["hero", "cutter"], "guest": ["hero"]}))
	check("three players may control two members each", party.assign_subgroups({"local": ["hero", "cutter"], "guest_a": ["visitor_1", "visitor_2"], "guest_b": ["visitor_3", "visitor_4"]}))
	var six := party.to_dict()
	party.load_data(JSON.parse_string(JSON.stringify(six)))
	check("six independent records and ownership serialize", party.members.size() == 6 and party.member("visitor_4").owner_id == "guest_profile" and party.member("visitor_4").xp == 900)
	check("campaign resources are not in imported character records", not party.member("visitor_4").to_dict().has("gold") and not party.member("visitor_4").to_dict().has("quests"))
	TownState.reset()
	party.member("hero").class_xp.melee = 10
	party.member("cutter").class_xp.ranged = 10
	var reward := TownState.add_party_reward_xp(100, false)
	check("quest/nest reward applies existing two-member party share", reward.hero.xp_gained == 90 and reward.cutter.xp_gained == 90)
	check("non-combat rewards preserve independent class choices", party.member("hero").class_xp.melee == 100 and party.member("cutter").class_xp.ranged == 100)
	party.member("cutter").health = 0.0
	reward = TownState.add_party_reward_xp(100, false)
	check("dead members excluded and living party share recalculated", reward.size() == 1 and reward.hero.xp_gained == 100 and party.member("cutter").xp == 90)
	print("PARTY STATE CHECK: %d failure(s)" % failures)
	quit(1 if failures else 0)
