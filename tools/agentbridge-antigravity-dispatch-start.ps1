param(
    [int]$PollSeconds = 30,
    [switch]$EnableAutonomousWrites
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $repoRoot ".agentbridge"
$pidPath = Join-Path $localDir "antigravity-dispatch.pid"
$stdout = Join-Path $localDir "antigravity-dispatch-host.log"
$stderr = Join-Path $localDir "antigravity-dispatch-host.err.log"
$worker = Join-Path $PSScriptRoot "agentbridge-antigravity-dispatch.ps1"

if (-not $EnableAutonomousWrites) {
    throw "Refusing to start unattended Antigravity without explicit -EnableAutonomousWrites."
}

$leaf = Split-Path -Leaf $repoRoot
if ($leaf -ne "curse-antigravity") {
    throw "Refusing to start outside dedicated worktree 'curse-antigravity'. Current root: $repoRoot"
}

Push-Location $repoRoot
try {
    $branch = (& git branch --show-current).Trim()
    if ($branch -ne "agents/antigravity") {
        throw "Refusing to start on branch '$branch'. Expected 'agents/antigravity'."
    }
}
finally { Pop-Location }

if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
    throw "Antigravity CLI (agy) is not installed or not on PATH."
}

New-Item -ItemType Directory -Path $localDir -Force | Out-Null

if (Test-Path $pidPath) {
    $oldPid = (Get-Content $pidPath -Raw).Trim()
    if ($oldPid -match "^\d+$" -and (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)) {
        Write-Host "Antigravity AgentBridge dispatcher already running (PID $oldPid)."
        exit 0
    }
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $worker),
    "-Project", "antigravity",
    "-PollSeconds", $PollSeconds,
    "-EnableAutonomousWrites"
)

$p = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Set-Content -Path $pidPath -Value $p.Id -Encoding ascii
Write-Host "Antigravity AgentBridge dispatcher started (PID $($p.Id)); polling every $PollSeconds seconds."
Write-Host "It is authorized for unattended host writes ONLY inside curse-antigravity / agents/antigravity."
Write-Host "State/logs: .agentbridge/"
