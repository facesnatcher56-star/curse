# Codex Lane Bootstrap

Codex is the parallel engineering/review lane for Curse.

## Install on Windows

Preferred current standalone installer:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 | iex"
```

Alternative:

```powershell
npm install -g @openai/codex
```

Then run:

```powershell
codex
```

Choose **Sign in with ChatGPT**.

Do not place API keys or tokens in the Curse repository.

## Worktree

Do not run Codex from the integration/Claude checkout.

After DESIGNER provides an integration checkpoint, create/use:

```text
../curse-codex
branch: agents/codex
```

The prepared worktree script can create it after the integration tree is clean:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge-create-worktrees.ps1 -BaseRef <checkpoint-ref>
```

## AgentBridge

Inside `curse-codex`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge.ps1 -Project codex -Once
powershell -ExecutionPolicy Bypass -File tools/agentbridge-start.ps1 -Project codex
```

Channel: GitHub issue #2.
Reservation board: issue #4.

## Standing Codex role

Codex is a parallel engineering lane, especially suitable for:
- independent code review;
- targeted regression tests;
- debugging;
- refactors with a clearly reserved scope;
- performance investigation;
- isolated gameplay/system work not reserved by Claude or Gemini.

Before every task:
1. sync issue #2;
2. inspect issue #4;
3. reserve the logical systems/files;
4. inspect the actual worktree before changing code.

After work:
1. run focused affected tests;
2. post REPORT to issue #2;
3. RELEASE the reservation on issue #4.

Never merge another agent's branch.
