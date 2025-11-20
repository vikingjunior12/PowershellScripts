[CmdletBinding()]
param(
    [switch]$IncludeDeviceList,

    [Parameter()]
    [string]$FilterByRelease,

    [Parameter()]
    [string]$FilterByDeviceGroup
)

#Requires -Modules Microsoft.Graph.DeviceManagement

$deviceGroupDefinitions = @(
    @{ Name = "CBZLA"; Pattern = "(?i)^CBZLA" }
    @{ Name = "CBZWS"; Pattern = "(?i)^CBZWS" }
    @{ Name = "CDHWS"; Pattern = "(?i)^CDHWS" }
    @{ Name = "CBZPR"; Pattern = "(?i)^CBZPR" }
    @{ Name = "CBZLGI"; Pattern = "(?i)^CBZLGI" }
    @{ Name = "CBZDI"; Pattern = "(?i)^CBZDI" }
    @{ Name = "CBZBM"; Pattern = "(?i)^CBZBM" }
    @{ Name = "CBZNA"; Pattern = "(?i)^CBZNA" }

)

$requiredScopes = @("DeviceManagementManagedDevices.Read.All")

if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
    throw "The Microsoft Graph PowerShell SDK is not available. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser"
}

try {
    $currentContext = Get-MgContext -ErrorAction Stop
} catch {
    $currentContext = $null
}

$hasRequiredScope = $false
if ($currentContext -and $currentContext.Scopes) {
    $hasRequiredScope = $requiredScopes | ForEach-Object { $currentContext.Scopes -contains $_ } | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
}

if (-not $currentContext -or -not $currentContext.Account -or $hasRequiredScope -lt $requiredScopes.Count) {
    Connect-MgGraph -Scopes $requiredScopes -NoWelcome | Out-Null
}

function Get-WindowsReleaseName {
    param(
        [Parameter(Mandatory)]
        [string]$OsVersion
    )

    if ([string]::IsNullOrWhiteSpace($OsVersion)) {
        return "Unknown"
    }

    switch -Regex ($OsVersion) {
        "^10\.0\.262\d+" { return "Windows 11 25H2" }
        "^10\.0\.261\d+" { return "Windows 11 24H2" }
        "^10\.0\.22631" { return "Windows 11 23H2" }
        "^10\.0\.22621" { return "Windows 11 22H2" }
        default { return "Other/Older" }
    }
}

function Get-DeviceGroupName {
    param(
        [Parameter(Mandatory)]
        [string]$DeviceName
    )

    if ([string]::IsNullOrWhiteSpace($DeviceName)) {
        return "Other"
    }

    foreach ($definition in $deviceGroupDefinitions) {
        if ($DeviceName -match $definition.Pattern) {
            return $definition.Name
        }
    }

    return "Other"
}

$allManagedDevices = Get-MgDeviceManagementManagedDevice -All -Select DeviceName,OperatingSystem,OsVersion,UserDisplayName,LastSyncDateTime
$windowsDevices = $allManagedDevices | Where-Object { $_.OperatingSystem -like "Windows*" -and $_.OsVersion }

$windowsDevicesWithRelease = $windowsDevices | ForEach-Object {
    $release = Get-WindowsReleaseName -OsVersion $_.OsVersion
    $deviceGroup = Get-DeviceGroupName -DeviceName $_.DeviceName

    [PSCustomObject]@{
        DeviceName      = $_.DeviceName
        UserDisplayName = $_.UserDisplayName
        OsVersion       = $_.OsVersion
        Release         = $release
        DeviceGroup     = $deviceGroup
        LastSyncDateTime = $_.LastSyncDateTime
    }
}

$grouped = $windowsDevicesWithRelease |
    Group-Object -Property Release |
    Sort-Object -Property Name

# Only show summary if not filtering by specific release or device group
if (-not $FilterByRelease -and -not $FilterByDeviceGroup) {
    $summary = $grouped | ForEach-Object {
        [PSCustomObject]@{
            Release = $_.Name
            Count   = $_.Count
        }
    }

    $summary | Format-Table -AutoSize
    Write-Host ""
    Write-Host ("Total Windows devices checked: {0}" -f $windowsDevicesWithRelease.Count)
}

# Only show device group pivot table if not filtering by specific release or device group
if (-not $FilterByRelease -and -not $FilterByDeviceGroup) {
    $releaseNames = $windowsDevicesWithRelease | Select-Object -ExpandProperty Release -Unique | Sort-Object
    $deviceGroupNames = $windowsDevicesWithRelease | Select-Object -ExpandProperty DeviceGroup -Unique | Sort-Object

    $groupPivot = foreach ($groupName in $deviceGroupNames) {
        $devicesInGroup = $windowsDevicesWithRelease | Where-Object { $_.DeviceGroup -eq $groupName }
        $row = [ordered]@{
            DeviceGroup = $groupName
            Total       = $devicesInGroup.Count
        }

        foreach ($releaseName in $releaseNames) {
            $row[$releaseName] = ($devicesInGroup | Where-Object { $_.Release -eq $releaseName }).Count
        }

        [PSCustomObject]$row
    }

    if ($groupPivot) {
        Write-Host ""
        Write-Host "Counts by device naming group:"
        $groupPivot | Format-Table -AutoSize
    }
}

if ($IncludeDeviceList -and $grouped) {
    foreach ($releaseGroup in $grouped) {
        Write-Host ""
        Write-Host ("=== {0} ===" -f $releaseGroup.Name)
        $releaseGroup.Group |
            Select-Object DeviceName, DeviceGroup, UserDisplayName, OsVersion |
            Sort-Object DeviceName |
            Format-Table -AutoSize
    }
}

# Filter by specific Windows release and/or device group if parameters are provided
if ($FilterByRelease -or $FilterByDeviceGroup) {
    Write-Host ""

    # Build filter description
    $filterParts = @()
    if ($FilterByRelease) { $filterParts += "Release: $FilterByRelease" }
    if ($FilterByDeviceGroup) { $filterParts += "Device Group: $FilterByDeviceGroup" }

    Write-Host ("=== Filtering devices by {0} ===" -f ($filterParts -join " AND "))
    Write-Host ""

    # Apply filters
    $filteredDevices = $windowsDevicesWithRelease

    if ($FilterByRelease) {
        $filteredDevices = $filteredDevices | Where-Object { $_.Release -eq $FilterByRelease }
    }

    if ($FilterByDeviceGroup) {
        $filteredDevices = $filteredDevices | Where-Object { $_.DeviceGroup -eq $FilterByDeviceGroup }
    }

    if ($filteredDevices.Count -eq 0) {
        Write-Host "No devices found matching the filter criteria." -ForegroundColor Yellow
        Write-Host ""

        if ($FilterByRelease) {
            Write-Host "Available releases:" -ForegroundColor Yellow
            $windowsDevicesWithRelease | Select-Object -ExpandProperty Release -Unique | Sort-Object | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }

        if ($FilterByDeviceGroup) {
            Write-Host ""
            Write-Host "Available device groups:" -ForegroundColor Yellow
            $windowsDevicesWithRelease | Select-Object -ExpandProperty DeviceGroup -Unique | Sort-Object | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
    } else {
        $now = Get-Date

        $deviceCheckInInfo = $filteredDevices | ForEach-Object {
            if ($_.LastSyncDateTime) {
                $lastSync = $_.LastSyncDateTime
                $daysSinceSync = [Math]::Round(($now - $lastSync).TotalDays, 1)
            } else {
                $lastSync = "Never"
                $daysSinceSync = "N/A"
            }

            [PSCustomObject]@{
                DeviceName      = $_.DeviceName
                DeviceGroup     = $_.DeviceGroup
                UserDisplayName = $_.UserDisplayName
                LastCheckIn     = if ($lastSync -eq "Never") { "Never" } else { $lastSync.ToString("yyyy-MM-dd HH:mm") }
                DaysOffline     = $daysSinceSync
            }
        } | Sort-Object -Property @{Expression = {if ($_.DaysOffline -eq "N/A") { 999999 } else { [double]$_.DaysOffline }}; Descending = $true}, DeviceName

        Write-Host ("Total devices matching filter: {0}" -f $filteredDevices.Count)
        Write-Host ""
        $deviceCheckInInfo | Format-Table -AutoSize
    }
}
