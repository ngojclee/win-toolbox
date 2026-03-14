<#
.SYNOPSIS
    Firefox Multi-Profile Taskbar Setup (Universal)
    Configures multiple Firefox profiles to appear as SEPARATE apps on the Windows taskbar.

.DESCRIPTION
    Works on ANY Windows machine with Firefox installed.
    Supports: Firefox, Firefox Developer Edition, Firefox Nightly, Firefox ESR
    - Auto-detects all Firefox editions and profiles
    - Maps each profile to its correct Firefox edition executable
    - Can create NEW profiles on a fresh Firefox install
    - Enables 'taskbar.grouping.useprofile' in each selected profile
    - Creates desktop shortcuts with -no-remote for taskbar separation
    - Re-runnable: add more profiles anytime without breaking existing setup

.PARAMETER Create
    Create new Firefox profiles interactively (for fresh installs)

.PARAMETER List
    List all detected Firefox profiles and exit

.PARAMETER Profiles
    Comma-separated profile names to set up (skip interactive selection)
    Example: -Profiles "Personal,Work"

.EXAMPLE
    # Interactive mode - detect & select profiles
    .\firefox-profile-taskbar.ps1

    # Create new profiles on fresh Firefox install
    .\firefox-profile-taskbar.ps1 -Create

    # List all profiles
    .\firefox-profile-taskbar.ps1 -List

    # Non-interactive: specify profile names directly
    .\firefox-profile-taskbar.ps1 -Profiles "Personal,Work"
#>

param(
    [switch]$Create,
    [switch]$List,
    [string]$Profiles,
    [switch]$Force
)

# --- Auto-detect All Firefox Editions ----------------------------------------

function Find-AllFirefox {
    <#
    .DESCRIPTION
    Returns a list of installed Firefox editions with their exe path and install hash.
    Supports: Firefox, Firefox Developer Edition, Firefox Nightly, Firefox ESR.
    #>

    $editions = @(
        @{ Name = "Firefox";               Dirs = @("Mozilla Firefox") },
        @{ Name = "Firefox Developer";      Dirs = @("Firefox Developer Edition") },
        @{ Name = "Firefox Nightly";        Dirs = @("Firefox Nightly") },
        @{ Name = "Firefox ESR";            Dirs = @("Mozilla Firefox ESR", "Firefox ESR") }
    )

    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA
    ) | Where-Object { $_ }

    $found = @()

    foreach ($edition in $editions) {
        foreach ($root in $roots) {
            foreach ($dir in $edition.Dirs) {
                $exePath = Join-Path $root "$dir\firefox.exe"
                if (Test-Path $exePath) {
                    $found += [PSCustomObject]@{
                        Edition = $edition.Name
                        ExePath = $exePath
                    }
                    break  # Found this edition, skip other roots
                }
            }
        }
    }

    # Also check registry for unlisted installs
    $regPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe" -ErrorAction SilentlyContinue
    if ($regPath) {
        $regExe = $regPath.'(default)'
        if ($regExe -and (Test-Path $regExe)) {
            $alreadyFound = $found | Where-Object { $_.ExePath -eq $regExe }
            if (-not $alreadyFound) {
                $found += [PSCustomObject]@{
                    Edition = "Firefox (Registry)"
                    ExePath = $regExe
                }
            }
        }
    }

    return $found
}

function Find-ProfilesIni {
    $iniPath = "$env:APPDATA\Mozilla\Firefox\profiles.ini"
    if (Test-Path $iniPath) { return $iniPath }
    return $null
}

function Find-InstallsIni {
    $iniPath = "$env:APPDATA\Mozilla\Firefox\installs.ini"
    if (Test-Path $iniPath) { return $iniPath }
    return $null
}

# --- Install Hash -> Edition Mapper -------------------------------------------

function Get-InstallHashMap {
    <#
    .DESCRIPTION
    Parses installs.ini and profiles.ini to map install hashes to their
    default profile paths. Then cross-references with detected Firefox editions.
    Returns a hashtable: ProfilePath -> Firefox Edition ExePath
    #>
    param([array]$FirefoxEditions)

    $profileToExe = @{}

    # Parse installs.ini: each section [HASH] has Default=Profiles/xxx
    $installsIni = Find-InstallsIni
    $profilesIni = Find-ProfilesIni
    if (-not $installsIni -or -not $profilesIni) { return $profileToExe }

    $profilesRoot = Split-Path $profilesIni
    $installContent = Get-Content $installsIni -Raw
    $profileContent = Get-Content $profilesIni -Raw

    # Parse [Install*] sections from profiles.ini -- these map install hash -> default profile
    $installSections = [regex]::Matches($profileContent, '(?ms)^\[Install([A-F0-9]+)\]\s*$(.*?)(?=^\[|\Z)')

    foreach ($section in $installSections) {
        $hash = $section.Groups[1].Value
        $block = $section.Value

        $defaultProfile = if ($block -match '(?m)^Default=(.+)$') { $Matches[1].Trim() } else { "" }
        if (-not $defaultProfile) { continue }

        $fullProfilePath = (Join-Path $profilesRoot $defaultProfile) -replace '/', '\'

        # Match hash to Firefox edition by checking install path hashes
        # Firefox uses a hash of the install directory as the section name
        # We match by trying each edition exe path
        foreach ($edition in $FirefoxEditions) {
            # Firefox's hash algorithm: lowercase path -> djb2 hash
            # We can't easily compute it, but we can use the installs.ini which has the same hashes
            $installsBlock = ""
            if ($installContent -match "(?ms)^\[$hash\](.+?)(?=^\[|\Z)") {
                $installsBlock = $Matches[0]
            }
            if ($installsBlock -match '(?m)^Default=(.+)$') {
                $installDefault = $Matches[1].Trim()
                $installFullPath = (Join-Path $profilesRoot $installDefault) -replace '/', '\'
                if ($installFullPath -eq $fullProfilePath) {
                    $profileToExe[$fullProfilePath] = $edition
                    break
                }
            }
        }
    }

    return $profileToExe
}

# --- Profile Parser ----------------------------------------------------------

function Get-FirefoxProfiles {
    param([array]$FirefoxEditions)

    $iniPath = Find-ProfilesIni
    if (-not $iniPath) { return @() }

    $profilesRoot = Split-Path $iniPath
    $content = Get-Content $iniPath -Raw
    $profiles = @()

    # Build install hash -> edition mapping
    $installMap = Get-InstallHashMap -FirefoxEditions $FirefoxEditions

    # Parse [Install*] sections to build profilePath -> edition lookup
    $installDefaults = @{}
    $installSections = [regex]::Matches($content, '(?ms)^\[Install([A-F0-9]+)\]\s*$(.*?)(?=^\[|\Z)')
    foreach ($section in $installSections) {
        $block = $section.Value
        if ($block -match '(?m)^Default=(.+)$') {
            $defPath = (Join-Path $profilesRoot $Matches[1].Trim()) -replace '/', '\'
            $installDefaults[$defPath] = $true
        }
    }

    # Parse INI sections for profiles
    $sections = [regex]::Matches($content, '(?ms)^\[Profile\d+\]\s*$(.*?)(?=^\[|\Z)')

    foreach ($section in $sections) {
        $block = $section.Value
        $name = if ($block -match '(?m)^Name=(.+)$') { $Matches[1].Trim() } else { "Unknown" }
        $path = if ($block -match '(?m)^Path=(.+)$') { $Matches[1].Trim() } else { "" }
        $isRelative = if ($block -match '(?m)^IsRelative=(\d)') { $Matches[1] -eq "1" } else { $true }
        $isDefault = $block -match '(?m)^Default=1'

        if ($path) {
            $fullPath = if ($isRelative) { Join-Path $profilesRoot $path } else { $path }
            $fullPath = $fullPath -replace '/', '\'

            if (Test-Path $fullPath) {
                # Determine which Firefox edition this profile belongs to
                $edition = $null
                if ($installMap.ContainsKey($fullPath)) {
                    $edition = $installMap[$fullPath]
                }

                # Heuristic: if profile name contains "dev-edition" -> Developer Edition
                if (-not $edition -and $name -match 'dev-edition') {
                    $edition = $FirefoxEditions | Where-Object { $_.Edition -match 'Developer' } | Select-Object -First 1
                }
                # If profile name contains "nightly" -> Nightly
                if (-not $edition -and $name -match 'nightly') {
                    $edition = $FirefoxEditions | Where-Object { $_.Edition -match 'Nightly' } | Select-Object -First 1
                }
                # Fallback: use regular Firefox
                if (-not $edition) {
                    $edition = $FirefoxEditions | Where-Object { $_.Edition -eq 'Firefox' } | Select-Object -First 1
                }
                # Last resort: first found edition
                if (-not $edition) {
                    $edition = $FirefoxEditions | Select-Object -First 1
                }

                $profiles += [PSCustomObject]@{
                    Name       = $name
                    Path       = $fullPath
                    FolderName = Split-Path $fullPath -Leaf
                    IsDefault  = $isDefault
                    Edition    = $edition.Edition
                    ExePath    = $edition.ExePath
                }
            }
        }
    }
    return $profiles
}

# --- UI Helpers ---------------------------------------------------------------

function Write-Banner {
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Magenta
    Write-Host "  Firefox Multi-Profile Taskbar Setup" -ForegroundColor White
    Write-Host "  github.com/ngojclee/win-toolbox" -ForegroundColor DarkGray
    Write-Host "===========================================================" -ForegroundColor Magenta
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host ""
    Write-Host "[$Step] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-OK   { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "  [ERR] $m" -ForegroundColor Red }

# --- Create New Profile ------------------------------------------------------

function New-FirefoxProfile {
    param([string]$ProfileName, [string]$FirefoxExe)

    Write-Host "  Creating profile '$ProfileName'..." -ForegroundColor Gray
    $proc = Start-Process -FilePath $FirefoxExe -ArgumentList "-CreateProfile `"$ProfileName`"" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -eq 0) {
        Write-OK "Profile '$ProfileName' created"
        return $true
    } else {
        Write-Err "Failed to create profile '$ProfileName'"
        return $false
    }
}

# --- Enable Taskbar Grouping -------------------------------------------------

function Enable-TaskbarGrouping {
    param([string]$ProfilePath)

    $prefsPath = Join-Path $ProfilePath "prefs.js"
    $prefLine = 'user_pref("taskbar.grouping.useprofile", true);'

    if (-not (Test-Path $prefsPath)) {
        return "NEEDS_INIT"
    }

    $content = Get-Content $prefsPath -Raw
    if ($content -match 'taskbar\.grouping\.useprofile') {
        if ($content -match 'user_pref\("taskbar\.grouping\.useprofile",\s*true\)') {
            return "ALREADY_SET"
        } else {
            $content = $content -replace 'user_pref\("taskbar\.grouping\.useprofile",\s*false\);', $prefLine
            Set-Content -Path $prefsPath -Value $content -NoNewline
            return "UPDATED"
        }
    } else {
        Add-Content -Path $prefsPath -Value "`n$prefLine"
        return "ADDED"
    }
}

# --- AppUserModelID Helper (COM Interop) -------------------------------------

# This is the KEY piece that makes separate taskbar grouping work.
# Windows groups taskbar icons by AppUserModelID (AUMID).
# When taskbar.grouping.useprofile=true, Firefox hashes the profile path
# using Mozilla's HashString() and sets the result as AUMID (a decimal number).
# The pinned .lnk shortcut ALSO needs the same AUMID embedded,
# otherwise Windows creates a NEW taskbar icon instead of matching the pin.

$appUserModelIdTypeAdded = $false

function Initialize-AppUserModelIdType {
    if ($script:appUserModelIdTypeAdded) { return }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public class ShortcutAppId {
    // CLSID_ShellLink
    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    public class ShellLink { }

    // IShellLinkW
    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    public interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszName, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszDir, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszArgs, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out ushort pwHotkey);
        void SetHotkey(ushort wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszIconPath, int cch, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    // IPropertyStore
    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    public interface IPropertyStore {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PROPERTYKEY pkey);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPERTYKEY {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPVARIANT {
        public ushort vt;
        public ushort wReserved1;
        public ushort wReserved2;
        public ushort wReserved3;
        public IntPtr p;
        public int p2;
    }

    // VT_LPWSTR = 31
    const ushort VT_LPWSTR = 31;

    // PKEY_AppUserModel_ID = {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, 5
    static PROPERTYKEY PKEY_AppUserModel_ID = new PROPERTYKEY {
        fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
        pid = 5
    };

    public static void SetAppUserModelId(string shortcutPath, string appId) {
        // Create ShellLink COM object
        var shellLink = (IShellLinkW)new ShellLink();

        // Load existing .lnk file
        var persistFile = (IPersistFile)shellLink;
        persistFile.Load(shortcutPath, 2); // STGM_READWRITE = 2

        // Get IPropertyStore
        var propertyStore = (IPropertyStore)shellLink;

        // Set AppUserModelID
        var pv = new PROPVARIANT();
        pv.vt = VT_LPWSTR;
        pv.p = Marshal.StringToCoTaskMemUni(appId);

        int hr = propertyStore.SetValue(ref PKEY_AppUserModel_ID, ref pv);
        Marshal.FreeCoTaskMem(pv.p);

        if (hr < 0) Marshal.ThrowExceptionForHR(hr);

        propertyStore.Commit();

        // Save the .lnk file
        persistFile.Save(shortcutPath, true);
    }

    // --- Window AUMID reading (for runtime detection) ---

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("shell32.dll")]
    static extern int SHGetPropertyStoreForWindow(
        IntPtr hwnd,
        ref Guid iid,
        out IPropertyStore propertyStore
    );

    /// <summary>
    /// Reads the AppUserModelID from a running process by scanning its visible windows.
    /// Used to detect the actual AUMID that Firefox sets at runtime.
    /// </summary>
    public static string GetProcessAumid(uint processId) {
        string result = null;
        EnumWindows((hwnd, lparam) => {
            if (!IsWindowVisible(hwnd)) return true;
            if (GetWindowTextLength(hwnd) <= 0) return true;

            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pid != processId) return true;

            try {
                Guid IID = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
                IPropertyStore store;
                int hr = SHGetPropertyStoreForWindow(hwnd, ref IID, out store);
                if (hr != 0 || store == null) return true;

                PROPERTYKEY pkey = PKEY_AppUserModel_ID;
                PROPVARIANT pv;
                hr = store.GetValue(ref pkey, out pv);
                if (hr == 0 && pv.vt == VT_LPWSTR && pv.p != IntPtr.Zero) {
                    result = Marshal.PtrToStringUni(pv.p);
                    return false; // stop enumeration, found it
                }
            } catch {}
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
"@ -ErrorAction Stop

    $script:appUserModelIdTypeAdded = $true
}

function Get-ProfileAppUserModelId {
    <#
    .DESCRIPTION
    Detects the ACTUAL AppUserModelID that Firefox sets at runtime for a given profile.

    Instead of trying to replicate Mozilla's internal hash algorithm (which depends
    on internal path resolution that varies by platform/version), we:
      1. Launch Firefox briefly with the target profile
      2. Read the AUMID from the window using SHGetPropertyStoreForWindow
      3. Close Firefox
      4. Return the real AUMID

    This is the only reliable way to get the exact AUMID Firefox uses.
    #>
    param(
        [string]$ProfilePath,
        [string]$FirefoxExe
    )

    # Ensure C# type is loaded
    Initialize-AppUserModelIdType

    Write-Host "    Detecting AUMID (launching Firefox briefly)..." -ForegroundColor Gray

    # Record existing Firefox PIDs so we can identify the new ones
    $existingPids = @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)

    # Launch Firefox with this profile
    $proc = Start-Process -FilePath $FirefoxExe -ArgumentList "-no-remote --profile `"$ProfilePath`"" -PassThru

    # Wait for Firefox to initialize and set its AUMID
    # Firefox spawns child processes; the original PID may exit quickly
    $aumid = $null
    $maxWait = 20  # seconds
    $waited = 0

    while ($waited -lt $maxWait -and -not $aumid) {
        Start-Sleep -Seconds 3
        $waited += 3

        # Scan ALL Firefox processes (not just launched PID) for AUMID
        $allFirefoxPids = @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)

        foreach ($fpid in $allFirefoxPids) {
            try {
                $detectedAumid = [ShortcutAppId]::GetProcessAumid([uint32]$fpid)
                if ($detectedAumid -and $detectedAumid -ne "") {
                    # Found an AUMID - but is it from our newly launched profile?
                    # If it's a new PID (not in existingPids), it's likely ours
                    if ($fpid -notin $existingPids -or $allFirefoxPids.Count -eq 1) {
                        $aumid = $detectedAumid
                        break
                    }
                }
            } catch {}
        }
    }

    # Close ALL newly-spawned Firefox processes
    $newPids = @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id | Where-Object { $_ -notin $existingPids })
    foreach ($fpid in $newPids) {
        try { Stop-Process -Id $fpid -Force -ErrorAction SilentlyContinue } catch {}
    }
    # Also try to stop the original process
    try { $proc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 2

    if ($aumid) {
        return $aumid
    }

    Write-Warn "    Could not detect AUMID automatically"
    return $null
}

function Set-ShortcutAppUserModelId {
    <#
    .DESCRIPTION
    Sets the System.AppUserModel.ID property on an existing .lnk shortcut file.
    This embeds the AUMID into the shortcut so Windows can match the pinned icon
    with the running Firefox window.
    #>
    param(
        [string]$ShortcutPath,
        [string]$AppUserModelId
    )

    Initialize-AppUserModelIdType

    try {
        [ShortcutAppId]::SetAppUserModelId($ShortcutPath, $AppUserModelId)
        return $true
    } catch {
        Write-Warn "Failed to set AppUserModelID on shortcut: $_"
        return $false
    }
}

# --- Create Shortcut ---------------------------------------------------------

function New-ProfileShortcut {
    param(
        [string]$ShortcutName,
        [string]$ProfilePath,
        [string]$FirefoxExe,
        [string]$OutputDir
    )

    $shortcutPath = Join-Path $OutputDir "$ShortcutName.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($shortcutPath)
    $lnk.TargetPath       = $FirefoxExe
    $lnk.Arguments        = "-no-remote --profile `"$ProfilePath`""
    $lnk.IconLocation     = "$FirefoxExe,0"
    $lnk.Description      = "$ShortcutName (Firefox Profile)"
    $lnk.WorkingDirectory = Split-Path $FirefoxExe
    $lnk.Save()

    # === KEY FIX: Embed AppUserModelID into the shortcut ===
    # This makes Windows match the pinned taskbar icon with the running Firefox window.
    # Without this, clicking a pinned icon opens Firefox but it appears as a NEW icon
    # instead of grouping under the pinned one.
    $aumid = Get-ProfileAppUserModelId -ProfilePath $ProfilePath -FirefoxExe $FirefoxExe
    if ($aumid) {
        $setResult = Set-ShortcutAppUserModelId -ShortcutPath $shortcutPath -AppUserModelId $aumid
        if ($setResult) {
            Write-OK "  AppUserModelID: $aumid"
        }
    } else {
        Write-Warn "  Could not embed AppUserModelID (pin manually from running app)"
    }

    return $shortcutPath
}

# ==============================================================================
# MAIN
# ==============================================================================

Write-Banner

# --- Find All Firefox Editions -----------------------------------------------
$AllFirefox = @(Find-AllFirefox)

if ($AllFirefox.Count -eq 0) {
    Write-Err "No Firefox installation found!"
    Write-Host "  Download: https://www.mozilla.org/firefox/" -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Host "  Detected Firefox editions:" -ForegroundColor White
foreach ($ff in $AllFirefox) {
    Write-OK "$($ff.Edition): $($ff.ExePath)"
}

# --- Create Mode -------------------------------------------------------------
if ($Create) {
    Write-Step "CREATE" "Creating new Firefox profiles"

    # Let user choose which Firefox edition to use for creating
    $createExe = $AllFirefox[0].ExePath
    if ($AllFirefox.Count -gt 1) {
        Write-Host ""
        Write-Host "  Which Firefox edition to create profiles for?" -ForegroundColor White
        for ($i = 0; $i -lt $AllFirefox.Count; $i++) {
            Write-Host "    [$($i+1)] $($AllFirefox[$i].Edition)" -ForegroundColor Cyan
        }
        $choice = Read-Host "  Choice (default: 1)"
        if ($choice -and [int]$choice -ge 1 -and [int]$choice -le $AllFirefox.Count) {
            $createExe = $AllFirefox[[int]$choice - 1].ExePath
        }
    }

    Write-Host ""
    Write-Host "  How many profiles do you want to create?" -ForegroundColor White
    $count = Read-Host "  Number (default: 2)"
    if (-not $count) { $count = 2 } else { $count = [int]$count }

    $newNames = @()
    for ($i = 1; $i -le $count; $i++) {
        $defaultName = if ($i -eq 1) { "Personal" } elseif ($i -eq 2) { "Work" } else { "Profile-$i" }
        $name = Read-Host "  Name for profile $i (default: $defaultName)"
        if (-not $name) { $name = $defaultName }
        $newNames += $name

        $ffProc = Get-Process firefox -ErrorAction SilentlyContinue
        if ($ffProc) {
            Write-Warn "Closing Firefox to create profile..."
            $ffProc | Stop-Process -Force
            Start-Sleep -Seconds 2
        }

        New-FirefoxProfile -ProfileName $name -FirefoxExe $createExe

        Write-Host "  Initializing profile (opens Firefox briefly)..." -ForegroundColor Gray
        $proc = Start-Process -FilePath $createExe -ArgumentList "-no-remote -P `"$name`" -headless" -PassThru
        Start-Sleep -Seconds 5
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    Write-OK "Created $count profiles. Re-detecting..."
    Write-Host ""
}

# --- Detect Profiles ---------------------------------------------------------
Write-Step "1/4" "Detecting Firefox profiles"

$allProfiles = @(Get-FirefoxProfiles -FirefoxEditions $AllFirefox)

if ($allProfiles.Count -eq 0) {
    Write-Err "No Firefox profiles found!"
    Write-Host "  Run with -Create flag to create profiles first:" -ForegroundColor Gray
    Write-Host "  .\firefox-profile-taskbar.ps1 -Create" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "  Found $($allProfiles.Count) profile(s):" -ForegroundColor White
Write-Host ""
for ($i = 0; $i -lt $allProfiles.Count; $i++) {
    $p = $allProfiles[$i]
    $default = if ($p.IsDefault) { " *" } else { "" }
    $editionTag = "[$($p.Edition)]"
    Write-Host "    [$($i+1)] " -ForegroundColor Cyan -NoNewline
    Write-Host "$($p.Name)$default " -ForegroundColor White -NoNewline
    Write-Host $editionTag -ForegroundColor DarkYellow
    Write-Host "        $($p.FolderName)" -ForegroundColor DarkGray
}

# List mode - just show and exit
if ($List) {
    Write-Host ""
    exit 0
}

# --- Select Profiles ---------------------------------------------------------
Write-Step "2/4" "Select profiles for taskbar separation"

$selectedProfiles = @()

if ($Profiles) {
    $requestedNames = $Profiles -split ',' | ForEach-Object { $_.Trim() }
    foreach ($rn in $requestedNames) {
        $match = $allProfiles | Where-Object { $_.Name -eq $rn }
        if ($match) {
            $selectedProfiles += $match
        } else {
            Write-Warn "Profile '$rn' not found, skipping"
        }
    }
} else {
    Write-Host ""
    if ($allProfiles.Count -eq 1) {
        Write-Warn "Only 1 profile found. You need at least 2 for taskbar separation."
        Write-Host "  Run with -Create flag to create more profiles." -ForegroundColor Gray
        exit 1
    }

    Write-Host "  Enter profile numbers to set up (comma-separated)" -ForegroundColor White
    Write-Host "  Example: 1,2  or  1,2,3  or  'all'" -ForegroundColor Gray
    $selection = Read-Host "  Selection (default: all)"

    if (-not $selection -or $selection -eq 'all') {
        $selectedProfiles = $allProfiles
    } else {
        $indices = $selection -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
        foreach ($idx in $indices) {
            if ($idx -ge 0 -and $idx -lt $allProfiles.Count) {
                $selectedProfiles += $allProfiles[$idx]
            }
        }
    }
}

if ($selectedProfiles.Count -lt 2) {
    Write-Err "At least 2 profiles are needed for taskbar separation."
    exit 1
}

Write-Host ""
Write-Host "  Selected:" -ForegroundColor White
foreach ($sp in $selectedProfiles) {
    Write-Host "    -> $($sp.Name) " -ForegroundColor Green -NoNewline
    Write-Host "[$($sp.Edition)]" -ForegroundColor DarkYellow
}

# --- Ask for human-friendly names --------------------------------------------
Write-Step "3/4" "Naming shortcuts"
Write-Host ""
Write-Host "  Give each profile a friendly shortcut name." -ForegroundColor White
Write-Host "  Press Enter to keep defaults." -ForegroundColor Gray
Write-Host ""

$shortcutMap = @()
for ($i = 0; $i -lt $selectedProfiles.Count; $i++) {
    $sp = $selectedProfiles[$i]
    $defaultLabel = $sp.Name
    # Suggest nicer names for common profile names
    if ($sp.Name -eq "default-release") { $defaultLabel = "Personal" }
    elseif ($sp.Name -eq "default") { $defaultLabel = "Work" }
    elseif ($sp.Name -eq "dev-edition-default") { $defaultLabel = "Developer" }

    # Include edition hint in prompt
    $editionHint = if ($sp.Edition -ne "Firefox") { " [$($sp.Edition)]" } else { "" }
    $label = Read-Host "  Shortcut name for '$($sp.Name)'$editionHint (default: $defaultLabel)"
    if (-not $label) { $label = $defaultLabel }

    # For non-standard edition, prefix the shortcut name to distinguish visually
    $shortcutPrefix = if ($sp.Edition -match 'Developer') { "Firefox Dev" }
                      elseif ($sp.Edition -match 'Nightly') { "Firefox Nightly" }
                      elseif ($sp.Edition -match 'ESR') { "Firefox ESR" }
                      else { "Firefox" }

    $shortcutMap += [PSCustomObject]@{
        Profile      = $sp
        ShortcutName = "$shortcutPrefix - $label"
        Label        = $label
    }
}

# --- Close Firefox -----------------------------------------------------------
$ffProc = Get-Process firefox -ErrorAction SilentlyContinue
if ($ffProc) {
    Write-Warn "Firefox is running. It must be closed to modify prefs."
    if (-not $Force) {
        $answer = Read-Host "  Close Firefox now? (Y/n)"
        if ($answer -eq '' -or $answer -match '^[Yy]') {
            $ffProc | Stop-Process -Force
            Start-Sleep -Seconds 2
        } else {
            Write-Err "Cannot continue. Close Firefox and re-run."
            exit 1
        }
    } else {
        $ffProc | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
}

# --- Enable taskbar.grouping.useprofile ---------------------------------------
Write-Step "4/4" "Applying configuration"

Write-Host ""
Write-Host "  Enabling taskbar.grouping.useprofile..." -ForegroundColor White

foreach ($item in $shortcutMap) {
    $result = Enable-TaskbarGrouping -ProfilePath $item.Profile.Path
    switch ($result) {
        "ALREADY_SET" { Write-OK "$($item.Label): Already enabled" }
        "UPDATED"     { Write-OK "$($item.Label): Enabled (was false)" }
        "ADDED"       { Write-OK "$($item.Label): Enabled (new pref)" }
        "NEEDS_INIT"  {
            Write-Warn "$($item.Label): Profile not initialized yet"
            Write-Host "    Launching $($item.Profile.Edition) briefly to initialize..." -ForegroundColor Gray
            $proc = Start-Process -FilePath $item.Profile.ExePath -ArgumentList "-no-remote --profile `"$($item.Profile.Path)`" -headless" -PassThru
            Start-Sleep -Seconds 5
            $proc | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $result2 = Enable-TaskbarGrouping -ProfilePath $item.Profile.Path
            if ($result2 -eq "NEEDS_INIT") {
                Write-Err "$($item.Label): Could not initialize. Please open this profile manually once first."
            } else {
                Write-OK "$($item.Label): Enabled (after init)"
            }
        }
    }
}

# --- Create Desktop Shortcuts ------------------------------------------------
Write-Host ""
Write-Host "  Creating desktop shortcuts..." -ForegroundColor White

$DesktopDir = [Environment]::GetFolderPath("Desktop")

foreach ($item in $shortcutMap) {
    $path = New-ProfileShortcut `
        -ShortcutName $item.ShortcutName `
        -ProfilePath $item.Profile.Path `
        -FirefoxExe $item.Profile.ExePath `
        -OutputDir $DesktopDir
    Write-OK "Desktop: $($item.ShortcutName).lnk -> $($item.Profile.Edition)"
}

# --- Final Instructions -------------------------------------------------------
Write-Host ""
Write-Host "===========================================================" -ForegroundColor Magenta
Write-Host "  Configuration Complete!" -ForegroundColor Green
Write-Host "===========================================================" -ForegroundColor Magenta

Write-Host ""
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  MANUAL STEPS (Windows requires these by hand):          |" -ForegroundColor DarkCyan
Write-Host "  |                                                          |" -ForegroundColor DarkCyan
Write-Host "  |  1. Right-click ALL Firefox icons on taskbar             |" -ForegroundColor White
Write-Host "  |     -> 'Unpin from taskbar'                              |" -ForegroundColor White
Write-Host "  |                                                          |" -ForegroundColor DarkCyan

$num = 2
foreach ($item in $shortcutMap) {
    Write-Host "  |  $num. Double-click '$($item.ShortcutName)' on Desktop" -ForegroundColor White
    Write-Host "  |     -> Wait for it to open                              |" -ForegroundColor White
    Write-Host "  |     -> Right-click its taskbar icon -> 'Pin to taskbar'  |" -ForegroundColor White
    Write-Host "  |                                                          |" -ForegroundColor DarkCyan
    $num++
}

Write-Host "  |  Each profile will get its own taskbar icon!             |" -ForegroundColor Green
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan

Write-Host ""
Write-Host "  Profile Summary:" -ForegroundColor Gray
foreach ($item in $shortcutMap) {
    Write-Host "    $($item.ShortcutName): " -ForegroundColor White -NoNewline
    Write-Host "$($item.Profile.FolderName) " -ForegroundColor DarkGray -NoNewline
    Write-Host "-> $($item.Profile.Edition)" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "  Tips:" -ForegroundColor Yellow
Write-Host "    - Re-run this script anytime to add more profiles" -ForegroundColor Gray
Write-Host "    - Use -Create flag on fresh Firefox installs" -ForegroundColor Gray
Write-Host "    - Use -List flag to see all profiles" -ForegroundColor Gray
Write-Host "    - Supports: Firefox, Developer Edition, Nightly, ESR" -ForegroundColor Gray
Write-Host "    - The '-no-remote' flag in shortcuts is what makes separation work" -ForegroundColor Gray
Write-Host ""
