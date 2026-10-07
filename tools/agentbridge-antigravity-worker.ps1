param(
    [Parameter(Mandatory=$true)][string]$PromptFile
)

$ErrorActionPreference = "Stop"
if (-not (Get-Command agy -ErrorAction SilentlyContinue)) { throw "Antigravity CLI (agy) is required." }
$prompt = Get-Content -LiteralPath $PromptFile -Raw
& agy --dangerously-skip-permissions --print-timeout 90m -p $prompt
exit $LASTEXITCODE
