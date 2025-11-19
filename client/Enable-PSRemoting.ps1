# PowerShell Remoting Aktivierungs-Script
# Dieses Script muss als Administrator ausgeführt werden

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   PowerShell Remoting Aktivierungs-Script" -ForegroundColor Cyan
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
        Write-Host "    PSRemoting ist bereits AKTIVIERT" -ForegroundColor Green
    }
} catch {
    Write-Host "    PSRemoting ist aktuell DEAKTIVIERT" -ForegroundColor Red
}

Write-Host ""

# PowerShell Remoting aktivieren
Write-Host "[2] PowerShell Remoting aktivieren..." -ForegroundColor Yellow
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Write-Host "    PSRemoting erfolgreich aktiviert!" -ForegroundColor Green
} catch {
    Write-Host "    FEHLER beim Aktivieren: $_" -ForegroundColor Red
    pause
    exit
}

Write-Host ""

# WinRM Service konfigurieren
Write-Host "[3] WinRM Service konfigurieren..." -ForegroundColor Yellow
try {
    Set-Service -Name WinRM -StartupType Automatic
    Start-Service -Name WinRM -ErrorAction SilentlyContinue
    Write-Host "    WinRM Service konfiguriert und gestartet!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: WinRM Service konnte nicht konfiguriert werden" -ForegroundColor Yellow
}

Write-Host ""

# Firewall-Regeln aktivieren
Write-Host "[4] Firewall-Regeln fuer WinRM aktivieren..." -ForegroundColor Yellow
try {
    Enable-NetFirewallRule -DisplayGroup "Windows-Remoteverwaltung"
    Write-Host "    Firewall-Regeln aktiviert!" -ForegroundColor Green
} catch {
    Write-Host "    Warnung: Firewall-Regeln konnten nicht aktiviert werden" -ForegroundColor Yellow
}

Write-Host ""

# TrustedHosts konfigurieren (optional, aber oft notwendig)
Write-Host "[5] TrustedHosts Konfiguration..." -ForegroundColor Yellow
Write-Host "    Aktuelle TrustedHosts: " -NoNewline
$currentTrustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
if ([string]::IsNullOrEmpty($currentTrustedHosts)) {
    Write-Host "Keine" -ForegroundColor Yellow
} else {
    Write-Host "$currentTrustedHosts" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "    Moechtest du alle Hosts als vertrauenswuerdig markieren? (Nicht empfohlen fuer Produktionsumgebungen)" -ForegroundColor Yellow
Write-Host "    Dies erlaubt Verbindungen von jedem Client." -ForegroundColor Yellow
$response = Read-Host "    Eingabe [J]a oder [N]ein (Standard: Nein)"

if ($response -eq "J" -or $response -eq "j" -or $response -eq "Ja" -or $response -eq "ja") {
    try {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
        Write-Host "    TrustedHosts auf '*' gesetzt (alle Hosts erlaubt)" -ForegroundColor Green
    } catch {
        Write-Host "    Warnung: TrustedHosts konnte nicht gesetzt werden" -ForegroundColor Yellow
    }
} else {
    Write-Host "    TrustedHosts wurde nicht geaendert" -ForegroundColor Cyan
    Write-Host "    Bei Verbindungsproblemen manuell konfigurieren mit:" -ForegroundColor Yellow
    Write-Host "    Set-Item WSMan:\localhost\Client\TrustedHosts -Value 'IP-ADRESSE' -Force" -ForegroundColor White
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
        Write-Host "AKTIVIERT" -ForegroundColor Green
    }
} catch {
    Write-Host "PSRemoting Status: " -NoNewline
    Write-Host "DEAKTIVIERT" -ForegroundColor Red
}

# WinRM Service Status
$serviceStatus = Get-Service -Name WinRM
Write-Host "WinRM Service: $($serviceStatus.Status) (Startup: $($serviceStatus.StartType))" -ForegroundColor Cyan

# Ports anzeigen
Write-Host "WinRM Ports: 5985 (HTTP), 5986 (HTTPS)" -ForegroundColor Cyan

Write-Host ""
Write-Host "Deine IP-Adressen:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | ForEach-Object {
    Write-Host "  $($_.IPAddress) - $($_.InterfaceAlias)" -ForegroundColor White
}

# Hostname anzeigen
$hostname = $env:COMPUTERNAME
Write-Host ""
Write-Host "Dein Computername: $hostname" -ForegroundColor Cyan

Write-Host ""
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host "   SO VERBINDEST DU DICH:" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "METHODE 1: Interaktive Session (wie SSH)" -ForegroundColor Green
Write-Host "  Enter-PSSession -ComputerName ZIEL-IP -Credential (Get-Credential)" -ForegroundColor White
Write-Host "  Beispiel:" -ForegroundColor Gray
Write-Host "  Enter-PSSession -ComputerName 192.168.1.100 -Credential (Get-Credential)" -ForegroundColor Gray
Write-Host ""

Write-Host "METHODE 2: Einzelnen Befehl ausfuehren" -ForegroundColor Green
Write-Host "  Invoke-Command -ComputerName ZIEL-IP -Credential (Get-Credential) -ScriptBlock { Get-Process }" -ForegroundColor White
Write-Host "  Beispiel:" -ForegroundColor Gray
Write-Host "  Invoke-Command -ComputerName 192.168.1.100 -Credential (Get-Credential) -ScriptBlock { Get-Service }" -ForegroundColor Gray
Write-Host ""

Write-Host "METHODE 3: Session fuer mehrere Befehle" -ForegroundColor Green
Write-Host "  `$session = New-PSSession -ComputerName ZIEL-IP -Credential (Get-Credential)" -ForegroundColor White
Write-Host "  Invoke-Command -Session `$session -ScriptBlock { Get-ComputerInfo }" -ForegroundColor White
Write-Host "  Remove-PSSession -Session `$session" -ForegroundColor White
Write-Host ""

Write-Host "WICHTIG:" -ForegroundColor Red
Write-Host "  - Verwende Admin-Credentials des Zielcomputers" -ForegroundColor Yellow
Write-Host "  - Bei Workgroup-PCs (keine Domain): Username im Format '.\Benutzername' oder 'PCNAME\Benutzername'" -ForegroundColor Yellow
Write-Host "  - Bei Domain-PCs: 'DOMAIN\Benutzername'" -ForegroundColor Yellow
Write-Host ""

Write-Host "OHNE Credential-Abfrage (wenn bereits als passender User angemeldet):" -ForegroundColor Green
Write-Host "  Enter-PSSession -ComputerName ZIEL-IP" -ForegroundColor White
Write-Host ""

Write-Host "FEHLERBEHEBUNG:" -ForegroundColor Magenta
Write-Host "  Falls 'Access denied' oder Verbindungsfehler:" -ForegroundColor Yellow
Write-Host "  1. Auf dem CLIENT (von wo du dich verbindest) ausfuehren:" -ForegroundColor White
Write-Host "     Set-Item WSMan:\localhost\Client\TrustedHosts -Value 'ZIEL-IP' -Force" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Oder alle Hosts erlauben (unsicherer):" -ForegroundColor White
Write-Host "     Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. WinRM Service neu starten:" -ForegroundColor White
Write-Host "     Restart-Service WinRM" -ForegroundColor Gray
Write-Host ""

Write-Host "PowerShell Remoting wurde erfolgreich aktiviert!" -ForegroundColor Green
Write-Host ""

pause
