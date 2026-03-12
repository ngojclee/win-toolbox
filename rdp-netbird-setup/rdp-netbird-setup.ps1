#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    RDP Secure Setup - Netbird Integration
    Safe to upload to GitHub public repo (no credentials stored)

.DESCRIPTION
    First run  : Cau hinh RDP + blank password + chon peers duoc phep
    Lan sau    : Chi hoi them/bo peer, khong hoi lai cau hinh cu

.NOTES
    Chay voi quyen Administrator
    Yeu cau Netbird da cai dat va connected
#>

# ============================================================
# CONSTANTS
# ============================================================
$FIREWALL_RULE_ALLOW  = "RDP - Allowed IPs Only"
$FIREWALL_RULE_BLOCK  = "RDP - Block All Others"
$STATE_FILE           = "$env:ProgramData\rdp-netbird-setup\state.json"

# ============================================================
# HELPERS
# ============================================================

function Write-Header([string]$Text) {
    Write-Host ""
    Write-Host ("=" * 52) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 52) -ForegroundColor Cyan
    Write-Host ""
}

function Save-State([hashtable]$State) {
    $dir = Split-Path $STATE_FILE
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $State | ConvertTo-Json | Set-Content -Path $STATE_FILE -Encoding UTF8
}

function Load-State {
    if (Test-Path $STATE_FILE) {
        return Get-Content $STATE_FILE -Raw | ConvertFrom-Json
    }
    return $null
}

function Get-NetbirdExe {
    $candidates = @(
        "netbird",
        "$env:ProgramFiles\Netbird\netbird.exe",
        "$env:ProgramFiles\netbird\netbird.exe",
        "C:\Program Files\Netbird\netbird.exe"
    )
    foreach ($c in $candidates) {
        $found = Get-Command $c -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Get-NetbirdPeers {
    $nb = Get-NetbirdExe
    if (-not $nb) {
        Write-Host "  [!] Khong tim thay Netbird CLI." -ForegroundColor Red
        return @()
    }

    $rawLines = & $nb status -d 2>&1
    $peers = @()
    $cur   = $null

    foreach ($line in $rawLines) {
        $line = $line.Trim()
        if ($line -match '^Peer:\s*(.+)$') {
            if ($cur) { $peers += $cur }
            $cur = [PSCustomObject]@{ Name=$Matches[1].Trim(); IP=""; Status="Unknown"; FQDN="" }
        }
        elseif ($line -match '^([a-zA-Z0-9][a-zA-Z0-9\-\.]+)\s*:$' -and -not $cur) {
            if ($cur) { $peers += $cur }
            $cur = [PSCustomObject]@{ Name=$Matches[1].Trim(); IP=""; Status="Unknown"; FQDN=$Matches[1].Trim() }
        }
        elseif ($line -match 'NetBird IP:\s*([\d\.]+)' -and $cur) { $cur.IP = $Matches[1] }
        elseif ($line -match 'Status:\s*(\w+)'         -and $cur) { $cur.Status = $Matches[1] }
        elseif ($line -match 'FQDN:\s*(.+)'            -and $cur) { $cur.FQDN = $Matches[1].Trim() }
    }
    if ($cur) { $peers += $cur }
    return $peers
}

function Show-PeerSelector {
    param(
        [array]$Peers,
        [string[]]$CurrentlyAllowed
    )

    Write-Host "  Peers hien co trong Netbird:" -ForegroundColor Yellow
    Write-Host ""

    $i = 1
    foreach ($p in $Peers) {
        $display  = if ($p.FQDN) { $p.FQDN } else { $p.Name }
        $inList   = $CurrentlyAllowed -contains $p.IP
        $statusOK = $p.Status -eq "Connected"
        $color    = if ($statusOK) { "Green" } else { "DarkGray" }
        $icon     = if ($statusOK) { "[ON] " } else { "[OFF]" }
        $tick     = if ($inList)   { "*" }     else { " " }

        Write-Host ("  [{0,2}]{1} {2} " -f $i, $tick, $icon) -NoNewline -ForegroundColor $color
        Write-Host ("{0,-42}" -f $display) -NoNewline -ForegroundColor White
        Write-Host $p.IP -ForegroundColor Cyan
        $i++
    }

    Write-Host ""
    Write-Host "  (* = dang duoc phep | [ON]=Connected | [OFF]=Disconnected)" -ForegroundColor DarkGray
    Write-Host "  Nhap so de TOGGLE (them neu chua co, bo neu da co): vi du '1 3'" -ForegroundColor Yellow
    Write-Host "  'all' = toggle tat ca Connected | Enter = giu nguyen" -ForegroundColor DarkGray
    $selection = Read-Host "  Chon"

    $toggled = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($ip in $CurrentlyAllowed) {
        if ($ip) { $toggled.Add($ip) | Out-Null }
    }

    if ($selection.Trim().ToLower() -eq "all") {
        foreach ($p in ($Peers | Where-Object { $_.Status -eq "Connected" -and $_.IP })) {
            if (-not $toggled.Remove($p.IP)) { $toggled.Add($p.IP) | Out-Null }
        }
    }
    elseif ($selection.Trim() -ne "") {
        $indices = $selection.Trim() -split '\s+' | ForEach-Object {
            $n = 0; if ([int]::TryParse($_, [ref]$n)) { $n - 1 }
        }
        foreach ($idx in $indices) {
            if ($idx -ge 0 -and $idx -lt $Peers.Count) {
                $ip = $Peers[$idx].IP
                if ($ip) {
                    if (-not $toggled.Remove($ip)) { $toggled.Add($ip) | Out-Null }
                }
            }
        }
    }

    return @($toggled)
}

function Get-CurrentWhitelistedIPs {
    $rule = Get-NetFirewallRule -DisplayName $FIREWALL_RULE_ALLOW -ErrorAction SilentlyContinue
    if (-not $rule) { return @() }
    $f = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
    if (-not $f) { return @() }
    return @($f.RemoteAddress)
}

function Apply-FirewallRules([string[]]$AllowedIPs) {
    Remove-NetFirewallRule -DisplayName $FIREWALL_RULE_ALLOW -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName $FIREWALL_RULE_BLOCK -ErrorAction SilentlyContinue

    if ($AllowedIPs.Count -eq 0) {
        Write-Host "  [WARN] Danh sach trong - RDP hien mo cho tat ca IP." -ForegroundColor Yellow
        return
    }

    New-NetFirewallRule `
        -DisplayName $FIREWALL_RULE_ALLOW -Direction Inbound -Protocol TCP `
        -LocalPort 3389 -RemoteAddress $AllowedIPs -Action Allow -Profile Any -Enabled True | Out-Null

    New-NetFirewallRule `
        -DisplayName $FIREWALL_RULE_BLOCK -Direction Inbound -Protocol TCP `
        -LocalPort 3389 -RemoteAddress "Any" -Action Block -Profile Any -Enabled True | Out-Null

    Write-Host "  [OK] Firewall da cap nhat." -ForegroundColor Green
}

function Enable-RDP {
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
    Set-ItemProperty -Path $reg -Name "fDenyTSConnections" -Value 0
    Set-Service -Name "TermService" -StartupType Automatic
    Start-Service -Name "TermService" -ErrorAction SilentlyContinue
    Write-Host "  [OK] RDP da duoc bat." -ForegroundColor Green
}

function Set-BlankPasswordPolicy([bool]$Allow) {
    $val = if ($Allow) { 0 } else { 1 }
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
                     -Name "LimitBlankPasswordUse" -Value $val -Type DWord
    $msg = if ($Allow) { "Cho phep blank password qua RDP." } else { "Khoa blank password (mac dinh Windows)." }
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

# ============================================================
# FIRST RUN FLOW
# ============================================================

function Run-FirstSetup {
    Write-Header "First Run - Cau Hinh Ban Dau"

    Write-Host "[1/3] Bat RDP..." -ForegroundColor Cyan
    Enable-RDP

    Write-Host ""
    Write-Host "[2/3] Blank password policy..." -ForegroundColor Cyan
    Write-Host "  Cho phep RDP bang tai khoan khong co mat khau?" -ForegroundColor Yellow
    Write-Host "  (Chi nen bat neu may nay trong LAN + da dung Netbird gioi han IP)" -ForegroundColor DarkGray
    $bpInput   = Read-Host "  (y/n)"
    $allowBlank = $bpInput.Trim().ToLower() -eq "y"
    Set-BlankPasswordPolicy -Allow $allowBlank

    Write-Host ""
    Write-Host "[3/3] Chon may duoc phep RDP vao may nay..." -ForegroundColor Cyan
    $peers    = Get-NetbirdPeers
    $finalIPs = @()

    if ($peers.Count -eq 0) {
        Write-Host "  Khong lay duoc peers. Nhap IP thu cong:" -ForegroundColor Yellow
        while ($true) {
            $ip = Read-Host "  IP (Enter de ket thuc)"
            if ([string]::IsNullOrWhiteSpace($ip)) { break }
            if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { $finalIPs += $ip }
            else { Write-Host "  ! Khong hop le" -ForegroundColor Red }
        }
    }
    else {
        $finalIPs = Show-PeerSelector -Peers $peers -CurrentlyAllowed @()
    }

    Apply-FirewallRules -AllowedIPs $finalIPs

    Save-State @{
        configured  = $true
        allowBlank  = $allowBlank
        allowedIPs  = $finalIPs
        lastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    Write-Host ""
    Write-Host "  === Cau hinh hoan tat ===" -ForegroundColor Green
    Write-Host "  Blank password : $(if ($allowBlank) { 'Cho phep' } else { 'Khoa' })" -ForegroundColor White
    Write-Host "  IP duoc phep   : $(if ($finalIPs.Count) { $finalIPs -join ', ' } else { '(chua co)' })" -ForegroundColor White

    gpupdate /force 2>&1 | Out-Null
    Write-Host "  Group Policy   : Da refresh" -ForegroundColor DarkGray
}

# ============================================================
# MANAGE PEERS FLOW
# ============================================================

function Run-ManagePeers([object]$State) {
    Write-Header "Quan Ly Peers RDP"

    $currentIPs = Get-CurrentWhitelistedIPs

    Write-Host "  Cau hinh hien tai:" -ForegroundColor DarkGray
    Write-Host "  Blank password : $(if ($State.allowBlank) { 'Cho phep' } else { 'Khoa' })" -ForegroundColor DarkGray
    Write-Host "  So IP trong list: $($currentIPs.Count)" -ForegroundColor DarkGray
    Write-Host "  Cap nhat lan cuoi: $($State.lastUpdated)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] Them / Bo peer (query Netbird)" -ForegroundColor White
    Write-Host "  [2] Nhap IP thu cong" -ForegroundColor White
    Write-Host "  [3] Xem danh sach IP hien tai" -ForegroundColor White
    Write-Host "  [4] Doi cau hinh blank password" -ForegroundColor White
    Write-Host "  [5] Reset - chay lai First Run" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "  Chon (1-5)"

    switch ($choice) {
        "1" {
            $peers = Get-NetbirdPeers
            if ($peers.Count -eq 0) { Write-Host "  Khong lay duoc peers." -ForegroundColor Red; return }
            $newIPs = Show-PeerSelector -Peers $peers -CurrentlyAllowed $currentIPs
            Write-Host ""
            Write-Host "  Danh sach sau khi cap nhat:" -ForegroundColor Cyan
            if ($newIPs.Count -eq 0) {
                Write-Host "  (Trong)" -ForegroundColor Yellow
            } else {
                $newIPs | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }
            }
            $ok = Read-Host "  Xac nhan? (y/n)"
            if ($ok.ToLower() -eq "y") {
                Apply-FirewallRules -AllowedIPs $newIPs
                Save-State @{
                    configured  = $true
                    allowBlank  = $State.allowBlank
                    allowedIPs  = $newIPs
                    lastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                }
            }
        }
        "2" {
            Write-Host "  Nhap IP muon them (Enter de ket thuc):" -ForegroundColor Yellow
            $added = @()
            while ($true) {
                $ip = Read-Host "  IP"
                if ([string]::IsNullOrWhiteSpace($ip)) { break }
                if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { $added += $ip }
                else { Write-Host "  ! Khong hop le" -ForegroundColor Red }
            }
            $merged = @($currentIPs + $added | Sort-Object -Unique)
            Apply-FirewallRules -AllowedIPs $merged
            Save-State @{ configured=$true; allowBlank=$State.allowBlank; allowedIPs=$merged; lastUpdated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
        }
        "3" {
            Write-Host ""
            if ($currentIPs.Count -eq 0) {
                Write-Host "  (Chua co IP nao trong whitelist)" -ForegroundColor Yellow
            } else {
                $currentIPs | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
            }
        }
        "4" {
            $newBlank = -not [bool]$State.allowBlank
            $msg = if ($newBlank) { "BAT phep blank password" } else { "TAT blank password" }
            $ok = Read-Host "  Xac nhan $msg? (y/n)"
            if ($ok.ToLower() -eq "y") {
                Set-BlankPasswordPolicy -Allow $newBlank
                Save-State @{ configured=$true; allowBlank=$newBlank; allowedIPs=$currentIPs; lastUpdated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
            }
        }
        "5" {
            $ok = Read-Host "  Xoa toan bo state va chay lai First Run? (y/n)"
            if ($ok.ToLower() -eq "y") {
                Remove-Item $STATE_FILE -Force -ErrorAction SilentlyContinue
                Write-Host "  Da xoa state." -ForegroundColor Yellow
                Run-FirstSetup
            }
        }
        default {
            Write-Host "  Lua chon khong hop le." -ForegroundColor Red
        }
    }
}

# ============================================================
# ENTRY POINT
# ============================================================

$state = Load-State

if (-not $state -or -not $state.configured) {
    Run-FirstSetup
} else {
    Run-ManagePeers -State $state
}

Write-Host ""
