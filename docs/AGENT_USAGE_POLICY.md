# Autonomous Agent Usage Policy

Applies to Claude Code, Codex, and Antigravity autonomous lanes for Curse.

## OWNER quota reserve

Percentages are **remaining allowance**, not used allowance.

An autonomous lane must PAUSE when either condition is true:

- rolling / five-hour allowance remaining <= 85%
- weekly allowance remaining <= 95%

This intentionally preserves substantial capacity for interactive OWNER/DESIGNER use.

## Hard gate behavior

Before starting any new TASK or REVIEW, the dispatcher must obtain a trustworthy current usage reading for that provider/account.

If either remaining threshold is at or below the OWNER limit:
- do not start another autonomous model run;
- record the lane as QUOTA_PAUSED;
- leave the AgentBridge message unexecuted/queued;
- notify through the lane's AgentBridge issue if that notification can be posted without consuming the constrained model allowance;
- resume only after the usage reading is back above BOTH thresholds.

If a reliable usage reading cannot be obtained:
- fail closed;
- do not start an autonomous task;
- report/record USAGE_UNKNOWN rather than guessing.

## While a task is already running

Do not deliberately kill a model process in the middle of a file write or other unsafe atomic operation.

At the next safe task boundary/checkpoint:
- stop further autonomous reasoning/tool work;
- leave the worktree recoverable;
- post/report PAUSED_FOR_QUOTA if possible;
- retain or HANDOFF the reservation according to whether incomplete work still owns that system.

No new task may begin while quota-paused.

## Provider adapters

Each lane must use a provider-supported or locally verified read-only usage source.

Known user-facing checks:
- Codex: usage is available in the CLI; official OpenAI guidance documents `/status` for active Codex CLI sessions.
- Antigravity: Google documents `/usage` in Antigravity CLI.
- Claude Code: inspect and verify the installed Claude Code client's supported usage/status mechanism before enabling the autonomous gate. Do not invent or scrape an undocumented format without validation.

The autonomous dispatcher should convert the provider's reading into:
- five_hour_remaining_percent (nullable only when provider has no such window)
- weekly_remaining_percent
- observed_at
- source

If the user's plan/provider genuinely has no five-hour window, only the weekly threshold applies. Unknown is not the same as absent.

## Scope

This policy governs autonomous agent execution. It does not prevent the OWNER from manually choosing to use an agent below these reserves.

Do not automatically purchase credits, consume banked resets, change plans, switch billing modes, or apply paid resets.
