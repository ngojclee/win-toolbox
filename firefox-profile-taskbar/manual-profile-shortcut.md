# Manual recipe — rebuild one profile shortcut without the launcher stub

Use this when you already have a pinned shortcut set from `firefox-profile-taskbar.ps1`
and only need to recreate/replace **one** profile shortcut (e.g. after accidentally
deleting it), or when the shortcut must open a *fresh window of its own profile*
instead of a new tab in whichever profile was opened first.

Quick path: run [`recreate-profile-shortcut.ps1`](recreate-profile-shortcut.ps1)
(`-ProfileDir`, `-ShortcutName`, optional `-EmbedAumid`). This note documents what was
verified, including the traps.

## Verified facts (Windows 11 + Firefox, Sept 2026)

- `profiles.ini` **does not list every profile folder on disk**. The profile holding the
  Etsy shops (`3bgkx3tc.default-release-…`) existed on disk but was absent from
  `profiles.ini`, so any tool that reads only the ini misses it. Enumerate the
  `Profiles` directory itself when hunting for a profile.
- Identifying a profile by *content* beats guessing by friendly name: `places.sqlite`
  history URL counts (e.g. `SELECT url FROM moz_places WHERE url LIKE '%etsy.com%'`) and
  `logins.json` hostnames told us exactly which profile held the shops. (Copy the sqlite
  file to a temp dir before opening it if Firefox is running.)
- A console window flashes if the shortcut points at the generated
  `…\Launchers\Firefox<Name>Launcher.exe` stub. Pointing the shortcut **directly at
  `firefox.exe` inside a junction** removes the stub from the launch path.
- `-no-remote` alone is not enough when several shortcuts share the *same* `firefox.exe`
  path — Firefox may still route the launch to the first-started instance of that binary.
  The **junction gives each profile a distinct exe path**, and then each click really
  starts its own process/window.
- Windows 11 gives no programmatic path to pin a taskbar item (`IShellItemArray`,
  `InvokeVerb('Pin to taskbar')` and the related COM paths are removed/refused).
  Pinning stays a manual right-click on the LIVE icon.

## The AUMID trap (why hard-coded ids fail)

Windows groups taskbar icons by AppUserModelID. With
`taskbar.grouping.useprofile = true`, Firefox sets the **runtime AUMID to a decimal hash
of the profile path** (Mozilla `HashString`) — e.g. `3403319287`, *not* something like
`Mozilla.Firefox.Shop`. A hard-coded name in the `.lnk` therefore never matches the live
window and Windows shows a second icon. The only reliable method (same as the main
script): launch the profile briefly, read `SHGetPropertyStoreForWindow` from its visible
window, close it again, then embed that exact string into the `.lnk`
(`-EmbedAumid` does all of it).

Embedding goes through `ShellLink` COM → `IPersistFile::Load(STGM_READWRITE)` → cast to
`IPropertyStore` → `SetValue(PKEY_AppUserModel_ID)` → `Commit()` → `Save()`.
Note `SHGetPropertyStoreForParsingName` is **refused for `.lnk` files** — do not use it.
Correct key: `{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, 5`, `VT_LPWSTR`.

## Layout that gives each profile its own icon + its own window

1. Junction mapping the Firefox install dir to a per-profile folder name:
   ```powershell
   $j = "$env:LOCALAPPDATA\Mozilla\FirefoxTaskbar\Profile$GroupKey"
   cmd /c mklink /J "$j" "C:\Program Files\Mozilla Firefox"
   ```
2. Desktop shortcut with `-no-remote` and the explicit profile directory:
   ```powershell
   $ws = New-Object -ComObject WScript.Shell
   $l  = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Firefox Shop.lnk'))
   $l.TargetPath       = "$j\firefox.exe"
   $l.Arguments        = '-no-remote --profile "<APPDATA>\Mozilla\Firefox\Profiles\<profile dir>"'
   $l.WorkingDirectory = "$j"
   $l.IconLocation     = "C:\Program Files\Mozilla Firefox\firefox.exe,0"
   $l.Save()
   ```
   No `-new-window`: `-no-remote` + distinct exe path already guarantees a separate
   top-level window of that profile.
3. Make sure `taskbar.grouping.useprofile = true` is a **valid** pref line in that
   profile's `prefs.js` (watch for a mangled key like
   `user_pref("taskbar.grouping.useprofile = true", true);` — Firefox ignores it; fix to
   `user_pref("taskbar.grouping.useprofile", true);`), then
   **right-click the live icon → Pin to taskbar** (manual, Windows 11).

## Cleanup notes

- A stale pin pointing at a deleted target keeps its own grouping id — unpin it before
  pinning the rebuilt shortcut.
- Junction folder names are part of the taskbar group key; keep them stable.
- When a script must close Firefox after a probe, kill **only the PIDs it spawned** —
  `taskkill /IM firefox.exe` would take down the other profiles' windows too.
