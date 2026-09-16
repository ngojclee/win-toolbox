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

## Recreating a single shortcut (no console flash)

> 📘 **Full end-to-end guide** — prerequisites, every step, scaling to any number of
> profiles and troubleshooting: [`CREATE-SHORTCUTS.md`](CREATE-SHORTCUTS.md).

If you deleted one shortcut and only need to rebuild **that one**, use
[`recreate-profile-shortcut.ps1`](recreate-profile-shortcut.ps1) — it wires the Desktop
shortcut straight to `firefox.exe` through a per-profile junction (no launcher stub, so
no terminal window flashes on open) and can embed the real runtime `AppUserModelID`:

```powershell
.\recreate-profile-shortcut.ps1 -ProfileDir "$env:APPDATA\Mozilla\Firefox\Profiles\<profile dir>" -ShortcutName "Firefox Shop"
# optional: also launch the profile once (~5-30s, closes itself afterwards) to embed the
# exact AUMID Firefox sets at runtime so the pinned icon matches the live window:
.\recreate-profile-shortcut.ps1 -ProfileDir "...\Profiles\<profile dir>" -ShortcutName "Firefox Shop" -EmbedAumid
```

Then: double-click it → right-click the live icon → **Pin to taskbar** (Windows 11 has no
programmatic pin; `IShellItemArray`/`InvokeVerb('Pin to taskbar')` are removed/refused).
Background and verified gotchas (incl. why a hard-coded AUMID like `Mozilla.Firefox.Shop`
does NOT match — Firefox hashes the profile path): [`manual-profile-shortcut.md`](manual-profile-shortcut.md).

## Taskbar pins that open the wrong profile (or steal focus)

Symptom: click pin **A** → profile A opens; click pin **B** → it just focuses A's window
instead of opening B's profile. Double-clicking the Desktop/Start shortcuts still works
in parallel — only the pinned buttons misbehave.

Cause: Windows decides "is this app already running?" by **AppUserModelID**. With
`taskbar.grouping.useprofile = true`, Firefox sets each window's AUMID to a **decimal
hash of the profile path** (e.g. `2842963073`) — not a name like `Mozilla.Firefox.Shop`.
A pin carrying no/stale AUMID therefore matches the *other* profile's window and gets
swallowed by it.

Fix: [`fix-taskbar-pin-aumid.ps1`](fix-taskbar-pin-aumid.ps1) — reads each pin's target +
`--profile` argument, grabs the real runtime AUMID from that profile's live window
(briefly launching it only if it is not already running, and closing only what it
spawned), then stamps it into **every copy** of the `.lnk` (Desktop **and**
`...\User Pinned\TaskBar\`) and verifies with a readback:

```powershell
./fix-taskbar-pin-aumid.ps1 -ShortcutName "Firefox Work"
./fix-taskbar-pin-aumid.ps1 -ShortcutName "Firefox Shop"
```

One name per call — some shells collapse `"A","B"` into a single argument.
If a pin still focuses the wrong window after stamping, unpin/re-pin it once (or restart
explorer) so the taskbar re-reads the pin metadata.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Pinned button opens the *other* profile / second pin does nothing | Run `fix-taskbar-pin-aumid.ps1 -ShortcutName "<pin name>"` — the pin must carry the profile's decimal-hash AUMID, and **both** copies (Desktop + TaskBar pin dir) must be stamped |
| Both profiles merge into one icon | Ensure `taskbar.grouping.useprofile` is `true` in **both** profiles' `about:config` |
| Second profile won't open / opens a tab in the first profile's window | Ensure `-no-remote` is in the shortcut Target and the exe path is unique per profile (junction dir) |
| Terminal/console window flashes before the browser opens | Shortcut points at the generated `Launchers\Firefox<Name>Launcher.exe` stub — rebuild it with `recreate-profile-shortcut.ps1` (targets `firefox.exe` directly) |
| Dev Edition profile uses wrong exe | Re-run script — it reads `installs.ini` for correct mapping |
| Profile not detected | Check `%APPDATA%\Mozilla\Firefox\profiles.ini` — but note **profiles can exist on disk without being in `profiles.ini`**; also enumerate `%APPDATA%\Mozilla\Firefox\Profiles\` and identify the right folder via its `places.sqlite` history / `logins.json` |
| Stale pin keeps stealing the click | Unpin the old taskbar entry first; a pin to a deleted target keeps its own group key |
| Script can't find Firefox | Install Firefox at default location |
