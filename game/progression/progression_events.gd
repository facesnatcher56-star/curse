class_name ProgressionEvents
extends RefCounted
## Where the hero's progression announces itself. `TownState` (static, no scene) emits here; whatever UI exists connects, so the
## persistent state never needs to know which HUD is up. One shared instance: `TownState.events`.

## Total XP changed (fired for every award that changed it).
signal hero_xp_changed(old_xp: int, new_xp: int)
## The level went up, by one or several levels at once: one event for one award.
signal hero_leveled(old_level: int, new_level: int, new_xp: int)
## Class skills increased through earned XP: class id -> final level, combined per award.
signal class_skills_leveled(levels: Dictionary)
## Passive ranks were bought (the hero's numbers follow them).
signal passives_changed()
signal member_xp_changed(member_id: String, old_xp: int, new_xp: int)
signal member_leveled(member_id: String, old_level: int, new_level: int, new_xp: int)
signal member_class_skills_leveled(member_id: String, levels: Dictionary)
signal member_passives_changed(member_id: String)
