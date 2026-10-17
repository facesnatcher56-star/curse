# Third-party plugins and assets

Everything here is free and permissively licensed. Pinned versions, hashes and 4.8-dev2 status are recorded so a
future update is a conscious choice. Hashes are SHA-256 of the archive as downloaded from the official source.
Nothing is wired into the game yet (install only). Saving stays off; none of these touch `user://`.

## PLUGINS

### ProtonScatter (installed, enabled)

| | |
|---|---|
| Folder | `addons/proton_scatter/` |
| Version | plugin.cfg `4.2.0`, official repo `HungryProton/scatter` commit `7198cc00078ebde61307578137c3f35223c6e438` (2026-09-27, `main`) |
| Source | https://github.com/HungryProton/scatter/archive/7198cc00.zip |
| Archive SHA-256 | `485295fa4a97cb54bcd20d1b1304ed8a2fc0b28fe3215a07be62d26df9208d5f` (`scatter-7198cc0.zip`) |
| Licence | MIT, (c) 2019 HungryProton (`addons/proton_scatter/LICENSE`) |
| Purpose | Scatter props (rubble, bones, candles, grass) over painted areas, non destructively |
| 4.8-dev2 | Works: `--import` twice, clean. |
| Native code | None (pure GDScript) |

Why a `main` commit and not a release: the newest tagged release (`4.0`, 2023, no attached files; the Asset Library
entry #1866 points at commit `8de6ffe`, Jan 2026) does not compile on Godot 4.8 (`scatter.gd:240` "Not all code paths
return a value", then an import segfault). The `main` commit above contains upstream's own fix for this, with no changes by us.
Trimmed on install: upstream `demos/` (12 MB of sample art) and `tests/` were removed. Consequence: the bundled
presets `presets/grass.tscn` and `presets/scatter_default.tscn` point at the removed `demos/assets/*` and show a missing
resource if used; they are editor templates only, nothing in the game references them.

### Phantom Camera (installed, enabled)

| | |
|---|---|
| Folder | `addons/phantom_camera/` |
| Version | `v0.11.0.3` (official repo `ramokz/phantom-camera`, tag commit `cb6e0966ac305202c47f1d1a81c105966e29da96`; Asset Library entry #1822 points at the same commit) |
| Source | https://github.com/ramokz/phantom-camera/archive/refs/tags/v0.11.0.3.zip |
| Archive SHA-256 | `42b4bbd7ce6efa726abc6e927328d349887c9343fe53900a5083860c1848749b` |
| Licence | MIT, (c) Marcus Skov (`addons/phantom_camera/LICENSE`) |
| Purpose | Camera follow, zoom, tween and shake tools. Install only: `game/camera_rig.gd` is untouched |
| 4.8-dev2 | Works: `--import` twice, clean |
| Native code | None (pure GDScript) |

Enabling it also registers the plugin's own autoload `PhantomCameraManager` in `project.godot`. With a headless
`--import` the plugin does not register it by itself (a Godot 4.7.1+ editor issue the release notes mention), which
gives "non-existent singleton" errors, so the autoload line is committed explicitly; with it the import log has 0 errors.
The autoload is idle until a `PhantomCamera3D` / `PhantomCameraHost` exists. Trimmed on install: `examples/`.

### LimboAI (installed, GDExtension; no editor plugin entry)

| | |
|---|---|
| Folder | `addons/limboai/` |
| Version | `v1.8.1` (official repo `limbonaut/limboai`, tag commit `e45e60e976dafab7f2c15cc341ae366e4cf3352b`) |
| Source | https://github.com/limbonaut/limboai/releases/download/v1.8.1/limboai%2Bv1.8.1.gdextension-4.6.zip |
| Archive SHA-256 | `0910411f8dbc0da8920f6c8bbbb6397c347cd9f2f193942468a702dfb11d5f0e` |
| Licence | MIT, (c) 2023-2025 Serhii Snitsaruk and the LimboAI contributors (`addons/limboai/LICENSE.md`; logo terms in `LOGO_LICENSE.md`) |
| Purpose | Behaviour trees and hierarchical state machines, for smarter elites and bosses later |
| 4.8-dev2 | Works on Windows: the `4.6` GDExtension build declares `compatibility_minimum = 4.2`, loads in 4.8-dev2, and `BTSelector`, `LimboHSM`, `BehaviorTree`, `BTPlayer` are registered and instantiate (checked with a throwaway `--script`). Linux: not loaded locally, see "CI" below |
| Native code | Yes, official prebuilt binaries only (below) |

| Binary (in `addons/limboai/bin/`) | SHA-256 |
|---|---|
| `liblimboai.windows.editor.x86_64.dll` | `f9e758ebf088da12e71dbe330572fb55f186619bda8b144b4d8e822569161b97` |
| `liblimboai.windows.template_release.x86_64.dll` | `5095e3e3daff5f441f58afb3b482de839c2b6d00b30668c59b3003848234f4c2` |
| `liblimboai.linux.editor.x86_64.so` | `48bf57a5b1c05288ea07e7809bfafd8fe77534ccd432b38167829235b1c3585c` |
| `liblimboai.linux.template_release.x86_64.so` | `693c244c66d41c2d5c073a557b67ed2b267013fd0b3728c01754cf9c1f74b405` |

Other platforms in the archive (Android, iOS, macOS, web, arm) were not kept; `limboai.gdextension` lists them, and Godot
only loads the entry matching the running platform. Re-add them before exporting to those platforms. There is no
`plugin.cfg`: the GDExtension registers its own editor tools.

### Terrain3D (installed, GDExtension, enabled)

| | |
|---|---|
| Folder | `addons/terrain_3d/` |
| Version | `v1.0.2-stable` (official repo `TokisanGames/Terrain3D`) |
| Source | https://github.com/TokisanGames/Terrain3D/releases/download/v1.0.2-stable/Terrain3D_v1.0.2-stable.zip |
| Archive SHA-256 | `a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2` |
| Licence | MIT (`addons/terrain_3d/LICENSE.txt`), Tokisan Games / Cory Petkovsek & Roope Palmroos |
| Purpose | Outdoor heightmap terrain for the Crypt Road and other outdoor areas later. Install only |
| 4.8-dev2 | Works on Windows: `Terrain3D` and `Terrain3DData` register and the import log is clean apart from two editor-shutdown leak lines (below). Linux not loaded locally, see "CI" |
| Native code | Yes, official prebuilt binaries only (below) |

| Binary (in `addons/terrain_3d/bin/`) | SHA-256 |
|---|---|
| `libterrain.windows.debug.x86_64.dll` | `bf72686a7e1d8d8370ba9ba5eaa70c59375ee2cb5638d63b8942f1ad7d448cda` |
| `libterrain.windows.release.x86_64.dll` | `40900e649c3c6c7619c383d28732c3e2e8dc87c2938de43b29122a668aedcf86` |
| `libterrain.linux.debug.x86_64.so` | `178ae39467bb0743c1bbdf854a00f8e7d258a3691bcc1b63d4493beb6bde865e` |
| `libterrain.linux.release.x86_64.so` | `e79ebb2e48a63a5d6189a825f1d63ec847319dc8fa030936d95bf6fad8f294ef` |

Known cosmetic noise: with the Terrain3D editor plugin enabled, `--import` exits 0 but prints two lines at editor shutdown
("1 RID allocations ... leaked at exit", "1 resources still in use at exit"). Not seen with the extension alone, and not
present at game runtime (the editor plugin does not load in a game run). macOS, Android, iOS and web binaries and the
upstream `demo/` were not kept.

### CI (Linux)

The self-test workflow runs the stock Linux Godot 4.8-dev2 editor binary, which loads the `linux.debug.x86_64` entries.
Both native plugins ship Linux x86_64 debug/editor builds and those are included (tracked with Git LFS: `*.dll`, `*.so` were
added to `.gitattributes`; the workflow already runs `git lfs pull`). So the plugins are expected to load on CI exactly as on
Windows; the PR's CI run is the first Linux load and is the authority on that. If a library fails to load, Godot logs an
error and continues without the extension (nothing in the game references these classes yet); in that case drop the plugin
rather than tolerate a noisy log.

## Licences

All four plugins are MIT licensed. Each plugin's full licence file stays inside its folder (listed above), unmodified.
Copyright holders: HungryProton (ProtonScatter), Marcus Skov (Phantom Camera), Serhii Snitsaruk and the LimboAI contributors
(LimboAI), Cory Petkovsek & Roope Palmroos / Tokisan Games (Terrain3D). There is no project-wide credits file yet
(`assets/audio/CREDITS.md` and `assets/fonts/CREDITS.md` cover only their own folders); this section is the plugin
credit until one exists.

<!-- ART section is added below by lane Q2. -->
