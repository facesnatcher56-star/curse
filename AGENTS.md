# Notes for agents

Read [docs/DEVELOPMENT_RULES.md](docs/DEVELOPMENT_RULES.md) before accepting development tasks. It is the
shared engineering and multi-agent policy. The owner's standing instructions below still apply.

Read [CLAUDE.md](CLAUDE.md) first. Its required checks and ask-when-uncertain rule apply to
every agent working on this project. Check the whole gameplay context and equivalent uses
of a mechanic, not just the edited component.

Visual verification is risk-based, as set out in CLAUDE.md, docs/UI_THEME.md and
docs/DEVELOPMENT_RULES.md. Minor localized UI changes need one representative inspection;
significant layout changes need representative resolutions and scale boundaries; only global
display, scaling or layout-system changes need the complete matrix. Screenshot inspection is
required when appearance changes and a display is available. Disclose any deferred visual check.

Standing visual direction for all new or revised art and gameplay effects: build in deliberate
contrast so the subject reads and pops against its actual gameplay surroundings. Use clear
value and color separation, a strong silhouette, and controlled highlights; avoid muddy,
washed-out, or low-contrast results that blend into the player, ground, or background. Judge
the effect in its real gameplay context, not just on an isolated preview, and keep the contrast
coherent with what the owner has asked for (the art direction itself is not decided yet; see `docs/ART_DIRECTION.md`).

Standing owner instruction, including future tasks: whenever uncertainty remains, ask the
owner before implementing the uncertain part. Do not guess. This applies to all agents.

Dungeon Siege II combat is the baseline; follow [docs/COMBAT_REFERENCE.md](docs/COMBAT_REFERENCE.md).

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

Fall back to scripts or headless runs only when the tools can't do the job or the app isn't open, and say so.
Codex: the same two servers are in `.codex/config.toml`. Other agents: register them in your own MCP config.
