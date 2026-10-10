class_name ProgressionEvents
extends RefCounted
## Where the hero's progression announces itself. `TownState` (static, no scene) emits here; whatever UI exists connects, so the
## persistent state never needs to know which HUD is up. One shared instance: `TownState.events`.

## Total XP changed (fired for every award that changed it).
signal hero_xp_changed(old_xp: int, new_xp: int)
## The level went up, by one or several levels at once: one event for one award, carrying the Passive and Evolution Points every level
## crossed granted in total (see HeroProgression.points_between).
## What the hero has bought changed (a passive, a skill evolution, or a load/reset): the progression screen and anything caching a choice listen.
signal hero_build_changed
signal hero_leveled(old_level: int, new_level: int, new_xp: int, passive_gained: int, evolution_gained: int)
