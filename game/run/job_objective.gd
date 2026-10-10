class_name JobObjective
extends RefCounted
## What a job asks of the hero. A job is {name, location, objective, modifiers, reward}; the objective is a Dictionary with a "type"
## and that type's own fields, so the town, the board and the reward do not care how a job is won. Today there is one type,
## "clear_waves" ({count}), which is the test arena's wave loop, and "destroy_nest" ({count}): an authored location (the Crypt Road)
## holds that many nests; there are no waves, the monsters are simply out there. New types (kill a target, rescue, clear a dungeon,
## recover an item, hold a place, escort) get their own case in each function here and need nothing changed in the town.
##
## "Stage" is a type's own measure of progress (for clear_waves, the wave number; for destroy_nest, the nests destroyed so far);
## modifiers can start at a later stage.

const CLEAR_WAVES := "clear_waves"
const DESTROY_NEST := "destroy_nest"

static func clear_waves(count: int) -> Dictionary:
	return {"type": CLEAR_WAVES, "count": count}

static func destroy_nest(count: int) -> Dictionary:
	return {"type": DESTROY_NEST, "count": count}

static func objective_of(job: Dictionary) -> Dictionary:
	return job.get("objective", {})

## How many stages the objective has (waves to clear, for clear_waves); 0 when it has no fixed length.
static func stages(job: Dictionary) -> int:
	var objective: Dictionary = objective_of(job)
	match String(objective.get("type", "")):
		CLEAR_WAVES, DESTROY_NEST:
			return int(objective.get("count", 0))
	return 0

## Whether the job is won, given the run's progress ({"stage": n}).
static func is_complete(job: Dictionary, progress: Dictionary) -> bool:
	if bool(progress.get("climax_cleared", false)) or bool(progress.get("forecourt_cleared", false)):
		return true
	match String(objective_of(job).get("type", "")):
		CLEAR_WAVES, DESTROY_NEST:
			return int(progress.get("stage", 0)) >= stages(job)
	return false

## Whether the job is played as the test arena's wave loop (a free run is too). Objectives set in an authored location are not.
static func uses_waves(job: Dictionary) -> bool:
	return job.is_empty() or String(objective_of(job).get("type", CLEAR_WAVES)) == CLEAR_WAVES

## Whether finishing the objective sends the hero home at once. A wave job does; in an authored location the hero may keep
## exploring and looting and walks back out to hand it in.
static func ends_run_when_complete(job: Dictionary) -> bool:
	return uses_waves(job)

## One line for the board and the HUD: what you have to do.
static func describe(job: Dictionary) -> String:
	var objective: Dictionary = objective_of(job)
	match String(objective.get("type", "")):
		CLEAR_WAVES:
			return "Clear %d waves" % int(objective.get("count", 0))
		DESTROY_NEST:
			return "Destroy %d corrupted nests" % int(objective.get("count", 0))
	return "Free run"

## How far along it is, for the wave banner ("" when the objective has no steps to count).
static func progress_text(job: Dictionary, progress: Dictionary) -> String:
	if bool(progress.get("climax_cleared", false)) or bool(progress.get("forecourt_cleared", false)):
		return "Forecourt secured — Return to Last Hearth"
	match String(objective_of(job).get("type", "")):
		CLEAR_WAVES:
			return "wave %d of %d" % [int(progress.get("stage", 0)), stages(job)]
		DESTROY_NEST:
			return "Destroy nests: %d / %d" % [int(progress.get("stage", 0)), stages(job)]
	return ""

## A job saved before objectives existed ({waves: n}) becomes {objective: clear_waves(n)}.
static func upgrade_legacy(job: Dictionary) -> Dictionary:
	if not job.has("objective") and job.has("waves"):
		job["objective"] = clear_waves(int(job["waves"]))
		job.erase("waves")
	if not job.has("location"):
		job["location"] = String(job.get("name", "")).trim_prefix("Clear ").trim_prefix("Hold ")
	return job
