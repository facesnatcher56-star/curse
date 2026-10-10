param(
    [string]$Project = "curse"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "agentbridge/projects/$Project.json"
if (-not (Test-Path $configPath)) { throw "Config not found: $configPath" }
$config = Get-Content $configPath -Raw | ConvertFrom-Json

Write-Host "AgentBridge lane: $Project"
Write-Host "Repo: $($config.repository)"
Write-Host "Issue: #$($config.issue_number)"
Write-Host "Recipients: $($config.accepted_recipients -join ', ')"

$pidPath = Join-Path $repoRoot ".agentbridge/watcher.pid"
if (Test-Path $pidPath) {
    $pidValue = (Get-Content $pidPath -Raw).Trim()
    $proc = $null
    if ($pidValue -match "^\d+$") { $proc = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue }
    if ($proc) { Write-Host "Watcher: RUNNING (PID $pidValue)" }
    else { Write-Host "Watcher: STALE PID FILE ($pidValue)" }
} else {
    Write-Host "Watcher: NOT RUNNING"
}

$inboxPath = Join-Path $repoRoot $config.local_inbox
if (Test-Path $inboxPath) {
    Write-Host "Inbox: present ($((Get-Item $inboxPath).Length) bytes)"
} else {
    Write-Host "Inbox: not created yet"
}
