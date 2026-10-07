class_name SavePolicy
extends RefCounted
## Where, and whether, the game may write the town save. ONE decision for the whole project, so no developer tool has to remember to turn
## saving off: a normal launch (no user arguments) uses the production save, `user://town.json`; ANY session started with user arguments
## after `--` (the self-test, every screenshot and diagnostic mode, `--level=`, `--xp=`, and any flag added later) is a developer session
## and gets its own file, `user://dev_session/town.json`, and no saving by default. A developer session can only touch the production
## save by passing REAL_SAVE_FLAG, which nothing else uses. Nothing here ever backs up, moves or deletes the production save.
##
## A developer who wants a real run with progress kept just launches the game normally (no arguments).

const PRODUCTION_PATH := "user://town.json"
const DEV_PATH := "user://dev_session/town.json"
const REAL_SAVE_FLAG := "--write-production-save"

## Any user argument makes it a developer session (fail safe: a new debug flag is protected without anyone listing it here).
static func is_dev_session(args: PackedStringArray) -> bool:
	return not args.is_empty()

## True only for an explicit opt-in: a developer session that really wants to use the production save.
static func allows_production(args: PackedStringArray) -> bool:
	return args.has(REAL_SAVE_FLAG)

## The file this session's town is saved to.
static func path_for(args: PackedStringArray) -> String:
	return PRODUCTION_PATH if (not is_dev_session(args) or allows_production(args)) else DEV_PATH

## Whether the town saves at all unless something turns it off: normal play, or a developer session that opted in. (A developer session
## otherwise keeps everything in memory; a check that wants to exercise saving can switch `TownState.persist` on and gets DEV_PATH.)
static func persists_by_default(args: PackedStringArray) -> bool:
	return not is_dev_session(args) or allows_production(args)

## The one gate every write, move, copy or delete of a save file goes through.
static func may_modify(path: String, args: PackedStringArray) -> bool:
	return not path.begins_with(PRODUCTION_PATH) or not is_dev_session(args) or allows_production(args)

## Deletes this session's own save file (the developer one in a developer session). Refuses anything that would touch production.
static func delete_session_save(args: PackedStringArray) -> bool:
	var path: String = path_for(args)
	if not may_modify(path, args) or not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

static func ensure_folder(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
