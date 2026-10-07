# Gemini Lane Bootstrap

Gemini is a parallel content/tooling/independent-subsystem lane for Curse.

## Install

Requires Node/npm.

```powershell
npm install -g @google/gemini-cli
```

Then run:

```powershell
gemini
```

For an individual account, use **Sign in with Google** when prompted.

Do not place API keys, Google credentials, tokens or private data in the Curse repository.

## Worktree

Do not run Gemini from the integration/Claude checkout.

After DESIGNER provides an integration checkpoint, create/use:

```text
../curse-gemini
branch: agents/gemini
```

The prepared worktree script can create it after the integration tree is clean:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge-create-worktrees.ps1 -BaseRef <checkpoint-ref>
```

## AgentBridge

Inside `curse-gemini`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/agentbridge.ps1 -Project gemini -Once
powershell -ExecutionPolicy Bypass -File tools/agentbridge-start.ps1 -Project gemini
```

Channel: GitHub issue #3.
Reservation board: issue #4.

## Standing Gemini role

Gemini is a parallel lane well suited for:
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
