class_name WaveModifierDef
extends Resource
## A rule that changes what a job's waves are like (see docs/zombasite-world-and-npcs.md, section 6): which enemies turn up, how
## tough or quick they are, how dark and foggy it is. Instances are .tres files in res://data/modifiers/, written by
## tools/write_town_defs.py. Everything is a multiplier, so modifiers stack.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
## Enemy id -> multiplier on how many of that enemy a wave brings (an enemy that is not in the wave's table stays out).
@export var spawn_weights: Dictionary = {}
@export var count_mult: float = 1.0
@export var health_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var size_mult: float = 1.0
## Scene mood: ambient light and fog density multipliers (below 1 darker / thinner, above 1 brighter / thicker).
@export var ambient_mult: float = 1.0
@export var fog_mult: float = 1.0
## Pays more (or less) gold when the job is done.
@export var reward_mult: float = 1.0
@export var min_wave: int = 1
## Modifiers this one cannot be combined with.
@export var excludes: Array[String] = []
