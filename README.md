# 🧰 win-toolbox

Portable PowerShell scripts for Windows workstation setup & maintenance.

Download a single script and run — no install needed.

## Scripts

| Folder | Script | Description |
|--------|--------|-------------|
| [`firefox-profile-taskbar/`](./firefox-profile-taskbar/) | `firefox-profile-taskbar.ps1` | Pin multiple Firefox profiles as **separate taskbar icons** |
| [`global-bump-push/`](./global-bump-push/) | `global-bump-push.ps1` | Auto-bump `x.y.z.k` versions across all git repos & push |

## Quick Start

```powershell
# Clone everything
git clone https://github.com/ngojclee/win-toolbox.git
cd win-toolbox

# Or download just one script
irm "https://raw.githubusercontent.com/ngojclee/win-toolbox/main/firefox-profile-taskbar/firefox-profile-taskbar.ps1" -OutFile setup.ps1
powershell -ExecutionPolicy Bypass -File setup.ps1
```

Each script has its own `README.md` inside its folder with full usage docs.

## License

MIT
