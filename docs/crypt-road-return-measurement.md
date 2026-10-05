# Crypt Road return measurement

Measured from the third nest at `(14, -98)` to the town exit trigger at `z = 174`, using the hero's normal click-to-move code and 5 m/s base run speed. The timing ends when the exit begins the completed-job return, including its short gate dwell. No rolls or combat skills were used. The hero started at `(18, -98)`, immediately after the third nest was destroyed; setup and enemy removal took one physics frame before the clock started.

| Return scenario | Enemies left alive | Time to exit | End state |
| --- | ---: | ---: | --- |
| Road mostly cleared | 0 | 57.88 s | 120 health, 100 stamina |
| Three encounters skipped, plus final nest defenders | 13 | 78.92 s | 30 health, 0 stamina |

The skipped groups were the walkers near the town gate, the brute in the wooded choke, and the shrine guard. The final nest's four spawned defenders were also left alive. Other enemies were removed to represent a road that had otherwise been cleared. The clear-road scenario removes those spawned defenders too, so its result measures the return traversal rather than the last fight.

Both runs used waypoints down the central road: `(0, -98)`, `(0, -40)`, `(0, 20)`, `(0, 92)`, `(0, 150)`, and the exit. A single click-to-move order from the nest to the exit stalled around `(19.5, -70.7)` for more than a minute; the waypoint runs reflect a player steering through the courtyard instead of waiting behind that obstacle.

The 57.88-second clear run exceeds the 45-second threshold even without fights, loot stops, or exploration. A physical return shortcut unlocked by the last nest is justified. This measurement did not change the road layout.

To repeat either run headlessly, use `tools/run_godot.sh LOG 180 -- res://game/main.tscn -- --crypt --roadreturn=clear` or `--roadreturn=skipped` (set `GODOT_BIN` to the local Godot executable where needed). The measurement implementation is in `game/dev/dev_harness.gd`.
