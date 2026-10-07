param(
    [Parameter(Mandatory = $true)]
    [string]$BaseRef,
    [string]$ParentDir = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ParentDir)) {
    $ParentDir = Split-Path -Parent $repoRoot
}

Push-Location $repoRoot
try {
    git rev-parse --verify $BaseRef 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Base ref does not exist locally: $BaseRef" }

    $dirty = git status --porcelain
    if ($dirty) {
        throw "Integration/current tree has uncommitted changes. Create an explicit checkpoint first; refusing to create parallel worktrees from an ambiguous state."
    }

    $lanes = @(
        @{ Name = "codex"; Branch = "agents/codex"; Path = (Join-Path $ParentDir "curse-codex") },
        @{ Name = "antigravity"; Branch = "agents/antigravity"; Path = (Join-Path $ParentDir "curse-antigravity") }
    )

    foreach ($lane in $lanes) {
        if (Test-Path $lane.Path) {
            throw "Worktree path already exists: $($lane.Path)"
        }

        git show-ref --verify --quiet ("refs/heads/" + $lane.Branch)
        if ($LASTEXITCODE -eq 0) {
            git worktree add $lane.Path $lane.Branch
        } else {
            git worktree add -b $lane.Branch $lane.Path $BaseRef
        }

        if ($LASTEXITCODE -ne 0) { throw "Failed to create $($lane.Name) worktree." }

        Write-Host "Created $($lane.Name) lane:"
        Write-Host "  path:   $($lane.Path)"
        Write-Host "  branch: $($lane.Branch)"
    }

    Write-Host ""
    Write-Host "Parallel worktrees created from $BaseRef."
    Write-Host "Each agent must use only its own worktree and reserve systems in GitHub issue #4 before editing."
}
finally {
    Pop-Location
}
