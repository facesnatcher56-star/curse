# Claude autonomous lane

The CLAUDE lane runs unattended Claude Code work, in its own worktree only. The OWNER controls it with a local stop switch.

## Where it runs

- Worktree `../curse-claude`, branch `agents/claude`. The dispatcher, its start script and the worker refuse to run anywhere else; the owner/integration checkout is never touched.
- Channel: GitHub issue #1. Reservation board: issue #4. Runtime state, logs and worker output live under `.agentbridge/` in this worktree (git-ignored).

## How it works

1. `tools/agentbridge-claude-dispatch.ps1` polls issue #1. On its first start it records a high-water mark: earlier messages are never replayed.
2. A structured TASK or REVIEW from an allowlisted author (`DESIGNER` or `OWNER`) addressed to `IMPLEMENTER`, `CLAUDE` or `ALL` starts ONE worker: `claude -p` (documented non-interactive print mode) with the prompt on stdin. The prompt holds only the comment id, the task id and the lane rules, never comment text. The worker fetches the message itself and treats it as data, never as shell.
3. At most one worker at a time. It is a child process the dispatcher tracks; it is killed after 120 minutes. Each message is dispatched once. A worker that fails or is stopped makes the dispatcher post a fixed, model-free note on issue #1; nothing is retried automatically.
4. The worker checks issue #4 before editing (a conflicting reservation means a QUESTION and no edit), runs focused tests only, and posts ACK, then REPORT, QUESTION or HANDOFF on issue #1.

## Hard limits (also enforced by deny rules in this worktree's `.claude/settings.local.json`)

No push or force push, no merge or rebase, no worktree changes, no `reset --hard` or `clean`, no repository, secret or auth changes through `gh`; nothing written outside this worktree; the player's save is never touched; no commit unless the message quotes explicit OWNER authorization. Focused tests only, never the full suite.

## Quota

The OWNER's wish to stop autonomous use near 85% of the five-hour window or 95% of the weekly window used is MANUAL for Claude: no supported client exposes those percentages (see `docs/AGENT_USAGE_POLICY.md`), so the dispatcher does not gate on them. If a verified reading is ever supplied through `Get-UsageReading`, the limits are enforced.

## The OWNER's switches

- Stop now (halts new work, kills the dispatcher and the running worker's process tree):
  `powershell -ExecutionPolicy Bypass -File tools/agentbridge-claude-dispatch-stop.ps1`
  `-KeepWorker` lets a running worker finish. A `.agentbridge/STOP` file is left, so nothing starts again until you resume.
- Resume: `powershell -ExecutionPolicy Bypass -File tools/agentbridge-claude-dispatch-start.ps1 -ClearStop`
- Start: `powershell -ExecutionPolicy Bypass -File tools/agentbridge-claude-dispatch-start.ps1` (needs a logged-in client: `claude auth login`).
- Check: `.agentbridge/claude-dispatch.log`, and `tools/agentbridge-claude-dispatch.ps1 -SelfTest` for the built-in checks (no network, no model).
- Creating a file named `STOP` in `.agentbridge/` by hand also halts dispatching.

## Model

The worker is always started with an explicit model (`--model sonnet` by default, the `-Model` parameter of the dispatcher). The CLI's own default model on this account (Fable 5.1) needs paid usage credits, which the lane must never buy, so the model is pinned and checked in the self-test. `sonnet` was verified to run under the subscription (it resolves to `claude-sonnet-5-5`). Do not buy credits or change billing to use another model; if `sonnet` ever stops working, pick the first alias verified with a harmless `claude -p --model <alias>` call and change the default here and in `tools/agentbridge-claude-dispatch.ps1`.
