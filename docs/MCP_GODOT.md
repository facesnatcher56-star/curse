# Godot MCP Server (`ziva-godot`) Guide

This document establishes the instructions and reference for all agents (**Claude Code**, **Codex**, **Antigravity**) working on the **Curse** project to connect to and use the local Godot Model Context Protocol (MCP) server.

---

## 1. Standing Rule for All Agents

Whenever an agent needs to:
- Inspect the scene hierarchy or node properties (`get_scene_tree`, `get_node_warnings`);
- Diagnose runtime issues, check engine errors, or read editor output (`get_godot_errors`, `clear_output_logs`);
- Run scenes or launch interactive playtests (`run_scene`, `playtest`, `get_screenshot`);
- Inspect input mappings or project configuration (`get_input_map`, `get_project_info`, `update_project_setting`);
- Validate tilemaps, physics shapes, collision masks, and layers (`validate_physics_setup`, `validate_tilemap_structure`, `get_tilemap_state`);
- Execute GDScript expressions directly within the engine environment (`execute_script`);
- Search official Godot 4 class reference / API (`search_docs`);

**Do not guess or rely exclusively on static text analysis.** Use the `ziva-godot` MCP tools directly to interact with the engine.

---

## 2. Server Architecture & Configuration

The `ziva-godot` MCP server runs locally as a bridge executable forwarding MCP JSON-RPC requests via stdio to the active Godot 4.8 editor / runtime server listening on `http://127.0.0.1:7012/api/mcp`.

### Bridge Executable and Parameters
- **Bridge Binary:** `C:\Users\lloyd\Desktop\CursePlaytest133d\Curse-owner-playtest-133d\owner-test-profile-80fd5d7b00f04ffc905c9ea504cd3e90\appdata\ziva-local\bin\zivacode.exe`
- **Godot Binary:** `C:/Users/lloyd/Downloads/Godot_v4.8-dev2_win64.exe/Godot_v4.8-dev2_win64.exe`
- **Upstream Port:** `http://127.0.0.1:7012/api/mcp`

### MCP Config Definition
Add this server block to your agent's MCP settings:

```json
{
  "mcpServers": {
    "ziva-godot": {
      "command": "C:\\Users\\lloyd\\Desktop\\CursePlaytest133d\\Curse-owner-playtest-133d\\owner-test-profile-80fd5d7b00f04ffc905c9ea504cd3e90\\appdata\\ziva-local\\bin\\zivacode.exe",
      "args": [
        "--mcp-bridge",
        "--godot-bin",
        "C:/Users/lloyd/Downloads/Godot_v4.8-dev2_win64.exe/Godot_v4.8-dev2_win64.exe",
        "--upstream",
        "http://127.0.0.1:7012/api/mcp"
      ]
    }
  }
}
```

### Agent Configuration Locations on this PC
- **Antigravity:** Registered in `C:\Users\lloyd\.gemini\antigravity\mcp_config.json` and `C:\Users\lloyd\.gemini\config\mcp_config.json`. Invoked using `call_mcp_tool(ServerName="ziva-godot", ToolName="<tool>", Arguments={...})`.
- **Claude Code:** Registered in Claude Code settings / `claude_desktop_config.json` or `.mcp.json`.
- **Codex:** Configured in active Codex CLI / bridge settings for MCP servers.

---

## 3. Tool Usage Convention: The `reasoning` Parameter

`ziva-godot` schema requires a mandatory `"reasoning"` string parameter on almost every tool call. Always supply a brief, descriptive statement explaining why the tool is being invoked.

Example invocation:
```json
{
  "ServerName": "ziva-godot",
  "ToolName": "get_godot_errors",
  "Arguments": {
    "reasoning": "Check whether recent GDScript edits triggered parser or runtime errors in the engine"
  }
}
```

---

## 4. Complete Tool Inventory (41 Tools)

### Scene & Node Hierarchy
| Tool | Description | Common Arguments |
| :--- | :--- | :--- |
| `get_scene_tree` | Get node hierarchy of the open scene or running scene | `reasoning`, `include_properties`, `max_depth` |
| `get_node_warnings` | Get node configuration warnings in current scene | `reasoning` |
| `open_scene` | Open a scene (.tscn) in the Godot editor | `path`, `reasoning` |
| `duplicate_node` | Duplicate a node in the scene tree | `node_path`, `new_name`, `reasoning` |
| `move_node` | Move or reparent a node in the hierarchy | `node_path`, `target_parent_path`, `reasoning` |
| `rm` | Remove a file or delete a scene node | `path`, `reasoning` |

### Diagnostics, Output & Documentation
| Tool | Description | Common Arguments |
| :--- | :--- | :--- |
| `get_godot_errors` | Retrieve engine errors and stack traces | `reasoning` |
| `clear_output_logs` | Clear the Godot editor output log panel | `reasoning` |
| `search_docs` | Search Godot 4 engine API documentation | `query`, `reasoning` |

### Scripting & In-Engine Execution
| Tool | Description | Common Arguments |
| :--- | :--- | :--- |
| `execute_script` | Execute GDScript snippet directly in Godot context | `code`, `reasoning` |
| `get_open_scripts` | List currently open scripts in the Godot editor | `reasoning` |
| `create_file` | Create a new script or file in the project | `path`, `content`, `reasoning` |
| `edit_file` | Edit an existing file | `path`, `content`, `reasoning` |
| `read` | Read file content from the project | `path`, `reasoning` |

### Runtime, Testing & Verification
| Tool | Description | Common Arguments |
| :--- | :--- | :--- |
| `run_scene` | Run a specific scene file in the engine | `scene_path`, `reasoning` |
| `playtest` | Launch interactive playtest with optional test script | `scene_path`, `actions`, `reasoning` |
| `run_tests` | Run project automated tests | `test_path`, `reasoning` |
| `get_screenshot` | Capture a screenshot of the running game/viewport | `reasoning` |

### TileMap & Physics Verification
| Tool | Description | Common Arguments |
| :--- | :--- | :--- |
| `get_tilemap_layout` | Inspect TileMapLayer node layout and dimensions | `tilemap_path`, `reasoning` |
| `get_tilemap_state` | Retrieve placed cells and data for a TileMap | `tilemap_path`, `layer_id`, `reasoning` |
| `get_tileset_info` | Inspect TileSet resource properties and layers | `tileset_path`, `reasoning` |
| `edit_tilemap` | Modify cell assignments on a TileMapLayer | `tilemap_path`, `cells`, `reasoning` |
| `configure_tileset_atlas` | Set atlas coordinates and properties | `tileset_path`, `atlas_coords`, `reasoning` |
| `validate_tilemap_structure` | Check TileMap hierarchy and layer integrity | `tilemap_path`, `reasoning` |
| `validate_physics_setup` | Check collision layers, masks, and shapes | `node_path`, `reasoning` |

### Sprites & Media
| Tool | Description | Common Arguments |
| :--- | :--- | :--- |
| `animate_sprite` | Set animation parameters on an AnimatedSprite2D/3D | `node_path`, `animation`, `reasoning` |
| `configure_sprite_frames` | Configure frames in a SpriteFrames resource | `resource_path`, `frames`, `reasoning` |
| `generate_image` | Generate an image asset | `prompt`, `output_path`, `reasoning` |
| `view_image` | View an image file in the project | `image_path`, `reasoning` |

### Project Configuration & Resources
| Tool | Description | Common Arguments |
| :--- | :--- | :--- |
| `get_project_info` | Engine version, project name, render method, features | `reasoning` |
| `get_input_map` | Retrieve all configured InputMap actions & keybindings | `reasoning` |
| `update_project_setting` | Update a setting in `project.godot` | `setting`, `value`, `reasoning` |
| `set_editor_setting` | Change an editor preference setting | `setting`, `value`, `reasoning` |
| `add_resource` | Add a resource to the Godot project | `resource_type`, `path`, `reasoning` |
| `project_path_to_uid` | Resolve `res://` path to Godot UID string | `path`, `reasoning` |
| `uid_to_project_path` | Resolve Godot UID string to `res://` path | `uid`, `reasoning` |

### File Search & Refactoring
| Tool | Description | Common Arguments |
| :--- | :--- | :--- |
| `glob` | Find files matching a wildcard pattern | `pattern`, `reasoning` |
| `grep_code` | Search code for a regex pattern | `pattern`, `path`, `reasoning` |
| `mv` | Move or rename a file or resource | `source`, `destination`, `reasoning` |
| `setup_multiplayer` | Configure multiplayer node scaffolding | `reasoning` |
| `setup_analytics` | Configure analytics tracking | `reasoning` |

---

## 5. Worktree and Safety Precautions

1. **Observe Worktree Boundaries:** When using file modification tools (`edit_file`, `create_file`, `rm`, `mv`) via MCP, verify the target paths reside in your assigned worktree.
2. **Never Touch the Production Save:** When running scenes or executing test scripts via `playtest`, `run_scene`, or `execute_script`, ensure that developer flags or test environments are used. Do not manipulate `user://town.json`.
3. **No Auto-Commit:** MCP tools may update Godot UID caches or metadata (`.uid` / `.godot`). Verify Git status before reporting, and remember that committing is strictly by owner instruction only.
