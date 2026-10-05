class_name EnemyDef
extends Resource
## Everything that makes one kind of enemy: stats, model and animations, how it behaves, and where it shows up in a run.
## Instances are .tres files in res://data/enemies/ (loaded by EnemyDb); `behavior` names an EnemyBehavior class and
## `params` holds that behaviour's tuning numbers, so a new enemy is usually data plus (at most) one small behaviour.

@export var id: String = ""
@export var display_name: String = ""

@export_group("Model")
@export var model_path: String = ""
## Used until the real model exists: borrow another enemy's model, scaled and (optionally) tinted.
@export var fallback_model_path: String = "res://assets/models/zombie"
@export var model_scale: Vector3 = Vector3.ONE
@export var height: float = 1.75
@export var radius: float = 0.42
@export var clips: Array[String] = ["idle", "walk", "attack", "hit", "death"]
@export var gib_color: Color = Color(0.42, 0.48, 0.37)

@export_group("Stats")
@export var health: float = 60.0
@export var damage_min: float = 6.0
@export var damage_max: float = 10.0
@export var speed: float = 2.4
@export var attack_range: float = 1.6
@export var attack_time: float = 1.1
@export var armor: float = 8.0
@export var defense: float = 12.0
@export var attack_rating: float = 28.0
@export var flinch: float = 0.35
@export var knock_resist: float = 0.0
@export var stun_resist: float = 0.0
@export var impalable: bool = true
@export var aggro_range: float = 12.0   # metres at which an enemy notices the hero (each enemy rolls 60-100% of this)

@export_group("Melee clip")
## Strike timing measured from the clip (see tools/anim_timing.gd): clip seconds where the swing starts, lands and ends.
@export var attack_clip: String = "attack"
@export var attack_start: float = 0.6
@export var attack_strike: float = 1.43
@export var attack_end: float = 2.0

@export_group("Behaviour")
@export var behavior: String = "melee"
@export var params: Dictionary = {}
## How many of the hero's "attackers at once" slots this enemy takes up.
@export var token_weight: int = 1

@export_group("Loot")
## Chance of dropping an item when killed, and how lucky the drop is (0 ordinary, 1 a Brute: rare or better, often unique).
@export var drop_chance: float = 0.0
@export var drop_luck: float = 0.0

@export_group("Spawning")
@export var min_wave: int = 1
## "pack" (clustered with its own kind), "solo" (scattered, alone) or "support" (placed behind a pack).
@export var spawn_mode: String = "pack"
## Rough count per wave: base + per_wave * (wave - min_wave), capped at max_per_wave. 0 = never spawned by waves.
@export var base_count: float = 0.0
@export var per_wave: float = 0.0
@export var max_per_wave: int = 0

func param(key: String, fallback: Variant) -> Variant:
	return params.get(key, fallback)
