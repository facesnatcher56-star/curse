# Starts the Antigravity lane dispatcher (hidden, one instance) from the isolated worktree ../curse-antigravity only. See docs/ANTIGRAVITY_LANE.md.
# Refuses to start: outside curse-antigravity / agents/antigravity; while a STOP file exists (use -ClearStop to remove it); without -EnableAutonomousWrites.
param(
    [string]$Project = "antigravity",
    [int]$PollSeconds = 30,
    [string]$AgyExe = "",
    [int]$MaxMinutes = 120,
    [switch]$EnableAutonomousWrites,
    [switch]$ClearStop
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $repoRoot ".agentbridge"
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$pidPath = Join-Path $localDir "antigravity-dispatch.pid"
$stdout = Join-Path $localDir "antigravity-dispatch-host.log"
$stderr = Join-Path $localDir "antigravity-dispatch-host.err.log"
$stopPath = Join-Path $localDir "STOP"
$worker = Join-Path $PSScriptRoot "agentbridge-antigravity-dispatch.ps1"

if (-not $EnableAutonomousWrites) {
    throw "Refusing to start unattended Antigravity without explicit -EnableAutonomousWrites."
}

# The same isolation rule the dispatcher enforces: the dedicated Antigravity worktree only.
$leaf = Split-Path -Leaf $repoRoot
$ErrorActionPreference = "Continue"   # (git's stderr must not become an exception here)
$branch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null)
$gitDir = (& git -C $repoRoot rev-parse --absolute-git-dir 2>$null)
$common = (& git -C $repoRoot rev-parse --path-format=absolute --git-common-dir 2>$null)
$isLaneBranch = ("$branch".Trim() -eq "agents/antigravity" -or "$branch".Trim() -match "^agents/antigravity(-.*)?$")
if ($leaf -ne "curse-antigravity" -or -not $isLaneBranch) {
    throw "Refusing to start: this is '$leaf' on branch '$branch'. The Antigravity lane runs only in the worktree 'curse-antigravity' on 'agents/antigravity' (or continuation branches)."
}
if ((("$gitDir").Trim().TrimEnd('/', '\') -replace '\\', '/') -eq (("$common").Trim().TrimEnd('/', '\') -replace '\\', '/')) {
    throw "Refusing to start: this is the main checkout, not the dedicated linked worktree."
}

if (Test-Path $stopPath) {
    if ($ClearStop) {
        Remove-Item $stopPath -Force
        Write-Host "Removed the STOP file."
    } else {
        throw "A STOP file exists (.agentbridge/STOP): the OWNER halted this lane. Start again with -ClearStop to resume."
    }
}

if ([string]::IsNullOrWhiteSpace($AgyExe)) {
    $found = Get-Command agy -ErrorAction SilentlyContinue
    if ($found) {
        $AgyExe = $found.Source
    } else {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA "agy\bin\agy.exe"),
            (Join-Path $env:USERPROFILE ".gemini\antigravity\bin\agy.exe"),
            (Join-Path $env:APPDATA "Antigravity\bin\agy.cmd"),
            (Join-Path $env:LOCALAPPDATA "Programs\antigravity\resources\bin\language_server.exe"),
            (Join-Path $env:USERPROFILE ".gemini\antigravity\bin\agentapi.bat")
        )
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath $c) {
                $AgyExe = $c
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($AgyExe)) {
        throw "Antigravity entry point is not found at standard candidate locations (pass -AgyExe)."
    }
}

if (-not (Test-Path -LiteralPath $AgyExe)) {
    throw "Antigravity executable not found: $AgyExe"
}

if (Test-Path $pidPath) {
    $oldPid = (Get-Content $pidPath -Raw).Trim()
    if ($oldPid -match "^\d+$" -and (Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue)) {
        Write-Host "Antigravity AgentBridge dispatcher already running (PID $oldPid)."
        exit 0
    }
}

if ([string]::IsNullOrWhiteSpace($env:ANTIGRAVITY_LS_ADDRESS)) {
    $lsProcs = Get-Process -Name "language_server" -ErrorAction SilentlyContinue
    if ($lsProcs) {
        foreach ($proc in $lsProcs) {
            $conn = Get-NetTCPConnection -State Listen -OwningProcess $proc.Id -ErrorAction SilentlyContinue |
                Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1', '0.0.0.0') } |
                Select-Object -First 1
            if ($conn) {
                $env:ANTIGRAVITY_LS_ADDRESS = "127.0.0.1:$($conn.LocalPort)"
                Write-Host "Set ANTIGRAVITY_LS_ADDRESS to $env:ANTIGRAVITY_LS_ADDRESS"
                break
            }
        }
    }
}

$cmdLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -Project {1} -PollSeconds {2} -AgyExe "{3}" -MaxMinutes {4} -EnableAutonomousWrites' -f $worker, $Project, $PollSeconds, $AgyExe, $MaxMinutes

# Win32_Process.Create detaches the dispatcher from this shell's job object / process tree (Start-Process children die with the invoking shell).
# Output goes to the dispatcher's own log (.agentbridge/antigravity-dispatch.log); the host stdout/stderr files are not redirected by this method.
$created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine; CurrentDirectory = $repoRoot }
if ($created.ReturnValue -ne 0 -or -not $created.ProcessId) {
    throw "Failed to launch the dispatcher (Win32_Process.Create returned $($created.ReturnValue))."
}
Start-Sleep -Seconds 3
if (-not (Get-Process -Id $created.ProcessId -ErrorAction SilentlyContinue)) {
    throw "The dispatcher (PID $($created.ProcessId)) exited immediately; see .agentbridge/antigravity-dispatch.log."
}
Set-Content -Path $pidPath -Value $created.ProcessId -Encoding ascii
Write-Host "Antigravity AgentBridge dispatcher started (PID $($created.ProcessId)); checking every $PollSeconds seconds. Client: $AgyExe"
Write-Host "State/logs are under .agentbridge/ and are git-ignored. To halt at once: tools/agentbridge-antigravity-dispatch-stop.ps1"
