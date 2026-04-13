function New-AutoDoctorAnomalyFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message
    )

    return [PSCustomObject]@{
        Category = $Category
        Severity = $Severity
        Message  = $Message
        Source   = "Anomaly"
    }
}

function Invoke-AutoDoctorAnomalyAnalysis {
    param($CPUObj)

    $findings = @()
    $topProcesses = if ($CPUObj -and $CPUObj.TopProcesses) { @($CPUObj.TopProcesses | Sort-Object CPU -Descending) } else { @() }

    if ($topProcesses.Count -eq 0) {
        return [PSCustomObject]@{
            Findings       = @()
            SeverityCounts = [PSCustomObject]@{ Info = 0; Warning = 0; Critical = 0 }
            Summary        = "No CPU anomalies detected"
        }
    }

    $cpuSamples = @($topProcesses |
            Where-Object { $null -ne $_.CPU -and [double]$_.CPU -ge 0 } |
            ForEach-Object { [double]$_.CPU })

    $topProcess = $topProcesses | Select-Object -First 1
    $averageCpu = if ($cpuSamples.Count -gt 0) {
        [double](($cpuSamples | Measure-Object -Average).Average)
    }
    else {
        0
    }
    $totalCpu = if ($cpuSamples.Count -gt 0) {
        [double](($cpuSamples | Measure-Object -Sum).Sum)
    }
    else {
        0
    }

    if ($averageCpu -gt 0) {
        $dominanceRatio = [math]::Round(([double]$topProcess.CPU / $averageCpu), 2)

        if ($dominanceRatio -ge 10) {
            $findings += New-AutoDoctorAnomalyFinding -Category "CPU" -Severity "Critical" -Message ("Dominant process anomaly detected: {0} is consuming {1} CPU seconds, {2}x the average top-process load" -f $topProcess.ProcessName, ([math]::Round([double]$topProcess.CPU, 2)), $dominanceRatio)
        }
        elseif ($dominanceRatio -ge 5) {
            $findings += New-AutoDoctorAnomalyFinding -Category "CPU" -Severity "Warning" -Message ("Dominant process anomaly detected: {0} is consuming {1} CPU seconds, {2}x the average top-process load" -f $topProcess.ProcessName, ([math]::Round([double]$topProcess.CPU, 2)), $dominanceRatio)
        }
    }

    if ($totalCpu -gt 0) {
        $topShare = [math]::Round((([double]$topProcess.CPU / $totalCpu) * 100), 1)

        if ($topShare -ge 60) {
            $findings += New-AutoDoctorAnomalyFinding -Category "CPU" -Severity "Warning" -Message ("CPU distribution is heavily skewed: {0} accounts for {1}% of sampled process CPU time" -f $topProcess.ProcessName, $topShare)
        }
    }

    $knownBaselineProcesses = @(
        "system", "idle", "dwm", "explorer", "firefox", "chrome", "msedge",
        "msedgewebview2", "outlook", "teams", "sqlservr", "wmiprvse", "powershell",
        "svchost", "msmpeng", "searchindexer", "taskmgr", "runtimebroker", "msaccess",
        "conhost", "services"
    )

    if ($averageCpu -gt 0 -and
        -not [string]::IsNullOrWhiteSpace([string]$topProcess.ProcessName) -and
        ($knownBaselineProcesses -notcontains ([string]$topProcess.ProcessName).ToLowerInvariant()) -and
        ([double]$topProcess.CPU -ge ($averageCpu * 3))) {

        $findings += New-AutoDoctorAnomalyFinding -Category "CPU" -Severity "Warning" -Message ("High CPU activity from non-baseline process detected: {0}" -f $topProcess.ProcessName)
    }

    $severityCounts = @{
        Info     = @($findings | Where-Object Severity -eq "Info").Count
        Warning  = @($findings | Where-Object Severity -eq "Warning").Count
        Critical = @($findings | Where-Object Severity -eq "Critical").Count
    }

    return [PSCustomObject]@{
        Findings        = @($findings)
        DominantProcess = $topProcess
        SeverityCounts  = [PSCustomObject]$severityCounts
        Summary         = if ($findings.Count -gt 0) { ($findings.Message -join "; ") } else { "No CPU anomalies detected" }
    }
}

Register-AutoDoctorModule -Name "Anomaly Analysis" -Execute {
    param($CPUObj)

    Invoke-AutoDoctorAnomalyAnalysis -CPUObj $CPUObj
}
