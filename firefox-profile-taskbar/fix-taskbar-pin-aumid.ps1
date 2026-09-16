<#
.SYNOPSIS
  Fix Firefox taskbar pins that open the wrong profile: clicking the second pin just
  focuses the first profile's window instead of opening its own profile.

.DESCRIPTION
  Windows decides "is this app already running?" by comparing the TASKBAR PIN's
  AppUserModelID (AUMID) with the AUMIDs of running windows. With
  `taskbar.grouping.useprofile = true`, Firefox sets each window's AUMID to a DECIMAL
  HASH of the profile path (e.g. 2842963073) - nothing like "Mozilla.Firefox.Shop".
  A pin carrying no/stale AUMID therefore matches the other profile's window and gets
  swallowed by it.

  This script:
    1. reads each pin's target + `--profile` argument,
    2. reads the REAL runtime AUMID from that profile's live window
       (launching it briefly if it is not already running; only spawns it closes),
    3. stamps that AUMID into EVERY copy of the .lnk - Desktop and the TaskBar pin dir,
    4. verifies with a readback.

  After stamping, click a pin to make sure the pin's grouping metadata is rebuilt;
  if Windows still misbehaves, unpin/re-pin once or restart explorer.

.PARAMETER ShortcutName
  One or more shortcut base names, e.g. "Firefox Work","Firefox Shop".
  Both "<name>.lnk" copies (Desktop + TaskBar pin dir) are processed.

.EXAMPLE
  .\fix-taskbar-pin-aumid.ps1 -ShortcutName "Firefox Work","Firefox Shop"
#>
param(
  [Parameter(Mandatory=$true)][string[]]$ShortcutName,
  [string]$DesktopDir = [Environment]::GetFolderPath('Desktop'),
  [string]$PinDir = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar",
  [int]$LaunchWaitSeconds = 40
)
$ErrorActionPreference = 'Stop'

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

    public static string GetAppUserModelId(string shortcutPath) {
        try {
            var shellLink = (IShellLinkW)new ShellLink();
            var persistFile = (IPersistFile)shellLink;
            persistFile.Load(shortcutPath, 0); // STGM_READ
            var ps = (IPropertyStore)shellLink;
            var pv = new PROPVARIANT();
            var key = PKEY_AppUserModel_ID;
            int hr = ps.GetValue(ref key, out pv);
            if (hr == 0 && pv.vt == VT_LPWSTR && pv.p != IntPtr.Zero) return Marshal.PtrToStringUni(pv.p);
        } catch { }
        return null;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IPropertyStore ppv);

    /// <summary>Reads the AUMID a process set on its visible window (Firefox uses the
    /// decimal profile-path hash when taskbar.grouping.useprofile=true).</summary>
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

$wsh = New-Object -ComObject WScript.Shell

function Get-PinProfile([string]$lnk) {
  $l = $wsh.CreateShortcut($lnk)
  $m = [regex]::Match($l.Arguments, '--profile\s+"([^"]+)"')
  if (-not $m.Success) { $m = [regex]::Match($l.Arguments, '--profile\s+(\S+)') }
  [pscustomobject]@{ Target = $l.TargetPath; Profile = $(if ($m.Success) { $m.Groups[1].Value } else { $null }); Lnk = $lnk }
}

foreach ($name in $ShortcutName) {
  Write-Output "===== $name ====="
  $lnks = @((Join-Path $DesktopDir "$name.lnk"), (Join-Path $PinDir "$name.lnk")) | Where-Object { Test-Path $_ }
  if (-not $lnks) { Write-Warning "  no .lnk found for '$name'"; continue }

  $info = Get-PinProfile $lnks[0]
  if (-not $info.Profile) { Write-Warning "  '$name' has no --profile argument; skipping"; continue }
  Write-Output ("  target : " + $info.Target)
  Write-Output ("  profile: " + $info.Profile)
  foreach ($l in $lnks) {
    $cur = [ShortcutAppId]::GetAppUserModelId($l)
    Write-Output ("  before : {0,-9} {1}" -f (Split-Path $l -Parent | Split-Path -Leaf), $(if ($cur) { $cur } else { '<none>' }))
  }

  # 1) live window of that profile already running?
  $aumid = $null
  $existing = @(Get-CimInstance Win32_Process -Filter "Name='firefox.exe'" |
                Where-Object { $_.CommandLine -like "*$($info.Profile)*" } |
                Select-Object -ExpandProperty ProcessId)
  foreach ($fpid in $existing) {
    $a = [ShortcutAppId]::GetProcessAumid([uint32]$fpid)
    if ($a) { $aumid = $a; Write-Output "  source : live window pid $fpid"; break }
  }

  # 2) otherwise launch it briefly
  if (-not $aumid) {
    $before = @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $proc = Start-Process -FilePath $info.Target -ArgumentList "-no-remote --profile `"$($info.Profile)`"" -PassThru
    $waited = 0
    while ($waited -lt $LaunchWaitSeconds -and -not $aumid) {
      Start-Sleep -Seconds 3; $waited += 3
      foreach ($fpid in @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)) {
        if ($fpid -in $before) { continue }
        try { $a = [ShortcutAppId]::GetProcessAumid([uint32]$fpid); if ($a) { $aumid = $a; break } } catch {}
      }
    }
    # close ONLY what we spawned
    foreach ($fpid in @(Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id | Where-Object { $_ -in $before -eq $false })) {
      try { Stop-Process -Id $fpid -Force -ErrorAction SilentlyContinue } catch {}
    }
    try { $proc | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
    if ($aumid) { Write-Output "  source : brief launch" }
  }

  if (-not $aumid) { Write-Warning "  could not detect AUMID (is taskbar.grouping.useprofile=true in that profile?)"; continue }

  # 3) stamp every copy + readback
  foreach ($l in $lnks) {
    [ShortcutAppId]::SetAppUserModelId($l, $aumid)
    $back = [ShortcutAppId]::GetAppUserModelId($l)
    $ok = if ($back -eq $aumid) { 'OK' } else { 'FAILED' }
    Write-Output ("  after  : {0,-9} {1}  [{2}]" -f (Split-Path $l -Parent | Split-Path -Leaf), $aumid, $ok)
  }
}
Write-Output ''
Write-Output 'Done. If a pin still focuses the wrong window: unpin/re-pin it once, or restart explorer.'
