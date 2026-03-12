# RDP Secure Setup — Netbird Integration

Lock down Windows RDP so **only your Netbird peers** can connect. No credentials stored, no hardcoded IPs.

## How It Works

```
┌─────────────────────────────────────────────────┐
│             First Run (no state file)           │
│                                                 │
│  1. Enable RDP service                          │
│  2. Ask: allow blank password? (y/n)            │
│  3. Query Netbird peers → pick which IPs        │
│  4. Create firewall rules (Allow + Block)       │
│  5. Save state to ProgramData                   │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│           Subsequent Runs (state exists)        │
│                                                 │
│  Shows current config, then menu:               │
│  [1] Toggle peers from Netbird                  │
│  [2] Add IP manually                            │
│  [3] View current whitelist                     │
│  [4] Toggle blank password policy               │
│  [5] Full reset → re-run First Run              │
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

The script guides you through 3 steps:

```
====================================================
  First Run - Cau Hinh Ban Dau
====================================================

[1/3] Bat RDP...
  [OK] RDP da duoc bat.

[2/3] Blank password policy...
  Cho phep RDP bang tai khoan khong co mat khau?
  (Chi nen bat neu may nay trong LAN + da dung Netbird gioi han IP)
  (y/n): n

[3/3] Chon may duoc phep RDP vao may nay...
  Peers hien co trong Netbird:

  [ 1]  [ON]  desktop-home.netbird.cloud          100.64.0.1
  [ 2]  [ON]  laptop-work.netbird.cloud            100.64.0.2
  [ 3]* [OFF] server-old.netbird.cloud             100.64.0.3

  Nhap so de TOGGLE: 1 2
```

## Subsequent Runs — Peer Management

```
====================================================
  Quan Ly Peers RDP
====================================================

  Cau hinh hien tai:
  Blank password : Khoa
  So IP trong list: 2
  Cap nhat lan cuoi: 2026-03-12 09:15:00

  [1] Them / Bo peer (query Netbird)
  [2] Nhap IP thu cong
  [3] Xem danh sach IP hien tai
  [4] Doi cau hinh blank password
  [5] Reset - chay lai First Run

  Chon (1-5):
```

## What the Script Does

| Action | Detail |
|--------|--------|
| **Enable RDP** | Sets `fDenyTSConnections = 0`, starts `TermService` |
| **Blank password** | Toggles `LimitBlankPasswordUse` in `HKLM:\...\Lsa` |
| **Firewall Allow** | Creates rule `RDP - Allowed IPs Only` (TCP 3389, whitelisted IPs) |
| **Firewall Block** | Creates rule `RDP - Block All Others` (TCP 3389, block everything else) |
| **State file** | Saves config to `%ProgramData%\rdp-netbird-setup\state.json` |
| **Group Policy** | Runs `gpupdate /force` after first setup |

## Firewall Rules

The script creates **two** Windows Firewall rules that work together:

1. **`RDP - Allowed IPs Only`** — Allow TCP 3389 from whitelisted Netbird IPs
2. **`RDP - Block All Others`** — Block TCP 3389 from all other sources

Windows evaluates Allow rules before Block rules, so only your selected peers get through.

> ⚠️ **If the whitelist is empty**, no firewall rules are created and RDP is open to all IPs. The script warns you about this.

## Security Notes

| Item | Detail |
|------|--------|
| **No credentials stored** | Safe for public repos — all config is interactive |
| **Blank password risk** | Only enable if your machine is exclusively behind Netbird VPN |
| **State file** | Contains only: `configured` flag, `allowBlank` bool, IP list, timestamp |
| **Admin required** | Script modifies firewall rules and registry — must run elevated |
| **Netbird dependency** | IPs come from Netbird peers; if Netbird is not running, you can enter IPs manually |

## Without Netbird

If Netbird CLI is not found or returns no peers, the script falls back to **manual IP entry**. You can use it to whitelist any IP addresses for RDP access.

## Re-Running

You can re-run anytime. The script detects the existing state file and skips initial setup, going straight to the peer management menu. Use **option 5** to fully reset and start over.

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
| Peers show `[OFF]` | Peer is registered but not currently connected |
| RDP still blocked after adding IP | Check `wf.msc` → Inbound Rules for conflicts |
| Can't connect with blank password | Ensure option was set to `y` and `gpupdate` ran |
| Want to undo everything | Run script → option 5 (reset), then manually delete FW rules |
