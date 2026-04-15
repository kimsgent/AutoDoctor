function New-AutoDoctorAnomalyFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Type = "",
        $HistoryContext = $null
    )

    return [PSCustomObject]@{
        Category       = $Category
        Severity       = $Severity
        Message        = $Message
        Source         = "Anomaly"
        Type           = $Type
        HistoryContext = $HistoryContext
    }
}

function Get-AutoDoctorAnomalyHistoryContext {
    param(
        $CPUObj
    )

    $history = Invoke-AutoDoctorHistoryAnalysis -CPUObj $CPUObj -WindowHours 24 -MinimumSamples 3
    $cpuState = @($history.MetricStates | Where-Object Metric -eq "CPU" | Select-Object -First 1)
    $cpuTrend = @($history.CPUTrend)

    if (-not $cpuState -or $null -eq $cpuState.Current -or $null -eq $cpuState.Baseline) {
        return [PSCustomObject]@{
            Classification     = "Stable"
            AnomalyThreshold   = $null
            PersistentSamples  = 0
            CurrentAboveAnomaly = $false
            SampleCount        = if ($cpuState) { $cpuState.SampleCount } else { 0 }
            WindowLabel        = if ($cpuState) { $cpuState.WindowLabel } else { "" }
            HistoryAnalysis    = $history
        }
    }

    $baseline = [double]$cpuState.Baseline
    $current = [double]$cpuState.Current
    $anomalyThreshold = [math]::Round(($baseline * 1.5), 2)
    $persistentSamples = @($cpuTrend | Where-Object { $null -ne $_.Value -and [double]$_.Value -gt $anomalyThreshold }).Count
    $currentAboveAnomaly = $current -gt $anomalyThreshold

    $classification = "Stable"

    if ($currentAboveAnomaly -and $persistentSamples -ge 3) {
        $classification = "Persistent"
    }
    elseif ($currentAboveAnomaly) {
        $classification = "Transient"
    }

    return [PSCustomObject]@{
        Classification      = $classification
        AnomalyThreshold    = $anomalyThreshold
        PersistentSamples   = $persistentSamples
        CurrentAboveAnomaly = $currentAboveAnomaly
        SampleCount         = $cpuState.SampleCount
        WindowLabel         = $cpuState.WindowLabel
        HistoryAnalysis     = $history
        MetricState         = $cpuState
    }
}

function Invoke-AutoDoctorAnomalyAnalysis {
    param($CPUObj)

    $findings = @()
    $topProcesses = if ($CPUObj -and $CPUObj.TopProcesses) { @($CPUObj.TopProcesses | Sort-Object CPU -Descending) } else { @() }
    $historyContext = Get-AutoDoctorAnomalyHistoryContext -CPUObj $CPUObj

    if ($topProcesses.Count -eq 0) {
        return [PSCustomObject]@{
            Findings               = @()
            SeverityCounts         = [PSCustomObject]@{ Info = 0; Warning = 0; Critical = 0 }
            Summary                = "No CPU anomalies detected"
            HistoryClassification  = $historyContext.Classification
            PersistentFindings     = @()
            TransientFindings      = @()
            HistoryContext         = $historyContext
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

    if ($historyContext.Classification -eq "Persistent") {
        $findings += New-AutoDoctorAnomalyFinding `
            -Category "CPU" `
            -Severity "Critical" `
            -Message ("Persistent CPU anomaly context detected: current load remains above historical anomaly baseline across {0} samples ({1})" -f $historyContext.PersistentSamples, $historyContext.WindowLabel) `
            -Type "Persistent" `
            -HistoryContext $historyContext
    }
    elseif ($historyContext.Classification -eq "Transient") {
        $findings += New-AutoDoctorAnomalyFinding `
            -Category "CPU" `
            -Severity "Warning" `
            -Message ("Transient CPU anomaly context detected: current load is above historical anomaly baseline but not persistent ({0})" -f $historyContext.WindowLabel) `
            -Type "Transient" `
            -HistoryContext $historyContext
    }

    if ($averageCpu -gt 0) {
        $dominanceRatio = [math]::Round(([double]$topProcess.CPU / $averageCpu), 2)

        if ($dominanceRatio -ge 10) {
            $findings += New-AutoDoctorAnomalyFinding -Category "CPU" -Severity "Critical" -Message ("Dominant process anomaly detected: {0} is consuming {1} CPU seconds, {2}x the average top-process load" -f $topProcess.ProcessName, ([math]::Round([double]$topProcess.CPU, 2)), $dominanceRatio) -HistoryContext $historyContext
        }
        elseif ($dominanceRatio -ge 5) {
            $findings += New-AutoDoctorAnomalyFinding -Category "CPU" -Severity "Warning" -Message ("Dominant process anomaly detected: {0} is consuming {1} CPU seconds, {2}x the average top-process load" -f $topProcess.ProcessName, ([math]::Round([double]$topProcess.CPU, 2)), $dominanceRatio) -HistoryContext $historyContext
        }
    }

    if ($totalCpu -gt 0) {
        $topShare = [math]::Round((([double]$topProcess.CPU / $totalCpu) * 100), 1)

        if ($topShare -ge 60) {
            $findings += New-AutoDoctorAnomalyFinding -Category "CPU" -Severity "Warning" -Message ("CPU distribution is heavily skewed: {0} accounts for {1}% of sampled process CPU time" -f $topProcess.ProcessName, $topShare) -HistoryContext $historyContext
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

        $findings += New-AutoDoctorAnomalyFinding -Category "CPU" -Severity "Warning" -Message ("High CPU activity from non-baseline process detected: {0}" -f $topProcess.ProcessName) -HistoryContext $historyContext
    }

    $severityCounts = @{
        Info     = @($findings | Where-Object Severity -eq "Info").Count
        Warning  = @($findings | Where-Object Severity -eq "Warning").Count
        Critical = @($findings | Where-Object Severity -eq "Critical").Count
    }

    $persistentFindings = @($findings | Where-Object Type -eq "Persistent")
    $transientFindings = @($findings | Where-Object Type -eq "Transient")

    return [PSCustomObject]@{
        Findings              = @($findings)
        DominantProcess       = $topProcess
        SeverityCounts        = [PSCustomObject]$severityCounts
        Summary               = if ($findings.Count -gt 0) { ($findings.Message -join "; ") } else { "No CPU anomalies detected" }
        HistoryClassification = $historyContext.Classification
        PersistentFindings    = @($persistentFindings)
        TransientFindings     = @($transientFindings)
        HistoryContext        = $historyContext
    }
}

Register-AutoDoctorModule -Name "Anomaly Analysis" -Execute {
    param($CPUObj)

    Invoke-AutoDoctorAnomalyAnalysis -CPUObj $CPUObj
}
