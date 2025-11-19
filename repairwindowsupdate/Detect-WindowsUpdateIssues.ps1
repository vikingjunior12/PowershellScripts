<#
.SYNOPSIS
    Detection-Script für Windows Update Probleme (Intune Remediation)

.DESCRIPTION
    Prüft ob Windows Update Probleme vorliegen, die eine Reparatur erfordern.
    Exit 0 = Alles OK, keine Remediation nötig
    Exit 1 = Problem erkannt, Remediation wird ausgeführt

.NOTES
    Autor: Windows Update Detection Script
    Datum: 2025-10-24
    Für: Microsoft Intune Proactive Remediations
#>

try {
    $IssuesFound = $false
    $IssueDetails = @()

    # 1. Prüfe Windows Update Dienste
    $RequiredServices = @("wuauserv", "BITS", "CryptSvc")
    foreach ($ServiceName in $RequiredServices) {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($Service.Status -ne "Running") {
            $IssuesFound = $true
            $IssueDetails += "Dienst $ServiceName läuft nicht (Status: $($Service.Status))"
        }
    }

    # 2. Prüfe auf fehlgeschlagene Updates im Windows Update Log
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()

    # Prüfe auf Updates mit Fehler-Status
    $HistoryCount = $UpdateSearcher.GetTotalHistoryCount()
    if ($HistoryCount -gt 0) {
        # Hole die letzten 50 Einträge
        $History = $UpdateSearcher.QueryHistory(0, [Math]::Min(50, $HistoryCount))

        # Zähle fehlgeschlagene Updates in den letzten 7 Tagen
        $LastWeek = (Get-Date).AddDays(-7)
        $RecentFailures = $History | Where-Object {
            $_.Date -gt $LastWeek -and
            $_.ResultCode -eq 4  # 4 = Failed
        }

        if ($RecentFailures.Count -ge 3) {
            $IssuesFound = $true
            $IssueDetails += "$($RecentFailures.Count) fehlgeschlagene Updates in den letzten 7 Tagen"
        }
    }

    # 3. Prüfe Größe des SoftwareDistribution Ordners (über 5GB könnte problematisch sein)
    $SoftwareDistribution = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $SoftwareDistribution) {
        $FolderSize = (Get-ChildItem -Path $SoftwareDistribution -Recurse -ErrorAction SilentlyContinue |
                       Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $FolderSizeGB = [Math]::Round($FolderSize / 1GB, 2)

        if ($FolderSizeGB -gt 5) {
            $IssuesFound = $true
            $IssueDetails += "SoftwareDistribution Ordner ist sehr groß: ${FolderSizeGB}GB"
        }
    }

    # 4. Prüfe Windows Update Error Code im Registry (optional)
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install"
    if (Test-Path $RegPath) {
        $LastError = Get-ItemProperty -Path $RegPath -Name "LastError" -ErrorAction SilentlyContinue
        if ($LastError.LastError -ne 0) {
            $IssuesFound = $true
            $IssueDetails += "Windows Update LastError: 0x$($LastError.LastError.ToString('X'))"
        }
    }

    # Ergebnis ausgeben
    if ($IssuesFound) {
        Write-Output "Windows Update Probleme erkannt:"
        foreach ($Issue in $IssueDetails) {
            Write-Output "- $Issue"
        }
        exit 1  # Problem gefunden -> Remediation ausführen
    } else {
        Write-Output "Keine Windows Update Probleme erkannt"
        exit 0  # Alles OK -> keine Remediation nötig
    }

} catch {
    Write-Output "Fehler bei der Detection: $_"
    exit 0  # Bei Fehler keine Remediation ausführen
}
