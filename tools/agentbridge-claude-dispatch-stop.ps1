# The OWNER's stop switch for the Claude lane. Halts autonomous Claude IMMEDIATELY:
#   1. writes .agentbridge/STOP (the dispatcher starts nothing while it exists; the start script refuses until -ClearStop);
#   2. stops the dispatcher;
#   3. kills the running worker and everything it started (its whole process tree), unless -KeepWorker.
# Run it from anywhere inside the worktree. It never touches any other worktree.
param([switch]$KeepWorker)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $repoRoot ".agentbridge"
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$pidPath = Join-Path $localDir "claude-dispatch.pid"
$statePath = Join-Path $localDir "claude-dispatch-state.json"
$stopPath = Join-Path $localDir "STOP"

Set-Content -Path $stopPath -Value ("stopped by the OWNER at " + (Get-Date -Format o)) -Encoding utf8
Write-Host "STOP file written: no new task will start."

if (-not $KeepWorker -and (Test-Path $statePath)) {
    try {
        $state = Get-Content $statePath -Raw | ConvertFrom-Json
        $workerPid = 0
        if ([int]::TryParse([string]$state.active_pid, [ref]$workerPid) -and $workerPid -gt 0 -and (Get-Process -Id $workerPid -ErrorAction SilentlyContinue)) {
            & taskkill.exe /T /F /PID $workerPid 2>&1 | Out-Null
            Write-Host "Killed the worker (PID $workerPid) and its process tree."
        }
    } catch { Write-Host "Could not read the dispatcher state: $($_.Exception.Message)" }
}

if (Test-Path $pidPath) {
    $pidValue = (Get-Content $pidPath -Raw).Trim()
    if ($pidValue -match "^\d+$") {
        $p = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
        if ($p) {
            Stop-Process -Id $p.Id -Force
            Write-Host "Stopped the Claude AgentBridge dispatcher (PID $($p.Id))."
        }
    }
    Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "The dispatcher was not running (no PID file)."
}
Write-Host "To resume later: tools/agentbridge-claude-dispatch-start.ps1 -ClearStop"
