# Architecture

> **Art direction (gritty and versatile) governs every asset: see [docs/ART_DIRECTION.md](docs/ART_DIRECTION.md) and [CLAUDE.md](CLAUDE.md).**

A Godot 4 click-to-move ARPG: fixed 3/4 camera, weighty melee, wave arena. Scripts live in `game/`, tunable data in `data/`.

## Layout

| Path | What lives there |
| --- | --- |
| `game/main.gd` | Builds the world (arena, hero, camera, HUD, menus) and creates the `RunDirector`. ~4 KB. |
| `game/run/run_director.gd` | The run: wave composition and spawning, kill tracking, the reward offered between waves. |
| `game/player.gd` | The hero node: input, cursor picking, orchestration of the components below, hit hooks. |
| `game/player/` | `PlayerStats` (mana/stamina/potions, cooldowns, equipment + affix queries, regen), `PlayerMovement` (click-to-move, locomotion animation, dodge roll), `SkillController` (hotkeys, aim preview, starting/ticking skills, combo, strike effects). |
| `game/skills/` | `SkewerSkill`, `LeapSkill`, `EarthshatterSkill` (the ultimate: charges from damage dealt, `PlayerStats.ult_charge`): self-contained skill state machines. |
| `game/enemy.gd`, `game/enemies/` | `Enemy` is the shared body (stats from its `EnemyDef`, aggro/stun, movement helpers, attack slots). `EnemyBehavior` subclasses decide what it does: `MeleeBehavior`, `PouncerBehavior`, `SpitterBehavior`, `BloaterBehavior`, `SupportBehavior`. `AcidGlob` and `HazardZone` are their effects. |
| `game/actor.gd` | Base of hero and enemies: health, hit reaction, burn/frost/ward/daze, ragdoll, gib bursts. |
| `game/data/` | Resource classes (`EnemyDef`, `SkillDef`, `AffixDef`) and their loaders (`EnemyDb`, `SkillDb`, `AffixDb`). |
| `data/` | The `.tres` files those loaders read: `data/enemies`, `data/skills`, `data/affixes`. |
| `game/gamepad.gd`, `game/input_setup.gd` | Controller support: sticks, aim, labels, rumble; all buttons are ordinary input actions, rebindable in Settings > Controls (keyboard/mouse and controller columns). |
| `game/loading_screen.gd` | Loading bar with real progress (assets load on background threads) and rotating messages; the menu's Play and the pause menu's Restart go through it. |
| `game/dev/dev_harness.gd` | Developer tooling: the headless self-test and the screenshot/pose tools. Not part of the game. |
| `game/night_sky.gd`, `game/night_sky.gdshader` | The night sky behind every scene (stars, a moon, drifting cloud streaks). `NightSky.apply(environment)`; it is painted on every direction, below the horizon too, because the 3/4 camera looks down and only sees it beyond the edge of the map. |
| `game/item_effects.gd`, `game/ember_trail.gd` | What worn affixes do (data in `data/affixes`, written by `tools/write_affix_defs.py`; the hooks here are keyed by affix id). Several are built to combine with skills and with each other: fire states (Kindling, Pyrebound, Smouldering, Ember-Treaded), thrown and stunned states (Juggler's, Breaker's, Maelstrom), skill chaining (Virtuoso's, Vaultborn, Wildfire, Ramming, Impaler's, Quakebound). |
| `game/ui_theme.gd` | The one UI look (worn metal, bronze trim, ember accent, muted bars): the Theme for menus plus drawing helpers for the HUD (`UiTheme.draw_panel`, `draw_bar`, `text` with a shadow). Use these for any new UI so it matches. |
| `game/destructible.gd`, `game/debris_chunk.gd` | `Destructible`: breakable props (barrels, carts, gravestones, braziers; see `STATS`). The arena builds them in `_place`. `Destructible.blast(tree, centre, radius, damage, dir, force)` is how anything breaks them: swings, Power Strike, Cleave, fireballs, bloater bursts, Earthshatter, and (force 2+, damage 999) a Skewer charge or a Leap, which throw the pieces along the path. Clicking a prop sends the hero to swing at it. Breaking one frees its collision and re-bakes the navmesh, and may drop a potion, a healing orb or an item. |
| `game/loot_drop.gd` | `LootDrop`: an item lying on the ground after a monster died (tossed from the body, rarity glow and name, picked up by walking over it). Monsters roll drops from `EnemyDef.drop_chance`/`drop_luck` (`Items.roll_drop`); `PlayerStats.pickup` fills an empty slot and sends anything else to the bag (rarity never swaps gear on its own), which goes to the town stash when a job run ends. There is no reward screen between waves any more. |
| `game/town/` | The hub between runs. `TownScene` (the plaza, gate, stone, board, stash, people), `TownNpc`, `TownPanel` (trader, jobs, healer, recruit, stash, gate), `TownHud`, `TownStage` (acts the sim out: people walk to each other to gossip, argue and brawl, and to the barrels, the stone and their stations to drink, pray and work), `TownSim` (what NPCs do all day: activities weighted by traits, likes and dislikes, opinions, brawls, leavers, events), `TownState` (everything that outlives a run: gold, food, gear, stash, moods, opinions, the board; saved to `user://town.json`). Play on the main menu opens the town; its gate starts the job you took (or a free run) and a finished or failed job comes back here. Design notes: [docs/zombasite-world-and-npcs.md](docs/zombasite-world-and-npcs.md). |
| `tools/` | Asset pipeline (Meshy generation, animation baking) and the generators for the `.tres` data files. |

## Data first

Skills, enemies and affixes are Resources, not dictionaries in scripts.

* **Edit a number**: change the table in `tools/write_enemy_defs.py` / `write_skill_defs.py` / `write_affix_defs.py`, run it, and the `.tres` files regenerate. (The `.tres` files can also be edited by hand or in the Godot inspector.)
* **Add an enemy**: add an entry to `write_enemy_defs.py` (stats, model path, `behavior`, `params`, spawn rules). If it needs new behaviour, write an `EnemyBehavior` subclass and add it to `EnemyBehaviors.create`. Waves pick it up from its spawn fields (`min_wave`, `base_count`, `per_wave`, `max_per_wave`, `spawn_mode`).
* **Add a skill**: add a `SkillDef` entry. Skills of an existing `kind` need no code; a new kind gets a branch in `SkillController` (or its own state machine in `game/skills/`, like Skewer and Leap).
* **Add an affix**: add the catalogue entry, then the behaviour hook in `item_effects.gd` keyed by its id.

* **Town data**: `tools/write_town_defs.py` writes `data/npcs` (`NpcDef`: Marlow the trader, Hale the keeper, Maren the healer, Cutter the recruit, Dorn the smith), `data/traits` (`TraitDef`) and `data/modifiers` (`RunModifierDef`). A run modifier (it belongs to the run, not to a kind of objective) is only multipliers (enemy spawn weights, health, speed, size, ambient light, fog, reward) applied by `RunDirector`, so adding one is a table entry. A new NPC is an entry plus a Meshy model (`tools/assets.json`, then bake its animations).
* **Town buildings and clutter**: `tools/blender/make_town_props.py` builds the forge, inn, chapel, granary and the small clutter (anvil, crates, wood pile, trough, drying rack, laundry line) into `assets/models/town/<name>/model.glb`, using the item script's palette and weathering plus a densify/warp and plank, shingle and grime pass so they match the Meshy cottages. They are placed by name `town/<name>` in `TownScene._build_town`; `Arena._place` switches their vertex colours on.
* **Town layout**: the static town is the scene `game/town/town_layout.tscn`, edited in Godot. `TownProp` nodes under `Props` (model, height, collides, lit; a preview shows in the editor) are the buildings, walls, lamps and clutter; `Marker3D`s under `Spots` are what you walk up to (gate, stone, board, stash) and under `Stations` where people go (`drink`, `pray`, `work_<role>`). `TownScene` places each prop through `Arena.place_prop` and deletes the markers; scripts keep the NPCs, interactions, simulation, state and transitions. NPC homes are still `NpcDef` data. To add a building, add a `TownProp` and set its `model_name`.
* **Items**: base items are data. `tools/write_item_defs.py` writes `data/items/*.tres` (`ItemDef`: id, name, slot, model, icon, base stats and how they grow per tier), read through `ItemDb`. An item in the world is still a Dictionary built by `Items.build` (`{def, tier, slot, rarity, name, base, stats, affix, flavor}`), but a save keeps only `{def, tier, rarity, affix}` (plus a unique's name) via `Items.to_save` and rebuilds it with `Items.from_save`, so changing a base's numbers or model reaches every copy and an item or affix that was removed is dropped on load instead of breaking the save. Save version 2 rewrote old whole-item saves (the version 1 migration step).
* **Jobs**: a job is `{name, location, objective, modifiers, reward}`. `JobObjective` (`game/run/job_objective.gd`) is the only place that knows what an objective means (`clear_waves` today, the test arena's wave loop; kill a target, destroy a nest, rescue, hold a place and so on get a case there). The board, town HUD and `RunDirector` ask it to describe, count and finish a job, so none of them mention waves. Modifiers start at an objective *stage* (`min_stage`), which for `clear_waves` is the wave number.

## Tests and CI

`godot --headless --path . res://game/main.tscn -- --selftest` runs every check in `game/dev/dev_harness.gd`; each check calls `expect(label, condition)` and the process exits non-zero if any fail. `--only=NAME` runs one (`gibs`, `swarm`, `enemies`, `leap`, `earthshatter`, `impact`, `fireblast`, `balance`, `items`, `autoattack`). `tools/run_godot.sh LOG SECS -- <args>` runs Godot and kills it the moment a script/parse error appears instead of waiting for a timeout. `-- --timing` prints how long each stage of starting a run takes. `.github/workflows/selftest.yml` runs the full suite on every push and pull request.

Screenshot modes (`--skillshot=…`, `--enemyshot`, `--enemyfight`, `--clipsheet=…`, `--poses`, …) write PNGs to `%TEMP%` for judging visuals by eye.

## Assets

Model textures are imported GPU-compressed (VRAM) and capped at 1024 px (hero 2048): lossless 2k textures made every prop take ~280 ms to load. Large binaries (`*.glb`, `*.res`, `*.jpg`, audio, video) are stored with Git LFS (see `.gitattributes`). Dropped-item models are made in Blender (`tools/blender/make_items.py`, painted on the vertices, no textures). Models, rigs, animations and icons come from Meshy via `tools/meshy.py` / `meshy_icons.py`; `tools/bake_anims.gd` bakes animations into small `anims.res` files.
