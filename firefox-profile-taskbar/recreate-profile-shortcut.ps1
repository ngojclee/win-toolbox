<#
.SYNOPSIS
  Recreate a single per-profile Firefox taskbar shortcut WITHOUT the console launcher stub,
  so double-clicking never flashes a terminal window and always opens that profile's own
  window (never a tab inside the profile that was opened first).
.DESCRIPTION
  Companion to firefox-profile-taskbar.ps1 for when you only need to rebuild ONE shortcut
  (e.g. after deleting it from taskbar/Desktop). See manual-profile-shortcut.md for the
  full background.

  What makes it work:
    - per-profile junction of the Firefox install dir  -> distinct exe path -> Firefox
      cannot hand the launch over to a running instance of another profile
    - -no-remote + --profile "<dir>"                   -> own process, own window
    - (optional -EmbedAumid) launch once, read the AUMID the running window really uses
      and write it into the .lnk so the pinned icon matches the live window.
      With taskbar.grouping.useprofile=true, Firefox's AUMID is a decimal hash of the
      PROFILE PATH (Mozilla HashString) - it cannot be composed from a name, so reading
      it from the live window is the only reliable way (same technique as the main script).
.PARAMETER ProfileDir
  Absolute path to the Firefox profile directory. NOTE: the profile does NOT have to appear
  in profiles.ini - some profiles exist only on disk; enumerate %APPDATA%\Mozilla\Firefox\Profiles
  when hunting for one.
.PARAMETER ShortcutName
  Friendly name, e.g. "Firefox Shop" -> "Firefox Shop.lnk" on Desktop.
.PARAMETER GroupKey
  Short tag for the junction dir (default: ShortcutName stripped of non-alphanumerics).
.PARAMETER EmbedAumid
  Briefly launches Firefox (~5-30s) to read the live window AUMID and embed it into the .lnk.
  Skip it if you only need separate windows; pin the LIVE icon and Windows handles grouping.
.EXAMPLE
  .\recreate-profile-shortcut.ps1 -ProfileDir "$env:APPDATA\Mozilla\Firefox\Profiles\3bgkx3tc.default-release-1767776684974" -ShortcutName "Firefox Shop"
#>
param(
  [Parameter(Mandatory=$true)][string]$ProfileDir,
  [Parameter(Mandatory=$true)][string]$ShortcutName,
  [string]$FirefoxInstall = "C:\Program Files\Mozilla Firefox",
  [string]$GroupKey = "",
  [switch]$EmbedAumid
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $FirefoxInstall 'firefox.exe'))) { throw "firefox.exe not found under $FirefoxInstall" }
if (-not (Test-Path (Join-Path $ProfileDir 'prefs.js'))) { throw "not a Firefox profile dir: $ProfileDir" }
if (-not $GroupKey) { $GroupKey = ($ShortcutName -replace '[^A-Za-z0-9]','') }

# --- C# helper: embed/read AppUserModelID. Embed goes through ShellLink -> IPersistFile
#     (READWRITE) -> IPropertyStore -> Commit -> Save; SHGetPropertyStoreForParsingName is
#     refused for .lnk files, this path is the one that works.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

public class ShortcutAppId {
    [ComImport][Guid("00021401-0000-0000-C000-000000000046")]
    public class ShellLink { }

    [ComImport][InterfaceType(ComInterfaceType.InterfaceIsIUnknown)][Guid("000214F9-0000-0000-C000-000000000046")]
    public interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out ushort pwHotkey);
        void SetHotkey(ushort wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cch, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport][InterfaceType(ComInterfaceType.InterfaceIsIUnknown)][Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    public interface IPropertyStore {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PROPERTYKEY pkey);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPVARIANT { public ushort vt, wReserved1, wReserved2, wReserved3; public IntPtr p; public int p2; }

    const ushort VT_LPWSTR = 31;
    static PROPERTYKEY PKEY_AppUserModel_ID = new PROPERTYKEY {
        fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };

    /// <summary>Embeds an AUMID into an existing .lnk (load READWRITE, set, commit, save).</summary>
    public static void SetAppUserModelId(string shortcutPath, string appId) {
        var shellLink = (IShellLinkW)new ShellLink();
        var persistFile = (IPersistFile)shellLink;
        persistFile.Load(shortcutPath, 2); // STGM_READWRITE
        var ps = (IPropertyStore)shellLink;
        var pv = new PROPVARIANT();
        pv.vt = VT_LPWSTR;
        pv.p = Marshal.StringToCoTaskMemUni(appId);
        int hr = ps.SetValue(ref PKEY_AppUserModel_ID, ref pv);
        Marshal.FreeCoTaskMem(pv.p);
        if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        ps.Commit();
        persistFile.Save(shortcutPath, true);
    }

    // --- window AUMID reading (runtime detection) ---
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IPropertyStore ppv);

    /// <summary>Reads the AppUserModelID that a running process set on its visible window.</summary>
    public static string GetProcessAumid(uint processId) {
        string result = null;
        Guid riid = typeof(IPropertyStore).GUID;
        EnumWindows((hwnd, lparam) => {
            if (!IsWindowVisible(hwnd)) return true;
            uint pid; GetWindowThreadProcessId(hwnd, out pid);
            if (pid != processId) return true;
            try {
                IPropertyStore ps;
                if (SHGetPropertyStoreForWindow(hwnd, ref riid, out ps) == 0 && ps != null) {
                    var pv = new PROPVARIANT();
                    var key = PKEY_AppUserModel_ID;
                    if (ps.GetValue(ref key, out pv) == 0 && pv.vt == VT_LPWSTR && pv.p != IntPtr.Zero)
                        result = Marshal.PtrToStringUni(pv.p);
                    Marshal.ReleaseComObject(ps);
                }
            } catch { }
            return result == null;
        }, IntPtr.Zero);
        return result;
    }
}
'@

# 1) Per-profile junction of the install dir -> distinct exe path -> Firefox cannot
#    hand the launch to an already-running instance of another profile.
$junc = Join-Path $env:LOCALAPPDATA "Mozilla\FirefoxTaskbar\Profile$GroupKey"
if (-not (Test-Path (Join-Path $junc 'firefox.exe'))) {
  New-Item -ItemType Directory -Path (Split-Path $junc) -Force | Out-Null
  cmd /c mklink /J "$junc" "$FirefoxInstall" | Out-Null
}
$fxj = Join-Path $junc 'firefox.exe'
if (-not (Test-Path $fxj)) { throw "junction firefox.exe missing: $fxj" }

# 2) Desktop shortcut: direct to junction exe (no launcher stub => no console flash),
#    -no-remote + explicit profile => own process, own window.
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop "$ShortcutName.lnk"
$sh = New-Object -ComObject WScript.Shell
$l = $sh.CreateShortcut($lnkPath)
$l.TargetPath       = $fxj
$l.Arguments        = "-no-remote --profile `"$ProfileDir`""
$l.WorkingDirectory = $junc
$l.IconLocation     = "$FirefoxInstall\firefox.exe,0"
$l.Description      = "Firefox profile shortcut (junction: $GroupKey)"
$l.Save()
Write-Host "OK  shortcut : $lnkPath"
Write-Host "OK  target   : $fxj"
Write-Host "OK  args     : $($l.Arguments)"

# 3) Optional: embed the REAL runtime AUMID (launch once, read from live window, close).
if ($EmbedAumid) {
  Write-Host "    Detecting live AUMID (Firefox opens briefly, ~5-30s)..." -ForegroundColor Gray
  $existingPids = @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  $proc = Start-Process -FilePath $fxj -ArgumentList "-no-remote --profile `"$ProfileDir`"" -PassThru
  $aumid = $null; $waited = 0
  while ($waited -lt 30 -and -not $aumid) {
    Start-Sleep -Seconds 3; $waited += 3
    foreach ($fpid in @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)) {
      if ($fpid -in $existingPids) { continue }
      try {
        $a = [ShortcutAppId]::GetProcessAumid([uint32]$fpid)
        if ($a) { $aumid = $a; break }
      } catch {}
    }
  }
  # close ONLY the pids we spawned (never taskkill /IM firefox.exe - would kill other profiles)
  foreach ($fpid in @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id | Where-Object { $_ -notin $existingPids })) {
    try { Stop-Process -Id $fpid -Force -ErrorAction SilentlyContinue } catch {}
  }
  try { $proc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
  Start-Sleep -Seconds 1
  if ($aumid) {
    try {
      [ShortcutAppId]::SetAppUserModelId($lnkPath, $aumid)
      Write-Host "OK  AUMID embedded: $aumid"
    } catch { Write-Warning "AUMID detected ($aumid) but embedding failed: $_" }
  } else {
    Write-Warning "Could not detect AUMID (is taskbar.grouping.useprofile set in this profile?). Pin the live icon instead."
  }
}

Write-Host ""
Write-Host "NEXT (Windows 11 has no programmatic taskbar pin):"
Write-Host "  1. Unpin any stale taskbar entry for this profile"
Write-Host "  2. Double-click '$ShortcutName.lnk' on Desktop"
Write-Host "  3. Right-click the live icon -> Pin to taskbar"
