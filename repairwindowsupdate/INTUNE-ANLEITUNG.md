# Windows Update Remediation für Microsoft Intune

## Übersicht

Diese Lösung besteht aus zwei PowerShell-Scripts für Microsoft Intune Proactive Remediations:

1. **Detect-WindowsUpdateIssues.ps1** - Detection Script
2. **Remediate-WindowsUpdate.ps1** - Remediation Script

## Funktionsweise

### Detection Script
Prüft auf folgende Windows Update Probleme:
- Windows Update Dienste laufen nicht
- Mehrere fehlgeschlagene Updates in den letzten 7 Tagen
- Übermäßig großer SoftwareDistribution Ordner (> 5GB)
- Windows Update Fehler-Codes im Registry

**Exit Codes:**
- `Exit 0` = Alles OK, keine Remediation nötig
- `Exit 1` = Problem erkannt, Remediation wird ausgeführt

### Remediation Script
Führt folgende Schritte aus:
- Stoppt Windows Update Dienste (BITS, wuauserv, AppIDSvc, CryptSvc)
- Benennt SoftwareDistribution Ordner um (Backup)
- Benennt catroot2 Ordner um (Backup)
- Löscht temporäre Download-Dateien
- Registriert Windows Update DLLs neu
- Setzt Winsock und WinHTTP Proxy zurück
- Startet alle Dienste neu

**Exit Codes:**
- `Exit 0` = Remediation erfolgreich
- `Exit 1` = Remediation fehlgeschlagen

**Logs:** `C:\ProgramData\WindowsUpdateRemediation\WindowsUpdate-Reset-*.log`

## Einrichtung in Microsoft Intune

### Schritt 1: Proactive Remediation erstellen

1. Gehe zu **Microsoft Intune Admin Center** (https://intune.microsoft.com)
2. Navigiere zu: **Devices** → **Scripts and Remediations** → **Proactive Remediations**
3. Klicke auf **+ Create**

### Schritt 2: Grundeinstellungen

- **Name:** `Windows Update - Reparatur`
- **Description:** `Erkennt und behebt Windows Update Probleme automatisch`

### Schritt 3: Scripts hochladen

**Detection script:**
- Lade `Detect-WindowsUpdateIssues.ps1` hoch
- **Run this script using the logged-on credentials:** `No` (als SYSTEM ausführen)
- **Enforce script signature check:** `No`
- **Run script in 64-bit PowerShell:** `Yes`

**Remediation script:**
- Lade `Remediate-WindowsUpdate.ps1` hoch
- **Run this script using the logged-on credentials:** `No` (als SYSTEM ausführen)
- **Enforce script signature check:** `No`
- **Run script in 64-bit PowerShell:** `Yes`

### Schritt 4: Zuweisungen (Assignments)

**Empfohlene Einstellungen:**

- **Assign to:** Wähle die gewünschten Gerätegruppen aus
  - z.B. "Alle Windows 10/11 Geräte"
  - Oder spezifische Gruppen mit Update-Problemen

**Schedule:**
- **Run schedule:** `Daily` (Täglich)
- **Start time:** z.B. `03:00` (außerhalb der Arbeitszeiten)
- Alternativ: `Every 4 hours` für kritische Umgebungen

### Schritt 5: Überprüfen und Erstellen

- Überprüfe alle Einstellungen
- Klicke auf **Create**

## Monitoring und Berichte

### Ergebnisse anzeigen

1. Gehe zu: **Devices** → **Scripts and Remediations** → **Proactive Remediations**
2. Klicke auf deine erstellte Remediation
3. Wähle **Device status** oder **Overview**

### Status-Bedeutungen

- **With issues** = Detection hat Probleme erkannt
- **Without issues** = Keine Probleme gefunden
- **Remediation successful** = Remediation erfolgreich ausgeführt
- **Remediation failed** = Remediation fehlgeschlagen

### Logs auf Client-Geräten

**Intune Management Extension Logs:**
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log
```

**Script-spezifische Logs:**
```
C:\ProgramData\WindowsUpdateRemediation\WindowsUpdate-Reset-*.log
```

## Wichtige Hinweise

### Neustart erforderlich
Nach der Remediation wird ein Neustart empfohlen. Du kannst optional ein Reboot-Script hinzufügen oder einen separaten Intune Reboot-Task erstellen.

### Berechtigungen
Die Scripts laufen automatisch mit SYSTEM-Rechten durch Intune - keine zusätzlichen Berechtigungen erforderlich.

### Häufigkeit
- **Empfehlung für Produktivumgebungen:** 1x täglich
- **Bei akuten Update-Problemen:** Alle 4-6 Stunden
- **Nach erfolgreicher Remediation:** Das Detection-Script verhindert unnötige Wiederholungen

### Rollout-Strategie

**Phase 1: Testgruppe**
1. Erstelle eine Testgruppe mit 5-10 Geräten
2. Aktiviere die Remediation für diese Gruppe
3. Überwache die Ergebnisse für 1-2 Tage

**Phase 2: Pilot-Gruppe**
1. Erweitere auf 50-100 Geräte
2. Überwache für 1 Woche
3. Sammle Feedback von Benutzern

**Phase 3: Vollständiger Rollout**
1. Aktiviere für alle Geräte
2. Kontinuierliches Monitoring

## Troubleshooting

### Detection läuft nicht
- Prüfe die Intune Management Extension Logs
- Stelle sicher, dass das Gerät mit Intune synchronisiert ist
- Prüfe ob das Gerät die Mindestanforderungen erfüllt

### Remediation schlägt fehl
- Prüfe das Script-Log: `C:\ProgramData\WindowsUpdateRemediation\WindowsUpdate-Reset-*.log`
- Häufige Ursachen:
  - Dienste können nicht gestoppt werden (andere Prozesse blockieren)
  - Dateien sind in Verwendung
  - Unzureichende Berechtigungen (sollte nicht vorkommen bei SYSTEM)

### Remediation läuft, aber Update funktioniert immer noch nicht
- Manueller Neustart des Geräts erforderlich
- Prüfe Windows Update Log: `C:\Windows\Logs\WindowsUpdate\`
- Eventuell tiefere Windows-Probleme, die manuelle Intervention erfordern

## Anpassungen

### Detection-Schwellwerte anpassen

In `Detect-WindowsUpdateIssues.ps1`:

```powershell
# Anzahl fehlgeschlagener Updates ändern
if ($RecentFailures.Count -ge 3) {  # Standard: 3, kann erhöht werden

# SoftwareDistribution Größe ändern
if ($FolderSizeGB -gt 5) {  # Standard: 5GB, kann angepasst werden
```

### Zusätzliche Dienste hinzufügen

In `Remediate-WindowsUpdate.ps1`:

```powershell
$Services = @("BITS", "wuauserv", "AppIDSvc", "CryptSvc", "DeinDienst")
```

## Support und Feedback

Bei Problemen oder Fragen:
- Prüfe die Log-Dateien auf beiden Scripts
- Teste die Scripts lokal als Administrator
- Kontaktiere deinen Intune-Administrator

## Version

- **Version:** 1.0
- **Datum:** 2025-10-24
- **Getestet mit:** Windows 10 (21H2+), Windows 11
- **Intune:** Proactive Remediations
