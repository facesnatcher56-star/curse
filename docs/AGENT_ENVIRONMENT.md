# Shared Local Agent Environment

These are capabilities available on the OWNER's development PC for Curse agents.

## Blender

Blender is installed locally and is available to **Claude Code, Codex, and Antigravity** whenever a task genuinely benefits from it.

Agents should consider Blender available for:
- 3D modeling and mesh cleanup;
- rigging and armature work;
- animation authoring/cleanup;
- collision/proxy mesh creation;
- UV/material preparation;
- Godot-oriented asset export and conversion;
- scripted/batch Blender operations when appropriate.

Do **not** waste task time reinstalling Blender merely because a task needs it. Verify the installed executable/version/path when first needed.

Blender use is not automatically required for every art or gameplay task. Use it when it is the appropriate tool.

Normal repository/worktree rules still apply:
- work only inside the agent's own assigned worktree/project paths;
- do not overwrite source art or generated assets destructively without a recoverable source;
- do not modify another agent's reserved logical system;
- generated/imported assets must follow the project's established source/export layout.

The DESIGNER may explicitly instruct an agent to use Blender when a task involves models, rigs, animation, collision geometry, asset conversion, or another Blender-suitable workflow.

## Godot MCP Server (`ziva-godot`)

A Model Context Protocol (MCP) bridge to Godot 4.8-dev2 is installed and available to **Claude Code, Codex, and Antigravity**.

Agents should use the Godot MCP server whenever working on this project for:
- Live scene inspection and node hierarchy queries (`get_scene_tree`, `get_node_warnings`);
- Engine diagnostics and error log reading (`get_godot_errors`, `clear_output_logs`);
- Executing scripts or automated tests in-engine (`execute_script`, `run_tests`);
- Running or playtesting scenes and capturing screenshots (`run_scene`, `playtest`, `get_screenshot`);
- Tilemap and physics setup validation (`validate_tilemap_structure`, `validate_physics_setup`);
- Inspecting input action maps, project info, and UID mappings (`get_input_map`, `get_project_info`, `uid_to_project_path`).

Complete tool list, argument schemas, and configuration snippets are documented in [docs/MCP_GODOT.md](MCP_GODOT.md).

