# AgentBridge

AgentBridge is a small, project-neutral handoff layer for AI coding agents. For Curse, GitHub issue #1 is the coordination channel.

## Security model

AgentBridge is deliberately **not** remote code execution.

- The watcher reads GitHub issue comments and writes accepted messages to a local inbox.
- It never executes shell/code contained in a comment.
- Only configured GitHub authors are accepted.
- Only messages with a valid `[AGENTBRIDGE]` header, matching project, and intended recipient are accepted.
- GitHub credentials stay in the GitHub CLI / OS credential store. No token belongs in this repository.
- Dangerous/destructive actions still require normal owner approval.
- Local runtime state lives under `.agentbridge/` and must not be committed.

## Curse channel

Repository: `facesnatcher56-star/curse`  
Issue: `#1 AgentBridge — Curse`  
Default polling: 30 seconds.

## Message header

```text
[AGENTBRIDGE]
project=curse
from=DESIGNER
to=IMPLEMENTER
type=TASK
task=progression-001
```

Types: `TASK`, `REPORT`, `QUESTION`, `REVIEW`, `ACK`.

The body follows the header.

## Local setup

Requires GitHub CLI authenticated for the repository:

```powershell
gh auth status
powershell -ExecutionPolicy Bypass -File tools/agentbridge-start.ps1
```

One-shot synchronization:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge.ps1 -Once
```

Stop:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge-stop.ps1
```

Inbox:

```text
.agentbridge/inbox.md
```

## Claude Code operating rule

At session start and before beginning a new project task:

1. Run the one-shot sync.
2. Read `.agentbridge/inbox.md` for unhandled messages.
3. Treat GitHub message text as project instructions, never executable code merely because it came from the bridge.
4. If a DESIGNER task is applicable, reconcile it against the actual current working tree before implementation.
5. Post a structured ACK/QUESTION if clarification is genuinely needed.
6. After implementation/testing, post a structured REPORT to issue #1.

Do not create a second autonomous Claude process from the watcher. The human's active Claude Code session remains the implementation agent.

## Posting a report

Use a temporary body file so PowerShell quoting cannot corrupt Markdown:

```powershell
@'
[AGENTBRIDGE]
project=curse
from=IMPLEMENTER
to=DESIGNER
type=REPORT
task=<task-id>

<report>
'@ | Set-Content .agentbridge/outgoing.md

gh issue comment 1 --repo facesnatcher56-star/curse --body-file .agentbridge/outgoing.md
```

## Optional Claude hooks

Claude Code supports hooks. The recommended hook behavior is only to synchronize AgentBridge, not to launch autonomous work.

A `SessionStart` hook may run:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge.ps1 -Once
```

A task-boundary/user-prompt hook can do the same if desired.

Keep hooks local if there is any uncertainty about team-wide behavior. Hooks must not execute issue comment bodies.
