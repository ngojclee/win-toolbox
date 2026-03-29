#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Backward-compatible wrapper for label-only fix.

.DESCRIPTION
    Legacy entrypoint kept for compatibility.
    Internally calls fix-win11-taskbar-menu.ps1 with -LabelsOnly.

.PARAMETER NilesoftPath
    Path to Nilesoft Shell installation directory.

.PARAMETER RestartExplorer
    Restart explorer.exe after fix.

.PARAMETER Backup
    Create .bak files before patching .nss files.
#>

[CmdletBinding()]
param(
    [string]$NilesoftPath = "C:\Program Files\Nilesoft Shell",
    [switch]$RestartExplorer,
    [bool]$Backup = $true
)

$ErrorActionPreference = "Stop"

$mainScript = Join-Path $PSScriptRoot "fix-win11-taskbar-menu.ps1"
if (-not (Test-Path -LiteralPath $mainScript)) {
    Write-Error "Main script not found: $mainScript"
    exit 1
}

$invokeParams = @{
    NilesoftPath = $NilesoftPath
    LabelsOnly   = $true
    Backup       = $Backup
}

if ($RestartExplorer) {
    $invokeParams.RestartExplorer = $true
}

& $mainScript @invokeParams
