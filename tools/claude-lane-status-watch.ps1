# READ-ONLY status watcher for the Claude lane. It only READS .agentbridge/claude-dispatcher-health.json in the Claude worktree and prints one
# line whenever the lane changes: STARTED a task, FINISHED a task, PAUSED/FAILED/STOPPED, dispatcher restarted, or the heartbeat went silent.
# It never writes, never calls GitHub and never touches the dispatcher, the worker or any repo file.
param(
    [string]$HealthPath = "C:\Users\lloyd\OneDrive\Documents\curse-claude\.agentbridge\claude-dispatcher-health.json",
    [int]$EverySeconds = 5,
    [int]$SilentAfterSeconds = 150
)

function Read-Health {
    try { return (Get-Content -LiteralPath $HealthPath -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}
function Say([string]$Text) { Write-Output ("{0} CLAUDE LANE: {1}" -f (Get-Date -Format "HH:mm:ss"), $Text); [Console]::Out.Flush() }

$prev = $null
$silent = $false
Say "watching (read-only)"
while ($true) {
    $h = Read-Health
    if ($null -eq $h) {
        if (-not $silent) { Say "health file unreadable or missing"; $silent = $true }
    } else {
        $age = [int]((Get-Date).ToUniversalTime() - ([datetime]$h.heartbeat_utc).ToUniversalTime()).TotalSeconds
        if ($age -gt $SilentAfterSeconds -and $h.status -ne "STOPPED") {
            if (-not $silent) { Say "NO HEARTBEAT for ${age}s (last status $($h.status), dispatcher PID $($h.dispatcher_pid)) - the dispatcher may be down"; $silent = $true }
        } else {
            if ($silent) { Say "heartbeat is back (status $($h.status))"; $silent = $false }
            if ($null -eq $prev) {
                Say "status $($h.status), dispatcher PID $($h.dispatcher_pid), active task '$($h.active_task)'"
            } else {
                if ($h.dispatcher_pid -ne $prev.dispatcher_pid) { Say "dispatcher restarted (PID $($prev.dispatcher_pid) -> $($h.dispatcher_pid))" }
                if ($h.active_task -ne $prev.active_task) {
                    if ($h.active_task) { Say "WORKING: started task $($h.active_task) (worker PID $($h.worker_pid))" }
                    if ($prev.active_task) { Say "FINISHED: task $($prev.active_task) is done (status now $($h.status))" }
                }
                if ($h.status -ne $prev.status -and $h.status -notin @("RUNNING", "IDLE")) { Say "status $($prev.status) -> $($h.status)$(if ($h.last_error) { ' (' + $h.last_error + ')' })" }
                elseif ($h.status -eq "IDLE" -and $prev.status -notin @("IDLE", "RUNNING")) { Say "back to IDLE" }
            }
            $prev = $h
        }
    }
    Start-Sleep -Seconds $EverySeconds
}
