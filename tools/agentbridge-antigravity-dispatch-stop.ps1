# The OWNER's stop switch for the Antigravity lane. Halts autonomous Antigravity IMMEDIATELY:
#   1. writes .agentbridge/STOP (the dispatcher starts nothing while it exists; the start script refuses until -ClearStop);
#   2. stops the dispatcher;
#   3. kills the running worker and everything it started (its whole process tree), unless -KeepWorker.
# Run it from anywhere inside the worktree. It never touches any other worktree.
param([switch]$KeepWorker)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $repoRoot ".agentbridge"
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$pidPath = Join-Path $localDir "antigravity-dispatch.pid"
$statePath = Join-Path $localDir "antigravity-dispatch-state.json"
$stopPath = Join-Path $localDir "STOP"

Set-Content -Path $stopPath -Value ("stopped by the OWNER at " + (Get-Date -Format o)) -Encoding utf8
Write-Host "STOP file written: no new task will start."

$healthPath = Join-Path $localDir "antigravity-dispatcher-health.json"
if (Test-Path $healthPath) {
    try {
        $h = Get-Content $healthPath -Raw | ConvertFrom-Json
        $h.status = "STOPPED"
        $h.heartbeat_utc = (Get-Date).ToUniversalTime().ToString("o")
        $h | ConvertTo-Json -Depth 5 | Set-Content -Path $healthPath -Encoding utf8
    } catch {}
}

if (-not $KeepWorker -and (Test-Path $statePath)) {
    try {
        $state = Get-Content $statePath -Raw | ConvertFrom-Json
        $workerPid = 0
        if ([int]::TryParse([string]$state.active_pid, [ref]$workerPid) -and $workerPid -gt 0 -and (Get-Process -Id $workerPid -ErrorAction SilentlyContinue)) {
            $proc = Get-Process -Id $workerPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -ne "language_server") {
                & taskkill.exe /T /F /PID $workerPid 2>&1 | Out-Null
                Write-Host "Killed the worker (PID $workerPid) and its process tree."
            } else {
                Write-Host "Worker was Agent API conversation (PID $workerPid is language_server daemon); leaving language_server running."
            }
        }
    } catch { Write-Host "Could not read the dispatcher state: $($_.Exception.Message)" }
}

if (Test-Path $pidPath) {
    $pidValue = (Get-Content $pidPath -Raw).Trim()
    if ($pidValue -match "^\d+$") {
        $p = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
        if ($p) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                Write-Host "Stopped the Antigravity AgentBridge dispatcher (PID $($p.Id))."
            } catch {
                try {
                    Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)" | Invoke-CimMethod -MethodName Terminate | Out-Null
                    Write-Host "Stopped the Antigravity AgentBridge dispatcher via CIM (PID $($p.Id))."
                } catch {
                    Write-Host "Could not stop dispatcher PID $($p.Id): $($_.Exception.Message)"
                }
            }
        }
    }
    Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "The dispatcher was not running (no PID file)."
}
Write-Host "To resume later: tools/agentbridge-antigravity-dispatch-start.ps1 -ClearStop -EnableAutonomousWrites"
