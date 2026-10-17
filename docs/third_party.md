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
