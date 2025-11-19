<#
.SYNOPSIS
    Remediation-Script für Windows Update Probleme (Intune Remediation)

.DESCRIPTION
    Bereinigt Windows Update Komponenten um fehlgeschlagene Updates (z.B. 24H2) zu beheben.
    Stoppt Windows Update Dienste, bereinigt temporäre Dateien und Cache,
    registriert DLLs neu und setzt Netzwerkkomponenten zurück.
    Exit 0 = Remediation erfolgreich
    Exit 1 = Remediation fehlgeschlagen

.NOTES
    Erfordert Administrator-Rechte (wird automatisch von Intune bereitgestellt)
    Autor: Windows Update Remediation Script
    Datum: 2025-10-24
    Für: Microsoft Intune Proactive Remediations
#>

#Requires -RunAsAdministrator

# Intune-konformer Log-Pfad (ProgramData statt PSScriptRoot)
$LogPath = "$env:ProgramData\WindowsUpdateRemediation"
if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}
$LogFile = "$LogPath\WindowsUpdate-Reset-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Funktion für Logging (Intune-optimiert)
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Write-Output $LogMessage  # Write-Output statt Write-Host für Intune
    Add-Content -Path $LogFile -Value $LogMessage -ErrorAction SilentlyContinue
}

# Fehler-Tracking
$Script:HasErrors = $false
$Script:ErrorMessages = @()

try {
    Write-Log "=== Windows Update Remediation wird gestartet ==="

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
                    Write-Log "Dienst $Service läuft bereits nicht" "INFO"
                }
            } else {
                Write-Log "Dienst $Service nicht gefunden" "WARNING"
            }
        } catch {
            $ErrorMsg = "Fehler beim Stoppen von $Service : $_"
            Write-Log $ErrorMsg "ERROR"
            $Script:ErrorMessages += $ErrorMsg
            # Nicht kritisch, weitermachen
        }
    }

    # Temporäre Dateien löschen
    Write-Log "Lösche temporäre Download-Dateien..."
    try {
        $NetworkDownloader = "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader"
        if (Test-Path $NetworkDownloader) {
            Remove-Item -Path "$NetworkDownloader\*" -Force -Recurse -ErrorAction Stop
            Write-Log "Download-Cache gelöscht"
        } else {
            Write-Log "Download-Cache Ordner existiert nicht"
        }
    } catch {
        $ErrorMsg = "Fehler beim Löschen der Download-Dateien: $_"
        Write-Log $ErrorMsg "ERROR"
        $Script:ErrorMessages += $ErrorMsg
    }

    # SoftwareDistribution Ordner umbenennen (sicherer als löschen)
    Write-Log "Benenne SoftwareDistribution Ordner um..."
    try {
        $SoftwareDistribution = "$env:SystemRoot\SoftwareDistribution"
        $BackupName = "$env:SystemRoot\SoftwareDistribution.old_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

        if (Test-Path $SoftwareDistribution) {
            Rename-Item -Path $SoftwareDistribution -NewName $BackupName -Force -ErrorAction Stop
            Write-Log "SoftwareDistribution nach $BackupName umbenannt"
        } else {
            Write-Log "SoftwareDistribution Ordner existiert nicht"
        }
    } catch {
        # Fallback: Versuche zu löschen
        try {
            Remove-Item -Path $SoftwareDistribution -Force -Recurse -ErrorAction Stop
            Write-Log "SoftwareDistribution Ordner gelöscht (Umbenennen fehlgeschlagen)"
        } catch {
            $ErrorMsg = "Fehler beim Löschen von SoftwareDistribution: $_"
            Write-Log $ErrorMsg "ERROR"
            $Script:HasErrors = $true
            $Script:ErrorMessages += $ErrorMsg
        }
    }

    # catroot2 Ordner umbenennen
    Write-Log "Benenne catroot2 Ordner um..."
    try {
        $Catroot2 = "$env:SystemRoot\System32\catroot2"
        $BackupName = "$env:SystemRoot\System32\catroot2.old_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

        if (Test-Path $Catroot2) {
            Rename-Item -Path $Catroot2 -NewName $BackupName -Force -ErrorAction Stop
            Write-Log "catroot2 nach $BackupName umbenannt"
        } else {
            Write-Log "catroot2 Ordner existiert nicht"
        }
    } catch {
        $ErrorMsg = "Fehler beim Umbenennen von catroot2: $_"
        Write-Log $ErrorMsg "ERROR"
        $Script:ErrorMessages += $ErrorMsg
    }

    # DLLs neu registrieren
    Write-Log "Registriere DLLs neu..."
    $DLLs = @("atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll",
              "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll",
              "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll",
              "dssenh.dll", "rsaenh.dll", "gpkcsp.dll", "sccbase.dll",
              "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll",
              "shell32.dll", "initpki.dll", "wuapi.dll", "wuaueng.dll",
              "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll",
              "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll",
              "muweb.dll", "wuwebv.dll")

    $DLLFailures = 0
    foreach ($DLL in $DLLs) {
        try {
            Write-Log "Registriere $DLL"
            $Process = Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s $DLL" -Wait -NoNewWindow -PassThru
            if ($Process.ExitCode -ne 0) {
                Write-Log "Warnung: $DLL konnte nicht registriert werden (Exit Code: $($Process.ExitCode))" "WARNING"
                $DLLFailures++
            }
        } catch {
            Write-Log "Fehler beim Registrieren von $DLL : $_" "WARNING"
            $DLLFailures++
        }
    }

    if ($DLLFailures -gt 0) {
        Write-Log "$DLLFailures DLLs konnten nicht registriert werden" "WARNING"
    }

    # Winsock zurücksetzen
    Write-Log "Setze Winsock zurück..."
    try {
        $Result = netsh winsock reset 2>&1
        Write-Log "Winsock reset: $Result"
    } catch {
        $ErrorMsg = "Fehler beim Winsock Reset: $_"
        Write-Log $ErrorMsg "WARNING"
        $Script:ErrorMessages += $ErrorMsg
    }

    # WinHTTP Proxy zurücksetzen
    Write-Log "Setze WinHTTP Proxy zurück..."
    try {
        $Result = netsh winhttp reset proxy 2>&1
        Write-Log "WinHTTP Proxy reset: $Result"
    } catch {
        $ErrorMsg = "Fehler beim WinHTTP Proxy Reset: $_"
        Write-Log $ErrorMsg "WARNING"
        $Script:ErrorMessages += $ErrorMsg
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

                # Verifiziere, dass der Dienst läuft
                $ServiceObj.Refresh()
                if ($ServiceObj.Status -ne "Running") {
                    $ErrorMsg = "Dienst $Service läuft nicht nach dem Start"
                    Write-Log $ErrorMsg "ERROR"
                    $Script:HasErrors = $true
                    $Script:ErrorMessages += $ErrorMsg
                }
            }
        } catch {
            $ErrorMsg = "Fehler beim Starten von $Service : $_"
            Write-Log $ErrorMsg "ERROR"
            $Script:HasErrors = $true
            $Script:ErrorMessages += $ErrorMsg
        }
    }

    Write-Log "=== Windows Update Remediation abgeschlossen ==="
    Write-Log "Log-Datei: $LogFile"

    # Exit-Code für Intune
    if ($Script:HasErrors) {
        Write-Output "FEHLER: Remediation mit Fehlern abgeschlossen:"
        foreach ($Err in $Script:ErrorMessages) {
            Write-Output "  - $Err"
        }
        Write-Output "Ein Neustart wird empfohlen."
        exit 1  # Fehler -> Intune zeigt Remediation als fehlgeschlagen an
    } else {
        Write-Output "Remediation erfolgreich abgeschlossen. Ein Neustart wird empfohlen."
        exit 0  # Erfolg -> Intune zeigt Remediation als erfolgreich an
    }

} catch {
    Write-Log "KRITISCHER FEHLER: $_" "ERROR"
    Write-Output "KRITISCHER FEHLER bei der Remediation: $_"
    exit 1  # Fehler -> Intune zeigt Remediation als fehlgeschlagen an
}
