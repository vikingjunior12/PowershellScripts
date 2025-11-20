# Voraussetzungen & Login
Install-Module Microsoft.Graph.Beta -Scope CurrentUser -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Beta.DeviceManagement
Disconnect-MgGraph -ErrorAction SilentlyContinue
Connect-MgGraph -Scopes "DeviceManagementScripts.Read.All" -NoWelcome

$out = "C:\Temp\IntuneScripts"
New-Item -ItemType Directory -Force -Path $out | Out-Null

# Hilfsfunktion: robust decodieren
function Decode-GraphScriptContent {
    param(
        [Parameter(Mandatory=$true)] $Content
    )
    try {
        if ($null -eq $Content) { return $null }

        # Falls Byte-Array → direkt UTF8 dekodieren
        if ($Content -is [byte[]]) {
            return [Text.Encoding]::UTF8.GetString($Content)
        }

        # Als String behandeln
        $s = [string]$Content
        $s = $s.Trim()
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }

        # URL-safe Base64 → normalisieren
        $s = $s.Replace('-', '+').Replace('_', '/')
        # Padding auffüllen auf Länge % 4 == 0
        switch ($s.Length % 4) {
            2 { $s += '==' }
            3 { $s += '='  }
            0 { } default { } # 1 ist theoretisch invalid, wir probieren trotzdem
        }

        $bytes = [Convert]::FromBase64String($s)
        return [Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
        # Als Fallback: vielleicht ist es Klartext (sehr selten, aber möglich)
        if ($Content -is [string]) { return $Content }
        throw
    }
}

# 1) Metadaten holen (Liste)
$meta = Get-MgBetaDeviceManagementScript -All | Select-Object Id, DisplayName, FileName

$report = [System.Collections.Generic.List[object]]::new()

foreach ($m in $meta) {
    try {
        # 2) Detail je ID (hier sollte ScriptContent drin sein)
        $detail = Get-MgBetaDeviceManagementScript -DeviceManagementScriptId $m.Id

        # Falls SDK leer liefert → REST-Fallback
        if (-not $detail.ScriptContent) {
            $detail = Invoke-MgGraphRequest -Method GET -OutputType PSObject -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$($m.Id)"
        }

        $fileName = if ($detail.fileName) { $detail.fileName } else { ($detail.displayName -replace '[\\/:*?"<>|]', '_') + ".ps1" }
        $path     = Join-Path $out $fileName

        $decoded = Decode-GraphScriptContent -Content $detail.scriptContent
        if ([string]::IsNullOrWhiteSpace($decoded)) {
            Write-Warning "Kein/ungültiger ScriptContent für '$($m.DisplayName)' (ID $($m.Id))."
            continue
        }

        # UTF-8 ohne BOM schreiben
        [IO.File]::WriteAllText($path, $decoded, (New-Object Text.UTF8Encoding($false)))

        $report.Add([pscustomobject]@{
            'Display Name' = $detail.displayName
            'File Name'    = $fileName
            'Output Path'  = $path
            'Bytes'        = (Get-Item $path).Length
        })
    }
    catch {
        Write-Warning "Fehler bei '$($m.DisplayName)' (ID $($m.Id)): $($_.Exception.Message)"
    }
}

$report | Format-Table -AutoSize
