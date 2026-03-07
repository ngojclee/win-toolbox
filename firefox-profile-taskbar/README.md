# Firefox Multi-Profile Taskbar Setup

Makes each Firefox profile show as a **separate icon** on the Windows taskbar — just like Chrome does per-profile.

## Supported Firefox Editions

| Edition | Install Path | Auto-detected |
|---------|-------------|:---:|
| Firefox | `Mozilla Firefox\` | ✅ |
| Firefox Developer Edition | `Firefox Developer Edition\` | ✅ |
| Firefox Nightly | `Firefox Nightly\` | ✅ |
| Firefox ESR | `Mozilla Firefox ESR\` | ✅ |

All editions share the same `profiles.ini`. The script auto-detects which profile belongs to which edition.

## The Problem

By default, all Firefox windows share **one taskbar icon** regardless of which profile or Firefox edition you're using. You can't pin two profiles separately.

## The Solution

This script uses Firefox's hidden `taskbar.grouping.useprofile` setting to give each profile its own unique Windows AppUserModelID, then creates separate desktop shortcuts you can pin.

## Requirements

- Windows 10 / 11
- Firefox installed (any edition, auto-detected)
- PowerShell 5.1+

## Usage

### Interactive Mode (recommended)

```powershell
powershell -ExecutionPolicy Bypass -File firefox-profile-taskbar.ps1
```

The script will:
1. Auto-detect all Firefox editions installed
2. Auto-detect all profiles and map them to their Firefox edition
3. Let you select which ones to set up
4. Ask for friendly names (e.g. "Personal", "Work", "Developer")
5. Enable the taskbar separation setting
6. Create desktop shortcuts with the correct Firefox exe per profile

### Fresh Firefox Install

```powershell
# Create new profiles first, then set up taskbar
powershell -ExecutionPolicy Bypass -File firefox-profile-taskbar.ps1 -Create
```

### List Profiles Only

```powershell
powershell -ExecutionPolicy Bypass -File firefox-profile-taskbar.ps1 -List
```

Example output:
```
  Found 3 profile(s):

    [1] default-release ★ [Firefox]
        JpIYBuOI.Profile 1
    [2] default [Firefox]
        8ek1pjuz.default
    [3] dev-edition-default [Firefox Developer]
        4yx7w8jc.dev-edition-default
```

### Non-Interactive (scripted)

```powershell
powershell -ExecutionPolicy Bypass -File firefox-profile-taskbar.ps1 -Profiles "default-release,dev-edition-default"
```

## After the Script Runs

The script creates desktop shortcuts but **cannot** pin to taskbar automatically (Windows blocks this). You need to:

1. **Unpin** all existing Firefox icons from taskbar
2. **Double-click** each new desktop shortcut (e.g. `Firefox - Personal`, `Firefox Dev - Developer`)
3. **Right-click** its taskbar icon → **Pin to taskbar**
4. Repeat for each profile

Each profile now has its own taskbar icon with the correct Firefox edition!

## How It Works

1. **`taskbar.grouping.useprofile = true`** — Hidden Firefox pref for unique [AppUserModelID](https://docs.microsoft.com/en-us/windows/win32/shell/appids) per profile
2. **Install hash mapping** — Parses `installs.ini` + `profiles.ini` to determine which Firefox exe each profile belongs to
3. **`-no-remote`** flag — Allows multiple Firefox instances simultaneously
4. **`--profile "path"`** — Forces Firefox to open a specific profile directory

## Re-Running

You can re-run the script anytime:
- Added a new profile? Run again, select the new ones
- Installed Developer Edition? Run again, it auto-detects the new exe
- Existing shortcuts are not affected

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Both profiles merge into one icon | Ensure `taskbar.grouping.useprofile` is `true` in **both** profiles' `about:config` |
| Second profile won't open | Ensure `-no-remote` is in the shortcut Target |
| Dev Edition profile uses wrong exe | Re-run script — it reads `installs.ini` for correct mapping |
| Profile not detected | Check `%APPDATA%\Mozilla\Firefox\profiles.ini` |
| Script can't find Firefox | Install Firefox at default location |
