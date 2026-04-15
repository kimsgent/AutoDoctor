function New-AutoDoctorFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Source = "Rule",
        [string]$Type = ""
    )

    return [PSCustomObject]@{
        Category = $Category
        Severity = $Severity
        Message  = $Message
        Source   = $Source
        Type     = $Type
    }
}

function Add-AutoDoctorFinding {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$Collection,
        [Parameter(Mandatory = $true)]$Finding
    )

    $existing = $Collection | Where-Object {
        $_.Category -eq $Finding.Category -and
        $_.Severity -eq $Finding.Severity -and
        $_.Message -eq $Finding.Message -and
        $_.Source -eq $Finding.Source -and
        $_.Type -eq $Finding.Type
    }

    if (-not $existing) {
        [void]$Collection.Add($Finding)
    }
}

function Convert-AutoDoctorHistoryIssueToFinding {
    param(
        [Parameter(Mandatory = $true)]$Issue
    )

    return New-AutoDoctorFinding `
        -Category $Issue.Category `
        -Severity $Issue.Severity `
        -Message $Issue.Message `
        -Source "History" `
        -Type $Issue.Type
}

function Get-AutoDoctorSeverityWeight {
    param($Finding)

    $weight = switch ($Finding.Severity) {
        "Info" { 1 }
        "Warning" { 5 }
        "Critical" { 15 }
        default { 0 }
    }

    if ($Finding.Source -eq "Anomaly") {
        $weight += 2
    }
    elseif ($Finding.Source -eq "Validation" -and $Finding.Severity -ne "Info") {
        $weight += 2
    }
    if ($Finding.Category -eq "Disk" -and $Finding.Message -match "failure") {
        $weight += 10
    }

    if ($Finding.Type -eq "Sustained") {
        $weight += 6
    }
    elseif ($Finding.Type -eq "Persistent") {
        $weight += 4
    }
    elseif ($Finding.Type -eq "Transient") {
        $weight += 1
    }
    elseif ($Finding.Type -eq "Baseline") {
        $weight += 4
    }

    return $weight
}

function Get-AutoDoctorPenaltyMultiplier {
    param(
        [Parameter(Mandatory = $true)]$Finding,
        [int]$CategoryOccurrence = 0
    )

    $categoryFactor = switch ($CategoryOccurrence) {
        0 { 1.0 }
        1 { 0.7 }
        2 { 0.5 }
        default { 0.35 }
    }

    if ($Finding.Source -eq "Validation" -and $Finding.Severity -eq "Info") {
        return [double]($categoryFactor * 0.5)
    }

    return [double]$categoryFactor
}

Register-AutoDoctorModule -Name "Root Cause Analysis" -Execute {
    param(
        $MemoryObj,
        $CPUObj,
        $DiskObj,
        $NetworkObj,
        $ErrorObj,
        $ValidationObj,
        $AnomalyObj,
        $CorrelationObj
    )

    $findings = [System.Collections.ArrayList]::new()
    $historyAnalysis = Invoke-AutoDoctorHistoryAnalysis -CPUObj $CPUObj -MemoryObj $MemoryObj -DiskObj $DiskObj -NetworkObj $NetworkObj

    $diskUsage = if ($DiskObj -and $DiskObj.DiskUsage) { @($DiskObj.DiskUsage) } else { @() }
    $smart = if ($DiskObj -and $DiskObj.SMARTHealth) { @($DiskObj.SMARTHealth) } else { @() }
    $diskIo = if ($DiskObj -and $DiskObj.DiskIOSummary) { @($DiskObj.DiskIOSummary) } else { @() }

    if ($MemoryObj -and $null -ne $MemoryObj.TotalMemoryGB -and [double]$MemoryObj.TotalMemoryGB -gt 0) {
        $totalMemory = [double]$MemoryObj.TotalMemoryGB
        $freeMemory = if ($null -ne $MemoryObj.FreeMemoryGB) { [double]$MemoryObj.FreeMemoryGB } else { 0 }
        $usedPercent = [math]::Round((($totalMemory - $freeMemory) / $totalMemory) * 100, 1)

        if ($freeMemory -lt 1) {
            Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Memory" -Severity "Critical" -Message ("Low RAM available: only {0} GB free" -f ([math]::Round($freeMemory, 2))))
        }
        elseif ($usedPercent -ge 85) {
            Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Memory" -Severity "Warning" -Message ("Memory pressure detected: {0}% of RAM is in use" -f $usedPercent))
        }
    }

    if ($CPUObj -and $null -ne $CPUObj.CurrentCPULoadPercent) {
        $cpuLoad = [double]$CPUObj.CurrentCPULoadPercent

        if ($cpuLoad -ge 85) {
            Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "CPU" -Severity "Critical" -Message ("CPU saturation detected at {0}%" -f ([math]::Round($cpuLoad, 2))))
        }
        elseif ($cpuLoad -ge 70) {
            Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "CPU" -Severity "Warning" -Message ("Elevated CPU load detected at {0}%" -f ([math]::Round($cpuLoad, 2))))
        }
    }

    $lowDiskWarning = @($diskUsage | Where-Object {
            $freeGb = if ($null -ne $_.FreeGB) { [double]$_.FreeGB } else { $null }
            $usedGb = if ($null -ne $_.UsedGB) { [double]$_.UsedGB } else { $null }
            $totalGb = if ($null -ne $freeGb -and $null -ne $usedGb) { $freeGb + $usedGb } else { 0 }
            $percentFree = if ($totalGb -gt 0) { ($freeGb / $totalGb) * 100 } else { $null }

            ($null -ne $freeGb -and $freeGb -lt 5) -or
            ($null -ne $percentFree -and $percentFree -lt 10)
        })

    if ($lowDiskWarning.Count -gt 0) {
        $criticalLowDisk = @($lowDiskWarning | Where-Object { [double]$_.FreeGB -lt 2 })
        $severity = if ($criticalLowDisk.Count -gt 0) { "Critical" } else { "Warning" }
        $drives = ($lowDiskWarning | ForEach-Object { [string]$_.Name }) -join ", "
        Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Disk" -Severity $severity -Message ("Low disk space detected on drive(s): {0}" -f $drives))
    }

    $maxDiskBusy = if ($diskIo.Count -gt 0) {
        [double](($diskIo | Measure-Object -Property PercentBusy -Maximum).Maximum)
    }
    else {
        0
    }

    if ($maxDiskBusy -ge 80) {
        Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Disk" -Severity "Critical" -Message ("Disk IO bottleneck detected: peak disk busy is {0}%" -f ([math]::Round($maxDiskBusy, 2))))
    }
    elseif ($maxDiskBusy -ge 60) {
        Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Disk" -Severity "Warning" -Message ("Elevated disk IO activity detected: peak disk busy is {0}%" -f ([math]::Round($maxDiskBusy, 2))))
    }

    if ($smart.Count -gt 0 -and ($smart.PredictFailure -contains $true)) {
        Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Disk" -Severity "Critical" -Message "Potential disk failure detected")
    }

    if ($NetworkObj -and $NetworkObj.Connectivity -and $null -ne $NetworkObj.Connectivity.AvgLatencyMS) {
        $latency = [double]$NetworkObj.Connectivity.AvgLatencyMS

        if ($latency -ge 200) {
            Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Network" -Severity "Critical" -Message ("High network latency detected: {0} ms average" -f ([math]::Round($latency, 2))))
        }
        elseif ($latency -ge 100) {
            Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Network" -Severity "Warning" -Message ("Elevated network latency detected: {0} ms average" -f ([math]::Round($latency, 2))))
        }
    }

    if ($ErrorObj -and $null -ne $ErrorObj.ErrorCount) {
        $errorCount = [int]$ErrorObj.ErrorCount

        if ($errorCount -ge 100) {
            Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Events" -Severity "Critical" -Message ("Very high error rate in event logs: {0} recent errors" -f $errorCount))
        }
        elseif ($errorCount -ge 30) {
            Add-AutoDoctorFinding -Collection $findings -Finding (New-AutoDoctorFinding -Category "Events" -Severity "Warning" -Message ("High error rate in event logs: {0} recent errors" -f $errorCount))
        }
    }

    foreach ($validationFinding in @($ValidationObj.Findings)) {
        Add-AutoDoctorFinding -Collection $findings -Finding $validationFinding
    }

    foreach ($anomalyFinding in @($AnomalyObj.Findings)) {
        Add-AutoDoctorFinding -Collection $findings -Finding $anomalyFinding
    }

    foreach ($correlationFinding in @($CorrelationObj.Findings)) {
        Add-AutoDoctorFinding -Collection $findings -Finding $correlationFinding
    }

    foreach ($historyIssue in @($historyAnalysis.SustainedIssues)) {
        Add-AutoDoctorFinding -Collection $findings -Finding (Convert-AutoDoctorHistoryIssueToFinding -Issue $historyIssue)
    }

    foreach ($historyIssue in @($historyAnalysis.TransientIssues)) {
        Add-AutoDoctorFinding -Collection $findings -Finding (Convert-AutoDoctorHistoryIssueToFinding -Issue $historyIssue)
    }

    foreach ($historyIssue in @($historyAnalysis.BaselineDeviations)) {
        Add-AutoDoctorFinding -Collection $findings -Finding (Convert-AutoDoctorHistoryIssueToFinding -Issue $historyIssue)
    }

    $orderedFindings = @($findings | Sort-Object @{ Expression = {
                    switch ($_.Severity) {
                        "Critical" { 0 }
                        "Warning" { 1 }
                        "Info" { 2 }
                        default { 3 }
                    }
                }
            }, Category, Message)

    $score = 100
    $categoryPenaltyCounts = @{}
    $penaltyBreakdown = @()
    foreach ($finding in $orderedFindings) {
        $categoryKey = if ($finding.Category) { [string]$finding.Category } else { "Uncategorized" }

        if (-not $categoryPenaltyCounts.ContainsKey($categoryKey)) {
            $categoryPenaltyCounts[$categoryKey] = 0
        }

        $baseWeight = Get-AutoDoctorSeverityWeight -Finding $finding
        $multiplier = Get-AutoDoctorPenaltyMultiplier -Finding $finding -CategoryOccurrence $categoryPenaltyCounts[$categoryKey]
        $penalty = [math]::Round(($baseWeight * $multiplier), 0)
        $score -= $penalty
        $penaltyBreakdown += [PSCustomObject]@{
            Category   = $categoryKey
            Severity   = $finding.Severity
            Source     = $finding.Source
            Type       = $finding.Type
            Message    = $finding.Message
            BaseWeight = $baseWeight
            Multiplier = [math]::Round($multiplier, 2)
            Penalty    = $penalty
        }
        $categoryPenaltyCounts[$categoryKey]++
    }

    if ($orderedFindings.Count -gt 0 -and @($orderedFindings | Where-Object Source -eq "Anomaly").Count -gt 0 -and $score -gt 95) {
        $score = 95
    }

    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    $severityCounts = [PSCustomObject]@{
        Info     = @($orderedFindings | Where-Object Severity -eq "Info").Count
        Warning  = @($orderedFindings | Where-Object Severity -eq "Warning").Count
        Critical = @($orderedFindings | Where-Object Severity -eq "Critical").Count
    }
    $categoryPenaltySummary = @($penaltyBreakdown |
            Group-Object Category |
            ForEach-Object {
                [PSCustomObject]@{
                    Category     = $_.Name
                    TotalPenalty = [int](($_.Group | Measure-Object -Property Penalty -Sum).Sum)
                    Findings     = @($_.Group)
                }
            } |
            Sort-Object TotalPenalty -Descending)

    $summary = if ($orderedFindings.Count -eq 0) {
        "No major issues detected"
    }
    else {
        (@($orderedFindings | Select-Object -First 4 | ForEach-Object { $_.Message })) -join "; "
    }

    $detectedIssues = @($orderedFindings | ForEach-Object { $_.Message })
    $roundedScore = [int][math]::Round($score, 0)

    return [PSCustomObject]@{
        HealthScore = $roundedScore
        HealthText  = ("{0} / 100" -f $roundedScore)
        Summary     = $summary
        Details     = [PSCustomObject]@{
            Findings           = @($orderedFindings)
            DetectedIssues     = @($detectedIssues)
            SeverityCounts     = $severityCounts
            Anomalies          = if ($AnomalyObj -and $AnomalyObj.Findings) { @($AnomalyObj.Findings) } else { @() }
            Correlations       = if ($CorrelationObj -and $CorrelationObj.Findings) { @($CorrelationObj.Findings) } else { @() }
            ValidationIssues   = if ($ValidationObj -and $ValidationObj.Findings) { @($ValidationObj.Findings) } else { @() }
            ScoreBreakdown     = [PSCustomObject]@{
                Findings  = @($penaltyBreakdown)
                Categories = @($categoryPenaltySummary)
            }
            HistoricalAnalysis = if ($historyAnalysis) {
                [PSCustomObject]@{
                    CPUTrend     = @($historyAnalysis.CPUTrend)
                    MemoryTrend  = @($historyAnalysis.MemoryTrend)
                    DiskTrend    = @($historyAnalysis.DiskTrend)
                    NetworkTrend = @($historyAnalysis.NetworkTrend)
                    MetricStates = @($historyAnalysis.MetricStates)
                    TrendWindow  = $historyAnalysis.TrendWindow
                }
            }
            else {
                $null
            }
            TrendSummary       = if ($historyAnalysis) { @($historyAnalysis.TrendSummary) } else { @() }
            MetricStates       = if ($historyAnalysis) { @($historyAnalysis.MetricStates) } else { @() }
            SustainedIssues    = if ($historyAnalysis) { @($historyAnalysis.SustainedIssues) } else { @() }
            TransientIssues    = if ($historyAnalysis) { @($historyAnalysis.TransientIssues) } else { @() }
            BaselineDeviations = if ($historyAnalysis) { @($historyAnalysis.BaselineDeviations) } else { @() }
            GradualTrends      = if ($historyAnalysis) { @($historyAnalysis.GradualTrends) } else { @() }
            PersistentAnomalies = if ($AnomalyObj -and $AnomalyObj.PersistentFindings) { @($AnomalyObj.PersistentFindings) } else { @() }
            TransientAnomalies  = if ($AnomalyObj -and $AnomalyObj.TransientFindings) { @($AnomalyObj.TransientFindings) } else { @() }
        }
    }
}
