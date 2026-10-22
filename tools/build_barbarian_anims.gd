extends SceneTree
## Bakes the barbarian hero's own clip library, assets/models/barbarian/anims.res, from the knight2 clips.
##
## Review of all 41 knight clips on him (game/dev/clip_review.tscn renders, game/dev/clip_fit_check.gd measures):
##   - 35 clips reproduce the knight's motion on him (every limb within 8 degrees) with no new clipping: kept as they are,
##     adapted to his proportions by CharacterModel._borrowed (hips track moved, thigh position tracks dropped).
##   - The six two-handed attacks (atk2_*) are a knight clasping a sword hilt in front of his belly; on the barbarian's
##     much bigger chest and arms his fists sink 14-17 cm into his chest, and with no sword shown he looks to be clutching
##     himself. Each is replaced by its one-handed counterpart (same length and strike timing, so combat is unchanged)
##     until his own two-handed animations are made.
##   godot --headless --path . --script tools/build_barbarian_anims.gd    (or paste into Ziva's execute_script)

const HERO := "res://assets/models/barbarian"
const KNIGHT := "res://assets/models/knight2"
const OUT := "res://assets/models/barbarian/anims.res"
const REPLACED := {"atk2_slash": "atk_slash", "atk2_slash_l": "atk_slash_l", "atk2_slash_r": "atk_slash_r",
	"atk2_thrust": "atk_thrust", "atk2_finisher": "atk_finisher", "atk2_spin": "atk_spin"}

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var clips: Array[String] = []
	clips.assign(Player.CLIPS)
	var source := CharacterModel._borrowed(HERO, KNIGHT, clips) as AnimationLibrary
	var lib := AnimationLibrary.new()
	for clip in source.get_animation_list():
		var from: String = REPLACED.get(clip, clip)
		var animation := source.get_animation(from).duplicate(true) as Animation
		assert(is_equal_approx(animation.length, source.get_animation(clip).length), "%s replaced by a clip of another length" % clip)
		animation.loop_mode = source.get_animation(clip).loop_mode
		lib.add_animation(clip, animation)
		if from != clip:
			print("BUILD %s <- %s" % [clip, from])
	print("BUILD saved ", OUT, " clips ", lib.get_animation_list().size(), " err ", ResourceSaver.save(lib, OUT))
	quit()
