# Nilesoft Shell / Win11 Taskbar Menu Text Fix

Fixes a common Windows 11 issue where taskbar context menu labels are missing or clipped after installing [Nilesoft Shell](https://nilesoft.org/) (or after custom Windows menu metrics were changed).

## Recommended Script

Use `fix-win11-taskbar-menu.ps1` for the full fix:

1. Patches `title.*` labels in Nilesoft `.nss` files to explicit text
2. Resets Windows menu width/height metrics (`MenuWidth`, `MenuHeight`) to defaults
3. Optionally restarts Explorer

## Quick Run (Other Machines)

```powershell
irm "https://raw.githubusercontent.com/ngojclee/win-toolbox/main/nilesoft-shell-fix/fix-win11-taskbar-menu.ps1" -OutFile "$env:TEMP\fix-win11-taskbar-menu.ps1"; Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$env:TEMP\fix-win11-taskbar-menu.ps1`" -RestartExplorer"
```

## Local Usage

Run as Administrator:

```powershell
cd nilesoft-shell-fix

# Full fix + restart Explorer
.\fix-win11-taskbar-menu.ps1 -RestartExplorer

# Only patch Nilesoft labels (skip registry menu metrics reset)
.\fix-win11-taskbar-menu.ps1 -SkipWindowsMetricsReset

# Custom Nilesoft path
.\fix-win11-taskbar-menu.ps1 -NilesoftPath "D:\Nilesoft Shell"

# No backup files
.\fix-win11-taskbar-menu.ps1 -Backup $false
```

## Legacy Script

`fix-nilesoft-labels.ps1` is still available if you only need label replacement and do not want the Windows metrics reset step.

## Requirements

- Windows 11
- [Nilesoft Shell](https://nilesoft.org/) installed (for label patching)
- Administrator privileges (if Nilesoft is in Program Files)

## Restore Original Nilesoft Files

If backups were created, each edited file has a `.bak` next to it:

```powershell
cd "C:\Program Files\Nilesoft Shell"
Get-ChildItem -Recurse -Filter "*.nss.bak" | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination ($_.FullName -replace '\.bak$','') -Force
}
```
