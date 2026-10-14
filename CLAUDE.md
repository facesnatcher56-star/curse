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
- For every visual change, repeat the workflow in `docs/UI_THEME.md`: test actual gameplay
  screens at every `GameSettings.RESOLUTIONS` entry (currently 1280x720, 1600x900,
  1920x1080 and 2560x1440) with supported interface-scale boundaries;
  capture and personally inspect screenshots, fix issues found, and rerun affected checks.
  Include hovered buttons/items, native and custom tooltips, keyboard/controller focus,
  long text, edge-of-screen placement, and disabled/unmet states. Check consistent subtle
  worn-gold feedback across equivalent controls, not only the edited screen. Use the theme
  matrix and focused interaction suites; record actual passes and unresolved gaps. Never
  substitute automated bounds assertions for visual inspection or claim unrun checks passed.
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
