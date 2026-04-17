function New-AutoDoctorValidationFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message
    )

    return [PSCustomObject]@{
        Category = $Category
        Severity = $Severity
        Message  = $Message
        Source   = "Validation"
    }
}

function Invoke-AutoDoctorValidationAnalysis {
    param(
        $MemoryObj,
        $CPUObj,
        $DiskObj,
        $NetworkObj,
        $ErrorObj,
        $SoftwareObj,
        $DriverObj
    )

    $findings = @()

    if (-not $MemoryObj) {
        $findings += New-AutoDoctorValidationFinding -Category "Telemetry" -Severity "Warning" -Message "Memory telemetry is missing"
    }

    if (-not $CPUObj) {
        $findings += New-AutoDoctorValidationFinding -Category "Telemetry" -Severity "Warning" -Message "CPU telemetry is missing"
    }

    if (-not $DiskObj) {
        $findings += New-AutoDoctorValidationFinding -Category "Telemetry" -Severity "Warning" -Message "Disk telemetry is missing"
    }

    if (-not $NetworkObj) {
        $findings += New-AutoDoctorValidationFinding -Category "Telemetry" -Severity "Info" -Message "Network telemetry is missing"
    }

    if (-not $ErrorObj) {
        $findings += New-AutoDoctorValidationFinding -Category "Telemetry" -Severity "Info" -Message "Event log telemetry is missing"
    }

    if ($MemoryObj) {
        $totalMemory = if ($null -ne $MemoryObj.TotalMemoryGB) { [double]$MemoryObj.TotalMemoryGB } else { $null }
        $freeMemory = if ($null -ne $MemoryObj.FreeMemoryGB) { [double]$MemoryObj.FreeMemoryGB } else { $null }

        if (($null -ne $totalMemory -and $totalMemory -lt 0) -or ($null -ne $freeMemory -and $freeMemory -lt 0)) {
            $findings += New-AutoDoctorValidationFinding -Category "Memory" -Severity "Warning" -Message "Memory telemetry contains negative values"
        }

        if ($null -ne $totalMemory -and $null -ne $freeMemory -and $freeMemory -gt $totalMemory) {
            $findings += New-AutoDoctorValidationFinding -Category "Memory" -Severity "Warning" -Message "Free memory exceeds total memory in telemetry"
        }
    }

    if ($CPUObj -and $null -ne $CPUObj.CurrentCPULoadPercent) {
        $cpuLoad = [double]$CPUObj.CurrentCPULoadPercent

        if ($cpuLoad -lt 0 -or $cpuLoad -gt 100) {
            $findings += New-AutoDoctorValidationFinding -Category "CPU" -Severity "Warning" -Message "CPU load telemetry is outside the expected 0-100 range"
        }
    }

    if ($DiskObj) {
        $diskUsage = if ($DiskObj.DiskUsage) { @($DiskObj.DiskUsage) } else { @() }
        $diskIoRows = if ($DiskObj.DiskIOSummary) { @($DiskObj.DiskIOSummary) } else { @() }

        if (($diskUsage | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Name) }).Count -gt 0) {
            $findings += New-AutoDoctorValidationFinding -Category "Disk" -Severity "Warning" -Message "Disk usage telemetry contains unnamed drives"
        }

        if (($diskUsage | Where-Object {
                    ($null -ne $_.FreeGB -and [double]$_.FreeGB -lt 0) -or
                    ($null -ne $_.UsedGB -and [double]$_.UsedGB -lt 0)
                }).Count -gt 0) {
            $findings += New-AutoDoctorValidationFinding -Category "Disk" -Severity "Warning" -Message "Disk usage telemetry contains negative capacity values"
        }

        if (($diskIoRows | Where-Object {
                    $null -eq $_.PercentBusy -or
                    [double]$_.PercentBusy -lt 0 -or
                    [double]$_.PercentBusy -gt 100
                }).Count -gt 0) {
            $findings += New-AutoDoctorValidationFinding -Category "Disk" -Severity "Warning" -Message "Disk IO telemetry contains malformed PercentBusy values"
        }
    }

    $softwareRows = if ($SoftwareObj) { @($SoftwareObj) } else { @() }
    $softwareNames = @($softwareRows |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.DisplayName) } |
            ForEach-Object { ([string]$_.DisplayName).Trim().ToLowerInvariant() })

    if (($softwareRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.DisplayName) }).Count -gt 0) {
        $findings += New-AutoDoctorValidationFinding -Category "Software" -Severity "Info" -Message "Software inventory contains blank entries"
    }

    $duplicateSoftware = @($softwareNames | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -First 3)
    if ($duplicateSoftware.Count -gt 0) {
        $duplicateNames = ($duplicateSoftware | ForEach-Object { $_.Name }) -join ", "
        $findings += New-AutoDoctorValidationFinding -Category "Software" -Severity "Info" -Message "Software inventory contains duplicate entries: $duplicateNames"
    }

    $driverRows = if ($DriverObj) { @($DriverObj) } else { @() }
    $malformedDrivers = @($driverRows | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.DeviceName) -or
            [string]::IsNullOrWhiteSpace([string]$_.DriverProviderName)
        })

    if ($malformedDrivers.Count -gt 0) {
        $findings += New-AutoDoctorValidationFinding -Category "Drivers" -Severity "Info" -Message ("Driver inventory contains {0} incomplete entries" -f $malformedDrivers.Count)
    }

    $severityCounts = @{
        Info     = @($findings | Where-Object Severity -eq "Info").Count
        Warning  = @($findings | Where-Object Severity -eq "Warning").Count
        Critical = @($findings | Where-Object Severity -eq "Critical").Count
    }

    return [PSCustomObject]@{
        Findings       = @($findings)
        SeverityCounts = [PSCustomObject]$severityCounts
        Summary        = if ($findings.Count -gt 0) { ($findings.Message -join "; ") } else { "Validation checks passed" }
    }
}

Register-AutoDoctorModule -Name "Data Validation" -Execute {
    param(
        $MemoryObj,
        $CPUObj,
        $DiskObj,
        $NetworkObj,
        $ErrorObj,
        $SoftwareObj,
        $DriverObj
    )

    Invoke-AutoDoctorValidationAnalysis `
        -MemoryObj $MemoryObj `
        -CPUObj $CPUObj `
        -DiskObj $DiskObj `
        -NetworkObj $NetworkObj `
        -ErrorObj $ErrorObj `
        -SoftwareObj $SoftwareObj `
        -DriverObj $DriverObj
}
