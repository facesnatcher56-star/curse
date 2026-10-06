param(
    [string]$Project = "curse",
    [int]$PollSeconds = 30
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $repoRoot ".agentbridge"
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$pidPath = Join-Path $localDir "watcher.pid"
$logPath = Join-Path $localDir "watcher.log"
$watcher = Join-Path $PSScriptRoot "agentbridge.ps1"

if (Test-Path $pidPath) {
    $oldPid = (Get-Content $pidPath -Raw).Trim()
    if ($oldPid -match "^\d+$" -and (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)) {
        Write-Host "AgentBridge watcher already running (PID $oldPid)."
        exit 0
    }
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $watcher),
    "-Project", $Project,
    "-PollSeconds", $PollSeconds
)
$p = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $logPath -RedirectStandardError ($logPath + ".err")
Set-Content -Path $pidPath -Value $p.Id -Encoding ascii
Write-Host "AgentBridge watcher started (PID $($p.Id)); polling every $PollSeconds seconds."
Write-Host "Inbox: .agentbridge/inbox.md"
Write-Host "Log: .agentbridge/watcher.log"
