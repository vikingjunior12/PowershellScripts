<#
.SYNOPSIS
    Intune Autopilot Device Registration Script
.DESCRIPTION
    Sammelt Hardware-Hash-Informationen für Autopilot und ermöglicht entweder
    lokale CSV-Speicherung oder direkten Online-Upload zu Intune.
.NOTES
    Erfordert Administratorrechte
#>

#Requires -RunAsAdministrator

# Farben für bessere Lesbarkeit
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Banner
Clear-Host
Write-ColorOutput "========================================" "Cyan"
Write-ColorOutput "  Intune Autopilot Registration Tool" "Cyan"
Write-ColorOutput "========================================" "Cyan"
Write-Host ""

# Überprüfung ob als Administrator ausgeführt
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-ColorOutput "FEHLER: Dieses Script muss als Administrator ausgefuehrt werden!" "Red"
    Write-Host ""
    Write-Host "Druecke eine beliebige Taste zum Beenden..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Variablen
$workingDir = "C:\HWID"

try {
    # TLS 1.2 aktivieren
    Write-ColorOutput "[+] Aktiviere TLS 1.2..." "Yellow"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Arbeitsverzeichnis erstellen
    if (-not (Test-Path -Path $workingDir)) {
        Write-ColorOutput "[+] Erstelle Arbeitsverzeichnis: $workingDir" "Yellow"
        New-Item -Type Directory -Path $workingDir -Force | Out-Null
    }
    Set-Location -Path $workingDir

    # PowerShell Scripts Pfad hinzufügen
    if ($env:Path -notlike "*WindowsPowerShell\Scripts*") {
        $env:Path += ";C:\Program Files\WindowsPowerShell\Scripts"
    }

    # ExecutionPolicy setzen
    Write-ColorOutput "[+] Setze ExecutionPolicy..." "Yellow"
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force

    # Überprüfen ob Get-WindowsAutopilotInfo bereits installiert ist
    $scriptInstalled = Get-InstalledScript -Name Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue

    if (-not $scriptInstalled) {
        Write-ColorOutput "[+] Installiere Get-WindowsAutopilotInfo Script..." "Yellow"

        # NuGet Provider prüfen
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nugetProvider) {
            Write-ColorOutput "[+] Installiere NuGet Provider..." "Yellow"
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }

        # PSGallery als vertrauenswürdig setzen
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        Install-Script -Name Get-WindowsAutopilotInfo -Force -Scope CurrentUser
        Write-ColorOutput "[OK] Get-WindowsAutopilotInfo erfolgreich installiert" "Green"
    } else {
        Write-ColorOutput "[OK] Get-WindowsAutopilotInfo ist bereits installiert" "Green"
    }

    # Benutzer nach Methode fragen
    Write-Host ""
    Write-ColorOutput "Waehle die Registrierungsmethode:" "Cyan"
    Write-Host "  [1] CSV-Datei lokal speichern"
    Write-Host "  [2] Online-Upload direkt zu Intune"
    Write-Host ""

    do {
        $choice = Read-Host "Deine Auswahl (1 oder 2)"
    } while ($choice -ne "1" -and $choice -ne "2")

    Write-Host ""

    if ($choice -eq "1") {
        # CSV-Methode
        Write-ColorOutput "=== CSV-Datei Modus ===" "Cyan"
        Write-Host ""

        # Dateinamen abfragen
        $defaultName = "AutopilotHWID"
        $fileName = Read-Host "Dateiname fuer die CSV (ohne .csv, Enter fuer Standard '$defaultName')"

        if ([string]::IsNullOrWhiteSpace($fileName)) {
            $fileName = $defaultName
        }

        # Ungültige Zeichen entfernen
        $fileName = $fileName -replace '[\\/:*?"<>|]', '_'
        $outputFile = Join-Path -Path $workingDir -ChildPath "$fileName.csv"

        Write-ColorOutput "[+] Sammle Hardware-Informationen..." "Yellow"
        Get-WindowsAutopilotInfo -OutputFile $outputFile

        if (Test-Path -Path $outputFile) {
            Write-Host ""
            Write-ColorOutput "[OK] CSV-Datei erfolgreich erstellt!" "Green"
            Write-ColorOutput "     Speicherort: $outputFile" "Green"
            Write-Host ""
            Write-ColorOutput "Naechste Schritte:" "Cyan"
            Write-Host "  1. Oeffne https://intune.microsoft.com"
            Write-Host "  2. Gehe zu Devices > Enroll devices > Windows > Devices"
            Write-Host "  3. Klicke auf 'Import' und waehle die CSV-Datei aus"
        } else {
            Write-ColorOutput "[FEHLER] CSV-Datei konnte nicht erstellt werden!" "Red"
            exit 1
        }

    } else {
        # Online-Upload-Methode
        Write-ColorOutput "=== Online-Upload Modus ===" "Cyan"
        Write-Host ""

        # Microsoft.Graph.Intune Modul prüfen und installieren
        $graphModule = Get-Module -Name Microsoft.Graph.Intune -ListAvailable -ErrorAction SilentlyContinue

        if (-not $graphModule) {
            Write-ColorOutput "[+] Installiere Microsoft.Graph.Intune Modul..." "Yellow"
            Write-ColorOutput "    Dies kann einige Minuten dauern..." "Yellow"
            Install-Module -Name Microsoft.Graph.Intune -Force -Scope CurrentUser -AllowClobber
            Write-ColorOutput "[OK] Modul erfolgreich installiert" "Green"
        }

        # Modul importieren
        Write-ColorOutput "[+] Importiere Microsoft.Graph.Intune Modul..." "Yellow"
        Import-Module Microsoft.Graph.Intune -ErrorAction Stop

        # Bei Intune anmelden
        Write-Host ""
        Write-ColorOutput "[+] Anmeldung bei Microsoft Intune..." "Yellow"
        Write-ColorOutput "    Bitte melde dich im Browser-Fenster mit deinem Admin-Account an." "Yellow"
        Write-Host ""

        try {
            Connect-MSGraph -ErrorAction Stop | Out-Null
            Write-ColorOutput "[OK] Erfolgreich angemeldet!" "Green"
        } catch {
            Write-ColorOutput "[FEHLER] Anmeldung fehlgeschlagen: $($_.Exception.Message)" "Red"
            exit 1
        }

        # Hardware-Info sammeln und direkt hochladen
        Write-Host ""
        Write-ColorOutput "[+] Sammle Hardware-Informationen und lade hoch..." "Yellow"

        # Gruppentag abfragen (optional)
        Write-Host ""
        $groupTag = Read-Host "Gruppentag (optional, Enter zum Ueberspringen)"

        if ([string]::IsNullOrWhiteSpace($groupTag)) {
            Get-WindowsAutopilotInfo -Online
        } else {
            Get-WindowsAutopilotInfo -Online -GroupTag $groupTag
        }

        Write-Host ""
        Write-ColorOutput "[OK] Geraet erfolgreich zu Autopilot hinzugefuegt!" "Green"
        Write-Host ""
        Write-ColorOutput "Naechste Schritte:" "Cyan"
        Write-Host "  1. Oeffne https://intune.microsoft.com"
        Write-Host "  2. Gehe zu Devices > Enroll devices > Windows > Devices"
        Write-Host "  3. Ueberprüfe ob das Geraet in der Liste erscheint"
        Write-Host "  4. Weise bei Bedarf ein Deployment Profile zu"
    }

} catch {
    Write-Host ""
    Write-ColorOutput "[FEHLER] Ein Fehler ist aufgetreten:" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    Write-Host ""
    Write-ColorOutput "Stack Trace:" "Yellow"
    Write-Host $_.ScriptStackTrace
    exit 1
} finally {
    # Aufräumen
    Write-Host ""
    Write-Host "Druecke eine beliebige Taste zum Beenden..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
