# PowerShell Watchdog Runner for Godot
# Usage:
#   powershell -File tools/run_godot.ps1 [LOGFILE] [TIMEOUT_SECONDS] [--] [GODOT_ARGS...]

$LogFile = "$env:TEMP\godot_run.log"
$TimeoutSeconds = 20
$rawArgs = @($args)

# Extract LogFile and TimeoutSeconds if provided as first positional arguments
$idx = 0
if ($rawArgs.Count -gt 0 -and $rawArgs[0] -match '\.log$') {
    $LogFile = $rawArgs[0]
    $idx++
}
if ($rawArgs.Count -gt $idx -and $rawArgs[$idx] -match '^\d+$') {
    $TimeoutSeconds = [int]$rawArgs[$idx]
    $idx++
}
if ($rawArgs.Count -gt $idx -and $rawArgs[$idx] -eq '--') {
    $idx++
}

$godotArgs = if ($idx -lt $rawArgs.Count) { $rawArgs[$idx..($rawArgs.Count - 1)] } else { @() }

$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "C:\Users\lloyd\Downloads\Godot_v4.8-dev2_win64.exe\Godot_v4.8-dev2_win64_console.exe" }
if (-not (Test-Path $GodotBin)) {
    Write-Error "Godot binary not found: $GodotBin"
    exit 1
}

# Clean log file
if (Test-Path $LogFile) { Remove-Item $LogFile -Force -ErrorAction SilentlyContinue }

$allArgs = @("--path", ".") + $godotArgs

Write-Host "WATCHDOG: Launching Godot (Timeout: ${TimeoutSeconds}s)..."
Write-Host "WATCHDOG: Command: $GodotBin $($allArgs -join ' ')"

$proc = Start-Process -FilePath $GodotBin -ArgumentList $allArgs -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err" -PassThru -NoNewWindow

$ErrorPatterns = @(
    "SCRIPT ERROR",
    "Parse Error",
    "Compile Error",
    "Failed to load script",
    "Invalid access to property",
    "Invalid call\. Nonexistent"
)
$ErrorRegex = ($ErrorPatterns -join "|")

$startTime = [System.DateTime]::UtcNow
$stoppedReason = ""

while (-not $proc.HasExited) {
    Start-Sleep -Milliseconds 250
    $elapsed = ([System.DateTime]::UtcNow - $startTime).TotalSeconds
    
    # Check log for errors
    if (Test-Path $LogFile) {
        $logContent = Get-Content -Path $LogFile -Tail 30 -ErrorAction SilentlyContinue
        if ($logContent -match $ErrorRegex) {
            Start-Sleep -Milliseconds 200
            $stoppedReason = "ERROR_DETECTED"
            break
        }
    }

    # Check timeout
    if ($elapsed -ge $TimeoutSeconds) {
        $stoppedReason = "TIMED_OUT"
        break
    }
}

if ($stoppedReason -ne "") {
    Write-Host "WATCHDOG: Killing Godot process ($stoppedReason)..." -ForegroundColor Red
    try {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    } catch {}
    
    if (Test-Path $LogFile) {
        Write-Host "--- LOG OUTPUT ---" -ForegroundColor Yellow
        Get-Content -Path $LogFile -Tail 30
    }
    if (Test-Path "$LogFile.err") {
        $errs = Get-Content -Path "$LogFile.err" -ErrorAction SilentlyContinue
        if ($errs) {
            Write-Host "--- STDERR ---" -ForegroundColor Red
            $errs | Select-Object -Last 20
        }
    }
    
    if ($stoppedReason -eq "ERROR_DETECTED") { exit 2 }
    if ($stoppedReason -eq "TIMED_OUT") { exit 124 }
}

$proc.WaitForExit()
$exitCode = $proc.ExitCode

if (Test-Path $LogFile) {
    $results = Select-String -Path $LogFile -Pattern "\[(PASS|FAIL)\]|Self-test|SELFTEST|SCREENSHOT_SAVED" -SimpleMatch
    if ($results) {
        $results | Select-Object -Last 20 | ForEach-Object { $_.Line }
    }
}

exit $exitCode
