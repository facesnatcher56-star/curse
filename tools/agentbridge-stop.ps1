$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$pidPath = Join-Path $repoRoot ".agentbridge/watcher.pid"
if (-not (Test-Path $pidPath)) {
    Write-Host "AgentBridge watcher is not running (no PID file)."
    exit 0
}
$pidValue = (Get-Content $pidPath -Raw).Trim()
if ($pidValue -match "^\d+$") {
    $p = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
    if ($p) {
        Stop-Process -Id $p.Id
        Write-Host "Stopped AgentBridge watcher (PID $($p.Id))."
    }
}
Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
