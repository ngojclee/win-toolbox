# RDP Secure Setup — Netbird Integration

Lock down Windows RDP so **only your Netbird peers** can connect. Non-standard port, dedicated user, IP whitelist — no credentials stored.

## Security Layers

```
┌───────────────────────────────────────────┐
│  Layer 1: Port 33389 (not default 3389)   │  Avoids 99% of bot scanners
│  Layer 2: Firewall IP whitelist           │  Only Netbird peers allowed
│  Layer 3: Dedicated "rdp" user            │  Separate account (admin optional)
│  Layer 4: Netbird VPN tunnel              │  Already encrypted + auth'd
└───────────────────────────────────────────┘
```

## How It Works

```
┌─────────────────────────────────────────────────┐
│             First Run (no state file)           │
│                                                 │
│  1. Enable RDP service                          │
│  2. Change port 3389 → 33389 (or custom)        │
│  3. Ask: allow blank password? (y/n)            │
│  4. Create dedicated RDP user (optional)        │
│  5. Query Netbird peers → pick which IPs        │
│  6. Create firewall rules (Allow + Block)       │
│  7. Save state to ProgramData                   │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│           Subsequent Runs (state exists)        │
│                                                 │
│  Shows current config summary, then menu:       │
│  [1] Toggle peers from Netbird                  │
│  [2] Add IP manually                            │
│  [3] Change RDP port                            │
│  [4] Toggle blank password policy               │
│  [5] Manage RDP user                            │
│  [6] Full reset → re-run First Run              │
└─────────────────────────────────────────────────┘
```

## Requirements

- **Windows 10 / 11**
- **PowerShell 5.1+**
- **Administrator** privileges
- **Netbird** installed and connected (for peer auto-detection)

## Quick Start

### Option A — Clone the whole toolbox

```powershell
git clone https://github.com/ngojclee/win-toolbox.git
cd win-toolbox\rdp-netbird-setup
powershell -ExecutionPolicy Bypass -File rdp-netbird-setup.ps1
```

### Option B — Download just this script

```powershell
irm "https://raw.githubusercontent.com/ngojclee/win-toolbox/main/rdp-netbird-setup/rdp-netbird-setup.ps1" -OutFile rdp-setup.ps1
powershell -ExecutionPolicy Bypass -File rdp-setup.ps1
```

## First Run Walkthrough

The script guides you through 5 steps:

```
====================================================
  First Run - Cau Hinh Ban Dau
====================================================

[1/5] Bat RDP...
  [OK] RDP da duoc bat.

[2/5] Doi port RDP...
  Port RDP hien tai: 3389
  Port khuyen nghi : 33389 (tranh scanner, de nho)
  Nhap port moi (Enter = 33389):
  Port: ↵
  [OK] RDP port da doi thanh 33389

[3/5] Blank password policy...
  Cho phep RDP bang tai khoan khong co mat khau?
  (y/n): y

[4/5] Cau hinh user RDP...
  [1] Tao user rieng (khuyen nghi)
  [2] Dung user hien tai (MyUser)
  Chon (Enter = 1): ↵
  Nhap ten user RDP (Enter = 'louis-rdp'):
  Username: ↵
  Cho user 'louis-rdp' quyen Administrator?
  Cho Admin? (y/n, Enter = n): ↵
  [OK] Tao user 'louis-rdp' (khong mat khau).
  [OK] Da them 'louis-rdp' vao Remote Desktop Users.

[5/5] Chon may duoc phep RDP vao may nay...
  [  0]  >>> CHON TAT CA (2 peers Connected) <<<

  [ 1]  [ON]  desktop-home.netbird.cloud          100.64.0.1
  [ 2]  [ON]  laptop-work.netbird.cloud            100.64.0.2
  Enter = chon tat ca Connected
  Chon (Enter = all): ↵
  [OK] Da chon tat ca 2 peers Connected.
```

## Config Summary

After setup, you'll see a summary box:

```
  ┌──────────────────────────────────────────────┐
  │          CAU HINH HIEN TAI                   │
  ├──────────────────────────────────────────────┤
  │  RDP Port      : 33389                      │
  │  RDP User      : louis-rdp                    │
  │  Blank password : Cho phep                   │
  │  IP whitelisted : 2                          │
  │                                              │
  │    - 100.64.0.1                              │
  │    - 100.64.0.2                              │
  └──────────────────────────────────────────────┘

  >> Ket noi: mstsc /v:<IP>:33389
     User   : louis-rdp
     Vi du  : mstsc /v:100.64.0.1:33389
```

## What the Script Does

| Action | Detail |
|--------|--------|
| **Enable RDP** | Sets `fDenyTSConnections = 0`, starts `TermService` |
| **Change port** | Modifies `PortNumber` in `HKLM:\...\RDP-Tcp`, restarts TermService |
| **Blank password** | Toggles `LimitBlankPasswordUse` in `HKLM:\...\Lsa` |
| **Create user** | `net user louis-rdp /add` + `Remote Desktop Users` (optionally `Administrators`) |
| **Firewall Allow** | Creates rule `RDP - Allowed IPs Only` (TCP on custom port, whitelisted IPs) |
| **Firewall Block** | Creates rule `RDP - Block All Others` (TCP on custom port, block everything else) |
| **State file** | Saves config to `%ProgramData%\rdp-netbird-setup\state.json` |
| **Group Policy** | Runs `gpupdate /force` after first setup |

## RDP User Details

The dedicated RDP user is:

| Property | Value |
|----------|-------|
| **Default name** | `louis-rdp` (customizable) |
| **Group** | `Remote Desktop Users` |
| **Admin rights** | Optional — script asks during setup (default: **no**) |
| **Password** | Blank (if allowed) or user-set |
| **Expiry** | Password never expires |

> 💡 **Tip**: Use the same username (`louis-rdp`) across all your machines for consistency. Every prompt has a sensible default—just press Enter through everything for a quick setup.
>
> You don't need to log into the `louis-rdp` user locally — just RDP in remotely. Your main local account stays separate.

## Port Configuration

| Setting | Value |
|---------|-------|
| **Default port** | `33389` (not the standard `3389`) |
| **Range** | `1024-65535` |
| **Reserved ports** | Script warns about well-known ports (80, 443, 22, etc.) |

> ⚠️ **After changing port**: You must specify the port when connecting: `mstsc /v:100.64.0.1:33389`

## Firewall Rules

Two Windows Firewall rules work together:

1. **`RDP - Allowed IPs Only`** — Allow TCP on custom port from whitelisted Netbird IPs
2. **`RDP - Block All Others`** — Block TCP on custom port from all other sources

Windows evaluates Allow rules before Block rules, so only your selected peers get through.

> ⚠️ **If the whitelist is empty**, no firewall rules are created and RDP is open to all IPs. The script warns you about this.

## Security Notes

| Item | Detail |
|------|--------|
| **No credentials stored** | Safe for public repos — all config is interactive |
| **Dedicated user** | `rdp` user is separate from main account; admin rights optional |
| **Non-standard port** | Eliminates automated scanner traffic |
| **Blank password risk** | Only enable if your machine is exclusively behind Netbird VPN |
| **State file** | Contains only: flags, port, username, IP list, timestamp |
| **Admin required** | Script modifies firewall, registry, user accounts — must run elevated |

## Without Netbird

If Netbird CLI is not found or returns no peers, the script falls back to **manual IP entry**. You can use it to whitelist any IP addresses for RDP access.

## Re-Running

Run anytime. The script detects the existing state file and shows the management menu. Use **option 6** to fully reset and start over.

## File Locations

| File | Path |
|------|------|
| Script | `rdp-netbird-setup.ps1` (portable) |
| State | `%ProgramData%\rdp-netbird-setup\state.json` |
| FW Rule 1 | `RDP - Allowed IPs Only` |
| FW Rule 2 | `RDP - Block All Others` |

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Khong tim thay Netbird CLI" | Install Netbird or add it to PATH |
| Can't connect after port change | Use `mstsc /v:<IP>:<port>` — port is required |
| Peers show `[OFF]` | Peer is registered but not currently connected |
| RDP still blocked after adding IP | Check `wf.msc` → Inbound Rules for conflicts with old port |
| Can't connect with blank password | Ensure option was set to `y` and `gpupdate` ran |
| User `louis-rdp` can't log in | Check user is in `Remote Desktop Users`: `net localgroup "Remote Desktop Users"` |
| Want to undo everything | Run script → option 6 (reset), then manually delete user & FW rules |
| Forgot the port | Check state: `type %ProgramData%\rdp-netbird-setup\state.json` |
