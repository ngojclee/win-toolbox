# 🧰 win-toolbox

Portable PowerShell scripts for Windows workstation setup & maintenance.

Download a single script and run — no install needed.

## Scripts

| Folder | Script | Description |
|--------|--------|-------------|
| [`firefox-profile-taskbar/`](./firefox-profile-taskbar/) | `firefox-profile-taskbar.ps1` | Pin multiple Firefox profiles as **separate taskbar icons** |
| [`global-bump-push/`](./global-bump-push/) | `global-bump-push.ps1` | Auto-bump `x.y.z.k` versions across all git repos & push |

## Firefox Extensions

| Extension | Version | Install |
|-----------|---------|---------|
| [Container Inspector](./firefox-extensions/container-inspector/) | 1.0.0.7 | [⬇️ Install XPI](https://github.com/ngojclee/win-toolbox/releases/download/container-inspector-v1.0.0.7/container-inspector-1.0.0.7.xpi) |

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
