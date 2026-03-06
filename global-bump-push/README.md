# Global Version Bump & Push

Scans all git repos under a project root, detects version files, auto-bumps the build number (`k` in `x.y.z.k`), commits, and pushes to GitHub.

## The Problem

When you have 10+ repos, manually bumping versions and pushing each one is tedious and error-prone.

## The Solution

One command bumps all dirty repos at once.

## Supported Version Files

| File | Format | Used By |
|------|--------|---------|
| `manifest.json` | `"version": "x.y.z.k"` | Chrome/Firefox extensions |
| `package.json` | `"version": "x.y.z.k"` | Node.js / Tauri apps |
| `pyproject.toml` | `version = "x.y.z.k"` | Python projects |
| `*.php` (WordPress) | `* Version: x.y.z.k` | WordPress plugins |

## Version Format: `x.y.z.k`

| Segment | Name  | When |
|---------|-------|------|
| `x` | Major | Breaking changes |
| `y` | Minor | New features (reset z, k) |
| `z` | Patch | Bug fixes (reset k) |
| `k` | Build | Auto-incremented on every push |

## Usage

```powershell
# Bump build (k++) for all repos with pending changes
.\global-bump-push.ps1

# Preview only — no changes
.\global-bump-push.ps1 -DryRun

# Sync k = total git commit count
.\global-bump-push.ps1 -Sync

# Bump patch (z++) for all dirty repos
.\global-bump-push.ps1 -Level patch

# Only repos matching a pattern
.\global-bump-push.ps1 -Only "LuxeClaw*"

# Exclude repos matching a pattern
.\global-bump-push.ps1 -Exclude "ARCHIVES*"

# Force bump ALL repos (even clean ones)
.\global-bump-push.ps1 -Force
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Level` | `build\|patch\|minor\|major` | `build` | Which version segment to bump |
| `-DryRun` | switch | off | Preview changes without writing |
| `-Sync` | switch | off | Set `k` = total git commit count |
| `-Force` | switch | off | Bump all repos, not just dirty ones |
| `-Only` | string | `""` | Glob filter for repo names |
| `-Exclude` | string | `""` | Glob pattern to exclude |
| `-ProjectsRoot` | string | `D:\Python\projects` | Root directory to scan |

## What It Does

1. Finds all `.git` directories with GitHub remotes under `ProjectsRoot`
2. Skips clean repos (unless `-Force`)
3. Detects version files (manifest.json, package.json, pyproject.toml, *.php)
4. Bumps version according to `-Level`
5. Commits with message like `chore: bump version [build] → manifest.json:1.0.0.5`
6. Pushes to `origin main`

## Example Output

```
🌍 Global Version Bump Tool
Level: build
Smart: only repos with pending changes
Root: D:\Python\projects

Found 12 git repos with remotes

----------------------------------------------------------------------
📦 LuxeClaw/Extension/Firefox/ContainerInspector
   manifest.json : 1.0.0.6 → 1.0.0.7
   ⬆️ Pushed (a3b8d1b)
📦 LuxeClaw/Deployer
   package.json : 1.2.0.3 → 1.2.0.4
   pyproject.toml : 1.2.0.3 → 1.2.0.4
   ⬆️ Pushed (f81d4fa)
----------------------------------------------------------------------

📊 Total: 3 version files bumped in 2 repos
✅ All done!
```

## Customization

To change the default project root, edit the `$ProjectsRoot` parameter default in the script, or pass it via command line:

```powershell
.\global-bump-push.ps1 -ProjectsRoot "C:\MyProjects"
```
