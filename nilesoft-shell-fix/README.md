# Nilesoft Shell - Fix Missing Labels

Fixes a common issue on **Windows 11** where [Nilesoft Shell](https://nilesoft.org/) context menu items appear as blank icons without text labels.

## Problem

Nilesoft Shell uses built-in string variables (e.g. `title.task_manager`, `title.settings`, `title.desktop`) for menu labels. On some Windows 11 setups, these variables fail to resolve, causing menu items to show only icons with no visible text.

**Before fix:**

| Icon | Label |
|------|-------|
| ✅ | Terminal |
| ✅ | Go To |
| ✅ | Apps |
| ⚠️ | *(blank)* |
| ⚠️ | *(blank)* |
| ✅ | Settings |
| ✅ | Desktop |

**After fix:** All items display their labels correctly (Windows, Task Manager, Taskbar Settings, etc.)

## Usage

Run as **Administrator** (Nilesoft Shell installs to Program Files):

```powershell
# Fix labels and manually restart Explorer
.\fix-nilesoft-labels.ps1

# Fix labels and auto-restart Explorer
.\fix-nilesoft-labels.ps1 -RestartExplorer

# Custom install path
.\fix-nilesoft-labels.ps1 -NilesoftPath "D:\Nilesoft Shell"

# Without backup
.\fix-nilesoft-labels.ps1 -Backup $false
```

## What it does

1. Scans all `.nss` config files in the Nilesoft Shell `imports/` directory
2. Replaces unresolved `title.*` variables with hardcoded English strings
3. Creates `.bak` backup files of originals (by default)
4. Optionally restarts Explorer to apply changes

### Labels fixed

| Variable | Replacement |
|---|---|
| `title.windows` | "Windows" |
| `title.task_manager` | "Task Manager" |
| `title.taskbar_Settings` | "Taskbar Settings" |
| `title.settings` | "Settings" |
| `title.desktop` | "Desktop" |
| `title.terminal` | "Terminal" |
| `title.command_prompt` | "Command Prompt" |
| `title.windows_powershell` | "Windows PowerShell" |
| `title.Windows_Terminal` | "Windows Terminal" |
| `title.go_to` | "Go To" |
| `title.control_panel` | "Control Panel" |
| `title.run` | "Run" |
| `title.copy_path` | "Copy Path" |
| `title.select` | "Select" |
| `title.folder_options` | "Folder Options" |
| ...and more | |

## Requirements

- Windows 11
- [Nilesoft Shell](https://nilesoft.org/) installed
- Administrator privileges (to modify files in Program Files)

## Restoring originals

Backup files are saved as `.bak` alongside the originals. To restore:

```powershell
cd "C:\Program Files\Nilesoft Shell\imports"
Get-ChildItem *.bak | ForEach-Object {
    Copy-Item $_.FullName ($_.FullName -replace '\.bak$','') -Force
}
```
