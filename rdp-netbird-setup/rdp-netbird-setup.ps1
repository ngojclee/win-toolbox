#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    RDP Secure Setup - Netbird Integration
    Safe to upload to GitHub public repo (no credentials stored)

.DESCRIPTION
    First run  : Cau hinh RDP + doi port + user RDP + blank password + chon peers
    Lan sau    : Quan ly peers, port, user - khong hoi lai cau hinh cu

.NOTES
    Chay voi quyen Administrator
    Yeu cau Netbird da cai dat va connected
#>

# ============================================================
# CONSTANTS
# ============================================================
$FIREWALL_RULE_ALLOW      = "RDP - Allowed IPs Only (TCP)"
$FIREWALL_RULE_ALLOW_UDP  = "RDP - Allowed IPs Only (UDP)"
$FIREWALL_RULE_BLOCK      = "RDP - Block All Others (TCP)"
$FIREWALL_RULE_BLOCK_UDP  = "RDP - Block All Others (UDP)"
$STATE_FILE           = "$env:ProgramData\rdp-netbird-setup\state.json"
$RDP_DEFAULT_PORT     = 33389
$RDP_PORT_MIN         = 1024
$RDP_PORT_MAX         = 65535
$RDP_DEFAULT_USER     = "louis-rdp"

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
        "netbird.exe",
        "$env:ProgramFiles\Netbird\netbird.exe",
        "$env:ProgramFiles\netbird\netbird.exe",
        "$env:ProgramFiles\NetBird\netbird.exe",
        "${env:ProgramFiles(x86)}\Netbird\netbird.exe",
        "$env:LOCALAPPDATA\Netbird\netbird.exe",
        "$env:LOCALAPPDATA\Programs\Netbird\netbird.exe",
        "$env:ProgramData\Netbird\netbird.exe",
        "C:\Program Files\Netbird\netbird.exe",
        "C:\Netbird\netbird.exe"
    )
    foreach ($c in $candidates) {
        $found = Get-Command $c -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
        if (Test-Path $c) { return $c }
    }
    # Fallback: try where.exe
    try {
        $w = (where.exe netbird 2>$null) | Select-Object -First 1
        if ($w -and (Test-Path $w)) { return $w }
    } catch {}
    return $null
}

# ---- RDP Port Helpers ----

function Get-CurrentRDPPort {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
    try {
        $port = (Get-ItemProperty -Path $regPath -Name "PortNumber" -ErrorAction Stop).PortNumber
        return [int]$port
    }
    catch {
        return 3389
    }
}

function Set-RDPPort([int]$Port) {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
    Set-ItemProperty -Path $regPath -Name "PortNumber" -Value $Port -Type DWord
    Write-Host "  [OK] RDP port da doi thanh $Port" -ForegroundColor Green

    Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] TermService da restart." -ForegroundColor Green
}

function Read-PortInput {
    param([int]$CurrentPort = 3389)

    Write-Host "  Port RDP hien tai: $CurrentPort" -ForegroundColor White
    Write-Host "  Port mac dinh Windows: 3389 (bi bot scan lien tuc)" -ForegroundColor DarkGray
    Write-Host "  Port khuyen nghi : $RDP_DEFAULT_PORT (tranh scanner, de nho)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Nhap port moi (Enter = $RDP_DEFAULT_PORT):" -ForegroundColor Yellow
    $portInput = Read-Host "  Port"

    if ([string]::IsNullOrWhiteSpace($portInput)) {
        return $RDP_DEFAULT_PORT
    }

    $portNum = 0
    if (-not [int]::TryParse($portInput.Trim(), [ref]$portNum)) {
        Write-Host "  [!] Khong phai so. Dung port $RDP_DEFAULT_PORT." -ForegroundColor Red
        return $RDP_DEFAULT_PORT
    }

    if ($portNum -lt $RDP_PORT_MIN -or $portNum -gt $RDP_PORT_MAX) {
        Write-Host "  [!] Port phai trong khoang $RDP_PORT_MIN-$RDP_PORT_MAX. Dung port $RDP_DEFAULT_PORT." -ForegroundColor Red
        return $RDP_DEFAULT_PORT
    }

    $reserved = @(80, 443, 21, 22, 25, 53, 110, 143, 445, 993, 995, 8080, 8443)
    if ($reserved -contains $portNum) {
        Write-Host "  [WARN] Port $portNum la port pho bien cua dich vu khac. Van dung?" -ForegroundColor Yellow
        $confirm = Read-Host "  (y/n)"
        if ($confirm.Trim().ToLower() -ne "y") {
            return $RDP_DEFAULT_PORT
        }
    }

    return $portNum
}

# ---- RDP User Helpers ----

function Get-RDPGroupMembers {
    try {
        $members = net localgroup "Remote Desktop Users" 2>&1
        $result = @()
        $capture = $false
        foreach ($line in $members) {
            if ($line -match '^---') { $capture = $true; continue }
            if ($capture -and $line -match '^\S') {
                $name = $line.Trim()
                if ($name -and $name -notmatch 'command completed') {
                    $result += $name
                }
            }
        }
        return $result
    }
    catch { return @() }
}

function Test-LocalUser([string]$Username) {
    try {
        Get-LocalUser -Name $Username -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}

function New-RDPUser {
    param(
        [string]$Username,
        [bool]$BlankPassword,
        [bool]$AddToAdmin = $false
    )

    $exists = Test-LocalUser -Username $Username

    if ($exists) {
        Write-Host "  User '$Username' da ton tai." -ForegroundColor Yellow
    } else {
        # Create new user
        if ($BlankPassword) {
            net user $Username /add /active:yes 2>&1 | Out-Null
            $emptySecure = New-Object System.Security.SecureString
            Set-LocalUser -Name $Username -Password $emptySecure -ErrorAction SilentlyContinue
            Write-Host "  [OK] Tao user '$Username' (khong mat khau)." -ForegroundColor Green
        }
        else {
            Write-Host "  Nhap mat khau cho user '$Username':" -ForegroundColor Yellow
            $secPwd = Read-Host "  Password" -AsSecureString
            net user $Username /add /active:yes 2>&1 | Out-Null
            Set-LocalUser -Name $Username -Password $secPwd
            Write-Host "  [OK] Tao user '$Username' (co mat khau)." -ForegroundColor Green
        }
        # Password never expires for RDP convenience
        Set-LocalUser -Name $Username -PasswordNeverExpires $true -ErrorAction SilentlyContinue
    }

    # Ensure user is in Remote Desktop Users group
    $inRDP = (Get-RDPGroupMembers) -contains $Username
    if (-not $inRDP) {
        net localgroup "Remote Desktop Users" $Username /add 2>&1 | Out-Null
        Write-Host "  [OK] Da them '$Username' vao Remote Desktop Users." -ForegroundColor Green
    } else {
        Write-Host "  [OK] '$Username' da co trong Remote Desktop Users." -ForegroundColor Green
    }

    # Admin group
    if ($AddToAdmin) {
        net localgroup "Administrators" $Username /add 2>&1 | Out-Null
        Write-Host "  [OK] Da them '$Username' vao Administrators." -ForegroundColor Green
    } else {
        net localgroup "Administrators" $Username /delete 2>&1 | Out-Null
    }

    return $Username
}

function Read-RDPUserSetup {
    param([bool]$AllowBlank)

    Write-Host "  Tao user rieng cho RDP?" -ForegroundColor Yellow
    Write-Host "  (Khuyen nghi: tach biet khoi account chinh)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] Tao user rieng (khuyen nghi)" -ForegroundColor White
    Write-Host "  [2] Dung user hien tai ($env:USERNAME)" -ForegroundColor White
    Write-Host ""
    $userChoice = Read-Host "  Chon (Enter = 1)"

    if ($userChoice -ne "2") {
        Write-Host ""
        Write-Host "  Nhap ten user RDP (Enter = '$RDP_DEFAULT_USER'):" -ForegroundColor Yellow
        Write-Host "  (Nen dung cung ten tren tat ca may de nho)" -ForegroundColor DarkGray
        $userName = Read-Host "  Username"

        if ([string]::IsNullOrWhiteSpace($userName)) {
            $userName = $RDP_DEFAULT_USER
        }
        $userName = $userName.Trim()

        # Validate username
        if ($userName -match '[\\\/\[\]:;|=,+\*\?<>@"]+' -or $userName.Length -gt 20) {
            Write-Host "  [!] Ten user khong hop le. Dung '$RDP_DEFAULT_USER'." -ForegroundColor Red
            $userName = $RDP_DEFAULT_USER
        }

        # Ask about admin rights
        Write-Host ""
        Write-Host "  Cho user '$userName' quyen Administrator?" -ForegroundColor Yellow
        Write-Host "  Co  = cai duoc phan mem, chay script admin, toan quyen" -ForegroundColor DarkGray
        Write-Host "  Khong = chi xem file, chay portable app, gioi han" -ForegroundColor DarkGray
        Write-Host "  (Da co Netbird + Firewall bao ve, cho Admin cung an toan)" -ForegroundColor DarkGray
        $adminChoice = Read-Host "  Cho Admin? (y/n, Enter = n)"
        $giveAdmin = $adminChoice.Trim().ToLower() -eq "y"

        $createdUser = New-RDPUser -Username $userName -BlankPassword $AllowBlank -AddToAdmin $giveAdmin
        return $createdUser
    }
    else {
        # Ensure current user is in Remote Desktop Users
        $current = $env:USERNAME
        $inGroup = (Get-RDPGroupMembers) -contains $current
        if (-not $inGroup) {
            net localgroup "Remote Desktop Users" $current /add 2>&1 | Out-Null
            Write-Host "  [OK] Da them '$current' vao Remote Desktop Users." -ForegroundColor Green
        }
        Write-Host "  [OK] Dung user '$current' cho RDP." -ForegroundColor Green
        return $current
    }
}

# ---- Netbird Peer Helpers ----

function Get-NetbirdPeers {
    $nb = Get-NetbirdExe
    if (-not $nb) {
        Write-Host "  [!] Khong tim thay Netbird CLI." -ForegroundColor Red
        Write-Host "  Thu chay 'netbird status' de kiem tra." -ForegroundColor DarkGray
        Write-Host "  Neu cai roi, thu chay: where.exe netbird" -ForegroundColor DarkGray
        return @()
    }
    Write-Host "  Netbird: $nb" -ForegroundColor DarkGray

    $rawLines = & $nb status -d 2>&1
    $peers = @()
    $cur   = $null

    foreach ($line in $rawLines) {
        $line = $line.Trim()

        # Format 1: "Peer: hostname" (older netbird)
        if ($line -match '^Peer:\s*(.+)$') {
            if ($cur) { $peers += $cur }
            $cur = [PSCustomObject]@{ Name=$Matches[1].Trim(); IP=""; Status="Unknown"; FQDN="" }
        }
        # Format 2: "hostname.domain.tld:" (newer netbird — FQDN with dots, ending with colon)
        # Require dot to distinguish from section headers like "Relays:", "Events:", etc.
        elseif ($line -match '^([a-zA-Z0-9][a-zA-Z0-9\-]*\.[a-zA-Z0-9\-\.]+)\s*:$') {
            if ($cur) { $peers += $cur }
            $cur = [PSCustomObject]@{ Name=$Matches[1].Trim(); IP=""; Status="Unknown"; FQDN=$Matches[1].Trim() }
        }
        # Peer properties (indented under each peer)
        elseif ($cur) {
            if ($line -match 'NetBird IP:\s*([\d\.]+)')  { $cur.IP = $Matches[1] }
            elseif ($line -match 'Status:\s*(\w+)')       { $cur.Status = $Matches[1] }
            elseif ($line -match 'FQDN:\s*(.+)')          { $cur.FQDN = $Matches[1].Trim() }
        }
    }
    if ($cur) { $peers += $cur }
    return $peers
}

function Show-PeerSelector {
    param(
        [array]$Peers,
        [string[]]$CurrentlyAllowed
    )

    $connectedCount = ($Peers | Where-Object { $_.Status -eq "Connected" -and $_.IP }).Count

    Write-Host "  Peers hien co trong Netbird:" -ForegroundColor Yellow
    Write-Host ""

    # Prominent "select all" option
    if ($connectedCount -gt 0) {
        Write-Host "  [  0]  >>> CHON TAT CA ($connectedCount peers Connected) <<<" -ForegroundColor Green
        Write-Host ""
    }

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
    Write-Host "  Nhap so de toggle: '1 3' | 0 = chon tat ca" -ForegroundColor Yellow
    Write-Host "  Enter = chon tat ca Connected" -ForegroundColor DarkGray
    $selection = Read-Host "  Chon (Enter = all)"

    $toggled = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($ip in $CurrentlyAllowed) {
        if ($ip) { $toggled.Add($ip) | Out-Null }
    }

    if ($selection.Trim() -eq "" -or $selection.Trim() -eq "0" -or $selection.Trim().ToLower() -eq "all") {
        # Select all connected peers (add all, don't toggle)
        foreach ($p in ($Peers | Where-Object { $_.Status -eq "Connected" -and $_.IP })) {
            $toggled.Add($p.IP) | Out-Null
        }
        Write-Host "  [OK] Da chon tat ca $connectedCount peers Connected." -ForegroundColor Green
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

# ---- Firewall Helpers ----

function Get-CurrentWhitelistedIPs {
    $rule = Get-NetFirewallRule -DisplayName $FIREWALL_RULE_ALLOW -ErrorAction SilentlyContinue
    if (-not $rule) { return @() }
    $f = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
    if (-not $f) { return @() }
    return @($f.RemoteAddress)
}

function Apply-FirewallRules {
    param(
        [string[]]$AllowedIPs,
        [int]$Port
    )

    # Remove our custom rules (clean slate)
    foreach ($name in @($FIREWALL_RULE_ALLOW, $FIREWALL_RULE_ALLOW_UDP, $FIREWALL_RULE_BLOCK, $FIREWALL_RULE_BLOCK_UDP)) {
        Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    }
    # Clean up legacy rule names
    Remove-NetFirewallRule -DisplayName "RDP - Allowed IPs Only" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "RDP - Block All Others" -ErrorAction SilentlyContinue

    # Disable built-in Windows RDP firewall rules (they allow ANY address)
    Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue |
        Set-NetFirewallRule -Enabled False -ErrorAction SilentlyContinue
    Write-Host "  [OK] Built-in RDP firewall rules disabled (dung rules whitelist thay the)." -ForegroundColor DarkGray

    if ($AllowedIPs.Count -eq 0) {
        Write-Host "  [WARN] Danh sach trong - RDP khong co IP nao duoc phep." -ForegroundColor Yellow
        return
    }

    # Allow rules for whitelisted IPs only (TCP + UDP)
    # Windows Firewall default-deny inbound handles blocking all other IPs
    New-NetFirewallRule `
        -DisplayName $FIREWALL_RULE_ALLOW -Direction Inbound -Protocol TCP `
        -LocalPort $Port -RemoteAddress $AllowedIPs -Action Allow -Profile Any -Enabled True | Out-Null

    New-NetFirewallRule `
        -DisplayName $FIREWALL_RULE_ALLOW_UDP -Direction Inbound -Protocol UDP `
        -LocalPort $Port -RemoteAddress $AllowedIPs -Action Allow -Profile Any -Enabled True | Out-Null

    Write-Host "  [OK] Firewall: cho phep $($AllowedIPs.Count) IP qua TCP + UDP (port $Port)." -ForegroundColor Green
}

# ---- RDP Enable / Blank Password ----

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

# ---- Display Config Summary ----

function Show-ConfigSummary {
    param(
        [int]$Port,
        [bool]$AllowBlank,
        [string]$RDPUser,
        [string[]]$AllowedIPs
    )
    Write-Host ""
    Write-Host "  +------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |          CAU HINH HIEN TAI                     |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ("  |  RDP Port      : {0,-29}|" -f $Port) -ForegroundColor White
    Write-Host ("  |  RDP User      : {0,-29}|" -f $(if ($RDPUser) { $RDPUser } else { '(chua cau hinh)' })) -ForegroundColor White
    Write-Host ("  |  Blank password : {0,-28}|" -f $(if ($AllowBlank) { 'Cho phep' } else { 'Khoa' })) -ForegroundColor White
    Write-Host ("  |  IP whitelisted : {0,-28}|" -f $AllowedIPs.Count) -ForegroundColor White
    Write-Host "  |                                                |" -ForegroundColor Cyan

    if ($AllowedIPs.Count -gt 0) {
        foreach ($ip in $AllowedIPs) {
            Write-Host ("  |    - {0,-42}|" -f $ip) -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  |    (chua co IP nao)                           |" -ForegroundColor Yellow
    }

    Write-Host "  +------------------------------------------------+" -ForegroundColor Cyan

    # Connection hint
    Write-Host ""
    $portSuffix = if ($Port -ne 3389) { ":$Port" } else { "" }
    Write-Host "  >> Ket noi: mstsc /v:<IP>$portSuffix" -ForegroundColor Yellow
    if ($RDPUser) {
        Write-Host "     User   : $RDPUser" -ForegroundColor Yellow
    }
    Write-Host "     Vi du  : mstsc /v:100.64.0.1$portSuffix" -ForegroundColor DarkGray
}

# ============================================================
# FIRST RUN FLOW
# ============================================================

function Run-FirstSetup {
    Write-Header "First Run - Cau Hinh Ban Dau"

    Write-Host "[1/5] Bat RDP..." -ForegroundColor Cyan
    Enable-RDP

    Write-Host ""
    Write-Host "[2/5] Doi port RDP..." -ForegroundColor Cyan
    Write-Host "  Port 3389 (mac dinh) bi bot scan lien tuc tren Internet." -ForegroundColor DarkGray
    Write-Host "  Doi sang port khac giup tranh 99% scan tu dong." -ForegroundColor DarkGray
    $rdpPort = Read-PortInput -CurrentPort (Get-CurrentRDPPort)
    $oldPort = Get-CurrentRDPPort
    if ($rdpPort -ne $oldPort) {
        Set-RDPPort -Port $rdpPort
    } else {
        Write-Host "  [OK] Giu nguyen port $rdpPort" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "[3/5] Blank password policy..." -ForegroundColor Cyan
    Write-Host "  Cho phep RDP bang tai khoan khong co mat khau?" -ForegroundColor Yellow
    Write-Host "  (Chi nen bat neu may nay trong LAN + da dung Netbird gioi han IP)" -ForegroundColor DarkGray
    $bpInput    = Read-Host "  (y/n, Enter = y)"
    $allowBlank = $bpInput.Trim().ToLower() -ne "n"
    Set-BlankPasswordPolicy -Allow $allowBlank

    Write-Host ""
    Write-Host "[4/5] Cau hinh user RDP..." -ForegroundColor Cyan
    $rdpUser = Read-RDPUserSetup -AllowBlank $allowBlank

    Write-Host ""
    Write-Host "[5/5] Chon may duoc phep RDP vao may nay..." -ForegroundColor Cyan
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

    Apply-FirewallRules -AllowedIPs $finalIPs -Port $rdpPort

    Save-State @{
        configured  = $true
        rdpPort     = $rdpPort
        rdpUser     = $rdpUser
        allowBlank  = $allowBlank
        allowedIPs  = $finalIPs
        lastUpdated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    Write-Host ""
    Write-Host "  === Cau hinh hoan tat ===" -ForegroundColor Green
    Show-ConfigSummary -Port $rdpPort -AllowBlank $allowBlank -RDPUser $rdpUser -AllowedIPs $finalIPs

    gpupdate /force 2>&1 | Out-Null
    Write-Host ""
    Write-Host "  Group Policy   : Da refresh" -ForegroundColor DarkGray
}

# ============================================================
# MANAGE PEERS FLOW
# ============================================================

function Run-ManagePeers([object]$State) {
    Write-Header "Quan Ly RDP"

    $currentIPs  = Get-CurrentWhitelistedIPs
    $currentPort = if ($State.rdpPort) { [int]$State.rdpPort } else { Get-CurrentRDPPort }
    $currentUser = if ($State.rdpUser) { $State.rdpUser } else { $null }

    Show-ConfigSummary -Port $currentPort -AllowBlank ([bool]$State.allowBlank) -RDPUser $currentUser -AllowedIPs $currentIPs

    Write-Host ""
    Write-Host "  Cap nhat lan cuoi: $($State.lastUpdated)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [1] Them / Bo peer (query Netbird)" -ForegroundColor White
    Write-Host "  [2] Nhap IP thu cong" -ForegroundColor White
    Write-Host "  [3] Doi port RDP" -ForegroundColor White
    Write-Host "  [4] Doi cau hinh blank password" -ForegroundColor White
    Write-Host "  [5] Quan ly user RDP" -ForegroundColor White
    Write-Host "  [6] Reset - chay lai First Run" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "  Chon (1-6)"

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
                Apply-FirewallRules -AllowedIPs $newIPs -Port $currentPort
                Save-State @{
                    configured=$true; rdpPort=$currentPort; rdpUser=$currentUser
                    allowBlank=$State.allowBlank; allowedIPs=$newIPs
                    lastUpdated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
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
            Apply-FirewallRules -AllowedIPs $merged -Port $currentPort
            Save-State @{
                configured=$true; rdpPort=$currentPort; rdpUser=$currentUser
                allowBlank=$State.allowBlank; allowedIPs=$merged
                lastUpdated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }
        "3" {
            $newPort = Read-PortInput -CurrentPort $currentPort
            if ($newPort -ne $currentPort) {
                $ok = Read-Host "  Xac nhan doi port $currentPort -> $newPort? (y/n)"
                if ($ok.ToLower() -eq "y") {
                    Set-RDPPort -Port $newPort
                    Apply-FirewallRules -AllowedIPs $currentIPs -Port $newPort
                    Save-State @{
                        configured=$true; rdpPort=$newPort; rdpUser=$currentUser
                        allowBlank=$State.allowBlank; allowedIPs=$currentIPs
                        lastUpdated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                    Write-Host ""
                    Write-Host "  >> Ket noi RDP moi: mstsc /v:<IP>:$newPort" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  Port khong doi." -ForegroundColor DarkGray
            }
        }
        "4" {
            $newBlank = -not [bool]$State.allowBlank
            $msg = if ($newBlank) { "BAT phep blank password" } else { "TAT blank password" }
            $ok = Read-Host "  Xac nhan $msg? (y/n)"
            if ($ok.ToLower() -eq "y") {
                Set-BlankPasswordPolicy -Allow $newBlank
                Save-State @{
                    configured=$true; rdpPort=$currentPort; rdpUser=$currentUser
                    allowBlank=$newBlank; allowedIPs=$currentIPs
                    lastUpdated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                }
            }
        }
        "5" {
            Write-Host ""
            Write-Host "  User RDP hien tai: $(if ($currentUser) { $currentUser } else { '(chua cau hinh)' })" -ForegroundColor White
            Write-Host ""
            Write-Host "  Thanh vien Remote Desktop Users:" -ForegroundColor DarkGray
            $rdpMembers = Get-RDPGroupMembers
            if ($rdpMembers.Count -eq 0) {
                Write-Host "    (trong)" -ForegroundColor Yellow
            } else {
                $rdpMembers | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }
            }
            Write-Host ""
            Write-Host "  [a] Tao / cau hinh user RDP" -ForegroundColor White
            Write-Host "  [b] Quay lai" -ForegroundColor White
            $sub = Read-Host "  Chon"
            if ($sub.ToLower() -eq "a") {
                $newUser = Read-RDPUserSetup -AllowBlank ([bool]$State.allowBlank)
                Save-State @{
                    configured=$true; rdpPort=$currentPort; rdpUser=$newUser
                    allowBlank=$State.allowBlank; allowedIPs=$currentIPs
                    lastUpdated=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                }
            }
        }
        "6" {
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
