class_name EnemyArt
extends RefCounted
## Opt-in staged enemy art. Only with the `--enemyart` user argument (`godot -- --enemyart`) does the zombie
## use the converted low-poly model in assets/art_staging; every other run, and every other enemy, keeps the
## live model_path. Nothing here changes AI, attacks, hitboxes or balance.

const FLAG := "--enemyart"
const ZOMBIE_CONVERTED := "res://assets/art_staging/enemies/zombie_converted"


static func enabled() -> bool:
	return OS.get_cmdline_user_args().has(FLAG)


## The model folder an enemy definition should load. Falls back to the live folder when the flag is off or
## the staged folder is missing its files.
static func model_folder(def: Resource) -> String:
	var live: String = def.model_path
	if not enabled() or def.id != "zombie":
		return live
	if ResourceLoader.exists(ZOMBIE_CONVERTED + "/rigged.glb") and ResourceLoader.exists(ZOMBIE_CONVERTED + "/anims.res"):
		return ZOMBIE_CONVERTED
	return live
