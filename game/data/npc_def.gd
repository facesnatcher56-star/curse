class_name NpcDef
extends Resource
## One townsperson: who they are, how they look, what they do for the player, how they behave and what they say.
## Instances are .tres files in res://data/npcs/ (loaded by NpcDb), written by tools/write_town_defs.py.

@export var id: String = ""
@export var display_name: String = ""
## "vendor", "keeper" (bulletin board), "healer" or "recruit".
@export var role: String = ""
@export var title: String = ""
@export var model_path: String = ""
@export var height: float = 1.75
@export var clips: Array[String] = ["idle", "calm"]
## Where they stand in town (x, z); the town builder faces them toward the plaza.
@export var home: Vector2 = Vector2.ZERO
@export var traits: Array[String] = []
@export var start_happiness: float = 20.0
## A recruit's price to join the clan, and the passive skill they bring ("forager", "scout", ...).
@export var recruit_cost: int = 0
@export var clan_skill: String = ""
## Short spoken lines by situation: "greet", "idle", "return_ok", "return_dead", "hire", "farewell", and one per
## interaction type they may start ("gossip", "argue", "praise", "joke", "small_talk").
@export var lines: Dictionary = {}
