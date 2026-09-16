# Creating per-profile Firefox shortcuts — the full recipe

Everything below was verified on Windows 11 + Firefox 156 with two live profiles
(Work = `JpIYBuOI.Profile 1`, Shop = `3bgkx3tc.default-release-…`). Follow it top to
bottom and any number of profiles get their own Desktop shortcut **and** their own
taskbar button that opens *its own* window — never a new tab in another profile's window.

---

## 0. What the end result looks like

| Piece | Example (real values from the reference machine) |
|---|---|
| Junction dir | `%LOCALAPPDATA%\Mozilla\FirefoxTaskbar\Profile1` → `C:\Program Files\Mozilla Firefox` |
| Shortcut target | `…\FirefoxTaskbar\Profile1\firefox.exe` (through the junction) |
| Shortcut arguments | `-no-remote --profile "C:\Users\<user>\AppData\Roaming\Mozilla\Firefox\Profiles\JpIYBuOI.Profile 1"` |
| Working directory | `…\FirefoxTaskbar\Profile1` |
| Icon | `C:\Program Files\Mozilla Firefox\firefox.exe,0` |
| AppUserModelID | `2842963073` (= decimal hash of that profile path — see step 4) |
| Shortcut files | `Desktop\<Name>.lnk` **and** `…\Quick Launch\User Pinned\TaskBar\<Name>.lnk` after pinning |

---

## 1. Conditions — all four must hold, or the shortcut will misbehave

1. **Firefox is installed** (default: `C:\Program Files\Mozilla Firefox`).
2. **The profile directory exists** — and note it does **not** have to appear in
   `profiles.ini`. Profiles created by other tools/scripts can live on disk without an
   ini entry (the Shop profile here was exactly that case: absent from `profiles.ini`,
   still fully working).
   Find one by *content*, not by name — copy its `places.sqlite` to temp and query, e.g.
   ```sql
   SELECT url FROM moz_places WHERE url LIKE '%etsy.com%' LIMIT 20;
   ```
   plus hostnames in `logins.json`. That identified the real profile immediately.
3. **`taskbar.grouping.useprofile = true` inside that profile.** Without it Firefox
   gives its window a generic AUMID, Windows groups every profile under one button, and
   per-profile pinning cannot work. Set it in `about:config` or write it into `prefs.js`
   **while Firefox for that profile is closed** (prefs.js is rewritten on exit):
   ```text
   user_pref("taskbar.grouping.useprofile", true);
   ```
   Watch for a mangled key such as `user_pref("taskbar.grouping.useprofile = true", true);`
   — Firefox ignores it; fix it to the exact form above.
4. **One junction dir per profile** (step 2). Two shortcuts pointing at the *same*
   `firefox.exe` path will be treated as one installation and the second launch is handed
   to the first instance — the classic "second profile opens a tab in the first window"
   bug. A distinct exe path + `-no-remote` fixes it.

> ⚠️ **Never remove a junction with `Remove-Item -Recurse`.** PowerShell deletes
> *through* the link and guts the real installation. Use `cmd /c rmdir "<junction>"`.

---

## 2. Create the junction (once per profile)

Pick a short, stable key (it becomes part of the exe path and thus part of the window's
identity):

```powershell
$key  = 'Profile1'                                   # must be unique per profile
$junc = Join-Path $env:LOCALAPPDATA "Mozilla\FirefoxTaskbar\$key"
cmd /c mklink /J "$junc" "C:\Program Files\Mozilla Firefox"
Test-Path (Join-Path $junc 'firefox.exe')            # must print True
```

Keep the dir name stable afterwards — it is part of the taskbar group key.

---

## 3. Create the Desktop shortcut

```powershell
$name = 'Firefox Shop'                                                    # what you see
$prof = "$env:APPDATA\Mozilla\Firefox\Profiles\3bgkx3tc.default-release-1767776684974"
$junc = "$env:LOCALAPPDATA\Mozilla\FirefoxTaskbar\ProfilePersonal"

$sh = New-Object -ComObject WScript.Shell
$l  = $sh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) "$name.lnk"))
$l.TargetPath       = Join-Path $junc 'firefox.exe'
$l.Arguments        = "-no-remote --profile `"$prof`""
$l.WorkingDirectory = $junc
$l.IconLocation     = 'C:\Program Files\Mozilla Firefox\firefox.exe,0'
$l.Save()
```

There is deliberately **no `-new-window`** and no launcher stub: `-no-remote` plus the
per-profile junction path already guarantees a separate top-level window, and pointing
straight at `firefox.exe` avoids the console window that the `…\Launchers\*Launcher.exe`
stubs cause.
Ready-made: [`recreate-profile-shortcut.ps1`](recreate-profile-shortcut.ps1) does steps
2–4 in one go.

---

## 4. Stamp the profile's real AppUserModelID (AUMID)

Windows answers "is this app already running?" by AUMID. With
`taskbar.grouping.useprofile = true`, Firefox sets its window's AUMID to a **decimal hash
of the profile path** — real values here: Work `2842963073`, Shop `1831375031`. A
hard-coded name such as `Mozilla.Firefox.Shop` will **never** match, and a pin whose
AUMID doesn't match gets swallowed by whichever profile *does* match.

Detect it from a live window and write it into the `.lnk`:

```powershell
./recreate-profile-shortcut.ps1 -ProfileDir "<profile dir>" -ShortcutName "<name>" -EmbedAumid
# or, for an existing shortcut/pin that misbehaves:
./fix-taskbar-pin-aumid.ps1 -ShortcutName "<name>"
```

Both scripts read the value from the running window (`SHGetPropertyStoreForWindow`, key
`PKEY_AppUserModelID` = `{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3},5`), close only the
Firefox PIDs they started, and verify with a readback.

**Both copies must be stamped** when the shortcut is pinned:
`Desktop\<name>.lnk` and
`%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\<name>.lnk`.

---

## 5. Pin it (manual, one time)

Windows 11 refuses every programmatic pin (`IShellItemArray.TryPin`,
`InvokeVerb('Pin to taskbar')`, property-store writes): double-click the Desktop
shortcut, then right-click its **live** icon → *Pin to taskbar*.
If an old pin sticks around, unpin it first — a pin to a stale target keeps its own
grouping key. After re-stamping AUMIDs, if a pin still misbehaves: unpin/re-pin once or
restart explorer so the taskbar re-reads the metadata.

---

## 6. Scaling to N profiles

### Batch script

```powershell
# one mapping per line: "<Shortcut name>=<profile dir>"
@'
Firefox Work=C:\Users\<user>\AppData\Roaming\Mozilla\Firefox\Profiles\JpIYBuOI.Profile 1
Firefox Shop=C:\Users\<user>\AppData\Roaming\Mozilla\Firefox\Profiles\3bgkx3tc.default-release-1767776684974
Firefox Google=C:\Users\<user>\AppData\Roaming\Mozilla\Firefox\Profiles\aa1ygowr.Google
'@ | Set-Content .\profiles.txt

.\new-profile-shortcuts.ps1 -MappingFile .\profiles.txt -SetGroupingPref -EmbedAumid -DryRun
```

`new-profile-shortcuts.ps1`:
- validates each profile dir (must contain `prefs.js`),
- ensures `taskbar.grouping.useprofile` is present and correct (with a `.bak` backup,
  skipped automatically if Firefox is running on that profile),
- creates junction + Desktop shortcut per profile (via `recreate-profile-shortcut.ps1`),
- with `-EmbedAumid`, reads and stamps each profile's real AUMID.

Start with `-DryRun` to see the plan without touching anything.

### Manual loop

```powershell
$map = @{
  'Firefox Work'   = "$env:APPDATA\Mozilla\Firefox\Profiles\JpIYBuOI.Profile 1"
  'Firefox Shop'   = "$env:APPDATA\Mozilla\Firefox\Profiles\3bgkx3tc.default-release-1767776684974"
  'Firefox Google' = "$env:APPDATA\Mozilla\Firefox\Profiles\aa1ygowr.Google"
}
$i = 0
foreach ($kv in $map.GetEnumerator()) {
  $i++
  $junc = "$env:LOCALAPPDATA\Mozilla\FirefoxTaskbar\Profile$i"
  if (-not (Test-Path "$junc\firefox.exe")) { cmd /c mklink /J "$junc" "C:\Program Files\Mozilla Firefox" }
  .\recreate-profile-shortcut.ps1 -ProfileDir $kv.Value -ShortcutName $kv.Key -EmbedAumid
}
```

Notes for >2 profiles:
- **One junction per profile, unique names** (`Profile1`, `Profile2`, … or `ProfileShop`,
  `ProfileWork`, …). Do not reuse a junction for two profiles.
- **Keep the junction name stable once a shortcut exists.** The exe path is part of the
  window's identity, and the AUMID is derived from the profile path, so pointing an
  existing shortcut at a *different* junction dir (or moving/renaming the profile) makes
  an already-pinned button stop matching. `recreate-profile-shortcut.ps1` accepts
  `-GroupKey <existing name>` for exactly this; the batch script derives the key from the
  shortcut name, so on first run keep whatever it generates.
- Each profile needs its own `taskbar.grouping.useprofile = true` — a profile missing it
  (the Google profile on the reference machine is one) will not group separately. Check
  all of them before blaming the pins.
- Firefox itself can only run one instance per profile: launching the same profile twice
  opens a window in the *existing* instance — that is expected, not a bug.
- Keep a note of which profile name maps to which directory; the AUMID is derived from
  the directory path, so **moving/renaming a profile dir changes its AUMID** and the pin
  must be re-stamped.

---

## 7. Verify (do this after every change)

1. Double-click `Firefox Work.lnk` → Work window opens.
2. Double-click `Firefox Shop.lnk` → a **second, separate** window opens on the Shop
   profile (both must be open side by side).
3. Repeat by clicking the two **taskbar pins** — this is the case that breaks when the
   AUMID is missing/stale.
4. Optional: `fix-taskbar-pin-aumid.ps1` prints `before`/`after` AUMIDs with a readback —
   both copies must show the same value and `[OK]`.

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Second shortcut opens a tab in the first profile's window | Same exe path for both profiles, or `-no-remote` missing → give each profile its own junction |
| Second **pin** focuses the first window (Desktop shortcuts fine) | The AUMID on the pin is missing/stale → `fix-taskbar-pin-aumid.ps1 -ShortcutName "<name>"` (both copies!) |
| Console window flashes before the browser opens | Shortcut points at `…\Launchers\Firefox<Name>Launcher.exe` → repoint to the junction's `firefox.exe` |
| Both profiles always share one taskbar button | `taskbar.grouping.useprofile` not `true` in at least one profile |
| Profile missing from `profiles.ini` | Doesn't matter for `--profile "<abs path>"`; find it by `places.sqlite`/`logins.json` |
| Settings shows ghost Firefox entries pointing at `FirefoxTaskbar\ProfileN` | Leftovers from the old setup; uninstalling one guts the real install. Delete those Uninstall keys, then reinstall Firefox (see the incident notes below) |
| After a Firefox update the shortcut lost `--profile` | Re-run `recreate-profile-shortcut.ps1`; Firefox updates rewrite Start-Menu shortcuts |

### Incident notes (why the ghosts are dangerous)

Ghost HKLM `Uninstall` keys whose `InstallLocation` points at a junction dir make
Settings offer to uninstall "Firefox" from `…\FirefoxTaskbar\Profile1`. Running that
uninstaller deletes **through the junction** and empties the real
`C:\Program Files\Mozilla Firefox` (only a stub file remained), killing every profile
shortcut. Recovery: delete the ghost keys + broken Start-Menu links, then run the
official installer elevated (`"Firefox Setup.exe" /s` via `Start-Process -Verb RunAs` —
a plain `/s` silently does nothing without admin, and winget refuses while ghosts exist).
The junctions resolve into the new install automatically, so all shortcuts work again.
