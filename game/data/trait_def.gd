class_name TraitDef
extends Resource
## A personality trait (see docs/zombasite-world-and-npcs.md, 3.3). A trait never changes stats: it re-weights what an NPC does
## in town and how they react to what others do to them.

@export var id: String = ""
@export var display_name: String = ""
## Activity id -> multiplier on how likely the NPC is to choose it.
@export var weights: Dictionary = {}
## Interaction types (what another NPC does to them) they enjoy or resent.
@export var likes: Array[String] = []
@export var dislikes: Array[String] = []
## Traits that cannot be held together.
@export var excludes: Array[String] = []
