# 🧰 win-toolbox

Portable Windows scripts (PowerShell 5.1+) for workstation setup & maintenance.

Download one script and run it. Nothing to install, no module dependencies, no service to keep alive.

> **No credentials in this repo.** Anything that needs a password, hash, token or secret reads it from a
> file or an environment variable; the docs use placeholders like `<USER>`, `<PANEL_PORT>`, `<scrypt-hash>`.
> Replace them locally — never commit the real values.

## Contents

| Folder | Entry points | What it does |
|--------|--------------|--------------|
| [`firefox-profile-taskbar/`](./firefox-profile-taskbar/) | `firefox-profile-taskbar.ps1` + 4 helpers | Pin each Firefox profile as its **own taskbar icon** (per-profile AUMID, junction + `-no-remote`) |
| [`global-bump-push/`](./global-bump-push/) | `global-bump-push.ps1` | Auto-bump `x.y.z.k` across every git repo under a root, commit and push |
| [`hermes-gateway-windows/`](./hermes-gateway-windows/) | *(docs only)* | Run **Hermes Agent** unattended: hidden dashboard task + scrypt auth, gateway autostart map, log hygiene |
| [`nilesoft-shell-fix/`](./nilesoft-shell-fix/) | `fix-win11-taskbar-menu.ps1` | Fix Win11 / Nilesoft Shell taskbar menu labels and clipped text (`-LabelsOnly`, `-RestartExplorer`) |
| [`rdp-netbird-setup/`](./rdp-netbird-setup/) | `rdp-netbird-setup.ps1` | Lock RDP down to **Netbird peers only**: custom port, firewall IP whitelist, dedicated user, no stored credentials |

Every folder has its own `README.md` with the full usage docs, parameters and pitfalls.

### `firefox-profile-taskbar/`

| Script | Purpose |
|--------|---------|
| `firefox-profile-taskbar.ps1` | Main setup — one taskbar identity + shortcut per profile |
| `new-profile-shortcuts.ps1` | Create/repair shortcuts for **any number** of profiles in one pass (`-EmbedAumid` optional) |
| `recreate-profile-shortcut.ps1` | Rebuild a single shortcut (no console stub, no wrong-profile handover) |
| `list-profile-shortcuts.ps1` | Audit Desktop + taskbar pins; flags `NO-PROFILE-ARG`, `NO-AUMID`, `DUP-AUMID` (exit 1 when dirty) |
| `fix-taskbar-pin-aumid.ps1` | Repair pins that focus the wrong profile window (stale per-profile AUMID) |

Reading: [`CREATE-SHORTCUTS.md`](./firefox-profile-taskbar/CREATE-SHORTCUTS.md) (end-to-end guide) and
[`manual-profile-shortcut.md`](./firefox-profile-taskbar/manual-profile-shortcut.md) (why it works).

### `nilesoft-shell-fix/`

| Script | Purpose |
|--------|---------|
| `fix-win11-taskbar-menu.ps1` | Main fix — missing Nilesoft `title.*` labels **and** clipped menu text (Windows `MenuWidth`/`MenuHeight` metrics) |
| `fix-nilesoft-labels.ps1` | Legacy wrapper, calls the main script with `-LabelsOnly` |

## Portable binaries

Some Windows apps publish their installers through this repo's releases (no source folder here):

| App | Latest |
|-----|--------|
| **LightroomSync** — Lightroom catalog & presets sync over NAS/SMB | [v2.0.7](https://github.com/ngojclee/win-toolbox/releases?q=LightroomSync) |

## Quick start

```powershell
# Clone everything
git clone https://github.com/ngojclee/win-toolbox.git
cd win-toolbox

# …or fetch a single script and run it
irm "https://raw.githubusercontent.com/ngojclee/win-toolbox/main/firefox-profile-taskbar/firefox-profile-taskbar.ps1" -OutFile setup.ps1
powershell -ExecutionPolicy Bypass -File setup.ps1
```

Scripts that change machine state (RDP/firewall, Explorer restart, scheduled tasks) request elevation
themselves — read the folder `README.md` first, they document the rollback path.

## Related repos

| Repo | Visibility | Role |
|------|:---:|------|
| `ngojclee/LNC-Extensions` | private | Firefox/Chrome extension source, signed-XPI archive — extensions are **not** distributed publicly |
| `ngojclee/win-toolbox-private` | private | Machine-specific provisioning (setup keys, tokens, internal configs) — deliberately **not** here |

## License

MIT — see [LICENSE](./LICENSE).
