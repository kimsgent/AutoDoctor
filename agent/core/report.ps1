<#
===============================================================================
AutoDoctor Report Module
Generates HTML Dashboard and Structured JSON Report
===============================================================================
#>

# -----------------------------
# HELPER: Safe access to module results
# -----------------------------
function Get-SafeModuleResult {
    param(
        [Parameter(Mandatory = $true)][array]$ModuleResults,
        [Parameter(Mandatory = $true)][string]$ModuleName,
        [Parameter()][string]$PropertyPath = ""
    )

    $mod = $ModuleResults | Where-Object { $_.Module -eq $ModuleName }
    if (-not $mod) { return $null }

    if ($PropertyPath) {
        try {
            $value = $mod.Result
            foreach ($prop in $PropertyPath -split "\.") {
                if ($value -and $value.PSObject.Properties.Match($prop)) {
                    $value = $value.$prop
                } else {
                    return $null
                }
            }
            return $value
        } catch { return $null }
    }

    return $mod.Result
}

function Get-AutoDoctorMetricUnit {
    param([string]$Metric)

    switch ($Metric) {
        "CPU" { return "%" }
        "Memory" { return "%" }
        "Disk" { return "%" }
        "Network" { return " ms" }
        default { return "" }
    }
}

function Format-AutoDoctorMetricValue {
    param(
        [string]$Metric,
        $Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "n/a"
    }

    $number = [double]$Value
    return ("{0}{1}" -f ([math]::Round($number, 2)), (Get-AutoDoctorMetricUnit -Metric $Metric))
}

function Format-AutoDoctorDeltaValue {
    param(
        [string]$Metric,
        $Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "n/a"
    }

    $number = [double]$Value
    $sign = if ($number -gt 0) { "+" } else { "" }
    return ("{0}{1}{2}" -f $sign, ([math]::Round($number, 2)), (Get-AutoDoctorMetricUnit -Metric $Metric))
}

function Get-AutoDoctorStateCssClass {
    param([string]$State)

    $normalizedState = if ($State) { $State.ToLowerInvariant() } else { "" }

    switch ($normalizedState) {
        "sustained" { return "state-critical" }
        "baseline deviation" { return "state-baseline" }
        "transient" { return "state-warning" }
        "increasing" { return "state-warning" }
        "decreasing" { return "state-improving" }
        "recovering" { return "state-improving" }
        default { return "state-stable" }
    }
}

function Get-AutoDoctorDirectionDisplay {
    param(
        [string]$DirectionIcon,
        [string]$Direction
    )

    $normalized = if ($DirectionIcon) { $DirectionIcon.ToLowerInvariant() } else { "" }

    switch ($normalized) {
        "up" { return "&uarr;" }
        "down" { return "&darr;" }
        "flat" { return "&rarr;" }
    }

    switch ($Direction) {
        "Increasing" { return "&uarr;" }
        "Decreasing" { return "&darr;" }
        default { return "&rarr;" }
    }
}

function ConvertTo-AutoDoctorHtmlString {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [string]) {
        return $Value
    }

    if ($Value -is [System.Array]) {
        return (@($Value) | ForEach-Object { [string]$_ }) -join "`n"
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return (@($Value) | ForEach-Object { [string]$_ }) -join "`n"
    }

    return [string]$Value
}

function ConvertTo-AutoDoctorCardHtml {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)]$Body,
        [switch]$FullWidth,
        [switch]$Collapsible,
        [switch]$Expanded,
        [string]$SummaryText = ""
    )

    $className = if ($FullWidth) { "card full" } else { "card" }
    $bodyHtml = ConvertTo-AutoDoctorHtmlString -Value $Body

    if ($Collapsible) {
        $openAttr = if ($Expanded) { " open" } else { "" }
        $meta = if ($SummaryText) { "<span class='summary-meta'>$SummaryText</span>" } else { "" }

        return @"
<details class='$className card-collapse'$openAttr>
<summary><span>$Title</span>$meta<span class='summary-icon'>+</span></summary>
<div class='card-content'>
$bodyHtml
</div>
</details>
"@
    }

    return @"
<div class='$className'>
<h2>$Title</h2>
$bodyHtml
</div>
"@
}

function Convert-AutoDoctorFindingsToHtml {
    param(
        [array]$Findings,
        [string]$Title,
        [switch]$Collapsible,
        [switch]$Expanded
    )

    if (-not $Findings -or $Findings.Count -eq 0) {
        return ""
    }

    $rows = @($Findings | ConvertTo-Html -Fragment) -join "`n"
    return ConvertTo-AutoDoctorCardHtml -Title $Title -Body $rows -FullWidth -Collapsible:$Collapsible -Expanded:$Expanded -SummaryText ("{0} item{1}" -f $Findings.Count, $(if ($Findings.Count -eq 1) { "" } else { "s" }))
}

function Convert-AutoDoctorTrendSummaryToHtml {
    param(
        [array]$MetricStates,
        $TrendWindow
    )

    if (-not $MetricStates -or $MetricStates.Count -eq 0) {
        return ""
    }

    $scope = if ($TrendWindow -and $TrendWindow.WindowLabel) {
        "<p class='card-meta'>$($TrendWindow.WindowLabel) | $($TrendWindow.HistoricalSamples + 1) samples</p>"
    }
    else {
        ""
    }

    $rows = @($MetricStates | ForEach-Object {
            $stateClass = Get-AutoDoctorStateCssClass -State $_.State
            @"
<div class='metric-row'>
  <div class='metric-main'>
    <span class='metric-name'>$($_.Metric)</span>
    <span class='state-badge $stateClass'>$($_.State)</span>
  </div>
  <div class='metric-stats'>
    <span>Current: <b>$(Format-AutoDoctorMetricValue -Metric $_.Metric -Value $_.Current)</b></span>
    <span>Baseline: $(Format-AutoDoctorMetricValue -Metric $_.Metric -Value $_.Baseline)</span>
    <span>Threshold: $(Format-AutoDoctorMetricValue -Metric $_.Metric -Value $_.Threshold)</span>
    <span>Delta: $(Format-AutoDoctorDeltaValue -Metric $_.Metric -Value $_.DeltaFromBaseline)</span>
  </div>
  <div class='metric-trend'>
    <span class='direction-indicator'>$(Get-AutoDoctorDirectionDisplay -DirectionIcon $_.DirectionIcon -Direction $_.Direction)</span>
    <span>$($_.Direction)</span>
  </div>
</div>
"@
        }) -join "`n"

    return ConvertTo-AutoDoctorCardHtml -Title "Trend Summary" -Body ($scope + "<div class='metric-board'>$rows</div>")
}

function Convert-AutoDoctorStateStripToHtml {
    param([array]$MetricStates)

    if (-not $MetricStates -or $MetricStates.Count -eq 0) {
        return ""
    }

    $items = @($MetricStates | ForEach-Object {
            $stateClass = Get-AutoDoctorStateCssClass -State $_.State
            "<div class='state-tile'><span class='state-label'>$($_.Metric)</span><span class='state-badge $stateClass'>$($_.State)</span></div>"
        }) -join "`n"

    return ConvertTo-AutoDoctorCardHtml -Title "Current State" -Body "<div class='state-strip'>$items</div>" -FullWidth
}

function Convert-AutoDoctorScoreExplanationToHtml {
    param(
        $ScoreBreakdown,
        [array]$MetricStates
    )

    if (-not $ScoreBreakdown -or -not $ScoreBreakdown.Categories) {
        return ""
    }

    $topCategory = @($ScoreBreakdown.Categories | Select-Object -First 1)
    $topFindingLines = if ($topCategory.Count -gt 0) {
        @($topCategory[0].Findings | Select-Object -First 3 | ForEach-Object {
                "<li>$($_.Message)</li>"
            }) -join ""
    }
    else {
        ""
    }

    $stableMetrics = @($MetricStates | Where-Object { $_.State -eq "Stable" -or $_.State -eq "Decreasing" })
    $stableText = if ($stableMetrics.Count -gt 0) {
        ($stableMetrics | ForEach-Object { "$($_.Metric): $($_.State)" }) -join " | "
    }
    else {
        "No clearly stable metrics in this run"
    }

    $supporting = @($ScoreBreakdown.Categories | Select-Object -Skip 1 -First 2 | ForEach-Object { "$($_.Category) ($($_.TotalPenalty))" }) -join " | "

    $body = @"
<div class='score-explainer'>
  <p><b>Primary driver:</b> $(if ($topCategory.Count -gt 0) { "$($topCategory[0].Category) (penalty $($topCategory[0].TotalPenalty))" } else { "n/a" })</p>
  <ul>$topFindingLines</ul>
  <p><b>Supporting factors:</b> $(if ($supporting) { $supporting } else { "None beyond primary driver" })</p>
  <p><b>Stable components:</b> $stableText</p>
</div>
"@

    return ConvertTo-AutoDoctorCardHtml -Title "Why The Score Changed" -Body $body -FullWidth
}

function Convert-AutoDoctorSectionToHtml {
    param($Section)

    if ($Section -is [string]) {
        return ConvertTo-AutoDoctorCardHtml -Title "Details" -Body $Section -FullWidth
    }

    if (-not $Section) {
        return ""
    }

    $summaryText = ""

    if ($Section.Collapsible -and $Section.ContentHtml) {
        $summaryText = if ($Section.ContentHtml -match "<tr>") { "Click to expand" } else { "" }
    }

    return ConvertTo-AutoDoctorCardHtml `
        -Title ([string]$Section.Title) `
        -Body $Section.ContentHtml `
        -FullWidth:([bool]$Section.FullWidth) `
        -Collapsible:([bool]$Section.Collapsible) `
        -Expanded:([bool]$Section.Expanded) `
        -SummaryText $summaryText
}

function Get-AutoDoctorDetailCollection {
    param($Value)

    if ($null -eq $Value) {
        return ,([object[]]@())
    }

    if ($Value -is [System.Array]) {
        return ,([object[]]@($Value))
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [psobject]) {
        return ,([object[]]@($Value))
    }

    if ($Value -is [psobject]) {
        $propertyNames = @($Value.PSObject.Properties.Name)
        $meaningfulPropertyNames = @($propertyNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($meaningfulPropertyNames.Count -eq 0) {
            return ,([object[]]@())
        }
    }

    return ,([object[]]@($Value))
}


# -----------------------------------------------------------------------------
# HTML REPORT FUNCTION
# -----------------------------------------------------------------------------
function New-AutoDoctorReport {
    param(
        [array]$Sections,
        [array]$ModuleResults,
        [string]$OutputPath
    )

    # -----------------------------
    # STYLE
    # -----------------------------
    $style = @"
<style>
body{font-family:Segoe UI,Arial;margin:30px;background:#f5f7fa}
h1{color:#1f4e79;border-bottom:3px solid #1f4e79;padding-bottom:6px}
h2{margin-top:0;font-size:18px}
.dashboard{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-top:20px}
.card{background:white;padding:18px;border-radius:8px;box-shadow:0 2px 6px rgba(0,0,0,0.1)}
.full{grid-column:1 / span 2}
.card-meta{margin:0 0 14px 0;color:#667085;font-size:13px}
table{border-collapse:collapse;width:100%;margin-top:10px}
td,th{border:1px solid #ddd;padding:6px}
th{background:#f2f2f2}
.health-good{color:#2e7d32;font-weight:bold}
.health-warning{color:#f9a825;font-weight:bold}
.health-bad{color:#c62828;font-weight:bold}
.scorebar{width:100%;height:22px;background:#ddd;border-radius:6px;overflow:hidden}
.scorefill{height:100%;background:linear-gradient(90deg,#4caf50,#ff9800,#e53935)}
.chartbar{width:100%;height:14px;background:#ddd;border-radius:3px;overflow:hidden;margin-bottom:6px}
.chartfill{height:100%;background:#1f77b4}
.cpufill{height:100%;background:#ff6f00}
.issuebox{background:#fff3cd;border-left:5px solid #ff9800;padding:10px;margin-top:10px}
.cpudonut{
width:140px;
height:140px;
border-radius:50%;
display:flex;
align-items:center;
justify-content:center;
font-size:22px;
font-weight:bold;
margin:auto;
background:conic-gradient(#ff6f00 var(--cpu), #e6e6e6 0);
}
.metric-board{display:flex;flex-direction:column;gap:12px}
.metric-row{display:grid;grid-template-columns:1.2fr 2.5fr 0.8fr;gap:12px;align-items:center;padding:12px;border:1px solid #e6eaf0;border-radius:10px;background:#fafbfd}
.metric-main{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.metric-name{font-weight:700;color:#1f4e79}
.metric-stats{display:flex;gap:12px;flex-wrap:wrap;color:#374151;font-size:13px}
.metric-trend{display:flex;align-items:center;gap:8px;justify-content:flex-end;font-weight:600;color:#344054}
.direction-indicator{font-size:18px;color:#1f4e79}
.state-strip{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}
.state-tile{display:flex;justify-content:space-between;align-items:center;padding:12px;border:1px solid #e6eaf0;border-radius:10px;background:#fafbfd}
.state-label{font-weight:700;color:#1f4e79}
.state-badge{display:inline-flex;align-items:center;padding:4px 10px;border-radius:999px;font-size:12px;font-weight:700}
.state-stable{background:#eef2f6;color:#44546a}
.state-warning{background:#fff3d6;color:#9a6700}
.state-critical{background:#fbe4e6;color:#b42318}
.state-baseline{background:#ffe5d0;color:#b54708}
.state-improving{background:#dff6eb;color:#027a48}
.score-explainer p{margin:0 0 10px 0}
.score-explainer ul{margin:0 0 10px 18px;padding:0}
.card-collapse{padding:0;overflow:hidden}
.card-collapse summary{display:flex;align-items:center;justify-content:space-between;gap:12px;cursor:pointer;list-style:none;padding:18px;font-weight:700;color:#1f4e79}
.card-collapse summary::-webkit-details-marker{display:none}
.card-collapse .card-content{padding:0 18px 18px 18px}
.summary-meta{font-weight:400;font-size:12px;color:#667085;margin-left:auto}
.summary-icon{font-size:20px;line-height:1;color:#667085}
.card-collapse[open] .summary-icon{transform:rotate(45deg)}
@media (max-width: 900px){
  .metric-row{grid-template-columns:1fr}
  .metric-trend{justify-content:flex-start}
}
</style>
"@

    # -----------------------------
    # HEALTH SCORE PANEL
    # -----------------------------
    $rootModule = $ModuleResults | Where-Object Module -eq "Root Cause Analysis"
    $score = if ($rootModule) { $rootModule.Result.HealthScore } else { 0 }
    $displayText = if ($rootModule) { $rootModule.Result.HealthText } else { "$score / 100" }
    $rootDetails = if ($rootModule -and $rootModule.Result) { $rootModule.Result.Details } else { $null }

    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    $healthClass = "health-good"
    if ($score -lt 80) { $healthClass = "health-warning" }
    if ($score -lt 60) { $healthClass = "health-bad" }

    $healthVisual = @"
<div class='card'>
<h2>System Health</h2>
<p class='$healthClass'>Health Score: $displayText</p>
<div class='scorebar'>
<div class='scorefill' style='width:${score}%'></div>
</div>
</div>
"@

    # -----------------------------
    # MEMORY PANEL
    # -----------------------------
    $memoryModule = $ModuleResults | Where-Object { $_.Module -eq "Memory Analysis" }
    if ($memoryModule) {
        $totalMem = if ($null -ne $memoryModule.Result.TotalMemoryGB) { [double]$memoryModule.Result.TotalMemoryGB } else { 0 }
        $freeMem = if ($null -ne $memoryModule.Result.FreeMemoryGB) { [double]$memoryModule.Result.FreeMemoryGB } else { 0 }

        if ($totalMem -gt 0) {
            if ($freeMem -lt 0) { $freeMem = 0 }
            if ($freeMem -gt $totalMem) { $freeMem = $totalMem }
            $memUsedPercent = [math]::Round((($totalMem - $freeMem) / $totalMem) * 100, 1)
        }
        else {
            $memUsedPercent = 0
        }

        $memChart = @"
<div class='card'>
<h2>Memory Pressure</h2>
<p>Used: $memUsedPercent %</p>
<div class='chartbar'>
<div class='chartfill' style='width:${memUsedPercent}%'></div>
</div>
</div>
"@
    } else { $memChart = "" }


    # -----------------------------
    # CPU PANEL
    # -----------------------------
    $cpuModule = $ModuleResults | Where-Object { $_.Module -eq "CPU Analysis" }

    if ($cpuModule) {

        # Fallback to WMI if CurrentCPULoadPercent is null
        if ($null -eq $cpuModule.Result.CurrentCPULoadPercent) {
            try {
                $cpuModule.Result.CurrentCPULoadPercent = (Get-CimInstance Win32_Processor).LoadPercentage
            } catch {
                Write-Warning "CPU fallback via WMI failed: $_"
                $cpuModule.Result.CurrentCPULoadPercent = 0
            }
        }

        $cpuPercent = if ($null -ne $cpuModule.Result.CurrentCPULoadPercent) { [double]$cpuModule.Result.CurrentCPULoadPercent } else { 0 }
        if ($cpuPercent -lt 0) { $cpuPercent = 0 }
        if ($cpuPercent -gt 100) { $cpuPercent = 100 }

        $cpuChartData = ""
        $topProcesses = if ($cpuModule.Result.TopProcesses) { @($cpuModule.Result.TopProcesses) } else { @() }

        if ($topProcesses.Count -gt 0) {
            $cpuChartData = ($topProcesses | ForEach-Object {
                    $processCpu = if ($null -ne $_.CPU) { [math]::Round([double]$_.CPU,2) } else { 0 }
                    "<p>$($_.ProcessName): $processCpu</p>"
                }) -join "`n"
        }

        $cpuChart = @"
<div class='card'>
<h2>CPU Utilization</h2>
<div class='cpudonut' style='--cpu:${cpuPercent}%'>
        ${cpuPercent}%
</div>
</div>
<div class='card'>
<h2>Top CPU Processes</h2>
        $cpuChartData
</div>
"@

    } else { $cpuChart = "" }

    # -----------------------------
    # DISK PANEL
    # -----------------------------
    $diskModule = $ModuleResults | Where-Object { $_.Module -eq "Disk Analysis" }
    if ($diskModule) {

        # Fallback to WMI if DiskIOSummary is null or empty
        if (-not $diskModule.Result.DiskIOSummary) {
            try {
                $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
                $diskModule.Result.DiskIOSummary = $disks | ForEach-Object {
                    [PSCustomObject]@{
                        Disk        = $_.DeviceID
                        PercentBusy = 0  # fallback, could be enhanced later
                    }
                }
            } catch {
                Write-Warning "Disk fallback via WMI failed: $_"
                $diskModule.Result.DiskIOSummary = @()
            }
        }

        $diskChartData = @()
        $diskSummaryRows = if ($diskModule.Result.DiskIOSummary) { @($diskModule.Result.DiskIOSummary) } else { @() }
        if ($diskSummaryRows.Count -gt 0) {
            $diskChartData += ($diskSummaryRows | ForEach-Object {
                    "<p>$($_.Disk): $($_.PercentBusy)% busy</p>"
                }) -join "`n"
        }

        $diskChart = @"
<div class='card full'>
<h2>Disk IO Activity</h2>
        $diskChartData
</div>
"@
    } else { $diskChart = "" }

    $severityPanel = ""
    $findingsPanel = ""
    $anomalyPanel = ""
    $correlationPanel = ""
    $trendSummaryPanel = ""
    $stateStripPanel = ""
    $scoreExplanationPanel = ""
    $sustainedPanel = ""
    $transientPanel = ""
    $baselinePanel = ""
    $rootSummaryPanel = ""

    if ($rootDetails) {
        if ($rootDetails.SeverityCounts) {
            $severityRows = @(@(
                [PSCustomObject]@{ Severity = "Critical"; Count = $rootDetails.SeverityCounts.Critical }
                [PSCustomObject]@{ Severity = "Warning"; Count = $rootDetails.SeverityCounts.Warning }
                [PSCustomObject]@{ Severity = "Info"; Count = $rootDetails.SeverityCounts.Info }
            ) | ConvertTo-Html -Fragment) -join "`n"

            $severityPanel = @"
<div class='card'>
<h2>Severity Summary</h2>
$severityRows
</div>
"@
        }

        $rootSummaryPanel = ConvertTo-AutoDoctorCardHtml -Title "Root Cause Summary" -Body "<p>$($rootModule.Result.Summary)</p>" -FullWidth
        $findingsPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.Findings) -Title "Root Cause Findings" -Collapsible
        $anomalyPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.Anomalies) -Title "Anomaly Insights" -Collapsible
        $correlationPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.Correlations) -Title "Correlation Insights" -Collapsible
        $trendSummaryPanel = Convert-AutoDoctorTrendSummaryToHtml -MetricStates @($rootDetails.MetricStates) -TrendWindow $rootDetails.HistoricalAnalysis.TrendWindow
        $stateStripPanel = Convert-AutoDoctorStateStripToHtml -MetricStates @($rootDetails.MetricStates)
        $scoreExplanationPanel = Convert-AutoDoctorScoreExplanationToHtml -ScoreBreakdown $rootDetails.ScoreBreakdown -MetricStates @($rootDetails.MetricStates)
        $sustainedPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.SustainedIssues) -Title "Sustained Issues" -Expanded
        $transientPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.TransientIssues) -Title "Transient Issues" -Collapsible
        $baselinePanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.BaselineDeviations) -Title "Baseline Deviations" -Expanded
    }

    # -----------------------------
    # JOIN MODULE SECTIONS
    # -----------------------------
    if (-not $Sections) { $Sections = @([PSCustomObject]@{ Title = "Details"; ContentHtml = "<p>No module results available.</p>"; Expanded = $true; Collapsible = $false; FullWidth = $true }) }
    $body = ($Sections | ForEach-Object { Convert-AutoDoctorSectionToHtml -Section $_ }) -join "`n"

    # -----------------------------
    # FINAL HTML
    # -----------------------------

    # -----------------------------
    # REPORT METADATA
    # -----------------------------
    $reportTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $runID = $Global:AutoDoctorRunID
    $hostName = $env:COMPUTERNAME

    $reportMetaHTML = @"
<div class='report-meta'>
Run ID: <b>$runID</b> |
Host: <b>$hostName</b> |
Generated: $reportTime
</div>
"@

    $logoHTML = @"
<div class='header'>
    <div class='header-left'>
        <img src='logo.png' alt='Project Indexly Logo'>
    </div>
    <div class='header-right'>
        <h1>Windows AutoDoctor Dashboard</h1>
        $reportMetaHTML
    </div>
</div>
"@

    $updateFooterHTML = ""

    if ($Global:AutoDoctorUpdateInfo -and $Global:AutoDoctorUpdateInfo.UpdateAvailable -and $Global:AutoDoctorUpdateInfo.LatestVersion) {
        $latestVersion = [string]$Global:AutoDoctorUpdateInfo.LatestVersion
        $currentVersion = [string]$Global:AutoDoctorUpdateInfo.CurrentVersion
        $repoUrl = [string]$Global:AutoDoctorUpdateInfo.RepoUrl

        if (-not $repoUrl) {
            $repoUrl = "https://github.com/kimsgent/autodoctor"
        }

        $updateFooterHTML = @"
<div style='text-align:center; margin-top:10px; color:#cc3300; font-size:14px;'>
  Update available: v$latestVersion (current: v$currentVersion) -
  <a href='$repoUrl' target='_blank'>Download here</a>
</div>
"@
    }

    $footerHTML = @"
<hr style='margin-top:60px;'>

<div class='footer'>
Projects: ProjectIndexly |
Email: kimscourse@projectindexly.com

<br>

Main Repository:
<a href='https://github.com/kimsgent/project-indexly'>
github.com/kimsgent/project-indexly
</a>

|

Documentation:
<a href='https://projectindexly.com'>
projectindexly.com
</a>

<br>

AutoDoctor Repository:
<a href='https://github.com/kimsgent/autodoctor'>
github.com/kimsgent/autodoctor
</a>

<br><br>

$updateFooterHTML

<br>

<span class='disclaimer'>
Disclaimer: AutoDoctor diagnostics are informational and provided without warranty.
</span>

</div>
"@

    $finalHTML = @"
<!DOCTYPE html>
<html lang='en'>

<head>

<meta charset='UTF-8'>
<title>Windows AutoDoctor Dashboard</title>

$style

<style>

.header{
display:flex;
align-items:center;
justify-content:space-between;
margin-bottom:20px;
}

.header-left img{
height:70px;
}

.header-right h1{
margin:0;
color:#1f4e79;
}

.report-meta{
font-size:13px;
color:#555;
margin-top:6px;
}

.footer{
text-align:center;
font-size:12px;
color:#555;
margin-top:20px;
}

.footer a{
color:#1f4e79;
text-decoration:none;
}

.footer a:hover{
text-decoration:underline;
}

.disclaimer{
font-style:italic;
}

img{
max-width:100%;
height:auto;
}

</style>

</head>

<body>

$logoHTML

<div class='dashboard'>

$healthVisual
$severityPanel
$memChart
$cpuChart
$trendSummaryPanel
$stateStripPanel
$diskChart
$rootSummaryPanel
$scoreExplanationPanel
$sustainedPanel
$transientPanel
$baselinePanel
$findingsPanel
$anomalyPanel
$correlationPanel
$body

</div>

$footerHTML

</body>

</html>
"@

    $finalHTML | Out-File $OutputPath -Encoding UTF8 -Force

    Write-Host "HTML report created: $OutputPath" -ForegroundColor Green

    Start-Process $OutputPath
}

# -----------------------------------------------------------------------------
# JSON REPORT FUNCTION
# -----------------------------------------------------------------------------
function New-AutoDoctorJsonReport {
    param(
        [array]$ModuleResults,
        [string]$OutputPath
    )

    # -------------------------
    # MEMORY
    # -------------------------
    $memoryModule = $ModuleResults | Where-Object { $_.Module -eq "Memory Analysis" }
    $totalMem = if ($memoryModule -and $null -ne $memoryModule.Result.TotalMemoryGB) { [double]$memoryModule.Result.TotalMemoryGB } else { 0 }
    $freeMem = if ($memoryModule -and $null -ne $memoryModule.Result.FreeMemoryGB) { [double]$memoryModule.Result.FreeMemoryGB } else { 0 }

    if ($totalMem -gt 0) {
        if ($freeMem -lt 0) { $freeMem = 0 }
        if ($freeMem -gt $totalMem) { $freeMem = $totalMem }
        $memUsedPercent = [math]::Round((($totalMem - $freeMem) / $totalMem) * 100, 1)
    }
    else {
        $memUsedPercent = 0
    }

    # -------------------------
    # CPU per-core (with fallback)
    # -------------------------
    $cpuCoreData = @()

    $cpuCounterPath = "\Processor(*)\% Processor Time"
    $cpuCounters = $null

    try {
        $cpuCounters = Get-Counter -Counter $cpuCounterPath -ErrorAction Stop
    }
    catch {
        $localizedCpuPath = Get-LocalizedCounterPath -CanonicalName "Processor" -CounterPath $cpuCounterPath

        if ($localizedCpuPath) {
            try {
                $cpuCounters = Get-Counter -Counter $localizedCpuPath -ErrorAction Stop
            }
            catch {
                $cpuCounters = $null
            }
        }
    }

    if ($cpuCounters) {
        $cpuCoreData = $cpuCounters.CounterSamples |
            Where-Object { $_.InstanceName -notmatch '^(?i)_?(total|gesamt)$' } |
            ForEach-Object {
                [PSCustomObject]@{
                    Core        = $_.InstanceName
                    PercentUsed = [math]::Round($_.CookedValue, 1)
                }
            }
    }
    else {
        Write-Warning "PerfCounter failed, fallback to WMI"

        try {
            $cpuPerf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor

            if ($cpuPerf) {
                $cpuCoreData = $cpuPerf |
                    Where-Object { $_.Name -notmatch '^(?i)_?(total|gesamt)$' } |
                    ForEach-Object {
                        [PSCustomObject]@{
                            Core        = $_.Name
                            PercentUsed = [math]::Round($_.PercentProcessorTime, 1)
                        }
                    }
            }
        }
        catch {
            Write-Warning "CPU per-core WMI fallback failed"
            $cpuCoreData = @()
        }
    }

    # -------------------------
    # Disk IO (with fallback)
    # -------------------------
    $diskIOSummaryData = @()

    $diskCounterPath = "\PhysicalDisk(*)\% Disk Time"
    $diskIO = $null

    try {
        $diskIO = Get-Counter -Counter $diskCounterPath -ErrorAction Stop
    }
    catch {
        $localizedDiskPath = Get-LocalizedCounterPath -CanonicalName "PhysicalDisk" -CounterPath $diskCounterPath

        if ($localizedDiskPath) {
            try {
                $diskIO = Get-Counter -Counter $localizedDiskPath -ErrorAction Stop
            }
            catch {
                $diskIO = $null
            }
        }
    }

    if ($diskIO) {
        $diskIOSummaryData = $diskIO.CounterSamples |
            Where-Object { $_.InstanceName -notmatch '^(?i)_?(total|gesamt)$' } |
            ForEach-Object {
            [PSCustomObject]@{
                Disk        = $_.InstanceName
                PercentBusy = [math]::Round($_.CookedValue, 2)
            }
        }
    }
    else {
        Write-Warning "PerfCounter failed, fallback to WMI"

        try {
            $diskPerf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk

            if ($diskPerf) {
                $diskIOSummaryData = $diskPerf | Where-Object { $_.Name -notmatch '^(?i)_?(total|gesamt)$' } | ForEach-Object {
                    [PSCustomObject]@{
                        Disk        = $_.Name
                        PercentBusy = [math]::Round($_.PercentDiskTime, 2)
                    }
                }
            }
        }
        catch {
            Write-Warning "Disk WMI fallback failed"
            $diskIOSummaryData = @()
        }
    }

    # -------------------------
    # Root & Remediation
    # -------------------------
    $rootResult = $ModuleResults | Where-Object { $_.Module -eq "Root Cause Analysis" }
    $remediationResult = $ModuleResults | Where-Object { $_.Module -eq "Self-Healing Remediation" }

    # Ensure content is human-readable
    $rootCauseAnalysis = if ($rootResult -and $rootResult.Result) {
        if ($rootResult.Result.Summary) { $rootResult.Result.Summary } else { "No major issues detected" }
    } else {
        "No Root Cause Analysis executed"
    }
    $rootDetails = if ($rootResult -and $rootResult.Result -and $rootResult.Result.Details) {
        [PSCustomObject]@{
            Findings           = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.Findings
            DetectedIssues     = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.DetectedIssues
            SeverityCounts     = if ($rootResult.Result.Details.SeverityCounts) {
                $rootResult.Result.Details.SeverityCounts
            }
            else {
                [PSCustomObject]@{
                    Info     = 0
                    Warning  = 0
                    Critical = 0
                }
            }
            Anomalies          = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.Anomalies
            Correlations       = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.Correlations
            ValidationIssues   = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.ValidationIssues
            ScoreBreakdown     = if ($rootResult.Result.Details.ScoreBreakdown) {
                [PSCustomObject]@{
                    Findings   = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.ScoreBreakdown.Findings
                    Categories = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.ScoreBreakdown.Categories
                }
            }
            else {
                $null
            }
            TrendSummary       = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.TrendSummary
            MetricStates       = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.MetricStates
            SustainedIssues    = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.SustainedIssues
            TransientIssues    = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.TransientIssues
            BaselineDeviations = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.BaselineDeviations
            GradualTrends      = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.GradualTrends
            PersistentAnomalies = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.PersistentAnomalies
            TransientAnomalies  = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.TransientAnomalies
            HistoricalAnalysis = if ($rootResult.Result.Details.HistoricalAnalysis) {
                [PSCustomObject]@{
                    CPUTrend     = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.HistoricalAnalysis.CPUTrend
                    MemoryTrend  = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.HistoricalAnalysis.MemoryTrend
                    DiskTrend    = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.HistoricalAnalysis.DiskTrend
                    NetworkTrend = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.HistoricalAnalysis.NetworkTrend
                    MetricStates = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.HistoricalAnalysis.MetricStates
                    TrendWindow  = $rootResult.Result.Details.HistoricalAnalysis.TrendWindow
                }
            }
            else {
                $null
            }
        }
    }
    else {
        $null
    }

    # -------------------------
    # HEALTH SCORE (JSON)
    # -------------------------
    $healthScore = if ($rootResult) {

        $score = $rootResult.Result.HealthScore
        $display = $rootResult.Result.HealthText

        if ($null -eq $score) { $score = 0 }

        if (-not $display) {
            $display = "$score / 100"
        }

        [PSCustomObject]@{
            Numeric = [int]$score
            Display = $display
        }
    } else {
        [PSCustomObject]@{
            Numeric = 0
            Display = "Health score not available"
        }
    }

    # Replace existing assignment
    $engineRuntime = $ModuleResults | Where-Object { $_.Module -eq "Engine Runtime" }

    $executionStats = if ($engineRuntime) {
        [PSCustomObject]@{
            ScriptRuntimeSeconds = $engineRuntime.Result.ScriptRuntimeSeconds
        }
    } else {
        [PSCustomObject]@{
            ScriptRuntimeSeconds = "N/A"
        }
    }

    $automaticRemediation = if ($remediationResult) {
        if ($remediationResult.Result) { $remediationResult.Result } else { "No remediation actions executed" }
    } else { "No remediation module executed" }

    $cpuModuleResult = ($ModuleResults | Where-Object Module -eq "CPU Analysis").Result
    $diskModuleResult = ($ModuleResults | Where-Object Module -eq "Disk Analysis").Result
    $networkModuleResult = ($ModuleResults | Where-Object Module -eq "Network Analysis").Result

    $cpuTopProcesses = if ($cpuModuleResult -and $cpuModuleResult.TopProcesses) { @($cpuModuleResult.TopProcesses) } else { @() }
    $diskUsageData = if ($diskModuleResult -and $diskModuleResult.DiskUsage) { @($diskModuleResult.DiskUsage) } else { @() }
    $diskSmartData = if ($diskModuleResult -and $diskModuleResult.SMARTHealth) { @($diskModuleResult.SMARTHealth) } else { @() }
    $networkConnectivityData = if ($networkModuleResult -and $networkModuleResult.Connectivity) {
        $networkModuleResult.Connectivity
    }
    else {
        [PSCustomObject]@{
            PacketsSent     = 0
            PacketsReceived = 0
            AvgLatencyMS    = 0
            Status          = "Unavailable"
        }
    }
    $networkAdaptersData = if ($networkModuleResult -and $networkModuleResult.Adapters) { @($networkModuleResult.Adapters) } else { @() }

    # -------------------------
    # Build JSON object
    # -------------------------
    $JSONReport = [PSCustomObject]@{
        SystemInfo           = ($ModuleResults | Where-Object Module -eq "System Information").Result
        SystemUptime         = ($ModuleResults | Where-Object Module -eq "System Uptime").Result
        CPU                  = @{
            TopProcesses = @($cpuTopProcesses)
            LoadStatus   = $cpuModuleResult
            PerCoreUsage = $cpuCoreData
        }
        Memory               = @{
            TotalGB     = $totalMem
            FreeGB      = $freeMem
            UsedPercent = $memUsedPercent
        }
        Disk                 = @{
            Usage       = @($diskUsageData)
            SMARTHealth = @($diskSmartData)
            IO          = $diskIOSummaryData
        }
        Network              = @{
            Connectivity = $networkConnectivityData
            Adapters     = @($networkAdaptersData)
        }
        EventLogs            = ($ModuleResults | Where-Object Module -eq "Event Log Analysis").Result.RecentErrors
        StartupPrograms      = ($ModuleResults | Where-Object Module -eq "Startup Analysis").Result.StartupPrograms
        InstalledSoftware    = ($ModuleResults | Where-Object Module -eq "Installed Software").Result
        WindowsUpdate        = ($ModuleResults | Where-Object Module -eq "Windows Update Status").Result
        WindowsPatchHistory  = ($ModuleResults | Where-Object Module -eq "Windows Patch History").Result
        Drivers              = ($ModuleResults | Where-Object Module -eq "Driver Inventory").Result
        RootCauseAnalysis    = $rootCauseAnalysis
        RootCauseDetails     = $rootDetails
        HealthScore          = $healthScore
        AutomaticRemediation = $automaticRemediation
        ExecutionStats       = $executionStats
    }

    # -------------------------
    # Export JSON
    # -------------------------
    $JSONReport | ConvertTo-Json -Depth 6 -Compress:$false | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Host "JSON report created: $OutputPath" -ForegroundColor Green
}
