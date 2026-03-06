# Firefox Multi-Profile Taskbar Setup

Makes each Firefox profile show as a **separate icon** on the Windows taskbar — just like Chrome does per-profile.

## The Problem

By default, all Firefox windows share **one taskbar icon** regardless of which profile you're using. You can't pin two profiles separately.

## The Solution

This script uses Firefox's hidden `taskbar.grouping.useprofile` setting to give each profile its own unique Windows AppUserModelID, then creates separate desktop shortcuts you can pin.

## Requirements

- Windows 10 / 11
- Firefox installed (auto-detected)
- PowerShell 5.1+

## Usage

### Interactive Mode (recommended)

```powershell
powershell -ExecutionPolicy Bypass -File firefox-profile-taskbar.ps1
```

The script will:
1. Auto-detect all Firefox profiles from `profiles.ini`
2. Let you select which ones to set up
3. Ask for friendly names (e.g. "Personal", "Work")
4. Enable the taskbar separation setting
5. Create desktop shortcuts

### Fresh Firefox Install

```powershell
# Create new profiles first, then set up taskbar
powershell -ExecutionPolicy Bypass -File firefox-profile-taskbar.ps1 -Create
```

### List Profiles Only

```powershell
powershell -ExecutionPolicy Bypass -File firefox-profile-taskbar.ps1 -List
```

### Non-Interactive (scripted)

```powershell
powershell -ExecutionPolicy Bypass -File firefox-profile-taskbar.ps1 -Profiles "Personal,Work"
```

## After the Script Runs

The script creates desktop shortcuts but **cannot** pin to taskbar automatically (Windows blocks this for security). You need to:

1. **Unpin** all existing Firefox icons from taskbar
2. **Double-click** each new desktop shortcut (e.g. `Firefox - Personal`)
3. **Right-click** its taskbar icon → **Pin to taskbar**
4. Repeat for each profile

That's it — each profile now has its own taskbar icon!

## How It Works

1. **`taskbar.grouping.useprofile = true`** — Hidden Firefox pref that makes each profile generate a unique [AppUserModelID](https://docs.microsoft.com/en-us/windows/win32/shell/appids)
2. **`-no-remote`** flag — Allows multiple Firefox instances to run simultaneously
3. **`--profile "path"`** — Forces Firefox to open a specific profile directory

## Re-Running

You can re-run the script anytime:
- Added a new profile? Run again, select the new ones
- Existing shortcuts are not affected

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Both profiles merge into one taskbar icon | Make sure `taskbar.grouping.useprofile` is `true` in **both** profiles' `about:config` |
| Second profile won't open | Ensure `-no-remote` is in the shortcut Target |
| Profile not detected | Check `%APPDATA%\Mozilla\Firefox\profiles.ini` |
| Script can't find Firefox | Install Firefox at default location or update `$FirefoxExe` in script |
