# The map-mode dungeon (`map_mode_01`): where things live and how to edit it

A dungeon built as a GRAPH for map mode: rooms are nodes, corridors are paths. Same GridMap kit, loader and look as the Crypt
(`docs/CRYPT_DUNGEON.md`); the Crypt itself is untouched. Reached with `-- --mapmode` (alone). `-- --crypt01 --mapmode` is still the Crypt with map mode.

```
godot --path . --screen 1 -- --mapmode
```

15 nodes, 16 corridors: start (0), 9 enemy nodes (6 packs, one 28-body swarm, 2 champion packs), 4 rewards (2 chests, 2 shrines), the boss (11).
Forks at nodes 1, 3, 4, 6, 9, 10, 14; the swarm and node 3 are alternatives (1 -> 2 -> 4 or 1 -> 3 -> 4); the rewards are dead-end spurs; the fastest
route to the boss skips two enemy nodes. Rooms are 40 m or more apart (home to home).
**Layout (owner-approved redesign, 2026-10-22):** rooms that join sit side by side in bands (Cloister - Iron Vestry - Charnel Pit, Reliquary - Drowned
Nave - Ghoul Warren, then the T-shaped Ossuary gallery), corridors are 2 cells (8 m) wide and 2 to 6 cells (8-24 m) long, doors sit in or near the middle
of walls, every fighting room has cover pillars (`NODES` `cover`), and the round boss court has a black rim outside its wall that hides the floor
cells the curve clips. 52 x 84 cells; the walk from the Landing to the boss is about 430 m (it was about 610 m).

## Where things live

| What | Where |
|---|---|
| The plan: nodes, corridors, the **contract the node-map UI reads** | `game/world/map_mode_layout.gd` (`MapModeLayout`) |
| The level (source of truth once baked) | `game/world/dungeons/map_mode_01.tscn` |
| Loader (names it, captures node -> group / chest / shrine, deterministic champions) | `game/world/map_mode_dungeon.gd` (`MapModeDungeon extends CryptDungeon`) |
| Shrine (heals and restores the party once) | `game/world/shrine.gd` (`Shrine.use_shrine()`) |
| Writer (rebakes the scene from the plan) | `tools/build_map_mode_01.gd` -> `game/dev/map_mode_baker.gd` (extends `game/dev/crypt_baker.gd`) |
| Checks | `--only=mapdungeon` (`game/dev/suites/map_mode_dungeon_tests.gd`), `game/dev/map_mode_nav_check.gd`, shots `game/dev/map_mode_shots.gd` |

The Crypt's loader got three tiny hooks (`scene_path()`, `zone_title()`, `_scene_read()`); the Crypt's baker reads its plan through a `L` variable
(`CryptLayout` by default) so `MapModeBaker` can hand it `MapModeLayout`. Behaviour for the Crypt is unchanged.

## The contract (`MapModeLayout`, pure static data)

* `nodes() -> Array[Dictionary]`: `{id, kind (start|pack|swarm|champion|chest|shrine|boss), name, pos (Vector2, world x/z, on the navigation mesh), groups ([[kind, count]]), champion ("" or e.g. "Swift Ghoul")}`.
* `links() -> Array[Dictionary]`: `{a, b, waypoints (Array[Vector2], from a's pos to b's pos, straight segments, all on the mesh)}`. Undirected.
* `start_id()` is 0, `boss_id()` is 11.
* Scene markers: each combat node is a `DungeonEnemyGroup` named `Node<id>`, each chest a `Chest` named `Node<id>` (under `Chests`), each shrine a `Marker3D` named `Node<id>` under `Shrines` (with an altar prop in `SetPieces`).
* After `spawn_encounters`, `MapModeDungeon` holds `node_groups` (node id -> `Enemy.group_id`), `node_chests` (id -> `Chest`), `node_shrines` (id -> `Shrine`).
* Champions: the two champion nodes (4: Swift Ghoul, 8: Warded Brute) carry a `map_champion` metadata flag on their marker; the loader switches the random champion roll off while spawning and attaches exactly those two with `Champion.attach`.

## How to edit

* **The graph / rooms.** Edit `NODES` (room rectangle in 4 m cells, `extra` rectangles for a shaped room, centre = where the party arrives = the pack's home, groups, stage, `cover` cells for pillars) and `LINKS` (a polyline of cell coordinates from room centre to room centre, running on the x.5 line between a corridor's two cells; the cells of its axis-aligned runs outside the rooms become the corridor, `CORRIDOR_WIDTH` cells wide, and the points are the waypoints). Two spaces that touch get a doorway between them, so rooms and corridors may only touch where the graph joins them. Add chamfers in `CUTS` only to rooms whose doors are mid-wall. Then rebake:
  `godot --headless --path . -s res://tools/build_map_mode_01.gd` (replaces hand edits to the scene).
* **By hand in the editor.** Open the scene: paint the GridMaps, move props, scatter and markers, exactly as for the Crypt. If you move a room or a marker, keep `MapModeLayout` in step (the tests read the plan *and* the scene).
* **Keep rooms apart.** No enemy's wake reach (its `aggro_range`, or a ranged thrower's `fire_range`) plus its pack's spread may reach another group's bodies or the party's arrival spot; the test enforces a margin and 40 m between homes.
* A corridor is 8 m wide (two cells): nothing may stand on a corridor's line (the baker keeps props, braziers and sarcophagi 2.6 to 3.4 m off every link path, and cover must be placed off it too).
* **Walking-game packs** (`MapModeDungeon.corridor_packs`, not in map mode) stand wherever 12.5 m of a link has been walked with no pack within 14 m, on a corridor cell or a room cell at least 28 m from every room's own group, so no walk is longer than 40.5 m (9 s) with nothing in view.

## Checks

```
godot --headless --path . res://game/main.tscn -- --selftest --only=mapdungeon
godot --headless --path . -s res://game/dev/map_mode_nav_check.gd -- --mapmode        # real navigation bake: waypoints, straight walks, groups, champions, shrines
godot --path . --screen 1 -s res://game/dev/map_mode_shots.gd --resolution 1920x1080 -- --mapmode --shots=<dir>
```

## Run-time estimate (assumptions, in the test)

Party runs 4.5 m/s. Fighting per body: zombie 3 s, ghoul 5, rock thrower 5, brute 14, warden 55; a champion +25 s; 8 s clean-up per cleared group; 12 s per chest or shrine.
Fastest route to the boss about 8.7 min, everything cleared about 15.8 min; a typical run (the mean) about 12 min. The test requires the mean in 10 to 15 minutes.
With the map's dash (1 s per hop) the walking part collapses and the fights are what is left (about 7 to 12 minutes).

## Known gaps

* Not played through by hand: the run-time model is arithmetic, not a measured playthrough.
* Only one screenshot set (1920x1080, screen 1): the start room, a corridor, the swarm room, a shrine, the chest room and the boss arch.
* The kit's usual gaps apply (south walls are low barriers; see `docs/CRYPT_DUNGEON.md`).
