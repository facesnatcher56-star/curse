# Codex autonomous lane

Infrastructure only. Dedicated root: curse-codex; branch: agents/codex.
Current lane runtime: installed desktop codex-cli 0.160.1 or newer. The old npm CLI
0.118.0 is rejected. Dispatcher activation and recovery are explicit OWNER actions.

## Invocation and setup

The dispatcher invokes the resolved desktop codex.exe directly using an argument array
(no shell): -a never exec --sandbox workspace-write --cd <root> --json
--output-last-message <runtime file> -. Prompt data travels through stdin.
CURSE_CODEX_EXECUTABLE and CURSE_GH_EXECUTABLE are explicitly injected into nested
worker shells. Use PowerShell's & operator with these paths; do not rely on old PATH shims.
GH_CONFIG_DIR is injected without copying credentials. The documented
sandbox_workspace_write.network_access=true option enables live Issue #2/#4 access,
while workspace-write filesystem isolation remains. Process-scoped Git safe.directory
trusts only curse-codex; no global Git configuration is written.
The launcher records selected non-secret argv/environment metadata under .agentbridge/.
It uses configured model defaults. REVIEW is a new bounded run with the exact comment,
current worktree and standing rules; it does not select an unrelated last session.

Before activation, authenticate GitHub CLI locally (gh auth login) in the OWNER's environment.
Standalone gh authentication is verified as facesnatcher56-star through the OWNER-supplied
GH_CONFIG_DIR. Desktop connector authentication remains separate. Do not copy tokens into this repo.
After setup review, from curse-codex:
powershell -ExecutionPolicy Bypass -File tools/agentbridge-codex-dispatch-start.ps1

First successful start baselines all existing #2 comments. Post the fresh harmless smoke TASK
only AFTER the first-start state says BASELINED. Do not delete state to retry an old task.
No startup registration, scheduler or smoke execution is installed.

## Safety and transport

Exact checkout name, Git top-level, worktree .git file, branch and origin are checked.
An OS-held exclusive lock prevents concurrent dispatchers. These checks protect dispatch;
workspace-write sandbox and standing instructions constrain the model. They are not a
security boundary against malicious code already installed on the PC.

Only issue #2 can provide tasks; all pages are fetched. Authenticated author must be
facesnatcher56-star; header must begin at the first line with [AGENTBRIDGE], have unique
keys and a blank separator, project=curse, from=OWNER/DESIGNER, to=CODEX/ALL,
type=TASK/REVIEW and a bounded task identifier. Edits to old comments are not replayed:
post a new TASK/REVIEW. Comment strings are never interpolated into shell commands.

Issue #4 must be fetched successfully before dispatch. Agent instructions require a fresh
board read, logical-scope conflict check, RESERVE, race recheck before editing and RELEASE
or HANDOFF on completion. Logical overlap is assessed by the model, not string matching;
conflicts require QUESTION without edits. Runtime board snapshots are supporting data,
not substitutes for the live check. Reports go to #2 via a body file.
An interrupted/failed model run or failed report delivery retains active state and pauses
for local recovery; no automatic duplicate execution. Inspect uncommitted changes and live
reservations, post a QUESTION/HANDOFF as needed, then consciously resolve active state.
Transient transport failures exit without consuming the pending task. Restart locally.

## Usage

Verified supported machine source: codex app-server, initialize/initialized handshake,
account/rateLimits/read. Installed protocol schemas and a live read verified 300-minute
and 10080-minute windows. Pause before new runs at >=85% five-hour or >=95% weekly used.
Paused comments stay queued and limits are rechecked while polling. No mid-write quota kill.
If readings fail or windows are unrecognized, record manual/advisory and permit autonomy,
as explicitly directed by OWNER for this lane. This overrides older fail-closed repository
policy. No UI scraping, private endpoints, token-count inference, resets or purchases.

The dispatcher host obtains quota via the supported app-server path before each launch.
It passes the fresh verified decision in trusted prompt metadata and CURSE_CODEX_USAGE_JSON.
Workers must use that snapshot for the launch check; they do not need Python and must not
run the dispatcher from their sandbox to retrieve usage. Host snapshots expire after 120
seconds before launch. Manual/advisory metadata is explicit when telemetry is unavailable.
For an OWNER host session only: python tools/agentbridge-codex-dispatch.py --usage

## Stop and recovery

powershell -ExecutionPolicy Bypass -File tools/agentbridge-codex-dispatch-stop.ps1

Persistent .agentbridge/codex.stop blocks new tasks. Current execution is allowed to finish
at a safe boundary; model checks the marker at safe checkpoints. This is a graceful stop,
not a guaranteed immediate cancellation of a hung child. PID and child PID files, lock,
atomic JSON state, task data, quota observations, JSONL and stderr logs live in .agentbridge/.
If a child hangs, OWNER may inspect the recorded PID and terminate it manually; do not
blindly kill a stale PID. Preserve active state and reservations for recovery.
After review/recovery, explicitly remove only the stop marker to restart. Never clear active
state blindly. Logs can contain project text; do not publish them wholesale.

## Validation and visual tasks

Focused local tests: python tools/agentbridge-codex-selftest.py (no model/GitHub calls).
Future visual work must include PNG screenshots/renders in REPORT; Blender renders are valid.
No full Godot suite is needed for this infrastructure change.

OWNER activation update: the start wrapper sets GH_CONFIG_DIR to C:\Users\lloyd\AppData\Roaming\GitHub CLI and verifies the active login is facesnatcher56-star. The dispatcher and its children inherit this environment; no credential files are read or copied by the launcher. GitHub CLI authentication was verified at activation; the earlier setup authentication blocker is resolved.
