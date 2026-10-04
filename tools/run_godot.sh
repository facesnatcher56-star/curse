#!/usr/bin/env bash
# Runs Godot headless and stops it the moment a script/parse/compile error appears, instead of waiting for a timeout.
#
#   tools/run_godot.sh LOGFILE [TIMEOUT_SECONDS] -- <godot args...>
#   tools/run_godot.sh /tmp/es.log 240 -- res://game/main.tscn -- --selftest --only=leap
#
# Exit code: 0 clean, 2 stopped on an error (the offending lines are printed), 124 timed out, otherwise Godot's own code.
# GODOT_BIN overrides the executable; GODOT_HEADLESS= (empty) opens a real window, for screenshot modes.

GODOT_BIN="${GODOT_BIN:-C:/Users/lloyd/Downloads/Godot_v4.8-dev2_win64.exe/Godot_v4.8-dev2_win64_console.exe}"
LOG="$1"; shift
LIMIT=240
if [[ "$1" =~ ^[0-9]+$ ]]; then LIMIT="$1"; shift; fi
[[ "$1" == "--" ]] && shift

ERRORS='SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Invalid access to property|Invalid call\. Nonexistent'

"$GODOT_BIN" ${GODOT_HEADLESS---headless} --path . "$@" > "$LOG" 2>&1 &
pid=$!
start=$SECONDS
while kill -0 "$pid" 2>/dev/null; do
	if grep -qE "$ERRORS" "$LOG"; then
		sleep 0.3   # let the rest of the message land
		kill "$pid" 2>/dev/null; taskkill //F //PID "$pid" > /dev/null 2>&1
		echo "STOPPED ON ERROR:"
		grep -E -A2 "$ERRORS" "$LOG" | head -20
		exit 2
	fi
	if (( SECONDS - start >= LIMIT )); then
		kill "$pid" 2>/dev/null; taskkill //F //PID "$pid" > /dev/null 2>&1
		echo "TIMED OUT after ${LIMIT}s"
		exit 124
	fi
	sleep 0.4
done
wait "$pid"
code=$?
grep -E "\[FAIL\]|Self-test|SELFTEST" "$LOG" | head -20
exit $code
