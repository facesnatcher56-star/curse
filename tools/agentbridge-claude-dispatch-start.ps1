# Starts the Claude lane dispatcher (hidden, one instance) from the isolated worktree ../curse-claude only. See docs/CLAUDE_LANE.md.
# Refuses to start: outside curse-claude / agents/claude; while a STOP file exists (use -ClearStop to remove it); when the Claude client is not logged in.
param(
    [string]$Project = "curse",
    [int]$PollSeconds = 30,
    [string]$ClaudeExe = "",
    [switch]$ClearStop
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $repoRoot ".agentbridge"
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$pidPath = Join-Path $localDir "claude-dispatch.pid"
$stdout = Join-Path $localDir "claude-dispatch-host.log"
$stderr = Join-Path $localDir "claude-dispatch-host.err.log"
$stopPath = Join-Path $localDir "STOP"
$worker = Join-Path $PSScriptRoot "agentbridge-claude-dispatch.ps1"

# The same isolation rule the dispatcher enforces: the dedicated Claude worktree only.
$leaf = Split-Path -Leaf $repoRoot
$ErrorActionPreference = "Continue"   # (git's stderr must not become an exception here)
$branch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null)
$ErrorActionPreference = "Stop"
if ($leaf -ne "curse-claude" -or "$branch".Trim() -ne "agents/claude") {
    throw "Refusing to start: this is '$leaf' on branch '$branch'. The Claude lane runs only in the worktree 'curse-claude' on 'agents/claude'."
}

if (Test-Path $stopPath) {
    if ($ClearStop) { Remove-Item $stopPath -Force; Write-Host "Removed the STOP file." }
    else { throw "A STOP file exists (.agentbridge/STOP): the OWNER halted this lane. Start again with -ClearStop to resume." }
}

if ([string]::IsNullOrWhiteSpace($ClaudeExe)) {
    $found = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $found) { throw "claude is not on PATH (or pass -ClaudeExe)." }
    $ClaudeExe = $found.Source
}
$auth = (& $ClaudeExe auth status 2>$null | Out-String)
$loggedIn = $false
try { $loggedIn = [bool]($auth | ConvertFrom-Json).loggedIn } catch {}
if (-not $loggedIn) { throw "The Claude client at $ClaudeExe is not logged in. Run: claude auth login" }

if (Test-Path $pidPath) {
    $oldPid = (Get-Content $pidPath -Raw).Trim()
    if ($oldPid -match "^\d+$" -and (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)) {
        Write-Host "Claude AgentBridge dispatcher already running (PID $oldPid)."
        exit 0
    }
}

$argList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $worker),
    "-Project", $Project,
    "-PollSeconds", $PollSeconds,
    "-ClaudeExe", ('"{0}"' -f $ClaudeExe)
)

$p = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Set-Content -Path $pidPath -Value $p.Id -Encoding ascii
Write-Host "Claude AgentBridge dispatcher started (PID $($p.Id)); checking every $PollSeconds seconds. Client: $ClaudeExe"
Write-Host "State/logs are under .agentbridge/ and are git-ignored. To halt at once: tools/agentbridge-claude-dispatch-stop.ps1"
