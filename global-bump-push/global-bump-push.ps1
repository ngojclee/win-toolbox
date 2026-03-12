#!/usr/bin/env pwsh
# ==============================================================
# Global Version Bump & Git Push — All Projects
# ==============================================================
# Scans D:\Python\projects (depth 4) for ALL git repos with GitHub remotes,
# including nested repos (e.g. LuxeClaw\LuxeClaw-Portable).
# detects version files, bumps version k, commits & pushes.
#
# Supports:
#   - manifest.json          (Chrome/Firefox extensions)
#   - package.json           (Node.js apps)
#   - pyproject.toml         (Python projects)
#   - WordPress plugin .php  (Version: x.y.z.k in header)
#   - Python *.py             (APP_VERSION = "x.y.z.k")
#
# Usage:
#   .\scripts\global-bump-push.ps1                           → bump k for ALL repos
#   .\scripts\global-bump-push.ps1 -DryRun                   → preview only
#   .\scripts\global-bump-push.ps1 -Sync                     → sync k = git commit count
#   .\scripts\global-bump-push.ps1 -Level patch              → bump z (reset k)
#   .\scripts\global-bump-push.ps1 -Only "LuxeClaw*"         → filter by name pattern
#   .\scripts\global-bump-push.ps1 -Exclude "ARCHIVES*"      → exclude pattern
# ==============================================================

param(
    [ValidateSet("build", "patch", "minor", "major")]
    [string]$Level = "build",

    [switch]$DryRun,
    [switch]$Sync,
    [switch]$Force,  # Force bump ALL repos even if clean

    [string]$Only = "",
    [string]$Exclude = "",

    [string]$ProjectsRoot = "D:\Python\projects"
)

$ErrorActionPreference = "Stop"

# ── Helper: Bump version string ──
function Bump-Version {
    param(
        [int]$x, [int]$y, [int]$z, [int]$k,
        [string]$Level,
        [switch]$SyncMode,
        [int]$CommitCount = 0
    )

    if ($SyncMode) {
        $k = $CommitCount
    }
    else {
        switch ($Level) {
            "build" { $k++ }
            "patch" { $z++; $k = 0 }
            "minor" { $y++; $z = 0; $k = 0 }
            "major" { $x++; $y = 0; $z = 0; $k = 0 }
        }
    }

    return @{ x = $x; y = $y; z = $z; k = $k; version = "$x.$y.$z.$k" }
}

# ── Helper: Parse x.y.z or x.y.z.k version ──
function Parse-Version {
    param([string]$ver)
    if ($ver -match '^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?$') {
        return @{
            x = [int]$Matches[1]
            y = [int]$Matches[2]
            z = [int]$Matches[3]
            k = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
        }
    }
    return $null
}

Write-Host "`n🌍 Global Version Bump Tool" -ForegroundColor Cyan
if ($Sync) {
    Write-Host "Mode: SYNC (k = git commit count)" -ForegroundColor Magenta
}
else {
    Write-Host "Level: $Level" -ForegroundColor Gray
}
if ($Force) {
    Write-Host "⚡ FORCE: bumping ALL repos" -ForegroundColor Yellow
}
else {
    Write-Host "Smart: only repos with pending changes" -ForegroundColor Gray
}
Write-Host "Root: $ProjectsRoot`n" -ForegroundColor Gray

# ── 1. Find all git repos with GitHub remotes ──
# Use -Force (not -Hidden) to catch .git dirs regardless of Hidden attribute
$gitDirs = Get-ChildItem -Path $ProjectsRoot -Directory -Recurse -Depth 4 -Filter ".git" -Force -ErrorAction SilentlyContinue
$repoResults = @()

foreach ($gd in $gitDirs) {
    $repoPath = $gd.Parent.FullName
    $relPath = $repoPath.Substring($ProjectsRoot.Length + 1)

    # Filter by -Only / -Exclude (match against full relPath OR repo folder name)
    $repoName = Split-Path $repoPath -Leaf
    if ($Only -and ($relPath -notlike $Only) -and ($repoName -notlike $Only)) { continue }
    if ($Exclude -and (($relPath -like $Exclude) -or ($repoName -like $Exclude))) { continue }

    # Must have a GitHub remote
    $remote = git -C $repoPath remote get-url origin 2>$null
    if (-not $remote) { continue }

    # Check if there are uncommitted changes or if the repo is clean
    $repoResults += @{
        Path    = $repoPath
        RelPath = $relPath
        Remote  = $remote
    }
}

if ($repoResults.Count -eq 0) {
    Write-Host "❌ No matching git repos found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($repoResults.Count) git repos with remotes`n" -ForegroundColor Gray
Write-Host ("-" * 70) -ForegroundColor DarkGray

$totalBumped = 0
$totalRepos = 0
$skippedClean = 0

foreach ($repo in $repoResults) {
    $repoPath = $repo.Path
    $relPath = $repo.RelPath

    # ── Check if repo has actual changes (skip clean repos) ──
    if (-not $Force) {
        $dirtyFiles = git -C $repoPath status --porcelain 2>$null
        if (-not $dirtyFiles) {
            $skippedClean++
            continue  # No pending changes → skip
        }
    }

    # ── Detect version files ──
    $bumped = $false
    $versionChanges = @()

    # ────────────────────────────────────────────
    # A. Chrome/Firefox Extensions (manifest.json)
    # ────────────────────────────────────────────
    $manifests = Get-ChildItem -Path $repoPath -Filter "manifest.json" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
    Where-Object {
        $rel = $_.FullName.Substring($repoPath.Length + 1)
        $rel -notmatch "(node_modules|\.git|sel-pro)" -and
        (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match '"manifest_version"'
    }

    foreach ($m in $manifests) {
        $content = Get-Content $m.FullName -Raw
        if ($content -match '"version"\s*:\s*"([\d.]+)"') {
            $oldVer = $Matches[1]
            $parsed = Parse-Version $oldVer
            if (-not $parsed) { continue }

            $extDir = $m.DirectoryName.Substring($repoPath.Length + 1)
            $commitCount = (git -C $repoPath log --oneline -- "$extDir" 2>$null | Measure-Object).Count

            $new = Bump-Version -x $parsed.x -y $parsed.y -z $parsed.z -k $parsed.k `
                -Level $Level -SyncMode:$Sync -CommitCount $commitCount

            if ($oldVer -ne $new.version -or "$($parsed.x).$($parsed.y).$($parsed.z).$($parsed.k)" -ne $new.version) {
                $content = $content -replace '"version"\s*:\s*"[\d.]+?"', "`"version`": `"$($new.version)`""
                if (-not $DryRun) { $content | Set-Content $m.FullName -NoNewline }
                $bumped = $true
            }
            $versionChanges += "$extDir : $oldVer → $($new.version)"
        }
    }

    # ────────────────────────────────────────────
    # B. Node.js (package.json at root)
    # ────────────────────────────────────────────
    $pkgPath = Join-Path $repoPath "package.json"
    if (Test-Path $pkgPath) {
        $content = Get-Content $pkgPath -Raw
        # Match "version": "x.y.z" or "x.y.z-k"
        if ($content -match '"version"\s*:\s*"([\d.]+)"') {
            $oldVer = $Matches[1]
            $parsed = Parse-Version $oldVer
            if ($parsed) {
                $commitCount = (git -C $repoPath log --oneline 2>$null | Measure-Object).Count
                $new = Bump-Version -x $parsed.x -y $parsed.y -z $parsed.z -k $parsed.k `
                    -Level $Level -SyncMode:$Sync -CommitCount $commitCount

                if ("$($parsed.x).$($parsed.y).$($parsed.z).$($parsed.k)" -ne $new.version) {
                    $content = $content -replace '("version"\s*:\s*")[\d.]+(")' , "`${1}$($new.version)`${2}"
                    if (-not $DryRun) { $content | Set-Content $pkgPath -NoNewline }
                    $bumped = $true
                }
                $versionChanges += "package.json : $oldVer → $($new.version)"
            }
        }
    }

    # ────────────────────────────────────────────
    # C. Python (pyproject.toml)
    # ────────────────────────────────────────────
    $pyprojectPath = Join-Path $repoPath "pyproject.toml"
    if (Test-Path $pyprojectPath) {
        $content = Get-Content $pyprojectPath -Raw
        if ($content -match 'version\s*=\s*"([\d.]+)"') {
            $oldVer = $Matches[1]
            $parsed = Parse-Version $oldVer
            if ($parsed) {
                $commitCount = (git -C $repoPath log --oneline 2>$null | Measure-Object).Count
                $new = Bump-Version -x $parsed.x -y $parsed.y -z $parsed.z -k $parsed.k `
                    -Level $Level -SyncMode:$Sync -CommitCount $commitCount

                if ("$($parsed.x).$($parsed.y).$($parsed.z).$($parsed.k)" -ne $new.version) {
                    $content = $content -replace '(version\s*=\s*")[\d.]+(")' , "`${1}$($new.version)`${2}"
                    if (-not $DryRun) { $content | Set-Content $pyprojectPath -NoNewline }
                    $bumped = $true
                }
                $versionChanges += "pyproject.toml : $oldVer → $($new.version)"
            }
        }
    }

    # ────────────────────────────────────────────
    # D. WordPress Plugins (*.php with Version: header)
    # ────────────────────────────────────────────
    $wpPlugins = Get-ChildItem "$repoPath\*.php" -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match '\*\s*Version:\s*[\d.]+' }

    foreach ($wp in $wpPlugins) {
        $content = Get-Content $wp.FullName -Raw
        if ($content -match '\*\s*Version:\s*([\d.]+)') {
            $oldVer = $Matches[1]
            $parsed = Parse-Version $oldVer
            if (-not $parsed) { continue }

            $commitCount = (git -C $repoPath log --oneline 2>$null | Measure-Object).Count
            $new = Bump-Version -x $parsed.x -y $parsed.y -z $parsed.z -k $parsed.k `
                -Level $Level -SyncMode:$Sync -CommitCount $commitCount

            if ("$($parsed.x).$($parsed.y).$($parsed.z).$($parsed.k)" -ne $new.version) {
                # Update plugin header
                $content = $content -replace '(\*\s*Version:\s*)[\d.]+', "`${1}$($new.version)"
                # Also update define() constant if present, e.g. define('PLUGIN_VERSION', 'x.y.z.k')
                $content = $content -replace "(\bdefine\s*\(\s*'[A-Z_]*VERSION'\s*,\s*')[\d.]+(')", "`${1}$($new.version)`${2}"
                if (-not $DryRun) { $content | Set-Content $wp.FullName -NoNewline }
                $bumped = $true
            }
            $versionChanges += "$($wp.Name) : $oldVer → $($new.version)"
        }
    }

    # ────────────────────────────────────────────
    # E. Python APP_VERSION (APP_VERSION = "x.y.z.k" in .py files)
    # ────────────────────────────────────────────
    $pyVersionFiles = Get-ChildItem -Path $repoPath -Filter "*.py" -Recurse -Depth 3 -ErrorAction SilentlyContinue |
    Where-Object {
        $rel = $_.FullName.Substring($repoPath.Length + 1)
        $rel -notmatch "(node_modules|\.git|__pycache__|\.venv|build|dist)" -and
        (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'APP_VERSION\s*=\s*"[\d.]+"'
    }

    foreach ($pyf in $pyVersionFiles) {
        $content = Get-Content $pyf.FullName -Raw
        if ($content -match 'APP_VERSION\s*=\s*"([\d.]+)"') {
            $oldVer = $Matches[1]
            $parsed = Parse-Version $oldVer
            if (-not $parsed) { continue }

            $commitCount = (git -C $repoPath log --oneline 2>$null | Measure-Object).Count
            $new = Bump-Version -x $parsed.x -y $parsed.y -z $parsed.z -k $parsed.k `
                -Level $Level -SyncMode:$Sync -CommitCount $commitCount

            if ("$($parsed.x).$($parsed.y).$($parsed.z).$($parsed.k)" -ne $new.version) {
                $content = $content -replace '(APP_VERSION\s*=\s*")[\d.]+(")', "`${1}$($new.version)`${2}"
                if (-not $DryRun) { $content | Set-Content $pyf.FullName -NoNewline }
                $bumped = $true
            }
            $relFile = $pyf.FullName.Substring($repoPath.Length + 1)
            $versionChanges += "$relFile : $oldVer → $($new.version)"
        }
    }
    # ── Display results for this repo ──
    if ($versionChanges.Count -gt 0) {
        $totalRepos++
        $icon = if ($bumped) { "📦" } else { "⏸️" }
        Write-Host "$icon $relPath" -ForegroundColor $(if ($bumped) { "White" } else { "Gray" })
        foreach ($vc in $versionChanges) {
            $totalBumped++
            Write-Host "   $vc" -ForegroundColor Green
        }
    }

    # ── Git commit & push (per repo) ──
    if ($bumped -and -not $DryRun) {
        Push-Location $repoPath
        try {
            git add -A 2>$null

            $vSummary = ($versionChanges | ForEach-Object { ($_ -split " : ")[0] + ":" + (($_ -split "→ ")[-1]).Trim() }) -join ", "
            $msg = if ($Sync) {
                "chore: sync version [k=$Level] → $vSummary"
            }
            else {
                "chore: bump version [$Level] → $vSummary"
            }

            git commit -m $msg 2>$null
            if ($LASTEXITCODE -eq 0) {
                git push origin main 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $hash = (git rev-parse --short HEAD)
                    Write-Host "   ⬆️ Pushed ($hash)" -ForegroundColor Cyan
                }
                else {
                    Write-Host "   ❌ Push failed!" -ForegroundColor Red
                }
            }
            else {
                Write-Host "   ⚠️ Nothing to commit" -ForegroundColor Yellow
            }
        }
        finally {
            Pop-Location
        }
    }
}

Write-Host ("-" * 70) -ForegroundColor DarkGray
Write-Host "`n📊 Total: $totalBumped version files bumped in $totalRepos repos" -ForegroundColor Cyan
if ($skippedClean -gt 0) {
    Write-Host "⏭️ Skipped $skippedClean clean repos (no pending changes)" -ForegroundColor Gray
    Write-Host "   Use -Force to bump all repos regardless" -ForegroundColor DarkGray
}

if ($DryRun) {
    Write-Host "🔍 DRY RUN — no changes made`n" -ForegroundColor Yellow
}
else {
    Write-Host "✅ All done!`n" -ForegroundColor Green
}
