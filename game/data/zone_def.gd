class_name ZoneDef
extends Resource
## A stretch of the Crypt Road and what lives in it: how far from the town gate it runs, how tough its monsters are, and the groups the
## road is stocked with wherever the hand-placed encounters leave a gap. This is Zombasite's way of describing an area (a chance per
## stretch of holding monsters, which kinds, how many, a level offset; see docs/zombasite-world-and-npcs.md section 6) as data. Instances
## are .tres files in res://data/zones/, written by tools/write_zone_defs.py and read through TownDb.

@export var id: String = ""
@export var display_name: String = ""
## The stretch, as metres from the town gate (the road is about 320 m long).
@export var from_m: float = 0.0
@export var to_m: float = 100.0
## Added to the road's monster level here (the further out, the tougher).
@export var level_offset: float = 0.0
## The chance that a gap in this stretch gets a group at all.
@export var density: float = 1.0
## What a group can be made of: [{weight, members: [enemy id, ...]}]. A kind listed twice is two of them.
@export var groups: Array = []
