# RDP Deaktivierungs-Script
# Dieses Script muss als Administrator ausgeführt werden

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   RDP Deaktivierungs-Script" -ForegroundColor Cyan
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

if ($currentStatus.fDenyTSConnections -eq 1) {
    Write-Host "    RDP ist bereits DEAKTIVIERT" -ForegroundColor Green
} else {
    Write-Host "    RDP ist aktuell AKTIVIERT" -ForegroundColor Red
}

Write-Host ""

# RDP deaktivieren
Write-Host "[2] RDP deaktivieren..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
    Write-Host "    RDP erfolgreich deaktiviert!" -ForegroundColor Green
} catch {
    Write-Host "    FEHLER beim Deaktivieren: $_" -ForegroundColor Red
    pause
    exit
}

Write-Host ""

# NLA (Network Level Authentication) wieder aktivieren für mehr Sicherheit
Write-Host "[3] Network Level Authentication aktivieren..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
    Write-Host "    NLA aktiviert (mehr Sicherheit)" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: NLA konnte nicht geaendert werden" -ForegroundColor Yellow
}

Write-Host ""

# Firewall-Regeln deaktivieren
Write-Host "[4] Firewall-Regeln fuer RDP deaktivieren..." -ForegroundColor Yellow
try {
    Disable-NetFirewallRule -DisplayGroup "Remotedesktop"
    Write-Host "    Firewall-Regeln deaktiviert!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: Firewall-Regeln konnten nicht deaktiviert werden" -ForegroundColor Yellow
}

Write-Host ""

# Remote Desktop Service stoppen
Write-Host "[5] Remote Desktop Service stoppen..." -ForegroundColor Yellow
try {
    Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue
    Set-Service -Name TermService -StartupType Manual
    Write-Host "    Service gestoppt!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: Service konnte nicht gestoppt werden" -ForegroundColor Yellow
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
if ($finalStatus.fDenyTSConnections -eq 1) {
    Write-Host "DEAKTIVIERT" -ForegroundColor Green
} else {
    Write-Host "AKTIVIERT" -ForegroundColor Red
}

# NLA Status
$nlaStatus = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication"
Write-Host "NLA Status: " -NoNewline
if ($nlaStatus.UserAuthentication -eq 1) {
    Write-Host "AKTIVIERT (sicher)" -ForegroundColor Green
} else {
    Write-Host "DEAKTIVIERT" -ForegroundColor Yellow
}

# Service Status
$serviceStatus = Get-Service -Name TermService
Write-Host "TermService: $($serviceStatus.Status) (Startup: $($serviceStatus.StartType))" -ForegroundColor Cyan

Write-Host ""
Write-Host "RDP wurde erfolgreich deaktiviert!" -ForegroundColor Green
Write-Host "Keine Remote-Verbindungen mehr moeglich." -ForegroundColor Yellow
Write-Host ""

pause
