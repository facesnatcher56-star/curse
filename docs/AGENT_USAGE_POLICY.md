# Autonomous Agent Usage Policy

Applies to Claude Code, Codex, and Antigravity autonomous lanes for Curse.

## OWNER quota intent

The OWNER's preferred stop limits are expressed as **usage consumed**:

- pause around rolling / five-hour usage >= 85% used
- pause around weekly usage >= 95% used

Equivalent remaining allowance:
- about 15% remaining in the five-hour window
- about 5% remaining in the weekly window

These limits preserve capacity for manual OWNER/DESIGNER work.

## Telemetry rule

Use an automatic quota gate only when the provider/client exposes a **reliable, supported, machine-readable** usage source that can be locally verified.

Never:
- scrape an interactive UI merely to manufacture a quota parser;
- call undocumented/private billing or quota endpoints;
- guess percentages from token counts;
- invent a five-hour or weekly percentage that the provider does not expose.

If reliable machine-readable telemetry exists:
- check it before each new autonomous TASK/REVIEW;
- pause new runs at the OWNER thresholds;
- leave queued work unconsumed until usage falls below the limits.

If reliable machine-readable telemetry does **not** exist:
- autonomy may still run;
- the 85% five-hour / 95% weekly limits become a manual/advisory stop rule for that provider;
- OWNER/DESIGNER may stop that lane when the visible UI indicates the threshold is near or reached;
- lack of quota telemetry by itself is not a reason to disable an otherwise isolated autonomous lane.

## Safe stopping

Every autonomous lane must have a local stop mechanism independent of model quota telemetry.

When OWNER stops a lane:
- do not begin another autonomous TASK/REVIEW;
- allow an active atomic file operation to finish safely;
- leave the worktree recoverable;
- retain or hand off reservations appropriately.

## Scope

This policy governs autonomous agent execution.

Do not automatically:
- purchase credits;
- consume banked resets;
- change plans or billing modes;
- switch accounts to evade limits;
- apply paid resets.

If a provider later adds a supported machine-readable usage API/CLI, the lane may be upgraded to automatic quota enforcement after local verification.
