# PowerShell Remoting Deaktivierungs-Script
# Dieses Script muss als Administrator ausgeführt werden

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   PowerShell Remoting Deaktivierungs-Script" -ForegroundColor Cyan
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

# Aktuellen PSRemoting-Status anzeigen
Write-Host "[1] Aktuellen PSRemoting-Status pruefen..." -ForegroundColor Yellow
try {
    $psStatus = Test-WSMan -ComputerName localhost -ErrorAction SilentlyContinue
    if ($psStatus) {
        Write-Host "    PSRemoting ist aktuell AKTIVIERT" -ForegroundColor Red
    }
} catch {
    Write-Host "    PSRemoting ist bereits DEAKTIVIERT" -ForegroundColor Green
}

Write-Host ""

# PowerShell Remoting deaktivieren
Write-Host "[2] PowerShell Remoting deaktivieren..." -ForegroundColor Yellow
try {
    Disable-PSRemoting -Force
    Write-Host "    PSRemoting erfolgreich deaktiviert!" -ForegroundColor Green
} catch {
    Write-Host "    FEHLER beim Deaktivieren: $_" -ForegroundColor Red
}

Write-Host ""

# WinRM Listener entfernen
Write-Host "[3] WinRM Listener entfernen..." -ForegroundColor Yellow
try {
    Get-ChildItem WSMan:\Localhost\listener | Where-Object {$_.Keys -like "Transport=HTTP*"} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "    WinRM Listener entfernt!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: Listener konnte nicht entfernt werden" -ForegroundColor Yellow
}

Write-Host ""

# WinRM Service stoppen
Write-Host "[4] WinRM Service stoppen..." -ForegroundColor Yellow
try {
    Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue
    Set-Service -Name WinRM -StartupType Manual
    Write-Host "    WinRM Service gestoppt!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: Service konnte nicht gestoppt werden" -ForegroundColor Yellow
}

Write-Host ""

# Firewall-Regeln deaktivieren
Write-Host "[5] Firewall-Regeln fuer WinRM deaktivieren..." -ForegroundColor Yellow
try {
    Disable-NetFirewallRule -DisplayGroup "Windows-Remoteverwaltung"
    Write-Host "    Firewall-Regeln deaktiviert!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: Firewall-Regeln konnten nicht deaktiviert werden" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Konfiguration abgeschlossen!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Status anzeigen
Write-Host "FINALER STATUS:" -ForegroundColor Green
Write-Host ""

# PSRemoting Status
try {
    $finalStatus = Test-WSMan -ComputerName localhost -ErrorAction SilentlyContinue
    if ($finalStatus) {
        Write-Host "PSRemoting Status: " -NoNewline
        Write-Host "AKTIVIERT" -ForegroundColor Red
    }
} catch {
    Write-Host "PSRemoting Status: " -NoNewline
    Write-Host "DEAKTIVIERT" -ForegroundColor Green
}

# WinRM Service Status
$serviceStatus = Get-Service -Name WinRM
Write-Host "WinRM Service: $($serviceStatus.Status) (Startup: $($serviceStatus.StartType))" -ForegroundColor Cyan

Write-Host ""
Write-Host "PowerShell Remoting wurde erfolgreich deaktiviert!" -ForegroundColor Green
Write-Host "Keine Remote-PowerShell-Verbindungen mehr moeglich." -ForegroundColor Yellow
Write-Host ""

pause
