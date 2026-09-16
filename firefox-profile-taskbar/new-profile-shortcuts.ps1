<#
.SYNOPSIS
  Create (or repair) per-profile Firefox shortcuts for ANY number of profiles.

.DESCRIPTION
  Batch wrapper around recreate-profile-shortcut.ps1. For every mapping it:
    1. validates the profile directory (must contain prefs.js),
    2. optionally ensures `taskbar.grouping.useprofile = true` in that profile's
       prefs.js (with a .bak backup; skipped if Firefox is running on that profile,
       because prefs.js is rewritten when Firefox exits),
    3. creates the junction dir + Desktop shortcut,
    4. with -EmbedAumid: detects the profile's real runtime AUMID and stamps it into
       the shortcut (Desktop + taskbar-pin copy when present).

  Pinning to the taskbar itself stays manual — Windows 11 blocks programmatic pinning.

.PARAMETER Mapping
  One or more "Shortcut name=profile directory" strings:
    -Mapping "Firefox Shop=C:\Users\me\AppData\Roaming\Mozilla\Firefox\Profiles\abc.default-release"

.PARAMETER MappingFile
  Text file with one mapping per line (blank lines and lines starting with # ignored).

.PARAMETER SetGroupingPref
  Ensure taskbar.grouping.useprofile=true in each profile before creating the shortcut.

.PARAMETER EmbedAumid
  Detect and embed the profile's real runtime AUMID (launches the profile briefly if it
  is not already running; only the PIDs it starts are closed).

.PARAMETER DryRun
  Print what would happen, change nothing.

.EXAMPLE
  .\new-profile-shortcuts.ps1 -MappingFile .\profiles.txt -SetGroupingPref -EmbedAumid -DryRun
.EXAMPLE
  .\new-profile-shortcuts.ps1 -Mapping "Firefox Shop=$env:APPDATA\Mozilla\Firefox\Profiles\3bgkx3tc.default-release-1767776684974"
#>
param(
  [string[]]$Mapping = @(),
  [string]$MappingFile,
  [string]$FirefoxInstall = 'C:\Program Files\Mozilla Firefox',
  [switch]$SetGroupingPref,
  [switch]$EmbedAumid,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$recreate = Join-Path $here 'recreate-profile-shortcut.ps1'
if (-not (Test-Path $recreate)) { throw "recreate-profile-shortcut.ps1 not found next to this script" }

# ---- collect mappings -------------------------------------------------------
$pairs = @()
foreach ($m in $Mapping) {
  if ($m -and $m.Trim()) { $pairs += $m.Trim() }
}
if ($MappingFile) {
  if (-not (Test-Path $MappingFile)) { throw "MappingFile not found: $MappingFile" }
  foreach ($line in Get-Content $MappingFile) {
    $t = $line.Trim()
    if ($t -and -not $t.StartsWith('#')) { $pairs += $t }
  }
}
if (-not $pairs) { throw "no mappings given (use -Mapping or -MappingFile)" }

function Get-FirefoxRunningProfileDirs {
  @(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" |
    Where-Object { $_.CommandLine } |
    ForEach-Object { $_.CommandLine })
}

function Ensure-GroupingPref([string]$ProfileDir, [bool]$Dry) {
  $prefs = Join-Path $ProfileDir 'prefs.js'
  $lines = Get-Content $prefs
  $good = 'user_pref("taskbar.grouping.useprofile", true);'
  $malformed = $lines | Where-Object { $_ -match 'taskbar\.grouping\.useprofile' -and $_ -ne $good }
  $hasGood = ($lines -contains $good)

  if ($hasGood -and -not $malformed) { Write-Output '    pref   : already correct'; return }

  $running = Get-FirefoxRunningProfileDirs | Where-Object { $_ -like "*$ProfileDir*" }
  if ($running) {
    Write-Warning "    pref   : SKIPPED — Firefox is running on this profile (set it in about:config or close Firefox)"
    return
  }

  if ($Dry) { Write-Output "    pref   : WOULD fix ($($malformed.Count) malformed line(s), present=$hasGood)"; return }

  $bak = "$prefs.bak-newshortcut"
  if (-not (Test-Path $bak)) { Copy-Item $prefs $bak }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($l in $lines) {
    if ($l -match 'taskbar\.grouping\.useprofile') { continue }
    $out.Add($l)
  }
  if (-not $hasGood) { $out.Add($good) }
  Set-Content -Path $prefs -Value $out -Encoding UTF8
  Write-Output ("    pref   : fixed (backup: {0})" -f (Split-Path $bak -Leaf))
}

# ---- run --------------------------------------------------------------------
Write-Output ('Firefox install : ' + $FirefoxInstall)
Write-Output ('Scripts         : ' + $here)
Write-Output ('Profiles        : ' + $pairs.Count)
Write-Output ''

$n = 0
foreach ($p in $pairs) {
  $n++
  $parts = $p -split '=', 2
  if ($parts.Count -ne 2) { Write-Warning "  [$n] invalid mapping (need Name=Dir): $p"; continue }
  $name = $parts[0].Trim()
  $dir  = $parts[1].Trim().Trim('"')
  Write-Output ("[$n/$($pairs.Count)] $name")
  Write-Output ("    dir    : $dir")

  if (-not (Test-Path (Join-Path $dir 'prefs.js'))) {
    Write-Warning ('    skip   : no prefs.js there (not a Firefox profile dir?)')
    continue
  }

  if ($SetGroupingPref) { Ensure-GroupingPref -ProfileDir $dir -Dry:$DryRun }

  if ($DryRun) {
    $key = ($name -replace '[^A-Za-z0-9]', '')
    Write-Output ("    plan   : junction $env:LOCALAPPDATA\Mozilla\FirefoxTaskbar\Profile$key -> $FirefoxInstall")
    Write-Output ("    plan   : create Desktop\{0}.lnk with -no-remote --profile ""{1}""" -f $name, $dir)
    if ($EmbedAumid) { Write-Output '    plan   : detect + embed runtime AUMID' }
    continue
  }

  $rcArgs = @('-ProfileDir', $dir, '-ShortcutName', $name, '-FirefoxInstall', $FirefoxInstall)
  if ($EmbedAumid) { $rcArgs += '-EmbedAumid' }
  & $recreate @rcArgs
}

Write-Output ''
if ($DryRun) { Write-Output 'DRY RUN — nothing was changed.' }
else {
  Write-Output 'Done. Next: double-click each Desktop shortcut, then right-click its live taskbar icon -> Pin to taskbar (manual by design).'
  Write-Output 'If an existing pin opens the wrong profile, run: .\fix-taskbar-pin-aumid.ps1 -ShortcutName "<name>"'
}
