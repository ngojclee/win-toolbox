#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Fix Win11 taskbar menu text truncation (Nilesoft Shell + Windows metrics).

.DESCRIPTION
    On some Windows 11 setups, taskbar context menus may show missing labels
    (Nilesoft title.* variables not resolving) or clipped text (custom menu
    metrics too small).

    This script applies two safe fixes:
      1) Patch Nilesoft .nss files and replace title.* labels with explicit text.
      2) Reset Windows menu width/height metrics to sane defaults.

    Use -RestartExplorer to apply changes immediately.

.PARAMETER NilesoftPath
    Nilesoft Shell installation directory.
    Default: C:\Program Files\Nilesoft Shell

.PARAMETER SkipNilesoftPatch
    Skip patching Nilesoft .nss files.

.PARAMETER SkipWindowsMetricsReset
    Skip resetting HKCU WindowMetrics values.

.PARAMETER RestartExplorer
    Restart explorer.exe after applying fixes.

.PARAMETER Backup
    Create .bak backup files before editing .nss files.
    Default: $true

.EXAMPLE
    .\fix-win11-taskbar-menu.ps1 -RestartExplorer

.EXAMPLE
    .\fix-win11-taskbar-menu.ps1 -SkipWindowsMetricsReset

.EXAMPLE
    .\fix-win11-taskbar-menu.ps1 -NilesoftPath "D:\Nilesoft Shell" -Backup $false
#>

[CmdletBinding()]
param(
    [string]$NilesoftPath = "C:\Program Files\Nilesoft Shell",
    [switch]$SkipNilesoftPatch,
    [switch]$SkipWindowsMetricsReset,
    [switch]$RestartExplorer,
    [bool]$Backup = $true
)

$ErrorActionPreference = "Stop"

function Write-OK {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!!] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [X]  $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [..] $Message" -ForegroundColor Gray
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Backup {
    param([string]$FilePath)

    if (-not $Backup) {
        return
    }

    $backupPath = "$FilePath.bak"
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force
        Write-Info "Backup created: $(Split-Path -Leaf $backupPath)"
    }
}

function Patch-NilesoftTitles {
    param([string]$RootPath)

    $titleReplacements = [ordered]@{
        # Taskbar menu
        "title.terminal"                  = "Terminal"
        "title.go_to"                     = "Go To"
        "title.windows"                   = "Windows"
        "title.cascade_windows"           = "Cascade windows"
        "title.show_windows_stacked"      = "Show windows stacked"
        "title.show_windows_side_by_side" = "Show windows side by side"
        "title.minimize_all_windows"      = "Minimize all windows"
        "title.restore_all_windows"       = "Restore all windows"
        "title.desktop"                   = "Desktop"
        "title.settings"                  = "Settings"
        "title.task_manager"              = "Task Manager"
        "title.taskbar_settings"          = "Taskbar settings"
        "title.exit_explorer"             = "Restart Explorer"

        # Terminal submenu
        "title.command_prompt"            = "Command Prompt"
        "title.windows_powershell"        = "Windows PowerShell"
        "title.windows_terminal"          = "Windows Terminal"

        # Go To submenu
        "title.control_panel"             = "Control Panel"
        "title.run"                       = "Run"

        # File management
        "title.copy_path"                 = "Copy Path"
        "title.select"                    = "Select"
        "title.folder_options"            = "Folder Options"
    }

    $nssFiles = Get-ChildItem -LiteralPath $RootPath -Filter "*.nss" -File -Recurse

    $filesChanged = 0
    $totalReplacements = 0

    foreach ($file in $nssFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        $updated = $content
        $fileReplacements = 0

        foreach ($entry in $titleReplacements.GetEnumerator()) {
            $regexPattern = "\btitle\s*=\s*$([regex]::Escape($entry.Key))\b"
            $regex = [regex]::new($regexPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)

            $matchCount = $regex.Matches($updated).Count
            if ($matchCount -gt 0) {
                $replacement = "title=\"$($entry.Value)\""
                $updated = $regex.Replace($updated, $replacement)
                $fileReplacements += $matchCount
            }
        }

        if ($fileReplacements -gt 0) {
            Ensure-Backup -FilePath $file.FullName
            Set-Content -LiteralPath $file.FullName -Value $updated -NoNewline
            Write-OK "$($file.Name): fixed $fileReplacements label(s)"
            $filesChanged++
            $totalReplacements += $fileReplacements
        } else {
            Write-Info "$($file.Name): no changes needed"
        }
    }

    return [pscustomobject]@{
        FilesChanged       = $filesChanged
        TotalReplacements  = $totalReplacements
        ScannedFileCount   = $nssFiles.Count
    }
}

function Reset-WindowsMenuMetrics {
    $metricsPath = "HKCU:\Control Panel\Desktop\WindowMetrics"
    if (-not (Test-Path -LiteralPath $metricsPath)) {
        New-Item -Path $metricsPath -Force | Out-Null
    }

    $defaults = [ordered]@{
        MenuWidth  = "-285"
        MenuHeight = "-285"
    }

    $changedCount = 0

    foreach ($entry in $defaults.GetEnumerator()) {
        $name = $entry.Key
        $defaultValue = $entry.Value

        $currentValue = $null
        try {
            $currentValue = (Get-ItemProperty -LiteralPath $metricsPath -Name $name -ErrorAction Stop).$name
        }
        catch {
            $currentValue = $null
        }

        if ([string]$currentValue -ne [string]$defaultValue) {
            New-ItemProperty -LiteralPath $metricsPath -Name $name -Value $defaultValue -PropertyType String -Force | Out-Null
            Write-OK ("{0}: {1} -> {2}" -f $name, $currentValue, $defaultValue)
            $changedCount++
        } else {
            Write-Info "$name already set to $defaultValue"
        }
    }

    $textScaleFactor = $null
    try {
        $textScaleFactor = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Accessibility" -Name "TextScaleFactor" -ErrorAction Stop).TextScaleFactor
    }
    catch {
        $textScaleFactor = $null
    }

    if ($null -ne $textScaleFactor -and [int]$textScaleFactor -ne 100) {
        Write-Warn "TextScaleFactor is $textScaleFactor%. If labels still look clipped, set text size back to 100% in Settings > Accessibility > Text size."
    }

    return $changedCount
}

Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  Win11 Taskbar Menu Text Fix (Nilesoft + Windows Metrics)" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""

$nilesoftResult = $null

if (-not $SkipNilesoftPatch) {
    Write-Host "  [1/3] Patching Nilesoft labels..." -ForegroundColor White

    if (-not (Test-Path -LiteralPath $NilesoftPath)) {
        Write-Warn "Nilesoft path not found: $NilesoftPath"
        Write-Warn "Skipping Nilesoft patch. Use -NilesoftPath if needed."
    } else {
        $resolvedPath = [IO.Path]::GetFullPath($NilesoftPath)

        $programFilesRaw = $env:ProgramFiles
        if ([string]::IsNullOrWhiteSpace($programFilesRaw)) {
            $programFilesRaw = "C:\Program Files"
        }
        $programFilesPath = [IO.Path]::GetFullPath($programFilesRaw)

        $programFilesX86Path = $null
        $programFilesX86Raw = ${env:ProgramFiles(x86)}
        if ([string]::IsNullOrWhiteSpace($programFilesX86Raw)) {
            $programFilesX86Raw = "C:\Program Files (x86)"
        }

        if ($programFilesPath -ne [IO.Path]::GetFullPath($programFilesX86Raw)) {
            $programFilesX86Path = [IO.Path]::GetFullPath($programFilesX86Raw)
        }

        $pathLooksProtected = $resolvedPath.StartsWith($programFilesPath, [StringComparison]::OrdinalIgnoreCase)
        if (-not $pathLooksProtected -and $programFilesX86Path) {
            $pathLooksProtected = $resolvedPath.StartsWith($programFilesX86Path, [StringComparison]::OrdinalIgnoreCase)
        }

        if ($pathLooksProtected -and -not (Test-IsAdministrator)) {
            Write-Err "Administrator privileges are required to patch files under Program Files."
            Write-Host "  Re-run PowerShell as Administrator, then run this script again." -ForegroundColor Gray
            exit 1
        }

        Write-Info "Scanning: $NilesoftPath"
        $nilesoftResult = Patch-NilesoftTitles -RootPath $NilesoftPath
    }
} else {
    Write-Info "SkipNilesoftPatch enabled"
}

Write-Host ""
$windowsMetricsChanged = 0
if (-not $SkipWindowsMetricsReset) {
    Write-Host "  [2/3] Resetting Windows menu metrics..." -ForegroundColor White
    $windowsMetricsChanged = Reset-WindowsMenuMetrics
} else {
    Write-Info "SkipWindowsMetricsReset enabled"
}

Write-Host ""
Write-Host "  [3/3] Summary" -ForegroundColor White
if ($null -ne $nilesoftResult) {
    Write-OK ("Nilesoft files scanned: {0}, changed: {1}, replacements: {2}" -f $nilesoftResult.ScannedFileCount, $nilesoftResult.FilesChanged, $nilesoftResult.TotalReplacements)
} else {
    Write-Info "Nilesoft patch not applied"
}

if ($SkipWindowsMetricsReset) {
    Write-Info "Windows metrics reset skipped"
} else {
    if ($windowsMetricsChanged -gt 0) {
        Write-OK "Windows menu metrics updated: $windowsMetricsChanged value(s)"
    } else {
        Write-Info "Windows menu metrics already in default state"
    }
}

if ($RestartExplorer) {
    Write-Host ""
    Write-Host "  Restarting Explorer..." -ForegroundColor Yellow
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Write-OK "Explorer restarted"
} else {
    Write-Host ""
    Write-Host "  To apply changes now:" -ForegroundColor Yellow
    Write-Host "    Stop-Process -Name explorer -Force; Start-Process explorer.exe" -ForegroundColor Gray
    Write-Host "  If menu width still looks wrong, sign out and sign in once." -ForegroundColor Gray
}

Write-Host ""
