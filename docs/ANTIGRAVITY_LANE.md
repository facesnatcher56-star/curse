# Antigravity Lane Bootstrap

Antigravity is the Google parallel implementation/content/tooling lane for Curse.

Google transitioned the consumer Gemini CLI path to Antigravity CLI / Antigravity 2.0. Use Antigravity for this lane.

## Install on Windows

```powershell
irm https://antigravity.google/cli/install.ps1 | iex
```

Start it with:

```powershell
agy
```

Antigravity CLI authenticates through the system keyring and Google sign-in when needed.

Do not place Google credentials, tokens, API keys or private data in the Curse repository.

## Worktree

Do not run Antigravity from the integration/Claude checkout.

After DESIGNER provides an integration checkpoint, create/use:

```text
../curse-antigravity
branch: agents/antigravity
```

The prepared worktree script can create it after the integration tree is clean:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge-create-worktrees.ps1 -BaseRef <checkpoint-ref>
```

## AgentBridge

Inside `curse-antigravity`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge.ps1 -Project antigravity -Once
powershell -ExecutionPolicy Bypass -File tools/agentbridge-start.ps1 -Project antigravity
```

Channel: GitHub issue #3.
Reservation board: issue #4.

## Standing Antigravity role

Antigravity is a parallel lane well suited for:
- quest/content authoring;
- data definitions;
- isolated tooling;
- documentation;
- independent subsystem implementation;
- UI/content work whose reservation does not overlap another agent.

Before every task:
1. sync issue #3;
2. inspect issue #4;
3. reserve the logical systems/files;
4. inspect the actual worktree before changing code.

After work:
1. run focused affected tests;
2. post REPORT to issue #3;
3. RELEASE the reservation on issue #4.

Never merge another agent's branch.
