# Container Inspector (Firefox Extension)

Display Firefox container IDs for easy FoxyProxy mapping and management.

## Install

**[⬇️ Install Container Inspector v1.0.0.7](https://github.com/ngojclee/win-toolbox/releases/download/container-inspector-v1.0.0.7/container-inspector-1.0.0.7.xpi)**

Click the link above in Firefox → Accept install prompt → Done!

> **Auto-updates**: Firefox automatically checks `updates.json` for new versions.

## Manual Install

1. Download the `.xpi` file from [Releases](https://github.com/ngojclee/win-toolbox/releases?q=container-inspector)
2. In Firefox: `about:addons` → ⚙️ → **"Install Add-on From File..."**
3. Select the `.xpi` file

## Features

- 🔍 View all Firefox containers with their IDs
- 📋 Copy container IDs to clipboard (for FoxyProxy config)
- 🎨 Color-coded display matching Firefox container colors
- 📦 Export all containers to JSON
- 🔄 Live updates when containers change

## Update Process

When a new version is released:

1. Upload signed `.xpi` to AMO (unlisted)
2. Download signed `.xpi` from AMO Developer Hub
3. Create new GitHub Release: `gh release create container-inspector-vX.Y.Z.K ./file.xpi --repo ngojclee/win-toolbox`
4. Update `updates.json` in this folder with new version + link
5. Push → Firefox auto-updates on all machines

## Source Code

[github.com/ngojclee/Luxeclaw-Extension](https://github.com/ngojclee/Luxeclaw-Extension) (private)
