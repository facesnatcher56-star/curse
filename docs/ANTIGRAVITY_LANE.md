# Antigravity Lane Bootstrap

Antigravity 2.0 is the Google parallel implementation lane for Curse.

## Permanent role

Antigravity complements, rather than duplicates, Claude Code and Codex.

Primary strengths/responsibilities:
- world/content implementation;
- quest and encounter content;
- data definitions and content pipelines;
- isolated gameplay/UI systems that are not reserved elsewhere;
- asset/tooling workflows;
- 3D/content pipeline work, including Blender when useful;
- independent implementation/review tasks specifically assigned by DESIGNER.

Claude Code remains the primary gameplay implementation lane.
Codex remains the parallel engineering/debug/review lane.
Antigravity must not opportunistically rewrite another lane's active subsystem.

## Local capabilities

Blender is already installed on the OWNER's PC and is available to Antigravity when appropriate. See `docs/AGENT_ENVIRONMENT.md`.

Do not reinstall Blender merely because a task needs modeling, rigging, animation, collision geometry, or export work. Verify its executable/version when first required.

## Install on Windows

Antigravity CLI's command is `agy`.

```powershell
irm https://antigravity.google/cli/install.ps1 | iex
```

Verify:

```powershell
agy --version
```

First launch is interactive:

```powershell
agy
```

Use Google OAuth, then trust **only the dedicated `curse-antigravity` worktree** when prompted.

Credentials/tokens belong in Antigravity/OS-managed storage, never in this repository.

## Dedicated worktree — required

Never run autonomous Antigravity in the OWNER/integration checkout or Claude/Codex worktrees.

After OWNER authorizes an integration checkpoint, create/use:

```text
../curse-antigravity
branch: agents/antigravity
```

Prepared worktree creator:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge-create-worktrees.ps1 -BaseRef <checkpoint-ref>
```

The Antigravity dispatcher refuses to run unless the checkout is the dedicated `curse-antigravity` worktree on branch `agents/antigravity`.

## AgentBridge channels

Antigravity channel: GitHub issue #3.
Shared reservation board: GitHub issue #4.

One-shot inbox sync:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge.ps1 -Project antigravity -Once
```

Passive watcher:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge-start.ps1 -Project antigravity
```

The watcher only copies allowlisted structured messages into the local inbox. It never executes comment bodies.

## Standing task protocol

Before implementing any TASK or REVIEW:

1. read the exact AgentBridge message;
2. inspect the actual Antigravity worktree;
3. inspect issue #4 for live reservations;
4. if the logical system is unreserved, post RESERVE to issue #4;
5. if another agent owns an overlapping logical system, post QUESTION to issue #3 and do not edit it;
6. implement only the assigned scope;
7. run focused affected tests, not the full suite unless OWNER explicitly requests;
8. post REPORT or QUESTION to issue #3;
9. RELEASE/HANDOFF reservations on issue #4 when work ends or transfers.

Never merge another agent's branch.
Never force-push.
Never deploy, modify production data, alter secrets, or perform destructive operations without explicit OWNER authorization.
Never auto-commit unless the task/integration workflow explicitly authorizes it.

## Autonomous AgentBridge flow

Antigravity CLI supports non-interactive prompt execution with `agy -p`.

Curse includes a dedicated Antigravity dispatcher:
- `tools/agentbridge-antigravity-dispatch.ps1`
- `tools/agentbridge-antigravity-dispatch-start.ps1`
- `tools/agentbridge-antigravity-dispatch-stop.ps1`

The dispatcher:
- polls only Antigravity issue #3;
- accepts only structured TASK/REVIEW messages from the configured allowlisted OWNER account;
- passes only trusted identifiers to Antigravity, never raw comment text as shell commands;
- processes one Antigravity run at a time;
- checks the dedicated worktree/branch before starting;
- establishes a high-water mark on first start so old bootstrap tasks are not replayed;
- lets Antigravity read the exact message and issue #4 before editing.

### Enabling host-writing autonomy

Antigravity's fully unattended host-write permission is powerful. It must **not** be enabled until the dedicated Antigravity worktree exists and the OWNER intentionally starts the dispatcher there.

The start command requires an explicit acknowledgement flag:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge-antigravity-dispatch-start.ps1 -EnableAutonomousWrites
```

That mode invokes Antigravity non-interactively with its documented permission-bypass flag so the agent can edit/test in its isolated worktree without stopping for approval.

Do not enable it in the shared/owner checkout.

Stop autonomous dispatch:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge-antigravity-dispatch-stop.ps1
```

Runtime PID/state/logs remain under `.agentbridge/` and are git-ignored.

## First activation sequence

After the OWNER-approved integration checkpoint exists:

1. create `curse-antigravity` / `agents/antigravity`;
2. install/verify `agy`;
3. launch `agy` interactively once;
4. sign in with Google OAuth;
5. trust only the dedicated Antigravity worktree;
6. run one-shot AgentBridge sync;
7. verify issue #3 and issue #4 access through `gh`;
8. start the autonomous dispatcher with `-EnableAutonomousWrites`;
9. DESIGNER posts a fresh harmless bootstrap TASK to issue #3;
10. verify Antigravity ACK/REPORT arrives without a human terminal prompt;
11. only then assign real implementation work.

Do not replay the obsolete Gemini CLI bootstrap instructions.


## Usage gate

Before autonomous TASK/REVIEW dispatch, obey `docs/AGENT_USAGE_POLICY.md`.

Antigravity's documented interactive usage command is `/usage`. The autonomous lane must use a locally verified reliable way to obtain the same quota state before dispatch. If that cannot be done reliably, fail closed rather than guessing.

OWNER reserve:
- five-hour remaining must be > 85% when that window applies;
- weekly remaining must be > 95%.

At or below either threshold, do not start another autonomous Antigravity run.
