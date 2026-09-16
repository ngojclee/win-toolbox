<#
.SYNOPSIS
  Audit every Firefox shortcut/pin: target, profile argument and AppUserModelID —
  and flag the two failure modes that make pins open the wrong profile.

.DESCRIPTION
  Prints one line per Firefox shortcut found on the Desktop and in the taskbar pin
  folder, then flags:
    NO-PROFILE-ARG  the .lnk launches firefox.exe without `--profile` -> Firefox hands
                    the launch over to whatever instance is already running (new tab
                    in the wrong profile). Usually a leftover/stray pin.
    NO-AUMID        profile has no per-profile AUMID -> its pin groups with others;
                    almost always because `taskbar.grouping.useprofile` is not set
                    to true in that profile.
    DUP-AUMID       two shortcuts share an AUMID -> the taskbar cannot tell them apart.
  Exit code: 0 when clean, 1 when any flag was raised (useful in scripts).

.EXAMPLE
  .\list-profile-shortcuts.ps1
.EXAMPLE
  .\list-profile-shortcuts.ps1 -ExeFilter 'Firefox' -Detailed
#>
param(
  [string[]]$Paths = @(
    [Environment]::GetFolderPath('Desktop'),
    "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
  ),
  [string]$NameFilter = 'Firefox*',
  [switch]$Detailed
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
public class LnkAuditRead {
    [ComImport][Guid("00021401-0000-0000-C000-000000000046")] public class ShellLink { }
    [ComImport][InterfaceType(ComInterfaceType.InterfaceIsIUnknown)][Guid("000214F9-0000-0000-C000-000000000046")]
    public interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int c, IntPtr p, uint g);
        void GetIDList(out IntPtr p); void SetIDList(IntPtr p);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder n, int c);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string n);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder d, int c);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string d);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder a, int c);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string a);
        void GetHotkey(out ushort h); void SetHotkey(ushort h);
        void GetShowCmd(out int s); void SetShowCmd(int s);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder p, int c, out int i);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string p, int i);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string p, uint r);
        void Resolve(IntPtr h, uint f);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string f);
    }
    [ComImport][InterfaceType(ComInterfaceType.InterfaceIsIUnknown)][Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    public interface IPropertyStore {
        int GetCount(out uint c); int GetAt(uint i, out PROPERTYKEY k);
        int GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
        int SetValue(ref PROPERTYKEY k, ref PROPVARIANT v); int Commit();
    }
    [StructLayout(LayoutKind.Sequential, Pack = 4)] public struct PROPERTYKEY { public Guid fmtid; public uint pid; }
    [StructLayout(LayoutKind.Sequential)] public struct PROPVARIANT { public ushort vt, r1, r2, r3; public IntPtr p; public int p2; }
    static PROPERTYKEY PKEY = new PROPERTYKEY { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
    public static string Aumid(string path) {
        try {
            var link = (IShellLinkW)new ShellLink();
            ((IPersistFile)link).Load(path, 0);
            var ps = (IPropertyStore)link;
            var pv = new PROPVARIANT(); var key = PKEY;
            if (ps.GetValue(ref key, out pv) == 0 && pv.vt == 31 && pv.p != IntPtr.Zero) return Marshal.PtrToStringUni(pv.p);
        } catch { }
        return null;
    }
}
'@

$sh = New-Object -ComObject WScript.Shell
$rows = @()
foreach ($dir in $Paths) {
  if (-not (Test-Path $dir)) { continue }
  $where = if ($dir -like '*User Pinned*') { 'TASKBAR' } else { 'DESKTOP' }
  foreach ($f in Get-ChildItem $dir -Filter "$NameFilter.lnk" -ErrorAction SilentlyContinue) {
    $l = $sh.CreateShortcut($f.FullName)
    $prof = $null
    if ($l.Arguments -match '--profile\s+"?([^"]+)"?') { $prof = $Matches[1].Trim() }
    $rows += [pscustomobject]@{
      Where   = $where
      Name    = $f.BaseName
      Target  = $l.TargetPath
      Profile = $prof
      Args    = $l.Arguments
      Aumid   = [LnkAuditRead]::Aumid($f.FullName)
      File    = $f.FullName
    }
  }
}
if (-not $rows) { Write-Output "no '$NameFilter.lnk' shortcuts found in: $($Paths -join '; ')"; exit 0 }

# An AUMID is only a problem when DIFFERENT profiles share it (Desktop + TaskBar copies
# of the same profile legitimately carry the same value). Multiple pins for one profile
# are also worth flagging — they confuse the taskbar.
$byAumid = @{}
foreach ($r in $rows) {
  if (-not $r.Aumid) { continue }
  if (-not $byAumid.ContainsKey($r.Aumid)) { $byAumid[$r.Aumid] = @() }
  $byAumid[$r.Aumid] += $r.Profile
}
$dup = @($byAumid.Keys | Where-Object { (@($byAumid[$_] | Sort-Object -Unique)).Count -gt 1 })

$multiPin = @($rows | Where-Object { $_.Where -eq 'TASKBAR' -and $_.Profile } |
  Group-Object Profile | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })

$flags = 0

Write-Output ('{0,-9} {1,-18} {2,-22} {3}' -f 'WHERE', 'NAME', 'AUMID', 'TARGET / PROFILE')
Write-Output ('-' * 110)
foreach ($r in $rows) {
  $a = if ($r.Aumid) { $r.Aumid } else { '<none>' }
  $mark = ''
  if (-not $r.Profile) { $mark += ' NO-PROFILE-ARG'; $flags++ }
  if (-not $r.Aumid)   { $mark += ' NO-AUMID';       $flags++ }
  if ($r.Aumid -and $dup -contains $r.Aumid) { $mark += ' DUP-AUMID'; $flags++ }
  if ($r.Where -eq 'TASKBAR' -and $r.Profile -and $multiPin -contains $r.Profile) { $mark += ' MULTI-PIN'; $flags++ }
  $profTxt = if ($r.Profile) { Split-Path $r.Profile -Leaf } else { '-- no --profile --' }
  Write-Output ('{0,-9} {1,-18} {2,-22} {3}' -f $r.Where, $r.Name, $a, ($profTxt + $mark))
  if ($Detailed) {
    Write-Output ('          target : ' + $r.Target)
    Write-Output ('          args   : ' + $r.Args)
    Write-Output ('          file   : ' + $r.File)
  }
}

Write-Output ''
if ($flags -eq 0) {
  Write-Output ('OK — ' + $rows.Count + ' shortcut(s), every one has a --profile target and a unique AUMID.')
  exit 0
} else {
  Write-Output ("WARNING — $flags flag(s).")
  Write-Output '  NO-PROFILE-ARG : drop the stray shortcut (it hands launches to the running instance).'
  Write-Output '  NO-AUMID       : set taskbar.grouping.useprofile=true in that profile, then re-run fix-taskbar-pin-aumid.ps1.'
  Write-Output '  DUP-AUMID      : two DIFFERENT profiles share one AUMID; re-stamp after fixing the targets.'
  Write-Output '  MULTI-PIN      : one profile is pinned more than once; remove the extra pin.'
  exit 1
}
