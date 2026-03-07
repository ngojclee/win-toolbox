# LuxeClaw-Proxy (Firefox Extension)

Privacy-focused proxy manager with timezone/geolocation spoofing and GitHub Gist sync.

> **⚠️ Currently unsigned.** Requires Firefox Developer Edition, Nightly, or ESR.

## Install (Dev/Nightly/ESR)

**[⬇️ Download LuxeClaw-Proxy v1.1.0.0 (unsigned)](https://github.com/ngojclee/win-toolbox/releases/download/luxeclaw-proxy-v1.1.0.0-unsigned/luxeclaw-proxy-1.1.0.0-unsigned.xpi)**

### Prerequisites

1. Use **Firefox Developer Edition**, **Nightly**, or **ESR**
2. Go to `about:config` → set `xpinstall.signatures.required` = `false`
3. Download the `.xpi` file
4. In Firefox: `about:addons` → ⚙️ → **"Install Add-on From File..."** → select `.xpi`

> Firefox Release (standard) does NOT support unsigned extensions.

## Features

- 🔒 **Proxy Management** — Full proxy configuration (HTTP/HTTPS/SOCKS4/SOCKS5)
- 🌍 **Timezone Spoofing** — Auto-detect timezone from proxy location, override Date/Intl APIs
- 📍 **Geolocation Spoofing** — Spoof navigator.geolocation based on proxy geo
- 🗣️ **Language Spoofing** — Override navigator.language + Accept-Language header
- 🛡️ **WebRTC Protection** — Auto-disable non-proxied UDP to prevent IP leaks
- 🔐 **DNS Protection** — Disable DNS prefetching when proxy is active
- ☁️ **GitHub Gist Sync** — Sync proxy config across machines via private GitHub Gist
- 🔗 **Container Inspector Integration** — Export/import proxy config from Container Inspector
- 🎨 **Dark/Light Theme** — Follows Firefox theme

## Architecture

Based on FoxyProxy with additional privacy and sync features:

| Component | Description |
|-----------|-------------|
| `background.js` | Core proxy engine, spoof config, DNS/WebRTC protection |
| `privacy-injector.js` | Content script — injects spoof config into page |
| `privacy-spoof.js` | MAIN world script — overrides Date/Intl/Geolocation APIs |
| `gist-sync.js` | GitHub Gist sync module |
| `popup.html/js` | Quick proxy switch popup |
| `options.html/js` | Full settings page |

## Update Process

1. Build: `npx web-ext build --source-dir . --artifacts-dir ./web-ext-artifacts`
2. Rename `.zip` to `.xpi`
3. Create GitHub Release: `gh release create luxeclaw-proxy-vX.Y.Z.K-unsigned ./file.xpi --repo ngojclee/win-toolbox`
4. Update `updates.json` in this folder
5. Push

## Source Code

[github.com/ngojclee/Luxeclaw-Extension](https://github.com/ngojclee/Luxeclaw-Extension) (private)
