# RDP Aktivierungs-Script
# Dieses Script muss als Administrator ausgeführt werden

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   RDP Aktivierungs-Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Prüfen ob Script als Administrator läuft
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "FEHLER: Dieses Script muss als Administrator ausgefuehrt werden!" -ForegroundColor Red
    Write-Host "Rechtsklick auf PowerShell -> Als Administrator ausfuehren" -ForegroundColor Yellow
    pause
    exit
}

# Aktuellen RDP-Status anzeigen
Write-Host "[1] Aktuellen RDP-Status pruefen..." -ForegroundColor Yellow
$currentStatus = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections"

if ($currentStatus.fDenyTSConnections -eq 0) {
    Write-Host "    RDP ist bereits AKTIVIERT" -ForegroundColor Green
} else {
    Write-Host "    RDP ist aktuell DEAKTIVIERT" -ForegroundColor Red
}

Write-Host ""

# RDP aktivieren
Write-Host "[2] RDP aktivieren..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Write-Host "    RDP erfolgreich aktiviert!" -ForegroundColor Green
} catch {
    Write-Host "    FEHLER beim Aktivieren: $_" -ForegroundColor Red
    pause
    exit
}

Write-Host ""

# NLA (Network Level Authentication) optional deaktivieren für einfacheren Zugriff
Write-Host "[3] Network Level Authentication konfigurieren..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0
    Write-Host "    NLA deaktiviert (einfacherer Zugriff)" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: NLA konnte nicht geaendert werden" -ForegroundColor Yellow
}

Write-Host ""

# Firewall-Regeln aktivieren
Write-Host "[4] Firewall-Regeln fuer RDP aktivieren..." -ForegroundColor Yellow
try {
    Enable-NetFirewallRule -DisplayGroup "Remotedesktop"
    Write-Host "    Firewall-Regeln aktiviert!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: Firewall-Regeln konnten nicht aktiviert werden" -ForegroundColor Yellow
}

Write-Host ""

# Remote Desktop Service starten
Write-Host "[5] Remote Desktop Service starten..." -ForegroundColor Yellow
try {
    Set-Service -Name TermService -StartupType Automatic
    Start-Service -Name TermService -ErrorAction SilentlyContinue
    Write-Host "    Service gestartet!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: Service konnte nicht gestartet werden" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Konfiguration abgeschlossen!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Status anzeigen
Write-Host "FINALER STATUS:" -ForegroundColor Green
Write-Host ""

# RDP Status
$finalStatus = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections"
Write-Host "RDP Status: " -NoNewline
if ($finalStatus.fDenyTSConnections -eq 0) {
    Write-Host "AKTIVIERT" -ForegroundColor Green
} else {
    Write-Host "DEAKTIVIERT" -ForegroundColor Red
}

# Port anzeigen
$port = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "PortNumber"
Write-Host "RDP Port: $($port.PortNumber)" -ForegroundColor Cyan

Write-Host ""
Write-Host "Deine IP-Adressen:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | ForEach-Object {
    Write-Host "  $($_.IPAddress) - $($_.InterfaceAlias)" -ForegroundColor White
}

Write-Host ""
Write-Host "Du kannst dich jetzt von einem anderen PC verbinden mit:" -ForegroundColor Yellow
Write-Host "  mstsc /v:DEINE-IP-ADRESSE" -ForegroundColor White
Write-Host ""

pause
