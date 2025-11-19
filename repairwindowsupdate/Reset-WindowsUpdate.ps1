<#
.SYNOPSIS
    Bereinigt Windows Update Komponenten um fehlgeschlagene Updates (z.B. 24H2) zu beheben.

.DESCRIPTION
    Dieses Skript stoppt Windows Update Dienste, bereinigt temporäre Dateien und Cache,
    registriert DLLs neu und setzt Netzwerkkomponenten zurück. Danach werden die Dienste
    neu gestartet, damit Intune das Update erneut versuchen kann.

.NOTES
    Erfordert Administrator-Rechte
    Autor: Windows Update Repair Script
    Datum: 2025-10-23
#>

#Requires -RunAsAdministrator

# Funktion für Logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Write-Host $LogMessage
    Add-Content -Path "$PSScriptRoot\WindowsUpdate-Reset.log" -Value $LogMessage
}

Write-Log "=== Windows Update Reset wird gestartet ==="

# Array der zu stoppenden Dienste
$Services = @("BITS", "wuauserv", "AppIDSvc", "CryptSvc")

# Dienste stoppen
Write-Log "Stoppe Windows Update Dienste..."
foreach ($Service in $Services) {
    try {
        $ServiceObj = Get-Service -Name $Service -ErrorAction SilentlyContinue
        if ($ServiceObj) {
            if ($ServiceObj.Status -eq "Running") {
                Write-Log "Stoppe Dienst: $Service"
                Stop-Service -Name $Service -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
            } else {
                Write-Log "Dienst $Service läuft nicht" "INFO"
            }
        } else {
            Write-Log "Dienst $Service nicht gefunden" "WARNING"
        }
    } catch {
        Write-Log "Fehler beim Stoppen von $Service : $_" "ERROR"
    }
}

# Temporäre Dateien löschen
Write-Log "Lösche temporäre Download-Dateien..."
try {
    $NetworkDownloader = "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\*"
    if (Test-Path $NetworkDownloader) {
        Remove-Item -Path $NetworkDownloader -Force -Recurse -ErrorAction Stop
        Write-Log "Download-Cache gelöscht"
    }
} catch {
    Write-Log "Fehler beim Löschen der Download-Dateien: $_" "ERROR"
}

# SoftwareDistribution Ordner löschen
Write-Log "Lösche SoftwareDistribution Ordner..."
try {
    $SoftwareDistribution = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $SoftwareDistribution) {
        Remove-Item -Path $SoftwareDistribution -Force -Recurse -ErrorAction Stop
        Write-Log "SoftwareDistribution Ordner gelöscht"
    }
} catch {
    Write-Log "Fehler beim Löschen von SoftwareDistribution: $_" "ERROR"
}

# catroot2 Ordner löschen
Write-Log "Lösche catroot2 Ordner..."
try {
    $Catroot2 = "$env:SystemRoot\System32\catroot2"
    if (Test-Path $Catroot2) {
        Remove-Item -Path $Catroot2 -Force -Recurse -ErrorAction Stop
        Write-Log "catroot2 Ordner gelöscht"
    }
} catch {
    Write-Log "Fehler beim Löschen von catroot2: $_" "ERROR"
}

# DLLs neu registrieren
Write-Log "Registriere DLLs neu..."
$DLLs = @("atl.dll", "urlmon.dll", "mshtml.dll")
foreach ($DLL in $DLLs) {
    try {
        Write-Log "Registriere $DLL"
        Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s $DLL" -Wait -NoNewWindow
    } catch {
        Write-Log "Fehler beim Registrieren von $DLL : $_" "ERROR"
    }
}

# Winsock zurücksetzen
Write-Log "Setze Winsock zurück..."
try {
    $Result = netsh winsock reset
    Write-Log "Winsock reset: $Result"
} catch {
    Write-Log "Fehler beim Winsock Reset: $_" "ERROR"
}

# WinHTTP Proxy zurücksetzen
Write-Log "Setze WinHTTP Proxy zurück..."
try {
    $Result = netsh winhttp reset proxy
    Write-Log "WinHTTP Proxy reset: $Result"
} catch {
    Write-Log "Fehler beim WinHTTP Proxy Reset: $_" "ERROR"
}

# Dienste wieder starten
Write-Log "Starte Windows Update Dienste neu..."
foreach ($Service in $Services) {
    try {
        $ServiceObj = Get-Service -Name $Service -ErrorAction SilentlyContinue
        if ($ServiceObj) {
            Write-Log "Starte Dienst: $Service"
            Start-Service -Name $Service -ErrorAction Stop
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Log "Fehler beim Starten von $Service : $_" "ERROR"
    }
}

Write-Log "=== Windows Update Reset abgeschlossen ==="
Write-Log "Bitte starte den Computer neu und lasse Intune das Update erneut versuchen."
Write-Host ""
Write-Host "WICHTIG: Ein Neustart wird empfohlen, damit alle Änderungen wirksam werden." -ForegroundColor Yellow
Write-Host "Log-Datei: $PSScriptRoot\WindowsUpdate-Reset.log" -ForegroundColor Cyan
