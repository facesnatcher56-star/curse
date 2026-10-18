# The Crypt (`crypt_01`): how it is built and how to edit it

A hand-designed dungeon made from the KayKit GridMap kit, dressed with ProtonScatter. Reached only with
`-- --crypt01` (Menu -> Play still loads the test dungeon until the owner says to switch). There is no dev-menu
entry: the main menu has none.

```
godot --path . --screen 1 -- --crypt01
```

Layout: 13 spaces on a 4 m grid (start vestibule, long hall, pillared crypt, ossuary, choke-point corridor, rotunda,
guard hall, antechamber and the final arena, plus three side rooms with a chest each), 22 doorways, one loop (pillared
crypt -> ossuary -> rotunda beside the choke point). Overview: `docs/screenshots/crypt01/crypt_overview.png`
(`crypt_overview_packs.png` marks the 19 packs).

## Where things live

| What | Where |
|---|---|
| The level (source of truth) | `game/world/dungeons/crypt_01.tscn` |
| The plan it was written from, the route, the packs | `game/world/crypt_layout.gd` (`CryptLayout`) |
| Loader (walls made solid, navigation bake, packs spawned) | `game/world/crypt_dungeon.gd` (`CryptDungeon extends TestDungeon`) |
| Writer (run to start over) | `tools/build_crypt_01.gd` -> `game/dev/crypt_baker.gd` |
| Checks | `--only=crypt01` (`game/dev/suites/crypt_dungeon_tests.gd`), `game/dev/dungeon_walk.gd -- --crypt01 [--loop]`, `game/dev/crypt_nav_check.gd`, shots + FPS `game/dev/crypt_shots.gd`, top-down `tools/render_crypt_overview.gd` |

The scene holds these groups: `Floor` (GridMap), `Walls` (four GridMaps, one per edge direction: `WallsN/E/S/W`),
`Pillars` (wall posts on every corner), `Props` (breakable barrels, crates, urns), `SetPieces` (sarcophagi, altars,
pillars, statues: solid), `Decor`, `Torches` (model + flickering light), `Scatter` (one ProtonScatter per space),
`Chests`, `EnemyGroups` and `PlayerStart`.

## Editing in the Godot editor

* **Floor and walls (GridMap).** Open the scene, select a GridMap, pick pieces from the MeshLibrary
  (`assets/third_party/kaykit_dungeon/dungeon_meshlib.tres`) and paint. One cell holds one item, so floors and the four
  wall directions are separate GridMaps. A wall piece sits on the cell's north edge at rotation 0; the maps are already
  rotated for E, S and W. Use `wall_doorway` where two spaces meet. The camera looks north, so south edges use the low
  `barrier`. **Collision is not the GridMap's:** the library's convex hulls would close doorways, so `CryptDungeon.make_solid`
  builds boxes from the wall cells when the game loads (a doorway gets two jambs and a 2.2 m opening). Paint, save,
  play: no extra step. The navigation mesh is baked on load from those boxes and the props.
* **Corridors stay empty.** A 4 m passage has about 2 m of walkable width; a prop in it can close the navigation mesh
  (the walk check found exactly that once).
* **Scatter.** Each `Scatter/Scatter_<space>` is a `ProtonScatter`: its `ScatterShape` children define where, its
  `Item_*` children what (set `proportion`), its modifier stack how many and how rotated. Move or resize a shape, change
  `Amount` in "Create Inside (Random)". Items are the kit's bones, skulls, candles and bricks. Do not add the kits'
  rocks and rubble: they are bigger than the hero (`rubble_half` is 4 x 3.5 x 3 m; so is the boulder on
  `floor_tile_large_rocks`). The scatter's output is not saved; it is built when the scene loads.
* **Props and set pieces.** Move them in the tree. Breakables are `Destructible` nodes (metadata `prop_kind`,
  `prop_height`, `obstacle_radius` make them breakable and solid when loaded); set pieces carry `obstacle_radius`.
  Chests are `Chest` nodes under `Chests` (one at the far end of each side room). Torches: a model plus an `OmniLight3D`
  with a `FlickerLight` child; the shared atmosphere profile warms them (`--classic` turns it off).
* **Enemy markers.** `EnemyGroups` holds `DungeonEnemyGroup` markers, exactly as in the test dungeon (see its class
  comment): position = home, the counts in the Inspector = what is in the pack, `behaviour` = stand/wander. Their
  `area` is the **stage** (0..7: how far along the way in, not a room: the editor's list still reads "Entry hall,
  Corridor 1 ..."), which decides the level: the level the hero is projected to be on reaching it, never above
  (`TestDungeon.project`). Pack rules to keep: 4-8 bodies, about one pack in five with an elite (brute or warden), no
  more than ~9 s of walking along the main route without a pack within 14 m, the first pack in sight of `PlayerStart`.
  `--only=crypt01` checks all of these. The final arena's warden pack is stage 7.

## After moving a room

The tests and walk check read the route and the pack rule from `CryptLayout`, not from the scene. If you move
rooms, update `CryptLayout.SPACES`, `MAIN_PATH`, `LOOP_PATH` and `PACKS` to match (or re-run the writer to start over:
`godot --headless --path . -s res://tools/build_crypt_01.gd`, which **replaces hand edits**). Then:

```
godot --headless --path . res://game/main.tscn -- --selftest --only=crypt01
godot --headless --path . -s res://game/dev/dungeon_walk.gd -- --crypt01          # main route
godot --headless --path . -s res://game/dev/dungeon_walk.gd -- --crypt01 --loop   # through the ossuary
godot --headless --path . -s res://game/dev/crypt_nav_check.gd -- --crypt01       # every space and doorway reachable
```

## Known gaps

* The round chamber is a stepped cross with a ring of eight pillars and a central altar: the kit has no curved or
  diagonal walls.
* Sarcophagi are plain stone boxes (the packs have none). Art direction is undecided (`docs/ART_DIRECTION.md`).
* Wall pieces on the camera's side (south edges) are low barriers; north, east and west walls are the full 4 m.
