class_name QuestDef
extends Resource
## One quest or event, as data (see docs/zombasite-world-and-npcs.md, section 5: Zombasite builds its whole world out of these, each with a
## chance to turn up on its own and links that start other ones). Instances are .tres files in res://data/quests/, written by
## tools/write_quest_defs.py. The logic that posts, measures, pays and chains them is `Quests` (game/town/quests.gd).
##
## kind:
##   kill_group  kill `count` of enemy `target` out on the road ("" = anything)
##   slay_unique a named monster (`unique_name`, a tougher `target`) stands somewhere on the road; kill it
##   fetch       an item `item_name` is carried by some `target` monsters: kill them until it drops, pick it up
##   matter      something happening in town that wants a decision: `choices` (each may cost something and may be a gamble)
##   world       the whole world changes for a few days (`world_mod`); nobody posts it
## Quest kinds are handed in to `giver` (a townsperson id); matters are resolved by talking to the giver.

@export var id: String = ""
@export var title: String = ""
## What the giver says when it turns up. {victim} and {suspect} name a townsperson picked when it is posted.
@export_multiline var text: String = ""
@export_multiline var thanks: String = ""
@export_multiline var fail_text: String = ""
@export var kind: String = "kill_group"
@export var giver: String = "hale"
## Relative chance of being the next one to turn up (0: only ever started by another quest's link).
@export var weight: float = 1.0
@export var min_jobs: int = 0
## Days to do it in (a day passes each time the hero comes back from the road); 0: no deadline.
@export var days: int = 0
@export var target: String = ""
@export var count: int = 1
@export var unique_name: String = ""
@export var unique_hp: float = 3.0
## The quest monster's own threat: absolute, on the same scale as `ZoneDef.base_threat` (an enemy's `level_scale`), not a multiplier of the zone's.
@export var unique_level: float = 1.3
## Roughly where on the road it is (distance from the town gate, in metres: the road is about 320 m long).
@export var zone: Vector2 = Vector2(60.0, 200.0)
@export var item_name: String = ""
## Gold, food, potions, item (a rarity to roll: 0 common, 1 rare, 2 unique), happy ({npc id or "all": change}), relation ([[a, b, change]]).
@export var reward: Dictionary = {}
@export var penalty: Dictionary = {}
## For matters: [{label, cost: {gold, food, potions}, outcome: "solve" | "fail" | "gamble", chance, result, reward, penalty}].
@export var choices: Array = []
## Other quests this one can start: {"start": [{quest, chance}], "complete": [...], "fail": [...]}.
@export var links: Dictionary = {}
## For world events: {gold_mult, drop_mult, health_mult, days}.
@export var world_mod: Dictionary = {}
