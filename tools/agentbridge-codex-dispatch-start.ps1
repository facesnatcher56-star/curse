$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ((Get-Location).Path -ne $root -or (Split-Path -Leaf $root) -ne "curse-codex") { throw "Run from curse-codex only" }
if ((& git branch --show-current) -ne "agents/codex") { throw "Wrong branch" }
$env:GH_CONFIG_DIR = 'C:\Users\lloyd\AppData\Roaming\GitHub CLI'
& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) { throw "Authenticate gh locally before starting; do not place credentials in the repository" }
$ownerLogin = & gh api user --jq .login
if ($LASTEXITCODE -ne 0 -or $ownerLogin -ne "facesnatcher56-star") { throw "Expected OWNER GitHub login facesnatcher56-star" }
if (Test-Path "$root/.agentbridge/codex.stop") { throw "STOP marker present. Review state/reservations, then explicitly remove .agentbridge/codex.stop before restarting." }
New-Item -ItemType Directory -Path "$root/.agentbridge" -Force | Out-Null
$env:CURSE_CODEX_EXECUTABLE = (Get-Command codex.exe -CommandType Application -ErrorAction Stop).Source
$python = (Get-Command python).Source
& $python "$PSScriptRoot/agentbridge-codex-dispatch.py" --preflight
if ($LASTEXITCODE -ne 0) { throw "Codex worker configuration preflight failed; dispatcher not started" }
Start-Process -FilePath $python -ArgumentList "tools/agentbridge-codex-dispatch.py" -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput "$root/.agentbridge/codex-dispatch.log" -RedirectStandardError "$root/.agentbridge/codex-dispatch-error.log"


