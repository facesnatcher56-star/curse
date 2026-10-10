# READ-ONLY feed of the Claude lane's AgentBridge traffic. Polls issues #1 and #4 and prints one line per NEW structured comment that involves the
# Claude lane (from or to IMPLEMENTER/CLAUDE): TASK, REVIEW, DISPATCHED, ACK, RESERVE, RELEASE, QUESTION, REPORT, HANDOFF. HEALTH is skipped.
# It only calls `gh api` GET requests. It never posts, edits or deletes anything. It starts from "now": history is not replayed.
param(
    [string]$Repo = "facesnatcher56-star/curse",
    [int[]]$Issues = @(1, 4),
    [int]$EverySeconds = 30,
    [switch]$AllLanes          # every lane's traffic (Codex, Antigravity, Claude, DESIGNER, OWNER), not only the Claude lane's
)
if ($AllLanes -and -not $PSBoundParameters.ContainsKey("Issues")) { $Issues = @(1, 2, 3, 4, 7) }
$ErrorActionPreference = "Continue"

function Parse-Header([string]$Body) {
    if ([string]::IsNullOrEmpty($Body)) { return $null }
    $b = $Body.TrimStart([char]0xFEFF)
    if (-not $b.StartsWith("[AGENTBRIDGE]")) { return $null }
    $h = @{}
    $lines = $b -split "\r?\n"
    foreach ($t in ($lines[0].Substring(13) -split "\s+")) { if ($t -match "^([a-z_]+)=(\S+)$") { $h[$matches[1]] = $matches[2] } }
    $body = @()
    $inHeader = $true
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($inHeader) { if ($lines[$i] -eq "") { $inHeader = $false; continue }; if ($lines[$i] -match "^([a-z_]+)=(.+)$") { $h[$matches[1]] = $matches[2].Trim() } }
        else { $body += $lines[$i] }
    }
    $h["_text"] = (($body -join " ") -replace "\s+", " ").Trim()
    return $h
}
function Get-All([int]$Issue) {
    $raw = & gh api "repos/$Repo/issues/$Issue/comments?per_page=100" --paginate 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    try { return @($raw | ConvertFrom-Json) } catch { return $null }
}

$seen = @{}
foreach ($n in $Issues) {
    $all = Get-All $n
    $seen[$n] = 0
    if ($null -ne $all) { foreach ($c in $all) { if ([long]$c.id -gt $seen[$n]) { $seen[$n] = [long]$c.id } } }
}
Write-Output ("{0} LANE FEED: watching issues {1} (read-only, from now)" -f (Get-Date -Format "HH:mm:ss"), ($Issues -join ","))
[Console]::Out.Flush()

while ($true) {
    foreach ($n in $Issues) {
        $all = Get-All $n
        if ($null -eq $all) { continue }
        foreach ($c in ($all | Sort-Object { [long]$_.id })) {
            if ([long]$c.id -le $seen[$n]) { continue }
            $seen[$n] = [long]$c.id
            $h = Parse-Header $c.body
            if ($null -eq $h) { continue }
            if ($h["type"] -eq "HEALTH") { continue }
            $ours = ($h["from"] -in @("IMPLEMENTER", "CLAUDE")) -or ($h["to"] -in @("IMPLEMENTER", "CLAUDE")) -or ($h["agent"] -eq "CLAUDE")
            if (-not $ours -and -not $AllLanes) { continue }
            $text = $h["_text"]; if ($text.Length -gt 170) { $text = $text.Substring(0, 170) + "..." }
            Write-Output ("{0} #{1} {2} {3}->{4} task={5} | {6}" -f (Get-Date -Format "HH:mm:ss"), $n, $h["type"], $h["from"], $h["to"], $h["task"], $text)
            [Console]::Out.Flush()
        }
    }
    Start-Sleep -Seconds $EverySeconds
}
