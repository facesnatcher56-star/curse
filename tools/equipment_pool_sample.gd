extends SceneTree
## Runtime sample of every equipment slot's ordinary level -5..+1 pool at five midgame levels.

const SAMPLE_LEVELS: Array[int] = [30, 35, 40, 45, 50]


func _initialize() -> void:
	randomize()
	var failures: PackedStringArray = []
	for monster_level in SAMPLE_LEVELS:
		var low: int = monster_level + Items.DROPS["normal"]["window"].x
		var high: int = monster_level + Items.DROPS["normal"]["window"].y
		for slot in range(8):
			var candidates: Array[ItemDef] = []
			for def in ItemDb.of_slot(slot):
				if def.levels.any(func(item_level: int) -> bool: return item_level >= low and item_level <= high):
					candidates.append(def)
			if candidates.is_empty():
				failures.append("no candidate for slot %d at monster level %d" % [slot, monster_level])
				continue
			var picked: Dictionary = Items.pick_base(low, high, slot)
			var def: ItemDef = picked["def"] as ItemDef
			var level: int = int(picked["level"])
			if not candidates.has(def) or level < low or level > high:
				failures.append("invalid pick %s level %d at monster level %d" % [def.id, level, monster_level])
				continue
			var item: Dictionary = Items.build(def, level, Items.Rarity.NORMAL)
			var restored: Dictionary = Items.from_save(Items.to_save(item))
			if String(restored.get("def", "")) != def.id or int(restored.get("level", 0)) != level:
				failures.append("save round trip lost %s level %d" % [def.id, level])
			print("POOL_SAMPLE monster=%d slot=%s candidate_bases=%d selected=%s item_level=%d model=%s icon=%s"
				% [monster_level, Items.SLOT_NAMES[slot], candidates.size(), def.id, level,
					"ok" if ResourceLoader.exists(def.model_path) else "missing",
					"ok" if ResourceLoader.exists(def.icon_path) else "missing"])
			if not ResourceLoader.exists(def.model_path) or not ResourceLoader.exists(def.icon_path):
				failures.append("asset path unresolved for %s" % def.id)
	var legacy: Dictionary = Items.from_save({"def": "longsword", "level": 38, "rarity": Items.Rarity.NORMAL, "mods": []})
	if String(legacy.get("def", "")) != "longsword":
		failures.append("existing item ID longsword no longer resolves")
	if failures.is_empty():
		print("EQUIPMENT_POOL_SAMPLE_DONE levels=30,35,40,45,50 slot_samples=40 existing_ids=preserved")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
