# Autonomous Agent Usage Policy

Applies to Claude Code, Codex, and Antigravity autonomous lanes for Curse.

## OWNER quota reserve

The OWNER's limits are expressed as **usage consumed**:

- PAUSE when rolling / five-hour usage reaches >= 85% used
- PAUSE when weekly usage reaches >= 95% used

Equivalent remaining allowance thresholds:

- PAUSE when five-hour remaining <= 15%
- PAUSE when weekly remaining <= 5%

The purpose is to preserve the final 15% of the five-hour allowance and the final 5% of the weekly allowance for OWNER/manual use and recovery.

## Hard gate behavior

Before starting any new TASK or REVIEW, the dispatcher must obtain a trustworthy current usage reading for that provider/account.

If either threshold has been reached:
- do not start another autonomous model run;
- record the lane as QUOTA_PAUSED;
- leave the AgentBridge message unexecuted/queued;
- notify through the lane's AgentBridge issue if that notification can be posted without consuming the constrained model allowance;
- resume only after BOTH applicable usage windows are back below their limits.

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

The autonomous dispatcher should normalize the provider's reading into:
- five_hour_used_percent
- weekly_used_percent
- observed_at
- source

If the user's plan/provider genuinely has no five-hour window, only the weekly threshold applies. Unknown is not the same as absent.

## Scope

This policy governs autonomous agent execution. It does not prevent the OWNER from manually choosing to use an agent after an autonomous limit has been reached.

Do not automatically purchase credits, consume banked resets, change plans, switch billing modes, or apply paid resets.

## Claude Code adapter status (verified 2026-10-06)

Checked on this PC: the standalone CLI (2.1.144) and the desktop app's embedded client (2.1.289).

- No `usage`, `status` or `limits` subcommand. `claude auth status` reports sign-in only.
- `claude -p "/usage"` (also `/cost`, `/stats`) is answered locally with no model call, but reports only THIS process's own token cost (2.1.289) or
  "you are using your subscription" (2.1.144). Neither gives five-hour or weekly used percent. `/status` is not available in print mode.
- So there is no documented, automatable plan-window reading. The Claude lane dispatcher (`tools/agentbridge-claude-dispatch.ps1`) therefore
  fails closed (`USAGE_UNKNOWN`) and starts nothing. Do not scrape the interactive `/usage` screen or call undocumented endpoints.
- To enable the lane the OWNER must choose a verified source for `Get-UsageReading` in that script (it must supply both windows, or document that the
  plan has no five-hour window), or explicitly accept a different proxy rule in this document.
