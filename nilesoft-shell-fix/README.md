# Nilesoft Shell / Win11 Taskbar Menu Text Fix

One main script is enough: `fix-win11-taskbar-menu.ps1`.

It fixes:
1. Missing labels from Nilesoft (`title.*`)
2. Clipped/too-narrow taskbar menu text from Windows metrics (`MenuWidth`, `MenuHeight`)

## Fastest Run (Other Machines)

Run full fix (recommended):

```powershell
irm "https://raw.githubusercontent.com/ngojclee/win-toolbox/main/nilesoft-shell-fix/fix-win11-taskbar-menu.ps1" -OutFile "$env:TEMP\fix-win11-taskbar-menu.ps1"; Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$env:TEMP\fix-win11-taskbar-menu.ps1`" -RestartExplorer"
```

Run labels-only (if you only need old behavior):

```powershell
irm "https://raw.githubusercontent.com/ngojclee/win-toolbox/main/nilesoft-shell-fix/fix-win11-taskbar-menu.ps1" -OutFile "$env:TEMP\fix-win11-taskbar-menu.ps1"; Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$env:TEMP\fix-win11-taskbar-menu.ps1`" -LabelsOnly -RestartExplorer"
```

## Local Usage

```powershell
cd nilesoft-shell-fix

# Full fix (recommended)
.\fix-win11-taskbar-menu.ps1 -RestartExplorer

# Labels-only mode
.\fix-win11-taskbar-menu.ps1 -LabelsOnly -RestartExplorer

# Advanced: skip one side explicitly
.\fix-win11-taskbar-menu.ps1 -SkipNilesoftPatch
.\fix-win11-taskbar-menu.ps1 -SkipWindowsMetricsReset
```

## Compatibility

`fix-nilesoft-labels.ps1` is kept as a compatibility wrapper and now forwards to:
`fix-win11-taskbar-menu.ps1 -LabelsOnly`

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
