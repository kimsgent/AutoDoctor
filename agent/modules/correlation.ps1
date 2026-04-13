function New-AutoDoctorCorrelationFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message
    )

    return [PSCustomObject]@{
        Category = $Category
        Severity = $Severity
        Message  = $Message
        Source   = "Correlation"
    }
}

function Invoke-AutoDoctorCorrelationAnalysis {
    param(
        $CPUObj,
        $DiskObj,
        $NetworkObj,
        $ErrorObj
    )

    $findings = @()
    $cpuLoad = if ($CPUObj -and $null -ne $CPUObj.CurrentCPULoadPercent) { [double]$CPUObj.CurrentCPULoadPercent } else { 0 }
    $diskBusy = if ($DiskObj -and $DiskObj.DiskIOSummary) {
        [double](($DiskObj.DiskIOSummary | Measure-Object -Property PercentBusy -Maximum).Maximum)
    }
    else {
        0
    }

    $topProcesses = if ($CPUObj -and $CPUObj.TopProcesses) { @($CPUObj.TopProcesses) } else { @() }
    $topProcessNames = @($topProcesses | ForEach-Object { ([string]$_.ProcessName).ToLowerInvariant() })

    if ($cpuLoad -ge 70 -and $diskBusy -lt 20) {
        $findings += New-AutoDoctorCorrelationFinding -Category "CPU" -Severity "Warning" -Message ("CPU-bound workload detected: CPU load is {0}% while disk busy is only {1}%" -f ([math]::Round($cpuLoad, 2)), ([math]::Round($diskBusy, 2)))
    }

    if ($cpuLoad -ge 70 -and $topProcessNames -contains "msmpeng") {
        $severity = if ($cpuLoad -ge 85) { "Critical" } else { "Warning" }
        $findings += New-AutoDoctorCorrelationFinding -Category "CPU" -Severity $severity -Message "Antivirus scan impact likely: MsMpEng is present during elevated CPU load"
    }

    if ($cpuLoad -ge 70 -and $topProcessNames -contains "sqlservr") {
        $severity = if ($cpuLoad -ge 85) { "Critical" } else { "Warning" }
        $findings += New-AutoDoctorCorrelationFinding -Category "CPU" -Severity $severity -Message "Database workload pressure likely: sqlservr is present during elevated CPU load"
    }

    $latency = if ($NetworkObj -and $NetworkObj.Connectivity -and $null -ne $NetworkObj.Connectivity.AvgLatencyMS) {
        [double]$NetworkObj.Connectivity.AvgLatencyMS
    }
    else {
        0
    }
    $packetsSent = if ($NetworkObj -and $NetworkObj.Connectivity -and $null -ne $NetworkObj.Connectivity.PacketsSent) {
        [int]$NetworkObj.Connectivity.PacketsSent
    }
    else {
        0
    }
    $packetsReceived = if ($NetworkObj -and $NetworkObj.Connectivity -and $null -ne $NetworkObj.Connectivity.PacketsReceived) {
        [int]$NetworkObj.Connectivity.PacketsReceived
    }
    else {
        0
    }

    if ($latency -ge 150 -and ($packetsSent + $packetsReceived) -le 20) {
        $findings += New-AutoDoctorCorrelationFinding -Category "Network" -Severity "Warning" -Message ("Connectivity issue likely: latency is {0} ms with very low packet throughput" -f ([math]::Round($latency, 2)))
    }

    $errorCount = if ($ErrorObj -and $null -ne $ErrorObj.ErrorCount) { [int]$ErrorObj.ErrorCount } else { 0 }
    if ($latency -ge 150 -and $errorCount -ge 30) {
        $findings += New-AutoDoctorCorrelationFinding -Category "Network" -Severity "Warning" -Message "Network instability may be contributing to elevated event log errors"
    }

    $severityCounts = @{
        Info     = @($findings | Where-Object Severity -eq "Info").Count
        Warning  = @($findings | Where-Object Severity -eq "Warning").Count
        Critical = @($findings | Where-Object Severity -eq "Critical").Count
    }

    return [PSCustomObject]@{
        Findings       = @($findings)
        SeverityCounts = [PSCustomObject]$severityCounts
        Summary        = if ($findings.Count -gt 0) { ($findings.Message -join "; ") } else { "No cross-metric correlations detected" }
    }
}

Register-AutoDoctorModule -Name "Correlation Analysis" -Execute {
    param(
        $CPUObj,
        $DiskObj,
        $NetworkObj,
        $ErrorObj
    )

    Invoke-AutoDoctorCorrelationAnalysis `
        -CPUObj $CPUObj `
        -DiskObj $DiskObj `
        -NetworkObj $NetworkObj `
        -ErrorObj $ErrorObj
}
