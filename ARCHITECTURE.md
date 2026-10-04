# Architecture

A Godot 4 click-to-move ARPG: fixed 3/4 camera, weighty melee, wave arena. Scripts live in `game/`, tunable data in `data/`.

## Layout

| Path | What lives there |
| --- | --- |
| `game/main.gd` | Builds the world (arena, hero, camera, HUD, menus) and creates the `RunDirector`. ~4 KB. |
| `game/run/run_director.gd` | The run: wave composition and spawning, kill tracking, the reward offered between waves. |
| `game/player.gd` | The hero node: input, cursor picking, orchestration of the components below, hit hooks. |
| `game/player/` | `PlayerStats` (mana/stamina/potions, cooldowns, equipment + affix queries, regen), `PlayerMovement` (click-to-move, locomotion animation, dodge roll), `SkillController` (hotkeys, aim preview, starting/ticking skills, combo, strike effects). |
| `game/skills/` | `SkewerSkill`, `LeapSkill`: the two self-contained skill state machines. |
| `game/enemy.gd`, `game/enemies/` | `Enemy` is the shared body (stats from its `EnemyDef`, aggro/stun, movement helpers, attack slots). `EnemyBehavior` subclasses decide what it does: `MeleeBehavior`, `PouncerBehavior`, `SpitterBehavior`, `BloaterBehavior`, `SupportBehavior`. `AcidGlob` and `HazardZone` are their effects. |
| `game/actor.gd` | Base of hero and enemies: health, hit reaction, burn/frost/ward/daze, ragdoll, gib bursts. |
| `game/data/` | Resource classes (`EnemyDef`, `SkillDef`, `AffixDef`) and their loaders (`EnemyDb`, `SkillDb`, `AffixDb`). |
| `data/` | The `.tres` files those loaders read: `data/enemies`, `data/skills`, `data/affixes`. |
| `game/dev/dev_harness.gd` | Developer tooling: the headless self-test and the screenshot/pose tools. Not part of the game. |
| `tools/` | Asset pipeline (Meshy generation, animation baking) and the generators for the `.tres` data files. |

## Data first

Skills, enemies and affixes are Resources, not dictionaries in scripts.

* **Edit a number**: change the table in `tools/write_enemy_defs.py` / `write_skill_defs.py` / `write_affix_defs.py`, run it, and the `.tres` files regenerate. (The `.tres` files can also be edited by hand or in the Godot inspector.)
* **Add an enemy**: add an entry to `write_enemy_defs.py` (stats, model path, `behavior`, `params`, spawn rules). If it needs new behaviour, write an `EnemyBehavior` subclass and add it to `EnemyBehaviors.create`. Waves pick it up from its spawn fields (`min_wave`, `base_count`, `per_wave`, `max_per_wave`, `spawn_mode`).
* **Add a skill**: add a `SkillDef` entry. Skills of an existing `kind` need no code; a new kind gets a branch in `SkillController` (or its own state machine in `game/skills/`, like Skewer and Leap).
* **Add an affix**: add the catalogue entry, then the behaviour hook in `item_effects.gd` keyed by its id.

## Tests and CI

`godot --headless --path . res://game/main.tscn -- --selftest` runs every check in `game/dev/dev_harness.gd`; each check calls `expect(label, condition)` and the process exits non-zero if any fail. `--only=NAME` runs one (`gibs`, `swarm`, `enemies`, `leap`, `impact`, `fireblast`, `balance`, `items`, `autoattack`). `.github/workflows/selftest.yml` runs the full suite on every push and pull request.

Screenshot modes (`--skillshot=…`, `--enemyshot`, `--enemyfight`, `--clipsheet=…`, `--poses`, …) write PNGs to `%TEMP%` for judging visuals by eye.

## Assets

Large binaries (`*.glb`, `*.res`, `*.jpg`, audio, video) are stored with Git LFS (see `.gitattributes`). Models, rigs, animations and icons come from Meshy via `tools/meshy.py` / `meshy_icons.py`; `tools/bake_anims.gd` bakes animations into small `anims.res` files.
