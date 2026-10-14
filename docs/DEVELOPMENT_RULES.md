# Curse — Permanent Engineering & Multi-Agent Development Rules

Project: Curse — Godot 4 Action RPG
Repository: `facesnatcher56-star/curse`
Applies to: Claude, Codex, Gemini, Antigravity, independent reviewers, coordinators, and all future development agents.
Status: PERMANENT PROJECT POLICY

These rules replace previous excessive testing, repetitive verification, and unnecessary approval procedures. They apply to all future development unless the project owner explicitly changes them.

The goal is to operate like a competent senior software engineering team: ship reliable, playable improvements efficiently without sacrificing meaningful quality.

## 1. Core Engineering Philosophy

Development progress is measured by working, integrated, player-visible improvements—not by the number of tests executed, reports generated, or approvals collected.

Agents must:

- Make practical engineering decisions.
- Prefer simple, maintainable implementations.
- Focus on actual problems and measurable improvements.
- Avoid speculative refactoring and unnecessary complexity.
- Resolve straightforward technical decisions independently.
- Avoid repeatedly requesting information already established.
- Prioritize delivering functioning gameplay over process overhead.

Do not confuse more verification with better engineering.
Testing and review are tools for reducing risk, not objectives themselves.

## 2. Risk-Based Testing Is Mandatory

Use the smallest meaningful tests that can establish whether a change works.

**Low-risk changes** (text corrections, minor UI spacing, documentation, small isolated logic changes)

Required:
- Relevant targeted check where useful.
- Import/parse validation if executable code changed.
- No repeated full-game simulations.
- No unnecessary independent review unless the change affects an important interface or the integration process requires it.

**Medium-risk changes** (inventory behavior, tooltip logic, enemy attacks, UI interaction, equipment calculations)

Required:
- Focused tests for changed behavior.
- Relevant regression tests.
- One authoritative integration/CI verification.
- Review appropriate to the affected subsystem.

**High-risk changes** (save compatibility, combat foundations, progression, major AI changes, large multi-branch integrations)

Required:
- Targeted and integration tests.
- One full-suite verification on the final candidate, normally through CI.
- Independent review of meaningful risks.
- Additional verification only when justified by an identifiable failure mode.

The testing burden must be proportional to the risk of the change.

## 3. Stop Redundant Full-Suite Testing

The default is: one authoritative full self-test execution per final integration candidate, normally in CI.

Do not automatically:
- Run the full suite after every small commit.
- Run it three or more times on unchanged code.
- Repeat identical test sequences without a reason.
- Duplicate successful CI coverage with another identical local run.
- Restart the entire verification process for comment-only or documentation-only changes.

If a full suite fails:
1. Identify the specific failure.
2. Run the smallest reproduction.
3. Fix the underlying problem.
4. Verify the affected area.
5. Run the required final integration verification.

A failed test does not automatically justify rerunning every unrelated test.
Repository-required checks and protections still apply.

## 4. Eliminate Arbitrary Repetition Counts

No default requirements for:
- 10 consecutive passes.
- 3 complete full-suite passes.
- Dozens of identical gameplay simulations.
- Thousands of unnecessary frames simply to establish repeatability.

Repeat testing only when investigating an actual intermittent failure, nondeterministic behavior, race condition, or environment-dependent problem.

When repetition is justified:
- Explain the suspected failure.
- Vary meaningful conditions where appropriate.
- Select a reasonable number of repetitions.
- Stop when sufficient evidence exists.
- Report any remaining uncertainty.

Prefer three genuinely different scenarios over ten repetitions of the same deterministic scenario.
Do not introduce repetition quotas without technical justification.

## 5. Optimize Slow Gameplay Tests

Godot automated testing must be efficient. Agents should:

- Separate fast logic tests from complete gameplay simulations.
- Use short, representative scenarios.
- Advance simulated frames faster than real time when safe.
- Avoid unnecessary animation waits and cooldowns in tests that do not depend on timing.
- Avoid reimporting unchanged assets repeatedly.
- Reuse valid build/import caches where safe.
- Keep the real movement, combat, physics, and navigation systems intact when those systems are what the test is intended to verify.

Full-speed, full-duration gameplay simulations should be reserved for situations where authentic timing or integrated behavior actually matters.
Do not build an elaborate testing framework merely to optimize one trivial test.

## 6. Fix Root Causes, Not Test Results

When tests fail, agents must investigate rather than blindly rerun them.

Determine whether a failure is:
- An actual code regression.
- An existing baseline issue.
- A flaky or incorrectly implemented test.
- A platform/display-environment difference.
- A timing or synchronization problem.
- A legitimate design ambiguity.

Compare against clean `main` when that comparison will meaningfully resolve uncertainty.
Do not disable, weaken, or delete meaningful assertions just to obtain green CI.
However, do not allow a demonstrably unreliable or obsolete test to hold development hostage indefinitely. Correct, replace, or quarantine it with a documented reason and appropriate approval.
A passing test does not prove that a player-facing feature feels right or renders correctly.

## 7. Independent Code Review Must Be Proportional

Independent review remains valuable, particularly for integration, complex logic, and high-risk systems. But review must not become an endless cycle.

- Review substantive changes and realistic failure modes.
- Prioritize correctness, regressions, maintainability, and unintended interactions.
- Avoid repeated independent reviews of the exact same unchanged code.
- Do not request a new full review for formatting or comment-only changes unless materially relevant.
- Do not require several agents to repeat the same review without a specific reason.
- Correct identified blocking issues promptly.
- Treat minor non-blocking observations as follow-up work, not automatic merge blockers.

One competent independent acceptance is normally sufficient unless project or repository requirements specify otherwise.

## 8. Maintain Efficient Multi-Agent Parallel Development

The coordinator is responsible for:
- Assigning clearly bounded tasks.
- Selecting agents based on capability, availability, and cost.
- Avoiding overlapping file ownership when possible.
- Keeping independent tasks moving concurrently.
- Integrating completed work promptly.
- Avoiding unnecessary idle time.
- Preventing agents from repeatedly investigating already-resolved issues.

Each implementation agent should have:
- A clearly defined objective.
- Its own branch or isolated worktree.
- A limited change scope.
- Concrete completion criteria.
- A known integration destination.

Agents should not block independent workstreams merely because an unrelated task is awaiting CI or review.
Do not create extra approval layers, meetings, reports, or dispatcher steps that provide no engineering value.

## 9. Integration and Merge Policy

`main` is the authoritative integrated project. Required practices:

- Preserve the user's existing working directories and uncommitted changes.
- Use isolated branches/worktrees.
- Integrate against the current repository state.
- Resolve conflicts intentionally.
- Preserve unrelated working behavior.
- Verify the exact SHA being integrated.
- Respect existing branch protections and required checks.
- Follow established owner authorization for merges.

Once the required checks and authorized review are satisfied, proceed with the merge workflow without inventing additional gates.
Do not continually request fresh permission for work already explicitly authorized under an established workflow.
Never force-push, overwrite another agent's work, or bypass repository protections merely to expedite integration.
After merging, verify that the expected commit reached `main` and that required post-merge checks passed.

## 10. CI Is the Authoritative Final Automated Gate

GitHub Actions should be the primary final integration verification wherever appropriate.

The preferred process:
1. Implement the change.
2. Run focused local tests.
3. Perform a local smoke/import check where needed.
4. Integrate completed work.
5. Run required CI on the final candidate.
6. Complete appropriate independent review.
7. Merge using the authorized workflow.

Review and CI can proceed concurrently.
Do not run an additional identical full local suite simply because CI succeeded.
If CI fails, investigate its logs and correct the specific failure. Do not start a broad testing campaign without justification.

## 11. Player-Facing Behavior Requires Player-Facing Validation

Automated tests cannot fully establish:
- Whether combat feels satisfying.
- Whether AI behaves naturally.
- Whether UI is readable.
- Whether mouse and keyboard interactions are intuitive.
- Whether animations and visual effects look correct.
- Whether a level feels populated, balanced, or enjoyable.

For these changes, use:
- Short targeted windowed checks.
- Actual screenshots where applicable.
- Focused gameplay demonstrations.
- Owner playtesting.

Headless startup proves that the game starts without certain errors. It does not prove visual correctness.
A windowed process exiting successfully does not prove the rendered result looks correct if nobody inspected it.

Clearly distinguish between:
- Automated verification.
- Visually observed behavior.
- Actual owner/player acceptance.

Do not claim verification that did not occur.

## 12. Playtest Readiness

Use `READY_TO_PLAYER_TEST=yes` only when a specific integrated candidate is genuinely ready for the owner to launch. Required:
- Exact commit SHA, branch, or packaged build location.
- Successful import and startup.
- Required integration checks passed.
- Clear launch instructions.
- Known issues disclosed.
- Sufficient independent acceptance for the change's risk.

Actual owner playtesting is not required before declaring a build ready for player testing.
However, do not label unobserved gameplay or visuals as already player-accepted.
Do not confuse an isolated agent patch with an integrated playable build.

## 13. Minimize Unnecessary Communication and Reporting

Agent reports should be concise and useful. A normal completed assignment should report:
- What changed.
- Exact branch and commit SHA.
- What was verified.
- Any real blockers.
- What should happen next.

Do not produce long transcripts of routine commands, repetitive status messages, or elaborate reports for trivial changes.
The coordinator should summarize information rather than forwarding every agent's raw output.

Escalate to the owner only when:
- A genuine design decision is needed.
- Requirements conflict.
- A significant risk or blocker exists.
- A change meaningfully alters agreed gameplay.
- Additional spending or resources need authorization.

Make routine engineering decisions without unnecessary interruptions.

## 14. Protect Scope and Avoid Overengineering

Agents must solve the assigned problem without expanding it into unrelated work. Examples:
- Fix a tooltip without redesigning the entire UI framework.
- Fix archer targeting without rewriting combat.
- Improve encounter density without replacing the world-generation system.
- Fix a test harness without restructuring all tests.

Prefer existing systems and reusable components.
Refactor only when it materially simplifies the solution, prevents a demonstrated problem, or is necessary for maintainability.
Do not turn minor improvements into large architectural projects.

## 15. Prioritize Actual Game Quality

Curse is a game, not a collection of passing tests. Development priority should favor:

1. Broken player-facing functionality.
2. Combat feel, movement, and enemy intelligence.
3. Gameplay variety, progression, and encounters.
4. UI clarity and responsiveness.
5. Visual consistency and presentation.
6. Performance and stability.
7. Technical debt with meaningful impact.

This ordering is guidance, not a reason to ignore critical stability defects.
When choosing between another redundant verification cycle and a meaningful gameplay improvement, prefer the gameplay improvement once existing quality gates are satisfied.

## 16. No New Process Gates Without Justification

Agents and coordinators may recommend additional checks where a real risk exists. However, they must not silently introduce:
- New repetition requirements.
- Extra review cycles.
- Additional approval layers.
- Mandatory lengthy demonstrations.
- Unrelated test suites as new blockers.

Explain why any proposed additional gate is necessary.
Do not continually move the finish line after the agreed acceptance criteria have been met.
The owner retains final authority over project priorities and process changes.

## 17. Continuous Improvement of the Development Workflow

If tests become unnecessarily expensive, agents should identify the bottleneck and improve it when the expected benefit justifies the effort. Examples:
- Reduce unnecessary test setup.
- Improve focused suite execution.
- Remove repeated imports.
- Fix unstable test synchronization.
- Improve agent task coordination.
- Reduce unnecessary merge conflicts.

Do not allow optimization of the workflow to consume more time than it reasonably saves.

## Default Completion Workflow

For ordinary future development tasks:

Implement → Focused verification → Integrate → One authoritative CI/full-suite check → Appropriate review → Authorized merge → Player test when relevant.

Review and CI may run simultaneously. For genuinely trivial or isolated work, use less ceremony where repository requirements allow it. For high-risk changes, apply additional checks only when justified by the risk. Passing the required verification means the task moves forward.

## Permanent Repository Instructions

1. This document lives at `docs/DEVELOPMENT_RULES.md`.
2. `AGENTS.md` and `CLAUDE.md` reference it. Agents must read it before accepting development tasks.
3. Existing security, safety, and repository-protection requirements are preserved.
4. Where an older local instruction conflicts with the excessive-testing process, the owner decides how to reconcile it. Until then, owner standing rules in `CLAUDE.md` (ask when uncertain, UI theme matrix for visual changes) still apply.

These rules remain in force unless explicitly revised by the project owner.

## FINAL DIRECTIVE

Operate as experienced software engineers working on a real commercial game. Apply judgment, manage risk, write maintainable code, avoid pointless ceremony, and deliver working software efficiently.

Quality is mandatory. Redundant process is not.
