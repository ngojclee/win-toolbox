<#
.SYNOPSIS
    Fix Nilesoft Shell context menu labels on Windows 11.

.DESCRIPTION
    Nilesoft Shell uses built-in title variables (e.g. title.task_manager,
    title.settings) that sometimes fail to resolve on Windows 11, causing
    context menu items to appear as blank icons without text labels.

    This script patches the .nss configuration files to replace those
    unresolved title variables with hardcoded English strings, ensuring
    all menu items display properly.

    Requires Administrator privileges (Nilesoft Shell is in Program Files).

.PARAMETER NilesoftPath
    Path to the Nilesoft Shell installation directory.
    Default: "C:\Program Files\Nilesoft Shell"

.PARAMETER RestartExplorer
    If specified, automatically restarts explorer.exe after patching.

.PARAMETER Backup
    If specified, creates a backup of original files before patching.
    Default: $true

.EXAMPLE
    .\fix-nilesoft-labels.ps1
    .\fix-nilesoft-labels.ps1 -RestartExplorer
    .\fix-nilesoft-labels.ps1 -NilesoftPath "D:\Nilesoft Shell"

.NOTES
    Author: ngojclee/win-toolbox
    Requires: Nilesoft Shell installed
    Platform: Windows 11
#>

param(
    [string]$NilesoftPath = "C:\Program Files\Nilesoft Shell",
    [switch]$RestartExplorer,
    [bool]$Backup = $true
)

# --- Helpers -----------------------------------------------------------------

function Write-OK   { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "  [!!] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "  [X]  $msg" -ForegroundColor Red }

# --- Validate Installation ---------------------------------------------------

Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  Nilesoft Shell - Fix Missing Labels" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $NilesoftPath)) {
    Write-Err "Nilesoft Shell not found at: $NilesoftPath"
    Write-Host "  Use -NilesoftPath to specify the correct location." -ForegroundColor Gray
    exit 1
}

$importsDir = Join-Path $NilesoftPath "imports"
if (-not (Test-Path $importsDir)) {
    Write-Err "Imports directory not found: $importsDir"
    exit 1
}

Write-OK "Found Nilesoft Shell at: $NilesoftPath"

# --- Define Replacements -----------------------------------------------------

# Map of title.* variables -> hardcoded English strings
# These are the built-in Nilesoft string references that fail to resolve on Win11
$titleReplacements = @{
    # Taskbar context menu
    'title.windows'                    = '"Windows"'
    'title.cascade_windows'            = '"Cascade windows"'
    'title.Show_windows_stacked'       = '"Show windows stacked"'
    'title.Show_windows_side_by_side'  = '"Show windows side by side"'
    'title.minimize_all_windows'       = '"Minimize all windows"'
    'title.restore_all_windows'        = '"Restore all windows"'
    'title.task_manager'               = '"Task Manager"'
    'title.taskbar_Settings'           = '"Taskbar Settings"'
    'title.settings'                   = '"Settings"'
    'title.desktop'                    = '"Desktop"'
    'title.exit_explorer'              = '"Restart Explorer"'

    # Terminal submenu
    'title.terminal'                   = '"Terminal"'
    'title.command_prompt'             = '"Command Prompt"'
    'title.windows_powershell'         = '"Windows PowerShell"'
    'title.Windows_Terminal'           = '"Windows Terminal"'

    # Go To submenu
    'title.go_to'                      = '"Go To"'
    'title.control_panel'              = '"Control Panel"'
    'title.run'                        = '"Run"'

    # File management
    'title.copy_path'                  = '"Copy Path"'
    'title.select'                     = '"Select"'
    'title.folder_options'             = '"Folder Options"'
}

# --- Patch Files -------------------------------------------------------------

Write-Host ""
Write-Host "  Scanning .nss files..." -ForegroundColor White

$nssFiles = Get-ChildItem -Path $importsDir -Filter "*.nss" -File
$totalFixed = 0

foreach ($file in $nssFiles) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    $fileFixed = 0

    foreach ($key in $titleReplacements.Keys) {
        $value = $titleReplacements[$key]

        # Match title=title.xxx (but not already title="xxx")
        # Use word boundary to avoid partial matches
        $pattern = "title=$([regex]::Escape($key))\b"

        if ($content -match $pattern) {
            $content = $content -replace $pattern, "title=$value"
            $fileFixed++
        }
    }

    if ($fileFixed -gt 0) {
        # Create backup if requested
        if ($Backup) {
            $backupPath = "$($file.FullName).bak"
            if (-not (Test-Path $backupPath)) {
                $originalContent | Set-Content $backupPath -NoNewline
                Write-Host "    Backup: $($file.Name).bak" -ForegroundColor DarkGray
            }
        }

        # Write patched content
        $content | Set-Content $file.FullName -NoNewline
        Write-OK "$($file.Name): Fixed $fileFixed label(s)"
        $totalFixed += $fileFixed
    } else {
        Write-Host "    $($file.Name): No changes needed" -ForegroundColor DarkGray
    }
}

# Also check the main shell.nss
$mainNss = Join-Path $NilesoftPath "shell.nss"
if (Test-Path $mainNss) {
    $content = Get-Content $mainNss -Raw
    $originalContent = $content
    $fileFixed = 0

    foreach ($key in $titleReplacements.Keys) {
        $value = $titleReplacements[$key]
        $pattern = "title=$([regex]::Escape($key))\b"
        if ($content -match $pattern) {
            $content = $content -replace $pattern, "title=$value"
            $fileFixed++
        }
    }

    if ($fileFixed -gt 0) {
        if ($Backup) {
            $backupPath = "$mainNss.bak"
            if (-not (Test-Path $backupPath)) {
                $originalContent | Set-Content $backupPath -NoNewline
            }
        }
        $content | Set-Content $mainNss -NoNewline
        Write-OK "shell.nss: Fixed $fileFixed label(s)"
        $totalFixed += $fileFixed
    }
}

# --- Summary -----------------------------------------------------------------

Write-Host ""
if ($totalFixed -gt 0) {
    Write-Host "  Fixed $totalFixed label(s) total." -ForegroundColor Green
} else {
    Write-Host "  All labels are already correct!" -ForegroundColor Green
}

# --- Restart Explorer --------------------------------------------------------

if ($RestartExplorer) {
    Write-Host ""
    Write-Host "  Restarting Explorer to apply changes..." -ForegroundColor Yellow
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 2
    Start-Process explorer
    Write-OK "Explorer restarted"
} else {
    Write-Host ""
    Write-Host "  To apply changes, restart Explorer:" -ForegroundColor Yellow
    Write-Host "    - Right-click taskbar > Shift + 'Restart Explorer'" -ForegroundColor Gray
    Write-Host "    - Or run: Stop-Process -Name explorer -Force; Start-Process explorer" -ForegroundColor Gray
}

Write-Host ""
