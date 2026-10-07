$ErrorActionPreference = "Continue"

function Show-CommandStatus([string]$Name, [string[]]$VersionArgs) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "$Name: NOT INSTALLED"
        return
    }

    Write-Host "$Name: $($cmd.Source)"
    try {
        $out = & $Name @VersionArgs 2>&1 | Select-Object -First 2
        if ($out) { Write-Host "  $($out -join ' ')" }
    } catch {
        Write-Host "  version check failed: $($_.Exception.Message)"
    }
}

Show-CommandStatus "gh" @("--version")
Show-CommandStatus "codex" @("--version")
Show-CommandStatus "agy" @("--version")

Write-Host ""
Write-Host "This script only reports command availability. It does not install, authenticate, or launch an agent."
