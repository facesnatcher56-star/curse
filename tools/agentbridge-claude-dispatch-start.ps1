param(
    [string]$Project = "curse",
    [int]$PollSeconds = 30
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $repoRoot ".agentbridge"
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$pidPath = Join-Path $localDir "claude-dispatch.pid"
$stdout = Join-Path $localDir "claude-dispatch-host.log"
$stderr = Join-Path $localDir "claude-dispatch-host.err.log"
$worker = Join-Path $PSScriptRoot "agentbridge-claude-dispatch.ps1"

if (Test-Path $pidPath) {
    $oldPid = (Get-Content $pidPath -Raw).Trim()
    if ($oldPid -match "^\d+$" -and (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)) {
        Write-Host "Claude AgentBridge dispatcher already running (PID $oldPid)."
        exit 0
    }
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $worker),
    "-Project", $Project,
    "-PollSeconds", $PollSeconds
)

$p = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Set-Content -Path $pidPath -Value $p.Id -Encoding ascii
Write-Host "Claude AgentBridge dispatcher started (PID $($p.Id)); checking every $PollSeconds seconds."
Write-Host "Dispatcher state/logs are under .agentbridge/ and are git-ignored."
