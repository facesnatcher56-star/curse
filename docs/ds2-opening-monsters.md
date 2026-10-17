# What Dungeon Siege 2 puts in its opening: monsters, levels and groups

Read from DS2's own data (`World.ds2map` region files and the monster templates in `Logic.ds2res`), so every number below is the
game's, not a guess. Tools: `tools/ds2_map/` (extract a region with its folder paths, parse the templates, count and group the monsters).
"Hero level" is DS2's own 0-based level (a fresh hero is Level 0, see `docs/COMBAT_REFERENCE.md`). Training dummies and scripted
cut-scene extras (invincible or `_nis`/`_npc` actors, the endless "evil dryad" ambience in the trenches) are left out.

## 1. Where the opening is

The game starts in the tutorial: **a0_01_01 Western Greilyn Beach** (a start group "Beginning of Tutorial": no monsters, only soldiers and
a scripted landing), then **a0_01_02 the arena** (a forced fight), **a0_01_04 the trenches** (a battlefield) and **a0_01_05 the cave**
(the tutorial's last fight, ending in a boss). The main campaign replays the same places as `a1_01_*` (tutmedic, tutcommand, trenches, cave)
with different packs, then opens the jungle at **a1_02_01 jnglight**.

## 2. The monsters, as the templates define them (normal difficulty)

| Monster | Role / tier | Level | Life | XP it pays | XP by the usual formula | Notes |
|---|---|---|---|---|---|---|
| bracken_defender | melee, trivial | 1 | 7.6 | 14 | 25 (56%) | sight 15 m, 2 s swing |
| bracken_defender_jump | melee, trivial | 1 | 7.6 | 14 | 25 (56%) | sight 20 m; leaps up to 6 m onto you |
| forest_golem | ranged, weak | 2 | 23.8 | 30 | 54 (56%) | sight 15 m; ranged attacker |
| mystic_protector | magic, weak | 3 | 24.5 | 35 | 63 (56%) | sight 15 m; magic |
| ketril | melee, normal (tank) | 2 | 166.0 | 40 | 72 (56%) | life is a hand-set 166, not the formula |
| ketril_boss | melee, miniboss | 3 | 373.0 | 152 | 280 (54%) | life hand-set 373; power level 37.5 |

**The tutorial pays about 55% of the usual XP.** Every opening monster's `experience_value` is a hand-set number (14, 30, 35, 40, 152), each
about 0.55 of what the level/tier formula gives. That slows levelling through the tutorial. Monsters from the jungle on use the formula.

## 3. Enemy level against the hero's level

| Stretch | Monster levels | Hero level on arriving | Gap |
|---|---|---|---|
| Arena | 1 | 0 | +1 |
| Trenches | 1 to 3 | 0 (finishes at 3) | +1 to +3 |
| Cave | 1 to 3 (boss 3) | 3 | 0 to -2 |
| Jungle, first region (jnglight) | 3 to 5 (one boar-beast at 7) | 3 | 0 to +2 (+4 for the boar) |

Fighting every fightable monster in the tutorial, in order, takes the hero to **level 3** (the same level as your Half-Giant screenshot):

| Region | Fightable monsters | XP | Hero level after |
|---|---|---|---|
| Arena | 10 | 140 (total 140) | 0 |
| Trenches | 88 | 1895 (total 2035) | 3 |
| Cave | 42 | 1222 (total 3257) | 3 |

The gap never reaches DS2's 4-level XP penalty zone in the opening; monsters stand at or just above the hero.

## 4. Group composition

Groups are not rolled. Each monster is a placed actor, or a generator that spawns exactly one (a generator with no settings spawns one child).
There are no "packs" as a data object: a pack is whatever stands in the same stretch of the map. Grouping the monsters by the map nodes they
stand in (nodes are DS2's ~10 m building blocks) gives these patterns:

**Arena (forced fight)**: 10 monsters over 136 map nodes (0.07 per node). Mix: 100% defender_forced_combat.

**Trenches**: 88 monsters over 1287 map nodes (0.07 per node). Mix: 38% defender, 25% defender_jump, 16% forest_golem, 12% mystic_protector, 9% ketril.
Monsters sharing one node: 38 node(s) hold 1, 6 node(s) hold 2, 6 node(s) hold 3, 2 node(s) hold 5, 1 node(s) hold 10.

**Cave**: 42 monsters over 213 map nodes (0.20 per node). Mix: 33% ketril, 31% defender, 17% defender_jump, 10% mystic_protector, 7% forest_golem, 2% ketril_boss.
Monsters sharing one node: 17 node(s) hold 1, 9 node(s) hold 2, 1 node(s) hold 3, 1 node(s) hold 4.

What the arrangement shows:

* **The arena is one scripted fight**: 10 level-1 Bracken Defenders (5 standing, then 2 and 3 spawned), fought beside two allied mercenaries; 140 XP in all.
* **The trenches are a battlefield, not a corridor of packs.** 88 fightable monsters over about 1,300 nodes, mostly melee defenders (62%, two fifths of them
  "jump" defenders), with golems (16%), protectors (12%) and a few ketrils (9%). The soldiers and dryad skirmishers staged around you are scenery (some invincible, some
  spawned without end) and are not counted. The real enemies come in loose clusters of 3 to 12 that mix kinds: for example 4 defenders + 2 golems
  + 1 protector, or 5 defenders + 4 golems, or 4 ketrils + 4 defenders + 3 protectors + 1 jumper.
* **Jump defenders arrive in ambush bunches**: 5 stand in one node (two such bunches in the trenches), and in tutcommand there are bunches of 5, 8 and 4. They leap up to 6 m when they see you.
* **Reinforcement streams**: two generators in the trenches feed 10 more defenders into one spot, 5 each but only 2 alive per generator at a time, so the fight there is a steady 4 at once until all 10 are dead.
* **Ranged and magic monsters are usually mixed in with melee ones, but not always**: there are spots held by a lone protector, by three protectors, or by three protectors with three golems and no melee at all.
* **The cave is a long path, not a room**: 42 monsters standing in 27 separate nodes along a path about 16 doors long, in small mixed packs of 1 to 4 per node
  (a defender and a ketril, two ketrils, a golem and a defender). The Ketril boss stands in the last node with a Mystic Protector, and the next nodes back hold a
  protector and a defender: the boss has an escort.
* **Ketrils are the tutorial's elites**: 166 life against a defender's 7.6, placed 1 to 3 at a time, then 14 of them through the cave, one boss at the end.

### The first real zone (a1_02_01 jnglight): 38 monsters, levels 3 to 7

| Group (by node) | Make-up | Levels |
|---|---|---|
| Haku camp | 3 slayers + 1 shaman | 3 and 4 |
| Morden outpost | 2 thugs + archer leader + trainee | 5 |
| Slayer ambush | 2 camouflaged slayers (jump) | 3 |
| Hunter line | 4 hunters (ranged), and a separate pair of 2 | 4 |
| Slayer + hunter bunch | 2 slayers + 1 hunter (jump) | 3 and 4 |
| Haku drum circle | 3 slayers + 1 drummer | 3 and 5 |
| Guard post | 2 outpost thugs, then 1 outpost soldier | 3 |
| Boar den | 4 hunters + 1 boar-beast (strong, life 210) | 4 and 7 |

Slayers (melee, trivial, life 15) are the fodder; hunters (ranged, weak), shamans and drummers (normal, 56 to 112 life) are the supports; a
boar-beast (strong) is the one big thing. Groups are 1 to 5, always mixed melee with ranged or support.

## 5. Against Curse's opening road (`RoadEncounterRoster`)

| | DS2 opening | Curse opening road |
|---|---|---|
| Monsters in the opening | 140 fightable in the three tutorial fights | 61 over the whole road (cap 64) |
| Monster levels | 1 to 3 in the tutorial, 3 to 7 in the first jungle region | 1 to 6 |
| Group size | 1 to 4 mixed per spot, bunches of 4 to 8 jumpers, 10-strong reinforcement streams | 2 to 3, mostly zombies |
| Mix | melee trivial 61%, ranged 12%, magic 11%, tank or elite 16% | mostly zombies, with ghouls and rock throwers added from level 2, then brutes and a warden |
| XP per level-1 trivial kill | 14 (hand-set, about 0.55 of formula) | 25 (formula) |
| Ambushes | jump defenders in bunches | none |
| Boss | Ketril boss (level 3, life 373, XP 152) with a protector escort | warden (level 6) at the end of the road |

