# Curse

Godot 4.8-dev2, GDScript. Click-to-move ARPG, fixed 3/4 camera, controller supported. Layout and where things live:
[ARCHITECTURE.md](ARCHITECTURE.md).

## Development process

Read [docs/DEVELOPMENT_RULES.md](docs/DEVELOPMENT_RULES.md) before accepting development tasks. It sets
the risk-based testing, review and integration policy for all agents. The owner's standing rules below
(ask when uncertain, UI visual checks) still apply and take precedence where they are more specific.

## Combat baseline

Dungeon Siege II combat is the baseline. Follow
[docs/COMBAT_REFERENCE.md](docs/COMBAT_REFERENCE.md), which builds on the traced game data in
[docs/ds2-combat-and-loot.md](docs/ds2-combat-and-loot.md).

## Required checks for every agent (owner instruction)

The inventory/HUD overlap and inconsistent active-power versus passive-skill requirement
feedback came from the same failure: treating a local change as complete without checking
the surrounding player experience or other places using the same mechanic. Do not repeat it.

Before calling a change complete:

- Check related uses of the same mechanic. Requirement feedback must be consistent across
  active powers and passive skills: show unmet requirements (for example, Melee 1) in red,
  show the required level clearly, and prevent unavailable purchases. Meeting a requirement
  must not look like the skill is already learned. Prefer shared existing logic over copies.
- Check the actual gameplay context, not only an isolated test scene. For UI changes, inspect
  the complete HUD with the affected window open: layering, overlap, clipping, readability,
  focus, tooltips, and mouse/controller interactions. Exercise applicable actions such as
  equip, move, sort, close, and cancel; verify expected actions are actually supported.
  Run visible playtests on the second monitor (1080p); native 2560x1440 checks may use
  the first monitor, as the owner explicitly authorized.
- Visual verification is risk-based (see `docs/DEVELOPMENT_RULES.md` and `docs/UI_THEME.md`):
  minor localized UI change: inspect the affected interaction at one representative resolution;
  significant UI/layout change: inspect representative supported resolutions and relevant
  interface-scale boundaries, including the affected hover, focus and scroll behaviour;
  global display, scaling or layout-system change: run the complete resolution and
  interface-scale matrix; unrelated gameplay or backend changes: no visual matrix requirement.
  When visual appearance changes and a suitable display is available, capture and inspect
  screenshots. Never claim visual verification that was not performed; list deferred visual
  checks as known gaps. Automated bounds assertions do not replace visual inspection.
- Preserve high-resolution texture backing and icon/portrait proportions. Do not shrink
  source art to logical control dimensions; check native-pixel captures for blurry trim,
  stretched material, and undersized 3D previews at the largest supported display/scale.
- Check empty, populated, locked/unlocked, and relevant boundary states. Automated checks
  alone do not establish visual usability. Report what was actually tested and any gaps;
  do not claim a feature is fully verified when its gameplay context was not inspected.
- Keep fixes proportional. Do not overcomplicate, duplicate systems, or create god files
  merely to satisfy these checks.

Standing owner instruction for every agent and every future task on this project:
whenever uncertainty remains, ask the owner a specific question instead of guessing.
This includes intended behavior, scope, controls, presentation, or a DS2 reference detail.
Do not treat this as optional or silently choose a departure.
Inspect available code/reference evidence first where it can resolve a factual question;
if uncertainty remains, explain what is known and ask before implementing that uncertain part.
Unrelated, clearly authorized work may continue while awaiting the answer.

## Godot and Blender tools (owner instruction, 2026-10-22)

`.mcp.json` registers two MCP servers for this project (owner's PC only):

- **`ziva-godot`** talks to the Godot editor open on this project (Ziva plugin). Use it **by default** for
  Godot editor work: project settings, input map, scene trees, opening and running scenes, screenshots,
  editor errors. Prefer it over hand-editing `project.godot` or `.tscn` files. The Godot editor must be
  open on this folder. Ziva takes the first free port from 7012; if calls fail with "Unable to
  connect", find its port (`Get-NetTCPConnection -State Listen`, process `zivacode`) and fix
  `--upstream` here and in the user config.
- **`blender`** talks to the running Blender (MCP add-on on port 9876). Use it **by default** for model
  and asset work in Blender (inspect the scene first, prefer operators, screenshot to check).
  Blender must be running with the add-on connected. Don't modify an unrelated open scene without asking.

**Standing owner rule (permanent, every agent, 2026-10-22): edit and work on Curse through the MCP connection
to the open Curse project whenever possible** (Ziva for Godot, the Blender MCP for models): inspect, edit,
import, run scenes and take screenshots there, not through a separate command-line Godot or Blender.
**If the MCP connection to Curse isn't there** (Godot not open on this folder, Ziva not answering, Blender
MCP not connected), **stop and tell the owner**; don't silently switch to command-line tools. Headless
command-line runs remain fine only for what the MCP can't do (CI-style selftest suites, rebaking scenes),
and say so when you use them.
Codex: the same two servers are in `.codex/config.toml`. Other agents: register them in your own MCP config.

## Playable character skeleton (owner rule, permanent, 2026-10-22)

**Every playable character, now and in future, is rigged to the detailed humanoid skeleton**: the 54-bone hero skeleton
(knight2's 24 game bones with their rest rotations, plus three Mixamo-named joints per finger), first built for the barbarian
hero (`assets/models/barbarian/rigged.glb`). Never ship a playable character on a reduced skeleton or its own bone names.
Equipment is made to fit the character, not the character to the equipment. The standard, rest pose and checks are in
[docs/art/PIPELINE.md](docs/art/PIPELINE.md) ("Humanoid skeleton standard").
