class_name EnemyArt
extends RefCounted
## Opt-in staged enemy art. Only with the `--enemyart` user argument (`godot -- --enemyart`) do the enemies in
## CONVERTED use their converted low-poly model in assets/art_staging; every other run, and every other enemy
## (including the brute), keeps the live model_path. Nothing here changes AI, attacks, hitboxes or balance.

const FLAG := "--enemyart"
## Enemy id -> converted model folder. The brute is intentionally absent: it stays on its live model.
const CONVERTED := {
	"zombie": "res://assets/art_staging/enemies/zombie_converted",
	"ghoul": "res://assets/art_staging/enemies/ghoul_converted",
}


static func enabled() -> bool:
	return OS.get_cmdline_user_args().has(FLAG)


## The model folder an enemy definition should load. Falls back to the live folder when the flag is off or
## the staged folder is missing its files.
static func model_folder(def: Resource) -> String:
	var live: String = def.model_path
	if not enabled() or not CONVERTED.has(def.id):
		return live
	var folder: String = CONVERTED[def.id]
	if ResourceLoader.exists(folder + "/rigged.glb") and ResourceLoader.exists(folder + "/anims.res"):
		return folder
	return live
