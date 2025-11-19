# Windows Update Reparatur & Installation - Detaillierte Anleitung

## Übersicht

Das Script `Repair-WindowsUpdate.ps1` ist ein umfassendes PowerShell-Tool zur Diagnose, Reparatur und Installation von Windows Updates. Es behebt häufige Probleme mit Windows Update und installiert anschließend verfügbare Updates automatisch.

---

## Inhaltsverzeichnis

1. [Voraussetzungen](#voraussetzungen)
2. [Verwendung](#verwendung)
3. [Parameter](#parameter)
4. [Schritt-für-Schritt Erklärung](#schritt-für-schritt-erklärung)
5. [Phase 1: Windows Update-Bereinigung](#phase-1-windows-update-bereinigung)
6. [Phase 2: Update-Suche und Installation](#phase-2-update-suche-und-installation)
7. [Hilfsfunktionen](#hilfsfunktionen)
8. [Fehlerbehandlung](#fehlerbehandlung)
9. [Log-Dateien](#log-dateien)
10. [Exit-Codes](#exit-codes)

---

## Voraussetzungen

- **Windows**: Windows 10 oder Windows 11
- **PowerShell**: Version 5.1 oder höher
- **Berechtigungen**: Administratorrechte erforderlich
- **Keine externen Module**: Das Script verwendet nur native Windows-Komponenten (COM-Objekte)

---

## Verwendung

### Einfache Ausführung (Standard)

```powershell
.\Repair-WindowsUpdate.ps1
```

Führt eine vollständige Bereinigung durch und installiert Software-Updates.

### Mit Treibern

```powershell
.\Repair-WindowsUpdate.ps1 -IncludeDrivers
```

Installiert auch Treiber-Updates.

### Mit automatischem Neustart

```powershell
.\Repair-WindowsUpdate.ps1 -RebootIfNeeded
```

Startet den Computer automatisch neu, wenn Updates dies erfordern.

### Nur Updates (ohne Bereinigung)

```powershell
.\Repair-WindowsUpdate.ps1 -SkipCleanup
```

Überspringt die Bereinigungsphase und installiert nur Updates.

### Vollständige Installation (alles inkl. Feature-Updates)

```powershell
.\Repair-WindowsUpdate.ps1 -IncludeDrivers -IncludeFeatureUpdates -RebootIfNeeded
```

---

## Parameter

| Parameter | Typ | Standard | Beschreibung |
|-----------|-----|----------|--------------|
| `IncludeDrivers` | Switch | Aus | Schließt Treiber-Updates mit ein |
| `IncludeFeatureUpdates` | Switch | Aus | Schließt Feature-Updates (z.B. Windows 11 23H2) mit ein |
| `RebootIfNeeded` | Switch | Aus | Startet automatisch neu, wenn erforderlich |
| `SkipCleanup` | Switch | Aus | Überspringt die Bereinigungsphase |
| `LogPath` | String | `C:\ProgramData\UpdateForce` | Verzeichnis für Log-Dateien |

---

## Schritt-für-Schritt Erklärung

### Initialisierung (Zeilen 76-84)

Das Script beginnt mit der Konfiguration grundlegender Variablen:

```powershell
$ErrorActionPreference = 'Stop'
$script:ErrorCount = 0
$script:WarningCount = 0
$script:StartTime = Get-Date
```

**Was passiert hier:**
- **ErrorActionPreference**: Alle Fehler stoppen die Ausführung (Sicherheitsmechanismus)
- **Zähler**: Tracking von Fehlern und Warnungen für die Zusammenfassung
- **Startzeit**: Wird für die Berechnung der Ausführungsdauer verwendet

### Log-System (Zeilen 98-138)

Die Funktion `Write-LogMessage` ist das zentrale Logging-System:

**Funktionen:**
- Zeitstempel zu jeder Nachricht hinzufügen
- Farbcodierung nach Schweregrad (Info, Success, Warning, Error, Header)
- Symbole (✓, ✗, ⚠, ℹ) für bessere Lesbarkeit
- Automatisches Schreiben in Console und Log-Datei
- Zähler für Fehler und Warnungen

**Beispiel-Ausgabe:**
```
[2025-10-16 14:23:45] ✓ Dienst 'wuauserv' erfolgreich gestoppt
[2025-10-16 14:23:46] ⚠ Timeout beim Stoppen von Dienst 'bits'
```

---

## Phase 1: Windows Update-Bereinigung

Diese Phase behebt typische Probleme mit Windows Update durch systematische Bereinigung aller Komponenten.

### Schritt 1.1: Dienste stoppen (Zeilen 333-341)

**Gestoppte Dienste:**
1. **wuauserv** (Windows Update)
   - Hauptdienst für Windows Update
   - Koordiniert die Update-Suche und Installation

2. **bits** (Background Intelligent Transfer Service)
   - Verwaltet Downloads im Hintergrund
   - Wird von Windows Update für Downloads verwendet

3. **cryptsvc** (Cryptographic Services)
   - Validiert digitale Signaturen von Updates
   - Verwaltet Zertifikate

4. **msiserver** (Windows Installer)
   - Installiert MSI-basierte Updates
   - Wird für einige Update-Typen benötigt

**Warum dieser Schritt wichtig ist:**
- Dienste müssen gestoppt werden, um Cache-Dateien zu löschen
- Verhindert Dateisperren beim Löschen von Verzeichnissen
- Sicherer Neustart der Dienste mit sauberen Komponenten

**Technische Details:**
```powershell
function Stop-ServiceSafely {
    # 1. Prüft, ob Dienst existiert
    # 2. Prüft aktuellen Status
    # 3. Stoppt Dienst mit -Force
    # 4. Wartet bis zu 30 Sekunden auf Bestätigung
    # 5. Fehlerbehandlung mit Timeout-Erkennung
}
```

### Schritt 1.2: Cache-Verzeichnisse löschen (Zeilen 343-353)

**Gelöschte Verzeichnisse:**

1. **C:\Windows\SoftwareDistribution**
   - Enthält heruntergeladene Update-Dateien
   - Speichert Update-Historie und -Metadaten
   - Datenbank mit Update-Informationen

   **Unterverzeichnisse:**
   - `Download\` - Heruntergeladene Updates (oft mehrere GB)
   - `DataStore\` - Datenbank-Dateien (.edb, .log)
   - `PostRebootEventCache.V2\` - Neustart-Ereignisse

2. **C:\Windows\System32\catroot2**
   - Kryptografischer Katalog-Cache
   - Signatur-Validierungsinformationen
   - Wird bei beschädigten Signaturen gelöscht

**Lösch-Mechanismus:**
```powershell
function Remove-DirectorySafely {
    # 1. Prüft, ob Verzeichnis existiert
    # 2. Bis zu 3 Versuche zum Löschen
    # 3. Wartet 2 Sekunden zwischen Versuchen
    # 4. Fehlerbehandlung für gesperrte Dateien
    # 5. Rekursives Löschen aller Unterverzeichnisse
}
```

**Warum dieser Schritt hilft:**
- Behebt beschädigte Download-Caches
- Löst "Update bleibt bei X% hängen"-Probleme
- Befreit oft mehrere GB Speicherplatz
- Zwingt Windows Update, Metadaten neu zu erstellen

### Schritt 1.3: Dienste neu starten (Zeilen 356-360)

**Was passiert:**
- Alle zuvor gestoppten Dienste werden neu gestartet
- Dienste initialisieren sich mit sauberen Caches
- Windows Update-Datenbank wird neu erstellt

**Technische Details:**
```powershell
function Start-ServiceSafely {
    # 1. Prüft, ob Dienst existiert
    # 2. Prüft, ob Dienst bereits läuft
    # 3. Startet Dienst
    # 4. Wartet bis zu 30 Sekunden auf "Running"-Status
    # 5. Fehlerbehandlung mit Timeout-Erkennung
}
```

### Schritt 1.4: DISM-Komponentenbereinigung (Zeilen 362-364)

**DISM (Deployment Image Servicing and Management):**

**Ausgeführte Befehle:**
```powershell
dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
```

**Parameter-Erklärung:**
- `/Online` - Arbeitet am laufenden System (nicht an Offline-Image)
- `/Cleanup-Image` - Bereinigt das Windows-Image
- `/StartComponentCleanup` - Entfernt veraltete Update-Komponenten
- `/ResetBase` - Löscht alte Update-Versionen (spart viel Speicherplatz)

**Was wird bereinigt:**
- Superseded Components (ersetzte Update-Komponenten)
- Alte Windows-Update-Backups
- WinSxS-Verzeichnis wird optimiert (oft mehrere GB)

**Dauer:** Kann 5-15 Minuten dauern

**Fehlerbehandlung:**
- Exit-Code 0 = Erfolg
- Andere Codes = Warnung (Script fährt fort)

### Schritt 1.5: Windows Update-Komponenten neu registrieren (Zeilen 367-394)

**Registrierte DLL-Dateien (insgesamt 34):**

**Kategorie 1: Kern-System-DLLs**
- `atl.dll`, `ole32.dll`, `oleaut32.dll`, `shell32.dll`
- Grundlegende Windows-Komponenten

**Kategorie 2: Internet/HTML-DLLs**
- `urlmon.dll`, `mshtml.dll`, `shdocvw.dll`, `browseui.dll`
- Für Update-Download über HTTPS

**Kategorie 3: Scripting-DLLs**
- `jscript.dll`, `vbscript.dll`, `scrrun.dll`
- Für Update-Installationsskripte

**Kategorie 4: XML-Parser**
- `msxml.dll`, `msxml3.dll`, `msxml6.dll`
- Für Update-Metadaten (XML-Dateien)

**Kategorie 5: Kryptografie-DLLs**
- `softpub.dll`, `wintrust.dll`, `dssenh.dll`, `rsaenh.dll`
- `gpkcsp.dll`, `sccbase.dll`, `slbcsp.dll`, `cryptdlg.dll`, `initpki.dll`
- Für digitale Signaturen und Zertifikate

**Kategorie 6: Windows Update-spezifische DLLs**
- `wuapi.dll` - Windows Update API
- `wuaueng.dll`, `wuaueng1.dll` - Update-Engine
- `wucltui.dll` - Client-UI
- `wups.dll`, `wups2.dll` - Update-Services
- `wuweb.dll`, `wuwebv.dll` - Web-Komponenten
- `wucltux.dll`, `muweb.dll` - Client-Erweiterungen

**Kategorie 7: BITS-DLLs**
- `qmgr.dll`, `qmgrprxy.dll`
- Background Intelligent Transfer Service

**Registrierungs-Prozess:**
```powershell
regsvr32.exe /s dll-name
```

- `/s` = Silent Mode (keine Popup-Fenster)
- Registriert DLL im Windows-System
- Behebt Probleme mit beschädigten COM-Registrierungen

**Erfolgsrate:**
- Script zählt erfolgreich registrierte DLLs
- Fehlende DLLs werden übersprungen (SilentlyContinue)
- Typischerweise 30-34 von 34 DLLs erfolgreich

---

## Phase 2: Update-Suche und Installation

### Schritt 2.1: Windows Update-Session erstellen (Zeilen 412-414)

**COM-Objekte:**
```powershell
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
```

**Was ist Microsoft.Update.Session:**
- Native Windows-API für Update-Verwaltung
- Gleiche API wie Windows Update verwendet
- Kein externes PowerShell-Modul erforderlich
- Funktioniert auf allen Windows 10/11-Versionen

### Schritt 2.2: Update-Suche mit Kriterien (Zeilen 417-426)

**Suchkriterien:**

**Standard (ohne -IncludeDrivers):**
```
"IsInstalled=0 and Type='Software' and IsHidden=0"
```
- `IsInstalled=0` - Nur nicht installierte Updates
- `Type='Software'` - Nur Software-Updates
- `IsHidden=0` - Keine versteckten Updates

**Mit -IncludeDrivers:**
```
"IsInstalled=0 and IsHidden=0"
```
- Schließt auch Treiber-Updates ein

**Suchprozess:**
- Kontaktiert Microsoft Update-Server
- Vergleicht installierte Updates mit verfügbaren
- Dauer: 1-5 Minuten (abhängig von Internet-Geschwindigkeit)
- Gibt `ISearchResult`-Objekt zurück

### Schritt 2.3: Update-Filterung (Zeilen 437-464)

**Filtering-Logik:**

1. **Titel-Validierung:**
   ```powershell
   if ([string]::IsNullOrWhiteSpace($update.Title)) {
       # Überspringe beschädigte Updates
   }
   ```

2. **Feature-Update-Erkennung:**
   ```powershell
   foreach ($category in $update.Categories) {
       if ($category.Name -match 'Upgrade|Feature Update|Feature Pack') {
           $isFeatureUpdate = $true
       }
   }
   ```

   **Feature-Updates sind:**
   - Windows 11 22H2 → 23H2
   - Windows 10 21H2 → 22H2
   - Große OS-Upgrades (10-20 GB)

   **Standard-Verhalten:**
   - Feature-Updates werden NICHT installiert
   - Verhindert unerwartete OS-Upgrades
   - Nur mit `-IncludeFeatureUpdates` installiert

3. **ArrayList für Performance:**
   ```powershell
   $updates = New-Object System.Collections.ArrayList
   [void]$updates.Add($update)
   ```
   - Schneller als Array-Konkatenation
   - Wichtig bei vielen Updates (50+)

### Schritt 2.4: Update-Liste anzeigen (Zeilen 501-516)

**Ausgabe-Beispiel:**
```
Gefundene Updates (5):
  1. 2025-10 Kumulative Update für Windows 11 (KB5031455) (324.56 MB)
  2. Windows Malicious Software Removal Tool (78.12 MB)
  3. Microsoft Defender Antivirus Update (5.23 MB)
  4. .NET Framework 4.8.1 Security Update (45.67 MB)
  5. Microsoft Edge Update (156.34 MB)
```

**Berechnung der Größe:**
```powershell
$size = $update.MaxDownloadSize / 1MB
```
- Gibt dem Benutzer Transparenz
- Hilft bei Zeitplanung (große Downloads)
- Zeigt 0 MB bei bereits gecachten Updates

### Schritt 2.5: Update-Collection erstellen (Zeilen 519-549)

**COM-Collection:**
```powershell
$updateCollection = New-Object -ComObject Microsoft.Update.UpdateColl
$updateCollection.Add($update)
```

**Validierung:**
- Überspringe `null`-Updates
- Try-Catch für jedes Update
- Zähle gültige Updates
- Fehle bei 0 gültigen Updates

### Schritt 2.6: Download-Phase (Zeilen 551-578)

**Download-Prozess:**
```powershell
$downloader = $session.CreateUpdateDownloader()
$downloader.Updates = $updateCollection
$downloadResult = $downloader.Download()
```

**Download-Verhalten:**
- Lädt Updates parallel herunter
- BITS (Background Intelligent Transfer Service)
- Setzt Downloads nach Unterbrechung fort
- Kann pausiert werden bei Bandbreiten-Mangel

**Result-Codes:**
- `0` - Nicht gestartet
- `1` - In Bearbeitung
- `2` - Erfolgreich ✓
- `3` - Erfolgreich mit Fehlern (einige Updates fehlgeschlagen)
- `4` - Fehlgeschlagen ✗
- `5` - Abgebrochen

**Fehlerbehandlung:**
- Bei Code 4 oder 5: Abbruch, keine Installation
- Bei Code 3: Installation wird versucht (teilweise erfolgreich)

### Schritt 2.7: Installations-Phase (Zeilen 580-642)

**Installations-Prozess:**
```powershell
$installer = $session.CreateUpdateInstaller()
$installer.Updates = $updateCollection
$installResult = $installer.Install()
```

**Wichtige Hinweise:**
- **Dauer:** 15-30 Minuten oder länger
- **Keine Unterbrechung:** Installation kann nicht pausiert werden
- **System-Ressourcen:** CPU- und Disk-intensiv

**Installations-Phasen:**
1. Updates werden extrahiert
2. Dateien werden ersetzt
3. Registrierungs-Änderungen
4. Dienste werden neu konfiguriert
5. Boot-Konfiguration wird aktualisiert (bei Bedarf)

**Result-Codes (gleich wie Download):**
- `2` = Alle Updates erfolgreich installiert
- `3` = Einige Updates erfolgreich, einige fehlgeschlagen
- `4` = Alle Updates fehlgeschlagen

### Schritt 2.8: Detaillierte Update-Ergebnisse (Zeilen 602-633)

**Pro-Update-Analyse:**
```powershell
for ($i = 0; $i -lt $installResult.GetUpdateResult.Count; $i++) {
    $updateResult = $installResult.GetUpdateResult($i)
}
```

**Ausgabe-Beispiel:**
```
Detaillierte Update-Ergebnisse:
  [Erfolgreich] 2025-10 Kumulative Update für Windows 11 (KB5031455)
  [Erfolgreich] Windows Malicious Software Removal Tool
  [Fehlgeschlagen] Microsoft Defender Antivirus Update
    HRESULT: 0x80070643
  [Erfolgreich] .NET Framework 4.8.1 Security Update
```

**HRESULT-Codes (häufige Fehler):**
- `0x80070643` - Installation fehlgeschlagen (allgemein)
- `0x80240016` - Update nicht anwendbar
- `0x80070002` - Datei nicht gefunden
- `0x8024200D` - Update wurde abgelehnt

### Schritt 2.9: Windows Defender-Signaturen (Zeilen 655-682)

**Update-Prozess:**
```powershell
Update-MpSignature
```

**Was wird aktualisiert:**
- Virus-Definitionen
- Malware-Signaturen
- Spyware-Definitionen
- Network Inspection System

**Fehlerbehandlung:**
- Überprüft, ob Defender-Dienst läuft
- Fehler werden als Warnung behandelt (kein Abbruch)
- Funktioniert auch mit Drittanbieter-Antivirus

---

## Hilfsfunktionen

### Test-AdministratorPrivileges (Zeilen 140-148)

**Zweck:** Prüft Administratorrechte

**Technologie:**
```powershell
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

**Warum wichtig:**
- Windows Update erfordert Admin-Rechte
- Dienste stoppen/starten erfordert Admin-Rechte
- Systemverzeichnisse löschen erfordert Admin-Rechte

### Test-ServiceExists (Zeilen 150-163)

**Zweck:** Prüft, ob Windows-Dienst existiert

**Use-Case:**
- Einige Dienste existieren nicht in allen Windows-Editionen
- Verhindert Fehler bei fehlenden Diensten
- Beispiel: `msiserver` kann in Server-Core fehlen

### Show-Summary (Zeilen 684-728)

**Zusammenfassung enthält:**
- Start- und Endzeit
- Ausführungsdauer (Stunden, Minuten, Sekunden)
- Anzahl gefundener Updates
- Anzahl installierter Updates
- Neustart-Status
- Fehler- und Warnungs-Zähler

**Beispiel-Ausgabe:**
```
═══════════════════════════════════════════════════════
ZUSAMMENFASSUNG
═══════════════════════════════════════════════════════
Startzeit:                  2025-10-16 14:23:12
Endzeit:                    2025-10-16 15:01:45
Dauer:                      0h 38m 33s
Gefundene Updates:          5
Installierte Updates:       5
Neustart erforderlich:      JA
Fehler aufgetreten:         0
Warnungen aufgetreten:      2

⚠ WICHTIG: Ein Neustart ist erforderlich, um die Installation abzuschließen!
Bitte starten Sie den Computer manuell neu.
═══════════════════════════════════════════════════════
```

---

## Fehlerbehandlung

### Globale Fehlerbehandlung (Zeilen 734-833)

**Try-Catch-Struktur:**
```powershell
try {
    # Gesamtes Script
} catch {
    Write-LogMessage "KRITISCHER FEHLER: $($_.Exception.Message)" -Level Error
    Write-LogMessage "Stack-Trace: $($_.ScriptStackTrace)" -Level Error
    Stop-Transcript
    exit 99
}
```

**Fehler-Kategorien:**

1. **Kritische Fehler (Exit 99):**
   - Unerwartete Exceptions
   - Script kann nicht fortfahren
   - Stack-Trace wird geloggt

2. **Service-Fehler:**
   - Timeout beim Stoppen/Starten
   - Dienst existiert nicht
   - Script fährt fort (Resilienz)

3. **Download-/Installations-Fehler:**
   - Update fehlgeschlagen
   - Einzelne Updates überspringen
   - Andere Updates werden fortgesetzt

### Fehler-Zähler

**Tracking:**
```powershell
$script:ErrorCount = 0
$script:WarningCount = 0
```

**Verwendung in Exit-Code:**
- Exit 0: Erfolgreich, keine Fehler
- Exit 1: Erfolgreich, aber Fehler/Warnungen
- Exit 2: Installation fehlgeschlagen
- Exit 99: Kritischer Fehler

---

## Log-Dateien

### Log-Verzeichnis (Standard)

```
C:\ProgramData\UpdateForce\
```

### Log-Dateiname

```
WindowsUpdate_20251016_142312.log
```

**Format:** `WindowsUpdate_JJJJMMTT_HHMMSS.log`

### Transcript-System

**Start:**
```powershell
Start-Transcript -Path $logFile -Append
```

**Inhalt:**
- Alle Console-Ausgaben
- Zeitstempel für jede Zeile
- Fehler und Stack-Traces
- Befehlsausgaben

**Stopp:**
```powershell
Stop-Transcript
```

### Log-Beispiel

```
[2025-10-16 14:23:12] ═ Windows Update Reparatur & Installation
[2025-10-16 14:23:12] ℹ Startzeit: 2025-10-16 14:23:12
[2025-10-16 14:23:12] ℹ Log-Datei: C:\ProgramData\UpdateForce\WindowsUpdate_20251016_142312.log
[2025-10-16 14:23:15] ℹ Stoppe Dienst 'wuauserv'...
[2025-10-16 14:23:17] ✓ Dienst 'wuauserv' erfolgreich gestoppt
[2025-10-16 14:23:17] ℹ Stoppe Dienst 'bits'...
[2025-10-16 14:23:19] ✓ Dienst 'bits' erfolgreich gestoppt
[2025-10-16 14:23:20] ℹ Lösche Verzeichnis: C:\Windows\SoftwareDistribution (Versuch 1/3)
[2025-10-16 14:23:25] ✓ Verzeichnis erfolgreich gelöscht: C:\Windows\SoftwareDistribution
```

---

## Exit-Codes

| Exit-Code | Bedeutung | Beschreibung |
|-----------|-----------|--------------|
| `0` | Erfolg | Installation erfolgreich, keine Fehler |
| `1` | Erfolg mit Warnungen | Installation erfolgreich, aber Fehler/Warnungen aufgetreten |
| `2` | Installations-Fehler | Installation fehlgeschlagen |
| `99` | Kritischer Fehler | Unerwarteter Fehler, Script konnte nicht abgeschlossen werden |

### Exit-Code-Logik (Zeilen 818-825)

```powershell
if ($installResult.Success -and $script:ErrorCount -eq 0) {
    exit 0  # Perfekt
} elseif ($installResult.Success -and $script:ErrorCount -gt 0) {
    exit 1  # OK, aber mit Problemen
} else {
    exit 2  # Installation fehlgeschlagen
}
```

---

## Häufige Probleme und Lösungen

### Problem 1: "Update bleibt bei X% hängen"

**Ursache:** Beschädigter Download-Cache

**Lösung durch Script:**
1. Stoppt Windows Update-Dienst
2. Löscht `C:\Windows\SoftwareDistribution`
3. Startet Dienst neu
4. Cache wird neu aufgebaut

### Problem 2: "0x80070643 - Installation fehlgeschlagen"

**Ursache:** Beschädigte Update-Komponenten

**Lösung durch Script:**
1. DISM-Komponentenbereinigung
2. Neuregistrierung aller Update-DLLs
3. Neue Update-Suche mit sauberen Komponenten

### Problem 3: "Windows Update findet keine Updates"

**Ursache:** Beschädigte kryptografische Kataloge

**Lösung durch Script:**
1. Stoppt `cryptsvc`-Dienst
2. Löscht `C:\Windows\System32\catroot2`
3. Startet Dienst neu
4. Katalog wird neu erstellt

### Problem 4: "Service kann nicht gestartet werden"

**Ursache:** Dienst-Abhängigkeiten oder Berechtigungen

**Lösung durch Script:**
1. Mehrere Neustart-Versuche (3x)
2. Timeout-Behandlung
3. Fehler wird geloggt, Script fährt fort
4. Manuelle Intervention möglich

---

## Sicherheitshinweise

### Was das Script NICHT macht

- ❌ Lädt keine externe Software herunter
- ❌ Ändert keine Sicherheitseinstellungen
- ❌ Deaktiviert keine Firewalls oder Antivirus
- ❌ Sendet keine Daten nach außen
- ❌ Ändert keine Gruppenrichtlinien

### Was das Script macht

- ✅ Verwendet nur native Windows-APIs
- ✅ Alle Aktionen werden geloggt
- ✅ Kein Code-Download von Internet
- ✅ Alle Dienste werden wieder gestartet
- ✅ Keine permanenten Änderungen an der Registry
- ✅ Vollständig transparent und nachvollziehbar

---

## Performance-Hinweise

### Typische Ausführungszeiten

| Phase | Dauer | Faktoren |
|-------|-------|----------|
| Bereinigung | 2-5 Minuten | Anzahl der Cache-Dateien |
| DISM-Cleanup | 5-15 Minuten | Größe des WinSxS-Verzeichnisses |
| DLL-Registrierung | 30-60 Sekunden | Anzahl der DLLs (34) |
| Update-Suche | 1-5 Minuten | Internet-Geschwindigkeit |
| Update-Download | 5-30 Minuten | Größe der Updates, Bandbreite |
| Update-Installation | 15-60 Minuten | Anzahl und Komplexität der Updates |
| **Gesamt** | **30-120 Minuten** | Abhängig von Updates |

### System-Ressourcen

**CPU-Auslastung:**
- Bereinigung: 5-10%
- DISM: 20-40%
- Installation: 30-70%

**Disk-Auslastung:**
- Download: Moderat (BITS)
- Installation: Hoch (80-100%)

**Speicher:**
- Minimal (< 100 MB)

---

## Best Practices

### Wann sollte das Script ausgeführt werden?

✅ **Gute Zeitpunkte:**
- Außerhalb der Geschäftszeiten
- Bei stabilem Internet
- Wenn Computer für 1-2 Stunden entbehrlich ist
- Vor wichtigen Projekten (präventiv)

❌ **Schlechte Zeitpunkte:**
- Während wichtiger Arbeit
- Bei instabilem Internet
- Kurz vor Meetings/Präsentationen
- Bei niedriger Batterie (Laptops)

### Empfohlene Verwendung

1. **Monatlich (Standard):**
   ```powershell
   .\Repair-WindowsUpdate.ps1
   ```

2. **Bei Problemen (vollständig):**
   ```powershell
   .\Repair-WindowsUpdate.ps1 -IncludeDrivers -RebootIfNeeded
   ```

3. **Wartungsfenster (alles):**
   ```powershell
   .\Repair-WindowsUpdate.ps1 -IncludeDrivers -IncludeFeatureUpdates -RebootIfNeeded
   ```

4. **Schnelle Update-Installation (ohne Bereinigung):**
   ```powershell
   .\Repair-WindowsUpdate.ps1 -SkipCleanup
   ```

---

## Technische Architektur

### Script-Struktur

```
Repair-WindowsUpdate.ps1
│
├── [Header] Synopsis, Description, Examples
├── [Parameters] Benutzerdefinierte Optionen
├── [Configuration] Globale Variablen
│
├── [Helper Functions]
│   ├── Write-LogMessage          # Logging-System
│   ├── Test-AdministratorPrivileges  # Admin-Check
│   ├── Test-ServiceExists        # Service-Validierung
│   ├── Stop-ServiceSafely        # Service-Management
│   ├── Start-ServiceSafely       # Service-Management
│   ├── Remove-DirectorySafely    # Datei-System-Operationen
│   ├── Invoke-ComponentCleanup   # DISM-Wrapper
│   └── Update-DefenderSignatures # Defender-Update
│
├── [Core Functions]
│   ├── Invoke-WindowsUpdateCleanup  # Phase 1: Bereinigung
│   ├── Get-WindowsUpdates           # Phase 2: Suche
│   ├── Install-WindowsUpdates       # Phase 2: Installation
│   └── Show-Summary                 # Zusammenfassung
│
└── [Main Program]
    ├── Log-Setup
    ├── Admin-Check
    ├── Phase 1: Cleanup (conditional)
    ├── Phase 2: Search & Install
    ├── Defender-Update
    ├── Summary
    └── Reboot (conditional)
```

### Abhängigkeiten

**Windows-Komponenten:**
- `Microsoft.Update.Session` (COM)
- `Microsoft.Update.UpdateSearcher` (COM)
- `Microsoft.Update.UpdateDownloader` (COM)
- `Microsoft.Update.UpdateInstaller` (COM)
- `dism.exe` (Deployment Image Servicing)
- `regsvr32.exe` (DLL-Registrierung)

**PowerShell-Cmdlets:**
- `Get-Service`, `Start-Service`, `Stop-Service`
- `Remove-Item`, `Test-Path`, `New-Item`
- `Start-Process`, `Start-Transcript`, `Stop-Transcript`
- `Update-MpSignature` (Defender)

---

## Troubleshooting

### Script startet nicht

**Fehler:** "Script kann nicht geladen werden, da die Ausführung von Skripts auf diesem System deaktiviert ist."

**Lösung:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Zugriff verweigert"

**Fehler:** Access denied / Zugriff verweigert

**Lösung:**
- PowerShell als Administrator starten
- Rechtsklick auf PowerShell → "Als Administrator ausführen"

### DISM-Fehler 0x800F081F

**Fehler:** "Die Quelldateien konnten nicht gefunden werden"

**Lösung:**
- Internet-Verbindung prüfen
- Windows Update-Dienst muss laufen
- Firewall-Regeln prüfen

### COM-Objekt kann nicht erstellt werden

**Fehler:** "Fehler beim Erstellen von Microsoft.Update.Session"

**Lösung:**
1. Script neu starten
2. Windows Update-Dienst manuell starten:
   ```powershell
   Start-Service wuauserv
   ```
3. System neu starten

---

## Lizenz und Haftungsausschluss

### Nutzung

Dieses Script wird "AS IS" ohne jegliche Gewährleistung bereitgestellt. Die Verwendung erfolgt auf eigenes Risiko.

### Empfehlung

- Erstellen Sie vor der Verwendung ein System-Backup
- Testen Sie das Script in einer Test-Umgebung
- Lesen Sie die Log-Dateien nach der Ausführung
- Konsultieren Sie bei Problemen die Log-Dateien

---

## Versionsinformationen

**Version:** 2.0
**Datum:** 2025-10-16
**PowerShell:** 5.1+
**Windows:** 10, 11, Server 2016+

---

## Support und Weiterführende Links

### Microsoft-Dokumentation

- [Windows Update-Fehlerbehandlung](https://support.microsoft.com/windows/troubleshoot-problems-updating-windows-188c2b0f-10a7-d72f-65b8-32d177eb136c)
- [DISM-Kommandozeilen-Optionen](https://learn.microsoft.com/windows-hardware/manufacture/desktop/dism-operating-system-package-servicing-command-line-options)
- [Windows Update-API](https://learn.microsoft.com/windows/win32/api/_wua/)

### Häufige Windows Update-Fehlercodes

| Code | Bedeutung |
|------|-----------|
| 0x80070002 | Datei nicht gefunden |
| 0x80070643 | Installations-Fehler (allgemein) |
| 0x8024200D | Update wurde abgelehnt |
| 0x80240016 | Update nicht anwendbar |
| 0x8024402C | Verbindungsfehler zu Update-Server |
| 0x80244019 | Download fehlgeschlagen |

---

**Ende der Dokumentation**
