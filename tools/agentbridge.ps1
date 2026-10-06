param(
    [string]$Project = "curse",
    [switch]$Once,
    [int]$PollSeconds = 0
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "agentbridge/projects/$Project.json"
if (-not (Test-Path $configPath)) { throw "AgentBridge config not found: $configPath" }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if ($PollSeconds -le 0) { $PollSeconds = [int]$config.poll_seconds }

$localDir = Join-Path $repoRoot ".agentbridge"
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
$inboxPath = Join-Path $repoRoot $config.local_inbox
$statePath = Join-Path $repoRoot $config.local_state

function Require-Gh {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) is required. Install it and run: gh auth login"
    }
    & gh auth status 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated. Run: gh auth login" }
}

function Read-State {
    if (Test-Path $statePath) {
        try { return Get-Content $statePath -Raw | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{ last_comment_id = 0 }
}

function Save-State([long]$LastCommentId) {
    @{ last_comment_id = $LastCommentId } |
        ConvertTo-Json |
        Set-Content -Path $statePath -Encoding utf8
}

function Parse-BridgeHeader([string]$Body) {
    if (-not $Body.StartsWith("[AGENTBRIDGE]")) { return $null }
    $header = @{}
    foreach ($line in ($Body -split "\r?\n")) {
        if ($line -eq "") { break }
        if ($line -match "^([a-z_]+)=(.+)$") { $header[$matches[1]] = $matches[2].Trim() }
    }
    if (-not $header.ContainsKey("project") -or $header["project"] -ne $config.project) { return $null }
    if (-not $header.ContainsKey("to")) { return $null }
    if ($config.accepted_recipients -notcontains $header["to"]) { return $null }
    return $header
}

function Sync-Inbox {
    $state = Read-State
    $endpoint = "repos/$($config.repository)/issues/$($config.issue_number)/comments?per_page=100"
    $comments = & gh api $endpoint | ConvertFrom-Json

    $accepted = @()
    $highestSeen = [long]$state.last_comment_id
    foreach ($c in $comments) {
        $cid = [long]$c.id
        if ($cid -gt $highestSeen) { $highestSeen = $cid }
        if ($cid -le [long]$state.last_comment_id) { continue }
        if ($config.allowed_authors -notcontains $c.user.login) { continue }
        $h = Parse-BridgeHeader $c.body
        if ($null -eq $h) { continue }
        $accepted += $c
    }

    if ($accepted.Count -gt 0) {
        $chunks = @()
        foreach ($c in $accepted) {
            $chunks += @"
## AgentBridge message $($c.id)
Author: $($c.user.login)
Created: $($c.created_at)
URL: $($c.html_url)

$($c.body)

---
"@
        }
        Add-Content -Path $inboxPath -Value ($chunks -join [Environment]::NewLine) -Encoding utf8
        Write-Host "AgentBridge: $($accepted.Count) new message(s) written to $($config.local_inbox)"
    }

    Save-State $highestSeen
}

Require-Gh
Write-Host "AgentBridge: project=$($config.project) repo=$($config.repository) issue=#$($config.issue_number)"
Write-Host "AgentBridge: comments are treated as data only; this watcher executes none of their contents."

do {
    try { Sync-Inbox } catch { Write-Warning "AgentBridge sync failed: $($_.Exception.Message)" }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
} while ($true)
