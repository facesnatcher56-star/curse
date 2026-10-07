$ErrorActionPreference = "Stop"
python "$PSScriptRoot/agentbridge-codex-dispatch.py" --stop
if ($LASTEXITCODE -ne 0) { throw "STOP failed" }
Write-Host "STOP requested. No new tasks; current task stops at a safe boundary. Inspect child PID/logs before restarting."
