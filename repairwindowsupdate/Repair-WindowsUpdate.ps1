<#
.SYNOPSIS
    Bereinigt und repariert Windows Update-Komponenten und installiert ausstehende Updates.

.DESCRIPTION
    Dieses Script führt eine umfassende Bereinigung der Windows Update-Komponenten durch
    und installiert anschließend verfügbare Updates. Es ist besonders nützlich bei:
    - Download-Fehlern von Updates
    - Installations-Fehlern von Updates
    - Hängenden Update-Prozessen
    - Beschädigten Update-Caches

    Das Script verwendet ausschließlich native Windows-Komponenten (COM-Objekte) und
    benötigt keine externen PowerShell-Module.

.PARAMETER IncludeDrivers
    Wenn aktiviert, werden auch Treiber-Updates eingeschlossen.
    Standard: Nur Software-Updates

.PARAMETER IncludeFeatureUpdates
    Wenn aktiviert, werden auch Feature-Updates (z.B. Windows 11 23H2) eingeschlossen.
    Standard: Feature-Updates werden übersprungen

.PARAMETER RebootIfNeeded
    Wenn aktiviert, wird der Computer automatisch neu gestartet, falls erforderlich.
    Standard: Benutzer wird nur informiert

.PARAMETER SkipCleanup
    Wenn aktiviert, wird die Bereinigung übersprungen und nur Updates installiert.
    Standard: Vollständige Bereinigung wird durchgeführt

.PARAMETER LogPath
    Pfad für die Log-Dateien. Standard: C:\ProgramData\UpdateForce

.EXAMPLE
    .\Repair-WindowsUpdate.ps1
    Führt eine Standard-Bereinigung durch und installiert Software-Updates.

.EXAMPLE
    .\Repair-WindowsUpdate.ps1 -IncludeDrivers -RebootIfNeeded
    Bereinigt, installiert Software- und Treiber-Updates und startet bei Bedarf neu.

.EXAMPLE
    .\Repair-WindowsUpdate.ps1 -IncludeFeatureUpdates -IncludeDrivers
    Bereinigt und installiert alle verfügbaren Updates inkl. Feature-Updates.

.NOTES
    Dateiname:      Repair-WindowsUpdate.ps1
    Autor:          Windows Update Repair Script
    Voraussetzung:  PowerShell 5.1+, Administratorrechte
    Version:        2.0
    Datum:          2025-10-16
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(HelpMessage="Treiber-Updates einschließen")]
    [switch]$IncludeDrivers,

    [Parameter(HelpMessage="Feature-Updates (z.B. neue Windows-Versionen) einschließen")]
    [switch]$IncludeFeatureUpdates,

    [Parameter(HelpMessage="Automatischer Neustart bei Bedarf")]
    [switch]$RebootIfNeeded,

    [Parameter(HelpMessage="Bereinigung überspringen, nur Updates installieren")]
    [switch]$SkipCleanup,

    [Parameter(HelpMessage="Pfad für Log-Dateien")]
    [ValidateScript({Test-Path (Split-Path $_ -Parent) -PathType Container -IsValid})]
    [string]$LogPath = 'C:\ProgramData\UpdateForce'
)

#Requires -RunAsAdministrator

# ============================================================================
# GLOBALE VARIABLEN UND KONFIGURATION
# ============================================================================

$ErrorActionPreference = 'Stop'
$script:ErrorCount = 0
$script:WarningCount = 0
$script:StartTime = Get-Date

# Farben für bessere Lesbarkeit
$script:Colors = @{
    Success = 'Green'
    Error   = 'Red'
    Warning = 'Yellow'
    Info    = 'Cyan'
    Header  = 'Magenta'
}

# ============================================================================
# HILFSFUNKTIONEN
# ============================================================================

function Write-LogMessage {
    <#
    .SYNOPSIS
        Schreibt formatierte Nachrichten in Konsole und Log-Datei.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Info','Success','Warning','Error','Header')]
        [string]$Level = 'Info',

        [Parameter(Mandatory=$false)]
        [switch]$NoTimestamp
    )

    $timestamp = if (-not $NoTimestamp) { "[{0:yyyy-MM-dd HH:mm:ss}] " -f (Get-Date) } else { "" }
    $icon = switch ($Level) {
        'Success' { '✓' }
        'Error'   { '✗' }
        'Warning' { '⚠' }
        'Info'    { 'ℹ' }
        'Header'  { '═' }
        default   { ' ' }
    }

    $fullMessage = "$timestamp$icon $Message"

    # In Konsole mit Farbe ausgeben
    $color = $script:Colors[$Level]
    Write-Host $fullMessage -ForegroundColor $color

    # Ins Transcript schreiben (ohne Farbe) - mit Out-Host um Pipeline-Pollution zu vermeiden
    # Write-Host schreibt bereits ins Transcript, daher keine zusätzliche Aktion nötig

    # Fehler- und Warnungszähler aktualisieren
    if ($Level -eq 'Error') { $script:ErrorCount++ }
    if ($Level -eq 'Warning') { $script:WarningCount++ }
}

function Test-AdministratorPrivileges {
    <#
    .SYNOPSIS
        Prüft, ob das Script mit Administratorrechten ausgeführt wird.
    #>
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ServiceExists {
    <#
    .SYNOPSIS
        Prüft, ob ein Windows-Dienst existiert.
    #>
    param([string]$ServiceName)

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Stop-ServiceSafely {
    <#
    .SYNOPSIS
        Stoppt einen Dienst sicher mit Timeout und Fehlerbehandlung.
    #>
    param(
        [string]$ServiceName,
        [int]$TimeoutSeconds = 30
    )

    try {
        if (-not (Test-ServiceExists -ServiceName $ServiceName)) {
            Write-LogMessage "Dienst '$ServiceName' existiert nicht" -Level Warning
            return $false
        }

        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq 'Stopped') {
            Write-LogMessage "Dienst '$ServiceName' ist bereits gestoppt" -Level Info
            return $true
        }

        Write-LogMessage "Stoppe Dienst '$ServiceName'..." -Level Info
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop

        # Warten bis Dienst gestoppt ist
        $service.WaitForStatus('Stopped', (New-TimeSpan -Seconds $TimeoutSeconds))
        Write-LogMessage "Dienst '$ServiceName' erfolgreich gestoppt" -Level Success
        return $true

    } catch [System.ServiceProcess.TimeoutException] {
        Write-LogMessage "Timeout beim Stoppen von Dienst '$ServiceName'" -Level Error
        return $false
    } catch {
        Write-LogMessage "Fehler beim Stoppen von '$ServiceName': $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Start-ServiceSafely {
    <#
    .SYNOPSIS
        Startet einen Dienst sicher mit Timeout und Fehlerbehandlung.
    #>
    param(
        [string]$ServiceName,
        [int]$TimeoutSeconds = 30
    )

    try {
        if (-not (Test-ServiceExists -ServiceName $ServiceName)) {
            Write-LogMessage "Dienst '$ServiceName' existiert nicht" -Level Warning
            return $false
        }

        $service = Get-Service -Name $ServiceName -ErrorAction Stop

        if ($service.Status -eq 'Running') {
            Write-LogMessage "Dienst '$ServiceName' läuft bereits" -Level Info
            return $true
        }

        Write-LogMessage "Starte Dienst '$ServiceName'..." -Level Info
        Start-Service -Name $ServiceName -ErrorAction Stop

        # Warten bis Dienst läuft
        $service.WaitForStatus('Running', (New-TimeSpan -Seconds $TimeoutSeconds))
        Write-LogMessage "Dienst '$ServiceName' erfolgreich gestartet" -Level Success
        return $true

    } catch [System.ServiceProcess.TimeoutException] {
        Write-LogMessage "Timeout beim Starten von Dienst '$ServiceName'" -Level Error
        return $false
    } catch {
        Write-LogMessage "Fehler beim Starten von '$ServiceName': $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Remove-DirectorySafely {
    <#
    .SYNOPSIS
        Löscht ein Verzeichnis sicher mit Wiederholungsversuchen.
    #>
    param(
        [string]$Path,
        [int]$MaxRetries = 3
    )

    if (-not (Test-Path -Path $Path)) {
        Write-LogMessage "Verzeichnis existiert nicht: $Path" -Level Info
        return $true
    }

    $retryCount = 0
    $success = $false

    while ((-not $success) -and ($retryCount -lt $MaxRetries)) {
        try {
            Write-LogMessage "Lösche Verzeichnis: $Path (Versuch $($retryCount + 1)/$MaxRetries)" -Level Info
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            $success = $true
            Write-LogMessage "Verzeichnis erfolgreich gelöscht: $Path" -Level Success
        } catch {
            $retryCount++
            if ($retryCount -lt $MaxRetries) {
                Write-LogMessage "Fehler beim Löschen, warte 2 Sekunden..." -Level Warning
                Start-Sleep -Seconds 2
            } else {
                Write-LogMessage "Verzeichnis konnte nicht gelöscht werden: $($_.Exception.Message)" -Level Error
                return $false
            }
        }
    }

    return $success
}

function Invoke-ComponentCleanup {
    <#
    .SYNOPSIS
        Führt DISM-Komponentenbereinigung durch.
    #>
    try {
        Write-LogMessage "Starte DISM-Komponentenbereinigung..." -Level Info

        $dismArgs = @(
            '/Online',
            '/Cleanup-Image',
            '/StartComponentCleanup',
            '/ResetBase'
        )

        $process = Start-Process -FilePath 'dism.exe' `
                                 -ArgumentList $dismArgs `
                                 -Wait `
                                 -PassThru `
                                 -NoNewWindow `
                                 -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            Write-LogMessage "DISM-Komponentenbereinigung erfolgreich abgeschlossen" -Level Success
            return $true
        } else {
            Write-LogMessage "DISM-Bereinigung mit Exit-Code $($process.ExitCode) beendet" -Level Warning
            return $false
        }

    } catch {
        Write-LogMessage "Fehler bei DISM-Bereinigung: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Invoke-WindowsUpdateCleanup {
    <#
    .SYNOPSIS
        Führt die vollständige Bereinigung der Windows Update-Komponenten durch.
    #>
    [CmdletBinding()]
    param()

    Write-LogMessage "═══════════════════════════════════════════════════════" -Level Header
    Write-LogMessage "PHASE 1: Windows Update-Bereinigung" -Level Header
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level Header

    # 1. Windows Update-Dienste stoppen
    Write-LogMessage "`n--- Stoppe Windows Update-Dienste ---" -Level Info
    $services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
    $stoppedServices = @()

    foreach ($service in $services) {
        if (Stop-ServiceSafely -ServiceName $service) {
            $stoppedServices += $service
        }
    }

    # 2. Update-Caches löschen
    Write-LogMessage "`n--- Lösche Update-Caches ---" -Level Info

    $cachePaths = @(
        'C:\Windows\SoftwareDistribution',
        'C:\Windows\System32\catroot2'
    )

    foreach ($cachePath in $cachePaths) {
        [void](Remove-DirectorySafely -Path $cachePath)
    }

    # 3. Windows Update-Dienste neu starten
    Write-LogMessage "`n--- Starte Windows Update-Dienste neu ---" -Level Info

    foreach ($service in $stoppedServices) {
        [void](Start-ServiceSafely -ServiceName $service)
    }

    # 4. DISM-Komponentenbereinigung (optional, kann lange dauern)
    Write-LogMessage "`n--- Führe DISM-Komponentenbereinigung durch ---" -Level Info
    [void](Invoke-ComponentCleanup)

    # 5. Windows Update-Datenbank zurücksetzen
    Write-LogMessage "`n--- Registriere Windows Update-Komponenten neu ---" -Level Info

    $dlls = @('atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll',
              'browseui.dll', 'jscript.dll', 'vbscript.dll', 'scrrun.dll',
              'msxml.dll', 'msxml3.dll', 'msxml6.dll', 'actxprxy.dll',
              'softpub.dll', 'wintrust.dll', 'dssenh.dll', 'rsaenh.dll',
              'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll',
              'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll',
              'wuapi.dll', 'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll',
              'wups.dll', 'wups2.dll', 'wuweb.dll', 'qmgr.dll',
              'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll', 'wuwebv.dll')

    $registeredCount = 0
    foreach ($dll in $dlls) {
        try {
            $result = Start-Process -FilePath 'regsvr32.exe' `
                                   -ArgumentList "/s $dll" `
                                   -Wait `
                                   -PassThru `
                                   -NoNewWindow `
                                   -ErrorAction SilentlyContinue
            if ($result.ExitCode -eq 0) { $registeredCount++ }
        } catch {
            # Ignorieren, wenn DLL nicht gefunden wird
        }
    }

    Write-LogMessage "Erfolgreich $registeredCount von $($dlls.Count) DLLs registriert" -Level Info

    Write-LogMessage "`nBereinigung abgeschlossen!" -Level Success
}

function Get-WindowsUpdates {
    <#
    .SYNOPSIS
        Sucht nach verfügbaren Windows Updates.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [bool]$IncludeDrivers = $false,
        [bool]$IncludeFeatureUpdates = $false
    )

    try {
        Write-LogMessage "Erstelle Windows Update-Session..." -Level Info
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()

        # Suchkriterien definieren
        $criteria = if ($IncludeDrivers) {
            "IsInstalled=0 and IsHidden=0"
        } else {
            "IsInstalled=0 and Type='Software' and IsHidden=0"
        }

        Write-LogMessage "Suche Updates mit Kriterien: $criteria" -Level Info
        Write-LogMessage "Dies kann einige Minuten dauern..." -Level Info

        $searchResult = $searcher.Search($criteria)

        if ($searchResult.Updates.Count -eq 0) {
            Write-LogMessage "Keine Updates gefunden" -Level Info
            # Explizit ein leeres Array zurückgeben
            return ,@()
        }

        # Updates filtern - ArrayList für bessere Performance
        $updates = New-Object System.Collections.ArrayList

        foreach ($update in $searchResult.Updates) {
            # Überspringe Updates ohne Titel (beschädigt)
            if ([string]::IsNullOrWhiteSpace($update.Title)) {
                Write-LogMessage "Überspringe Update ohne Titel (ID: $($update.Identity.UpdateID))" -Level Warning
                continue
            }

            $isFeatureUpdate = $false

            # Prüfe, ob es ein Feature-Update ist
            try {
                foreach ($category in $update.Categories) {
                    if ($category.Name -match 'Upgrade|Feature Update|Feature Pack') {
                        $isFeatureUpdate = $true
                        break
                    }
                }
            } catch {
                Write-LogMessage "Warnung: Kategorien für Update '$($update.Title)' nicht lesbar" -Level Warning
            }

            # Nur hinzufügen, wenn Kriterien erfüllt
            if ($IncludeFeatureUpdates -or -not $isFeatureUpdate) {
                [void]$updates.Add($update)
            } else {
                Write-LogMessage "Überspringe Feature-Update: $($update.Title)" -Level Info
            }
        }

        # ArrayList in reguläres Array konvertieren
        return ,$updates.ToArray()

    } catch {
        Write-LogMessage "Fehler beim Suchen von Updates: $($_.Exception.Message)" -Level Error
        Write-LogMessage "Stack-Trace: $($_.ScriptStackTrace)" -Level Error
        # Explizit ein leeres Array zurückgeben
        return ,@()
    }
}

function Install-WindowsUpdates {
    <#
    .SYNOPSIS
        Lädt herunter und installiert Windows Updates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Object[]]$Updates
    )

    Write-LogMessage "═══════════════════════════════════════════════════════" -Level Header
    Write-LogMessage "PHASE 2: Download und Installation von Updates" -Level Header
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level Header

    if ($Updates.Count -eq 0) {
        Write-LogMessage "Keine Updates zum Installieren" -Level Info
        return @{
            Success = $true
            RebootRequired = $false
            InstalledCount = 0
        }
    }

    # Update-Liste anzeigen
    Write-LogMessage "`nGefundene Updates ($($Updates.Count)):" -Level Info
    for ($i = 0; $i -lt $Updates.Count; $i++) {
        $update = $Updates[$i]

        # Validiere Update-Objekt
        if ($null -eq $update -or [string]::IsNullOrWhiteSpace($update.Title)) {
            Write-LogMessage "  $($i + 1). [Ungültiges Update-Objekt]" -Level Warning
            continue
        }

        $size = if ($update.MaxDownloadSize -gt 0) {
            " ({0:N2} MB)" -f ($update.MaxDownloadSize / 1MB)
        } else { "" }
        Write-LogMessage "  $($i + 1). $($update.Title)$size" -Level Info
    }

    try {
        # Update-Collection erstellen
        $session = New-Object -ComObject Microsoft.Update.Session
        $updateCollection = New-Object -ComObject Microsoft.Update.UpdateColl

        # Nur gültige Update-Objekte hinzufügen
        $validUpdateCount = 0
        foreach ($update in $Updates) {
            if ($null -eq $update) {
                Write-LogMessage "Überspringe null-Update-Objekt" -Level Warning
                continue
            }

            # Versuche, Update hinzuzufügen
            try {
                $null = $updateCollection.Add($update)
                $validUpdateCount++
            } catch {
                Write-LogMessage "Fehler beim Hinzufügen von Update '$($update.Title)': $($_.Exception.Message)" -Level Error
            }
        }

        if ($validUpdateCount -eq 0) {
            Write-LogMessage "Keine gültigen Updates zum Installieren gefunden" -Level Error
            return @{
                Success = $false
                RebootRequired = $false
                InstalledCount = 0
            }
        }

        Write-LogMessage "$validUpdateCount von $($Updates.Count) Updates werden verarbeitet" -Level Info

        # ========== DOWNLOAD ==========
        Write-LogMessage "`n--- Download-Phase ---" -Level Info
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updateCollection

        Write-LogMessage "Starte Download von $($Updates.Count) Update(s)..." -Level Info
        $downloadResult = $downloader.Download()

        $downloadResultText = switch ($downloadResult.ResultCode) {
            0 { "Nicht gestartet" }
            1 { "In Bearbeitung" }
            2 { "Erfolgreich" }
            3 { "Erfolgreich mit Fehlern" }
            4 { "Fehlgeschlagen" }
            5 { "Abgebrochen" }
            default { "Unbekannt ($($downloadResult.ResultCode))" }
        }

        Write-LogMessage "Download-Ergebnis: $downloadResultText" -Level $(if ($downloadResult.ResultCode -eq 2) { 'Success' } else { 'Warning' })

        if ($downloadResult.ResultCode -eq 4 -or $downloadResult.ResultCode -eq 5) {
            Write-LogMessage "Download fehlgeschlagen oder abgebrochen" -Level Error
            return @{
                Success = $false
                RebootRequired = $false
                InstalledCount = 0
            }
        }

        # ========== INSTALLATION ==========
        Write-LogMessage "`n--- Installations-Phase ---" -Level Info
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $updateCollection

        Write-LogMessage "Starte Installation von $($Updates.Count) Update(s)..." -Level Info
        Write-LogMessage "WICHTIG: Dieser Vorgang kann 15-30 Minuten oder länger dauern!" -Level Warning

        $installResult = $installer.Install()

        $installResultText = switch ($installResult.ResultCode) {
            0 { "Nicht gestartet" }
            1 { "In Bearbeitung" }
            2 { "Erfolgreich" }
            3 { "Erfolgreich mit Fehlern" }
            4 { "Fehlgeschlagen" }
            5 { "Abgebrochen" }
            default { "Unbekannt ($($installResult.ResultCode))" }
        }

        Write-LogMessage "Installations-Ergebnis: $installResultText" -Level $(if ($installResult.ResultCode -eq 2) { 'Success' } elseif ($installResult.ResultCode -eq 3) { 'Warning' } else { 'Error' })

        # Detaillierte Ergebnisse pro Update
        Write-LogMessage "`nDetaillierte Update-Ergebnisse:" -Level Info
        $successCount = 0

        for ($i = 0; $i -lt $installResult.GetUpdateResult.Count; $i++) {
            $updateResult = $installResult.GetUpdateResult($i)
            $update = $Updates[$i]

            $resultText = switch ($updateResult.ResultCode) {
                0 { "Nicht gestartet" }
                1 { "In Bearbeitung" }
                2 { "Erfolgreich"; $successCount++ }
                3 { "Erfolgreich mit Fehlern"; $successCount++ }
                4 { "Fehlgeschlagen" }
                5 { "Abgebrochen" }
                default { "Unbekannt" }
            }

            $level = switch ($updateResult.ResultCode) {
                2 { 'Success' }
                3 { 'Warning' }
                4 { 'Error' }
                5 { 'Error' }
                default { 'Info' }
            }

            Write-LogMessage "  [$resultText] $($update.Title)" -Level $level

            if ($updateResult.HResult -ne 0) {
                Write-LogMessage "    HRESULT: 0x$($updateResult.HResult.ToString('X8'))" -Level Warning
            }
        }

        Write-LogMessage "`nErfolgreich installiert: $successCount von $($Updates.Count)" -Level $(if ($successCount -eq $Updates.Count) { 'Success' } else { 'Warning' })

        return @{
            Success = ($installResult.ResultCode -eq 2 -or $installResult.ResultCode -eq 3)
            RebootRequired = $installResult.RebootRequired
            InstalledCount = $successCount
            ResultCode = $installResult.ResultCode
        }

    } catch {
        Write-LogMessage "Kritischer Fehler während Installation: $($_.Exception.Message)" -Level Error
        Write-LogMessage "Stack-Trace: $($_.ScriptStackTrace)" -Level Error
        return @{
            Success = $false
            RebootRequired = $false
            InstalledCount = 0
        }
    }
}

function Update-DefenderSignatures {
    <#
    .SYNOPSIS
        Aktualisiert Windows Defender-Signaturen.
    #>
    try {
        Write-LogMessage "`n--- Aktualisiere Windows Defender-Signaturen ---" -Level Info

        # Prüfe, ob Windows Defender verfügbar ist
        $mpService = Get-Service -Name 'WinDefend' -ErrorAction SilentlyContinue

        if (-not $mpService) {
            Write-LogMessage "Windows Defender ist nicht verfügbar" -Level Warning
            return
        }

        if ($mpService.Status -ne 'Running') {
            Write-LogMessage "Windows Defender-Dienst läuft nicht" -Level Warning
            return
        }

        Update-MpSignature -ErrorAction Stop
        Write-LogMessage "Windows Defender-Signaturen erfolgreich aktualisiert" -Level Success

    } catch {
        Write-LogMessage "Defender-Signaturen konnten nicht aktualisiert werden: $($_.Exception.Message)" -Level Warning
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
        Zeigt eine Zusammenfassung der Ausführung an.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [hashtable]$InstallResult,

        [Parameter(Mandatory=$true)]
        [int]$UpdateCount
    )

    $duration = (Get-Date) - $script:StartTime

    Write-LogMessage "`n`n═══════════════════════════════════════════════════════" -Level Header
    Write-LogMessage "ZUSAMMENFASSUNG" -Level Header
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level Header

    Write-LogMessage "Startzeit:                  $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info
    Write-LogMessage "Endzeit:                    $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info
    Write-LogMessage "Dauer:                      $($duration.Hours)h $($duration.Minutes)m $($duration.Seconds)s" -Level Info
    Write-LogMessage "Gefundene Updates:          $UpdateCount" -Level Info

    # Sichere Zugriffe auf Hashtable-Werte
    $installedCount = if ($InstallResult.ContainsKey('InstalledCount')) { $InstallResult.InstalledCount } else { 0 }
    $rebootRequired = if ($InstallResult.ContainsKey('RebootRequired')) { $InstallResult.RebootRequired } else { $false }

    Write-LogMessage "Installierte Updates:       $installedCount" -Level $(if ($installedCount -gt 0) { 'Success' } else { 'Info' })
    Write-LogMessage "Neustart erforderlich:      $(if ($rebootRequired) { 'JA' } else { 'NEIN' })" -Level $(if ($rebootRequired) { 'Warning' } else { 'Success' })
    Write-LogMessage "Fehler aufgetreten:         $script:ErrorCount" -Level $(if ($script:ErrorCount -gt 0) { 'Error' } else { 'Success' })
    Write-LogMessage "Warnungen aufgetreten:      $script:WarningCount" -Level $(if ($script:WarningCount -gt 0) { 'Warning' } else { 'Success' })

    if ($rebootRequired) {
        Write-LogMessage "`n⚠ WICHTIG: Ein Neustart ist erforderlich, um die Installation abzuschließen!" -Level Warning
        if ($RebootIfNeeded) {
            Write-LogMessage "Der Computer wird in 30 Sekunden neu gestartet..." -Level Warning
        } else {
            Write-LogMessage "Bitte starten Sie den Computer manuell neu." -Level Warning
        }
    }

    Write-LogMessage "═══════════════════════════════════════════════════════`n" -Level Header
}

# ============================================================================
# HAUPTPROGRAMM
# ============================================================================

try {
    # Log-Verzeichnis erstellen
    if (-not (Test-Path -Path $LogPath)) {
        $null = New-Item -ItemType Directory -Path $LogPath -Force -ErrorAction Stop
    }

    # Log-Datei erstellen
    $logFile = Join-Path $LogPath ("WindowsUpdate_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
    Start-Transcript -Path $logFile -Append -ErrorAction Stop

    # Header anzeigen
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level Header
    Write-LogMessage "Windows Update Reparatur & Installation" -Level Header
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level Header
    Write-LogMessage "Startzeit: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info
    Write-LogMessage "Log-Datei: $logFile" -Level Info
    Write-LogMessage "═══════════════════════════════════════════════════════`n" -Level Header

    # Parameter anzeigen
    Write-LogMessage "Konfiguration:" -Level Info
    Write-LogMessage "  Treiber einschließen:        $IncludeDrivers" -Level Info
    Write-LogMessage "  Feature-Updates einschließen: $IncludeFeatureUpdates" -Level Info
    Write-LogMessage "  Auto-Neustart:               $RebootIfNeeded" -Level Info
    Write-LogMessage "  Bereinigung überspringen:    $SkipCleanup`n" -Level Info

    # Administratorrechte prüfen
    if (-not (Test-AdministratorPrivileges)) {
        Write-LogMessage "FEHLER: Dieses Script benötigt Administratorrechte!" -Level Error
        Write-LogMessage "Bitte führen Sie PowerShell als Administrator aus." -Level Error
        exit 1
    }

    # ========== BEREINIGUNG ==========
    if (-not $SkipCleanup) {
        Invoke-WindowsUpdateCleanup
    } else {
        Write-LogMessage "Bereinigung wurde übersprungen (Parameter -SkipCleanup)" -Level Warning
    }

    # ========== UPDATE-SUCHE ==========
    Write-LogMessage "`n`n═══════════════════════════════════════════════════════" -Level Header
    Write-LogMessage "PHASE 2: Suche nach Updates" -Level Header
    Write-LogMessage "═══════════════════════════════════════════════════════" -Level Header

    $updates = Get-WindowsUpdates -IncludeDrivers $IncludeDrivers.IsPresent `
                                   -IncludeFeatureUpdates $IncludeFeatureUpdates.IsPresent

    if ($updates.Count -eq 0) {
        Write-LogMessage "`nKeine passenden Updates gefunden." -Level Success
        Write-LogMessage "Das System ist auf dem aktuellen Stand!" -Level Success

        # Defender-Signaturen trotzdem aktualisieren
        Update-DefenderSignatures

        $installResult = @{
            Success = $true
            RebootRequired = $false
            InstalledCount = 0
        }
    } else {
        # ========== INSTALLATION ==========
        $installResult = Install-WindowsUpdates -Updates $updates

        # ========== DEFENDER-SIGNATUREN ==========
        Update-DefenderSignatures
    }

    # ========== ZUSAMMENFASSUNG ==========
    Show-Summary -InstallResult $installResult -UpdateCount $updates.Count

    # ========== NEUSTART ==========
    if ($installResult.RebootRequired -and $RebootIfNeeded) {
        Write-LogMessage "Stoppe Transkript vor Neustart..." -Level Info
        Stop-Transcript

        Write-Host "`nNeustart in 30 Sekunden..." -ForegroundColor Yellow
        Write-Host "Drücken Sie Strg+C zum Abbrechen`n" -ForegroundColor Yellow
        Start-Sleep -Seconds 30

        Restart-Computer -Force
    } else {
        Stop-Transcript
    }

    # Exit-Code basierend auf Erfolg
    if ($installResult.Success -and $script:ErrorCount -eq 0) {
        exit 0
    } elseif ($installResult.Success -and $script:ErrorCount -gt 0) {
        exit 1
    } else {
        exit 2
    }

} catch {
    Write-LogMessage "`nKRITISCHER FEHLER: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack-Trace: $($_.ScriptStackTrace)" -Level Error

    try { Stop-Transcript } catch { }
    exit 99
}
