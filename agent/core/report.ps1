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

function ConvertTo-AutoDoctorHtmlAttributeValue {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).Replace("&", "&amp;").Replace("'", "&#39;").Replace('"', "&quot;").Replace("<", "&lt;").Replace(">", "&gt;")
}

function ConvertTo-AutoDoctorCardHtml {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)]$Body,
        [string]$SectionId = "",
        [string]$Category = "general",
        [string]$Tier = "detail",
        [string]$ContentType = "text",
        [string]$Role = "section",
        [switch]$FullWidth,
        [switch]$Collapsible,
        [switch]$Expanded,
        [string]$SummaryText = ""
    )

    $className = if ($FullWidth) { "card full report-block" } else { "card report-block" }
    $bodyHtml = ConvertTo-AutoDoctorHtmlString -Value $Body
    $attributes = @(
        "data-section-id='$(ConvertTo-AutoDoctorHtmlAttributeValue -Value $SectionId)'"
        "data-category='$(ConvertTo-AutoDoctorHtmlAttributeValue -Value $Category)'"
        "data-tier='$(ConvertTo-AutoDoctorHtmlAttributeValue -Value $Tier)'"
        "data-content-type='$(ConvertTo-AutoDoctorHtmlAttributeValue -Value $ContentType)'"
        "data-role='$(ConvertTo-AutoDoctorHtmlAttributeValue -Value $Role)'"
    ) -join " "

    if ($Collapsible) {
        $openAttr = if ($Expanded) { " open" } else { "" }
        $meta = if ($SummaryText) { "<span class='summary-meta'>$SummaryText</span>" } else { "" }

        return @"
<details class='$className card-collapse' $attributes$openAttr>
<summary><span>$Title</span>$meta<span class='summary-icon'>+</span></summary>
<div class='card-content'>
$bodyHtml
</div>
</details>
"@
    }

    return @"
<div class='$className' $attributes>
<h2>$Title</h2>
$bodyHtml
</div>
"@
}

function Convert-AutoDoctorFindingsToHtml {
    param(
        [array]$Findings,
        [string]$Title,
        [string]$SectionId = "",
        [string]$Category = "rootcause",
        [string]$Tier = "detail",
        [switch]$Collapsible,
        [switch]$Expanded
    )

    if (-not $Findings -or $Findings.Count -eq 0) {
        return ""
    }

    $rows = @($Findings | ConvertTo-Html -Fragment) -join "`n"
    return ConvertTo-AutoDoctorCardHtml -Title $Title -Body $rows -SectionId $SectionId -Category $Category -Tier $Tier -ContentType "table" -FullWidth -Collapsible:$Collapsible -Expanded:$Expanded -SummaryText ("{0} item{1}" -f $Findings.Count, $(if ($Findings.Count -eq 1) { "" } else { "s" }))
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

    return ConvertTo-AutoDoctorCardHtml -Title "Trend Summary" -Body ($scope + "<div class='metric-board'>$rows</div>") -SectionId "trend-summary" -Category "overview" -Tier "summary" -ContentType "metrics"
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

    return ConvertTo-AutoDoctorCardHtml -Title "Current State" -Body "<div class='state-strip'>$items</div>" -SectionId "current-state" -Category "overview" -Tier "summary" -ContentType "metrics" -FullWidth
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

    return ConvertTo-AutoDoctorCardHtml -Title "Why The Score Changed" -Body $body -SectionId "score-explanation" -Category "overview" -Tier "summary" -ContentType "text" -FullWidth
}

function Convert-AutoDoctorSectionToHtml {
    param($Section)

    if ($Section -is [string]) {
        return ConvertTo-AutoDoctorCardHtml -Title "Details" -Body $Section -SectionId "details" -Category "general" -Tier "detail" -ContentType "text" -FullWidth
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
        -SectionId ([string]$Section.SectionId) `
        -Category ([string]$Section.Category) `
        -Tier ([string]$Section.Tier) `
        -ContentType ([string]$Section.ContentType) `
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
body[data-filter-active='true'] .report-block[data-print-visible='false']{display:none}
@media (max-width: 900px){
  .metric-row{grid-template-columns:1fr}
  .metric-trend{justify-content:flex-start}
}
@page{margin:14mm}
@media print{
  body{margin:0;background:#fff;color:#000;font-size:11pt;-webkit-print-color-adjust:exact;print-color-adjust:exact}
  .dashboard{display:block;margin-top:0}
  .report-block{display:block!important}
  .report-block[data-print-visible='false']{display:none!important}
  .card,.card-collapse{margin:0 0 12pt 0;padding:0;border:1px solid #cbd5e1;border-radius:0;box-shadow:none;background:#fff;break-inside:auto;page-break-inside:auto}
  .full{grid-column:auto}
  .card>h2,.card-collapse summary{padding:12pt 14pt;margin:0;border-bottom:1px solid #d0d7de;color:#000}
  .card>h2{font-size:14pt}
  .card-collapse summary{display:block;cursor:default}
  .card-collapse summary::-webkit-details-marker{display:none}
  .summary-icon{display:none}
  .summary-meta{float:right;color:#444}
  .card-collapse .card-content{padding:12pt 14pt 14pt 14pt}
  details.card-collapse:not([open])>.card-content{display:block!important}
  details.card-collapse:not([open])>*:not(summary){display:block!important}
  .metric-board,.state-strip,.scorebar,.chartbar,.cpudonut{display:none!important}
  table{width:100%;margin-top:0;table-layout:auto;font-size:9.5pt}
  thead{display:table-header-group}
  tfoot{display:table-footer-group}
  tr{break-inside:avoid;page-break-inside:avoid}
  th,td{padding:5px 6px;vertical-align:top;word-break:break-word}
  th{background:#efefef!important;color:#000}
  .state-badge{background:#fff!important;color:#000!important;border:1px solid currentColor}
  .state-critical,.health-bad{color:#000!important;font-weight:700;border-left:4px solid #000;padding-left:8px}
  .state-warning,.health-warning{color:#000!important;font-weight:700;border-left:2px solid #666;padding-left:8px}
  .state-stable,.state-improving,.state-baseline,.health-good{color:#000!important}
  .header,.footer{break-inside:avoid;page-break-inside:avoid}
  .header-left img{max-height:48px}
  .footer{margin-top:18pt;padding-top:8pt;border-top:1px solid #d0d7de}
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
<div class='card report-block' data-section-id='system-health' data-category='overview' data-tier='summary' data-content-type='metric' data-role='section' data-print-visible='true'>
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
<div class='card report-block' data-section-id='memory-pressure' data-category='overview' data-tier='summary' data-content-type='metric' data-role='section' data-print-visible='true'>
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
<div class='card report-block' data-section-id='cpu-utilization' data-category='overview' data-tier='summary' data-content-type='metric' data-role='section' data-print-visible='true'>
<h2>CPU Utilization</h2>
<div class='cpudonut' style='--cpu:${cpuPercent}%'>
        ${cpuPercent}%
</div>
</div>
<div class='card report-block' data-section-id='top-cpu-processes' data-category='overview' data-tier='summary' data-content-type='text' data-role='section' data-print-visible='true'>
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
<div class='card full report-block' data-section-id='disk-io-activity' data-category='overview' data-tier='summary' data-content-type='text' data-role='section' data-print-visible='true'>
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
<div class='card report-block' data-section-id='severity-summary' data-category='overview' data-tier='summary' data-content-type='table' data-role='section' data-print-visible='true'>
<h2>Severity Summary</h2>
$severityRows
</div>
"@
        }

        $rootSummaryPanel = ConvertTo-AutoDoctorCardHtml -Title "Root Cause Summary" -Body "<p>$($rootModule.Result.Summary)</p>" -SectionId "root-cause-summary" -Category "overview" -Tier "summary" -ContentType "text" -FullWidth
        $findingsPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.Findings) -Title "Root Cause Findings" -SectionId "root-cause-findings" -Category "rootcause" -Collapsible
        $anomalyPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.Anomalies) -Title "Anomaly Insights" -SectionId "anomaly-insights" -Category "rootcause" -Collapsible
        $correlationPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.Correlations) -Title "Correlation Insights" -SectionId "correlation-insights" -Category "rootcause" -Collapsible
        $trendSummaryPanel = Convert-AutoDoctorTrendSummaryToHtml -MetricStates @($rootDetails.MetricStates) -TrendWindow $rootDetails.HistoricalAnalysis.TrendWindow
        $stateStripPanel = Convert-AutoDoctorStateStripToHtml -MetricStates @($rootDetails.MetricStates)
        $scoreExplanationPanel = Convert-AutoDoctorScoreExplanationToHtml -ScoreBreakdown $rootDetails.ScoreBreakdown -MetricStates @($rootDetails.MetricStates)
        $sustainedPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.SustainedIssues) -Title "Sustained Issues" -SectionId "sustained-issues" -Category "rootcause" -Expanded
        $transientPanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.TransientIssues) -Title "Transient Issues" -SectionId "transient-issues" -Category "rootcause" -Collapsible
        $baselinePanel = Convert-AutoDoctorFindingsToHtml -Findings @($rootDetails.BaselineDeviations) -Title "Baseline Deviations" -SectionId "baseline-deviations" -Category "rootcause" -Expanded
    }

    # -----------------------------
    # JOIN MODULE SECTIONS
    # -----------------------------
    if (-not $Sections) { $Sections = @([PSCustomObject]@{ SectionId = "details"; Title = "Details"; Category = "general"; Tier = "detail"; ContentType = "text"; DataPath = ""; ContentHtml = "<p>No module results available.</p>"; Expanded = $true; Collapsible = $false; FullWidth = $true }) }
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
<div class='header report-block' data-section-id='report-header' data-category='meta' data-tier='meta' data-content-type='meta' data-role='meta' data-print-visible='true'>
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

<div class='footer report-block' data-section-id='report-footer' data-category='meta' data-tier='meta' data-content-type='meta' data-role='meta' data-print-visible='true'>
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

    $toolbarHTML = @"
<div class='report-toolbar-shell'>
    <div class='report-toolbar'>
        <div class='toolbar-copy'>
            <span class='toolbar-eyebrow'>Output Tools</span>
            <strong>Print & Export</strong>
            <span class='toolbar-note'>Choose a preset and optional category, then print the current view or open the generated Markdown export.</span>
        </div>
        <div class='toolbar-controls'>
            <div class='toolbar-group'>
                <span class='toolbar-label'>Preset</span>
                <label class='toolbar-field'>
                    <select id='preset-selector' aria-label='Report preset'>
                        <option value='admin'>Admin</option>
                        <option value='user'>User</option>
                        <option value='compliance'>Compliance</option>
                    </select>
                </label>
            </div>
            <div class='toolbar-group' id='category-field'>
                <span class='toolbar-label'>Category</span>
                <label class='toolbar-field'>
                    <select id='category-selector' aria-label='Report category'>
                        <option value=''>Select category</option>
                    </select>
                </label>
            </div>
        </div>
        <div class='toolbar-actions'>
            <button type='button' class='toolbar-action secondary' data-mode-action='full'>Print Full</button>
            <button type='button' class='toolbar-action secondary' data-mode-action='summary'>Print Summary</button>
            <button type='button' class='toolbar-action secondary' data-mode-action='category'>Print Category</button>
            <button type='button' class='toolbar-action primary' id='export-pdf-button'>Export PDF</button>
            <a class='toolbar-action tertiary' id='export-markdown-link' href='#' target='_blank' rel='noopener'>Export Markdown</a>
        </div>
        <div class='toolbar-status' id='toolbar-status'>Current view: Full | Admin preset</div>
    </div>
</div>
"@

    $behaviorScript = @"
<script>
(function () {
  var state = null;

  function getPresetDefaultMode(preset) {
    switch (preset) {
      case "user":
        return "summary";
      case "compliance":
        return "full";
      default:
        return "full";
    }
  }

  function titleCase(value) {
    return (value || "").replace(/-/g, " ").replace(/\b\w/g, function (match) {
      return match.toUpperCase();
    });
  }

  function getAvailableCategories() {
    var seen = {};
    var categories = [];

    document.querySelectorAll(".report-block[data-role='section']").forEach(function (node) {
      var category = (node.getAttribute("data-category") || "").toLowerCase();
      var tier = (node.getAttribute("data-tier") || "").toLowerCase();

      if (!category || category === "overview" || category === "meta" || tier === "summary") {
        return;
      }

      if (!seen[category]) {
        seen[category] = true;
        categories.push(category);
      }
    });

    return categories.sort();
  }

  function normalizeState(nextState) {
    var categories = getAvailableCategories();
    var preset = (nextState && nextState.preset ? nextState.preset : "admin").toLowerCase();
    var mode = (nextState && nextState.mode ? nextState.mode : getPresetDefaultMode(preset)).toLowerCase();
    var category = (nextState && nextState.category ? nextState.category : "").toLowerCase();

    if (["admin", "user", "compliance"].indexOf(preset) === -1) {
      preset = "admin";
    }

    if (["full", "summary", "category"].indexOf(mode) === -1) {
      mode = getPresetDefaultMode(preset);
    }

    if (mode === "category") {
      if (categories.indexOf(category) === -1) {
        category = categories.length > 0 ? categories[0] : "";
      }
    } else if (categories.indexOf(category) === -1) {
      category = "";
    }

    return {
      preset: preset,
      mode: mode,
      category: category
    };
  }

  function buildStateFromLocation() {
    var params = new URLSearchParams(window.location.search);
    return normalizeState({
      preset: params.get("preset") || "admin",
      mode: params.get("print-mode") || "",
      category: params.get("category") || ""
    });
  }

  function syncUrl(nextState) {
    var url = new URL(window.location.href);
    url.searchParams.set("preset", nextState.preset);
    url.searchParams.set("print-mode", nextState.mode);

    if (nextState.mode === "category" && nextState.category) {
      url.searchParams.set("category", nextState.category);
    } else {
      url.searchParams.delete("category");
    }

    window.history.replaceState({}, "", url.toString());
  }

  function getAssetUrl(extension) {
    var url = new URL(window.location.href);
    url.search = "";
    url.hash = "";
    url.pathname = url.pathname.replace(/\.html?$/i, "." + extension);
    return url.toString();
  }

  function populateCategorySelector() {
    var selector = document.getElementById("category-selector");
    if (!selector) {
      return;
    }

    var categories = getAvailableCategories();
    var selectedValue = state ? state.category : "";

    selector.innerHTML = "";

    if (categories.length === 0) {
      var emptyOption = document.createElement("option");
      emptyOption.value = "";
      emptyOption.textContent = "No categories";
      selector.appendChild(emptyOption);
      selector.disabled = true;
      return;
    }

    var placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = "Select category";
    selector.appendChild(placeholder);

    categories.forEach(function (category) {
      var option = document.createElement("option");
      option.value = category;
      option.textContent = titleCase(category);
      selector.appendChild(option);
    });

    selector.disabled = false;
    selector.value = selectedValue && categories.indexOf(selectedValue) !== -1 ? selectedValue : "";
  }

  function updateToolbar() {
    var presetSelector = document.getElementById("preset-selector");
    var categorySelector = document.getElementById("category-selector");
    var categoryField = document.getElementById("category-field");
    var status = document.getElementById("toolbar-status");
    var markdownLink = document.getElementById("export-markdown-link");

    if (presetSelector) {
      presetSelector.value = state.preset;
    }

    populateCategorySelector();

    if (categorySelector) {
      categorySelector.disabled = state.mode !== "category" || categorySelector.options.length <= 1;
      if (state.mode === "category" && state.category) {
        categorySelector.value = state.category;
      }
    }

    if (categoryField) {
      categoryField.classList.toggle("is-disabled", state.mode !== "category");
    }

    document.querySelectorAll("[data-mode-action]").forEach(function (button) {
      var buttonMode = button.getAttribute("data-mode-action");
      button.setAttribute("aria-pressed", buttonMode === state.mode ? "true" : "false");
      button.classList.toggle("is-active", buttonMode === state.mode);
    });

    if (status) {
      var statusText = "Current view: " + titleCase(state.mode) + " | " + titleCase(state.preset) + " preset";
      if (state.mode === "category" && state.category) {
        statusText += " | " + titleCase(state.category);
      }
      status.textContent = statusText;
    }

    if (markdownLink) {
      markdownLink.href = getAssetUrl("md");
    }
  }

  function readToolbarState() {
    var presetSelector = document.getElementById("preset-selector");
    var categorySelector = document.getElementById("category-selector");

    return normalizeState({
      preset: presetSelector ? presetSelector.value : "admin",
      mode: state ? state.mode : "full",
      category: categorySelector ? categorySelector.value : ""
    });
  }

  function applyFilters(nextState) {
    var body = document.body;
    if (!body) {
      return;
    }

    state = normalizeState(nextState || buildStateFromLocation());
    syncUrl(state);

    body.setAttribute("data-export-preset", state.preset);
    body.setAttribute("data-print-mode", state.mode);
    body.setAttribute("data-print-category", state.category);
    body.setAttribute("data-filter-active", "true");

    document.querySelectorAll(".report-block").forEach(function (node) {
      var tier = (node.getAttribute("data-tier") || "detail").toLowerCase();
      var nodeCategory = (node.getAttribute("data-category") || "").toLowerCase();
      var role = (node.getAttribute("data-role") || "section").toLowerCase();
      var visible = true;

      if (state.mode === "summary") {
        visible = tier === "summary" || role === "meta";
      } else if (state.mode === "category") {
        visible = role === "meta" || tier === "summary" || (state.category !== "" && nodeCategory === state.category);
      }

      node.setAttribute("data-print-visible", visible ? "true" : "false");
    });

    updateToolbar();
  }

  function printMode(mode) {
    var nextState = readToolbarState();
    nextState.mode = mode;
    applyFilters(nextState);
    window.print();
  }

  function bindToolbar() {
    var presetSelector = document.getElementById("preset-selector");
    var categorySelector = document.getElementById("category-selector");
    var exportPdfButton = document.getElementById("export-pdf-button");

    if (presetSelector) {
      presetSelector.addEventListener("change", function () {
        var nextState = readToolbarState();
        nextState.preset = presetSelector.value;
        applyFilters(nextState);
      });
    }

    if (categorySelector) {
      categorySelector.addEventListener("change", function () {
        var nextState = readToolbarState();
        nextState.category = categorySelector.value;
        if (nextState.category) {
          nextState.mode = "category";
        }
        applyFilters(nextState);
      });
    }

    document.querySelectorAll("[data-mode-action]").forEach(function (button) {
      button.addEventListener("click", function () {
        printMode(button.getAttribute("data-mode-action"));
      });
    });

    if (exportPdfButton) {
      exportPdfButton.addEventListener("click", function () {
        applyFilters(readToolbarState());
        window.print();
      });
    }
  }

  var expandedBeforePrint = [];

  function expandDetailsForPrint() {
    expandedBeforePrint = [];
    document.querySelectorAll("details.card-collapse").forEach(function (node) {
      expandedBeforePrint.push({ node: node, open: node.hasAttribute("open") });
      node.setAttribute("open", "open");
    });
  }

  function restoreDetailsAfterPrint() {
    expandedBeforePrint.forEach(function (entry) {
      if (!entry.open) {
        entry.node.removeAttribute("open");
      }
    });
    expandedBeforePrint = [];
  }

  window.addEventListener("beforeprint", expandDetailsForPrint);
  window.addEventListener("afterprint", restoreDetailsAfterPrint);
  window.addEventListener("DOMContentLoaded", function () {
    bindToolbar();
    applyFilters(buildStateFromLocation());
  });
})();
</script>
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

.report-toolbar-shell{
margin:0 0 24px 0;
}

.report-toolbar{
display:grid;
grid-template-columns:1.3fr 1fr 1.2fr;
gap:18px;
align-items:end;
padding:18px 20px;
background:linear-gradient(135deg,#ffffff 0%,#eef4fb 100%);
border:1px solid #d7e2ee;
border-radius:14px;
box-shadow:0 10px 24px rgba(31,78,121,0.08);
}

.toolbar-copy{
display:flex;
flex-direction:column;
gap:4px;
}

.toolbar-eyebrow{
font-size:11px;
font-weight:700;
letter-spacing:0.08em;
text-transform:uppercase;
color:#5f7b99;
}

.toolbar-copy strong{
font-size:18px;
color:#163b5c;
}

.toolbar-note{
font-size:13px;
color:#526375;
line-height:1.45;
max-width:42ch;
}

.toolbar-controls{
display:flex;
gap:14px;
align-items:end;
flex-wrap:wrap;
}

.toolbar-group{
display:flex;
flex-direction:column;
gap:6px;
min-width:150px;
}

.toolbar-group.is-disabled{
opacity:0.65;
}

.toolbar-label{
font-size:12px;
font-weight:700;
color:#43576d;
text-transform:uppercase;
letter-spacing:0.04em;
}

.toolbar-field{
display:block;
}

.toolbar-field select{
width:100%;
padding:10px 12px;
border:1px solid #c8d6e5;
border-radius:10px;
background:#fff;
color:#1f2d3d;
font-size:14px;
}

.toolbar-field select:disabled{
background:#f4f7fa;
color:#7a8794;
cursor:not-allowed;
}

.toolbar-actions{
display:flex;
gap:10px;
justify-content:flex-end;
align-items:center;
flex-wrap:wrap;
}

.toolbar-action{
display:inline-flex;
align-items:center;
justify-content:center;
min-height:40px;
padding:0 14px;
border-radius:10px;
border:1px solid #c6d3e0;
background:#fff;
color:#20476b;
font-size:14px;
font-weight:600;
text-decoration:none;
cursor:pointer;
transition:transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease, background 0.15s ease;
}

.toolbar-action:hover{
transform:translateY(-1px);
box-shadow:0 8px 18px rgba(31,78,121,0.10);
}

.toolbar-action.primary{
background:#1f4e79;
border-color:#1f4e79;
color:#fff;
}

.toolbar-action.secondary{
background:#fff;
}

.toolbar-action.tertiary{
background:#f7fafc;
}

.toolbar-action.is-active,
.toolbar-action[aria-pressed='true']{
border-color:#1f4e79;
background:#eaf2fb;
}

.toolbar-status{
grid-column:1 / -1;
font-size:13px;
color:#516578;
padding-top:2px;
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

@media (max-width: 1100px){
.report-toolbar{
grid-template-columns:1fr;
align-items:start;
}

.toolbar-actions{
justify-content:flex-start;
}
}

@media (max-width: 720px){
.toolbar-actions,
.toolbar-controls{
flex-direction:column;
align-items:stretch;
}

.toolbar-group{
min-width:0;
}

.toolbar-action{
width:100%;
}
}

@media print{
.report-toolbar-shell,
.report-toolbar{
display:none !important;
}
}

</style>

$behaviorScript

</head>

<body>

$logoHTML

$toolbarHTML

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
        [array]$Sections = @(),
        [string]$OutputPath
    )

    $report = Get-AutoDoctorStructuredReport -ModuleResults $ModuleResults -Sections $Sections
    $report | ConvertTo-Json -Depth 6 -Compress:$false | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Host "JSON report created: $OutputPath" -ForegroundColor Green
}

function Get-AutoDoctorObjectValueByPath {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $value = $Object
    foreach ($segment in $Path -split "\.") {
        if ($null -eq $value) {
            return $null
        }

        if ($value -is [System.Collections.IDictionary]) {
            if ($value.Contains($segment)) {
                $value = $value[$segment]
                continue
            }

            return $null
        }

        $property = $value.PSObject.Properties[$segment]
        if ($property) {
            $value = $property.Value
            continue
        }

        return $null
    }

    return $value
}

function Get-AutoDoctorReportMetadata {
    $generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    return [PSCustomObject]@{
        Title       = "Windows AutoDoctor Dashboard"
        RunId       = $Global:AutoDoctorRunID
        HostName    = $env:COMPUTERNAME
        GeneratedAt = $generatedAt
    }
}

function Get-AutoDoctorStructuredReport {
    param(
        [array]$ModuleResults,
        [array]$Sections = @()
    )

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

    $rootResult = $ModuleResults | Where-Object { $_.Module -eq "Root Cause Analysis" }
    $remediationResult = $ModuleResults | Where-Object { $_.Module -eq "Self-Healing Remediation" }

    $rootCauseAnalysis = if ($rootResult -and $rootResult.Result) {
        if ($rootResult.Result.Summary) { $rootResult.Result.Summary } else { "No major issues detected" }
    }
    else {
        "No Root Cause Analysis executed"
    }

    $rootDetails = if ($rootResult -and $rootResult.Result -and $rootResult.Result.Details) {
        [PSCustomObject]@{
            Findings            = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.Findings
            DetectedIssues      = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.DetectedIssues
            SeverityCounts      = if ($rootResult.Result.Details.SeverityCounts) {
                $rootResult.Result.Details.SeverityCounts
            }
            else {
                [PSCustomObject]@{
                    Info     = 0
                    Warning  = 0
                    Critical = 0
                }
            }
            Anomalies           = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.Anomalies
            Correlations        = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.Correlations
            ValidationIssues    = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.ValidationIssues
            ScoreBreakdown      = if ($rootResult.Result.Details.ScoreBreakdown) {
                [PSCustomObject]@{
                    Findings   = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.ScoreBreakdown.Findings
                    Categories = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.ScoreBreakdown.Categories
                }
            }
            else {
                $null
            }
            TrendSummary        = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.TrendSummary
            MetricStates        = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.MetricStates
            SustainedIssues     = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.SustainedIssues
            TransientIssues     = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.TransientIssues
            BaselineDeviations  = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.BaselineDeviations
            GradualTrends       = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.GradualTrends
            PersistentAnomalies = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.PersistentAnomalies
            TransientAnomalies  = Get-AutoDoctorDetailCollection -Value $rootResult.Result.Details.TransientAnomalies
            HistoricalAnalysis  = if ($rootResult.Result.Details.HistoricalAnalysis) {
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

    $healthScore = if ($rootResult) {
        $score = $rootResult.Result.HealthScore
        $display = $rootResult.Result.HealthText

        if ($null -eq $score) { $score = 0 }
        if (-not $display) { $display = "$score / 100" }

        [PSCustomObject]@{
            Numeric = [int]$score
            Display = $display
        }
    }
    else {
        [PSCustomObject]@{
            Numeric = 0
            Display = "Health score not available"
        }
    }

    $engineRuntime = $ModuleResults | Where-Object { $_.Module -eq "Engine Runtime" }
    $executionStats = if ($engineRuntime) {
        [PSCustomObject]@{
            ScriptRuntimeSeconds = $engineRuntime.Result.ScriptRuntimeSeconds
        }
    }
    else {
        [PSCustomObject]@{
            ScriptRuntimeSeconds = "N/A"
        }
    }

    $automaticRemediation = if ($remediationResult) {
        if ($remediationResult.Result) { $remediationResult.Result } else { "No remediation actions executed" }
    }
    else {
        "No remediation module executed"
    }

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

    $sectionCatalog = @($Sections | ForEach-Object {
            [PSCustomObject]@{
                SectionId   = $_.SectionId
                Title       = $_.Title
                Category    = $_.Category
                Tier        = $_.Tier
                ContentType = $_.ContentType
                DataPath    = $_.DataPath
            }
        })

    return [PSCustomObject]@{
        Metadata             = Get-AutoDoctorReportMetadata
        SectionCatalog       = $sectionCatalog
        SystemInfo           = ($ModuleResults | Where-Object Module -eq "System Information").Result
        SystemUptime         = ($ModuleResults | Where-Object Module -eq "System Uptime").Result
        CPU                  = [PSCustomObject]@{
            TopProcesses = @($cpuTopProcesses)
            LoadStatus   = $cpuModuleResult
            PerCoreUsage = $cpuCoreData
        }
        Memory               = [PSCustomObject]@{
            TotalGB     = $totalMem
            FreeGB      = $freeMem
            UsedPercent = $memUsedPercent
        }
        Disk                 = [PSCustomObject]@{
            Usage       = @($diskUsageData)
            SMARTHealth = @($diskSmartData)
            IO          = $diskIOSummaryData
        }
        Network              = [PSCustomObject]@{
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
}

function ConvertTo-AutoDoctorMarkdownEscapedText {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).Replace("|", "\|").Replace("`r", "").Replace("`n", "<br>")
}

function ConvertTo-AutoDoctorMarkdownTable {
    param([array]$Rows)

    $rowList = @($Rows | Where-Object { $null -ne $_ })
    if ($rowList.Count -eq 0) {
        return @("No data available")
    }

    $columns = @($rowList[0].PSObject.Properties.Name)
    if ($columns.Count -eq 0) {
        return @("No data available")
    }

    $lines = @()
    $lines += "| " + (($columns | ForEach-Object { ConvertTo-AutoDoctorMarkdownEscapedText -Value $_ }) -join " | ") + " |"
    $lines += "| " + (($columns | ForEach-Object { "---" }) -join " | ") + " |"

    foreach ($row in $rowList) {
        $values = @($columns | ForEach-Object {
                $property = $row.PSObject.Properties[$_]
                ConvertTo-AutoDoctorMarkdownEscapedText -Value $(if ($property) { $property.Value } else { "" })
            })
        $lines += "| " + ($values -join " | ") + " |"
    }

    return $lines
}

function ConvertTo-AutoDoctorMarkdownBlock {
    param($Value)

    if ($null -eq $Value) {
        return @("No data available")
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @("No data available")
        }

        return @([string]$Value)
    }

    if ($Value -is [System.Array]) {
        $items = @($Value)
        if ($items.Count -eq 0) {
            return @("No data available")
        }

        if ($items[0] -is [psobject] -and $items[0].PSObject.Properties.Count -gt 0) {
            return ConvertTo-AutoDoctorMarkdownTable -Rows $items
        }

        return @($items | ForEach-Object { "- $(ConvertTo-AutoDoctorMarkdownEscapedText -Value $_)" })
    }

    if ($Value -is [psobject]) {
        $propertyNames = @($Value.PSObject.Properties.Name)
        if ($propertyNames.Count -eq 0) {
            return @("No data available")
        }

        $rows = @($propertyNames | ForEach-Object {
                [PSCustomObject]@{
                    Field = $_
                    Value = $Value.$_
                }
            })
        return ConvertTo-AutoDoctorMarkdownTable -Rows $rows
    }

    return @((ConvertTo-AutoDoctorMarkdownEscapedText -Value $Value))
}

function New-AutoDoctorMarkdownReport {
    param(
        [array]$ModuleResults,
        [array]$Sections = @(),
        [string]$OutputPath
    )

    $report = Get-AutoDoctorStructuredReport -ModuleResults $ModuleResults -Sections $Sections
    $lines = @(
        "# $($report.Metadata.Title)"
        ""
        "- Run ID: $($report.Metadata.RunId)"
        "- Host: $($report.Metadata.HostName)"
        "- Generated: $($report.Metadata.GeneratedAt)"
        "- Health Score: $($report.HealthScore.Display)"
        ""
        "## Root Cause Summary"
        ""
        "$($report.RootCauseAnalysis)"
        ""
    )

    $rootCauseMarkdownSections = @(
        [PSCustomObject]@{ Title = "Severity Summary"; DataPath = "RootCauseDetails.SeverityCounts" }
        [PSCustomObject]@{ Title = "Root Cause Findings"; DataPath = "RootCauseDetails.Findings" }
        [PSCustomObject]@{ Title = "Anomaly Insights"; DataPath = "RootCauseDetails.Anomalies" }
        [PSCustomObject]@{ Title = "Correlation Insights"; DataPath = "RootCauseDetails.Correlations" }
        [PSCustomObject]@{ Title = "Sustained Issues"; DataPath = "RootCauseDetails.SustainedIssues" }
        [PSCustomObject]@{ Title = "Transient Issues"; DataPath = "RootCauseDetails.TransientIssues" }
        [PSCustomObject]@{ Title = "Baseline Deviations"; DataPath = "RootCauseDetails.BaselineDeviations" }
    )

    foreach ($section in @($report.SectionCatalog) + $rootCauseMarkdownSections) {
        $value = Get-AutoDoctorObjectValueByPath -Object $report -Path $section.DataPath
        $lines += "## $($section.Title)"
        $lines += ""
        $lines += ConvertTo-AutoDoctorMarkdownBlock -Value $value
        $lines += ""
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($OutputPath, $lines, $utf8NoBom)
    Write-Host "Markdown report created: $OutputPath" -ForegroundColor Green
}

function Resolve-AutoDoctorChromiumPath {
    param([string]$PreferredPath = "")

    $candidateList = @(
        $PreferredPath
        $env:AUTO_DOCTOR_CHROMIUM_PATH
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe")
        (Join-Path $env:LocalAppData "Google\Chrome\Application\chrome.exe")
        (Join-Path $env:ProgramFiles "Chromium\Application\chrome.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Chromium\Application\chrome.exe")
        (Join-Path $env:LocalAppData "Chromium\Application\chrome.exe")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique

    foreach ($candidate in $candidateList) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    foreach ($commandName in @("chrome.exe", "chrome", "chromium.exe", "chromium")) {
        try {
            $resolved = (Get-Command $commandName -ErrorAction Stop).Source
            if ($resolved) {
                return $resolved
            }
        }
        catch {
        }
    }

    return $null
}

function ConvertTo-AutoDoctorFileUri {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [hashtable]$Query = @{}
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $baseUri = ([System.Uri]$resolvedPath).AbsoluteUri

    $queryPairs = @()
    foreach ($entry in $Query.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            continue
        }

        $queryPairs += ("{0}={1}" -f [System.Uri]::EscapeDataString([string]$entry.Key), [System.Uri]::EscapeDataString([string]$entry.Value))
    }

    if ($queryPairs.Count -eq 0) {
        return $baseUri
    }

    return ("{0}?{1}" -f $baseUri, ($queryPairs -join "&"))
}

function Export-AutoDoctorPdfReport {
    param(
        [Parameter(Mandatory = $true)][string]$HtmlPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [ValidateSet("full", "summary", "category")][string]$PrintMode = "full",
        [ValidateSet("admin", "user", "compliance")][string]$Preset = "admin",
        [string]$Category = "",
        [string]$ChromiumPath = ""
    )

    if (-not (Test-Path -LiteralPath $HtmlPath)) {
        Write-Warning "PDF export skipped because the HTML report does not exist: $HtmlPath"
        return $false
    }

    $browserPath = Resolve-AutoDoctorChromiumPath -PreferredPath $ChromiumPath
    if (-not $browserPath) {
        $installCommand = "winget install -e --id Google.Chrome"
        Write-Warning "Headless Chromium export is unavailable because Google Chrome was not found. Install it with: $installCommand"
        return $false
    }

    $targetUri = ConvertTo-AutoDoctorFileUri -Path $HtmlPath -Query @{
        "preset"     = $Preset
        "print-mode" = $PrintMode
        "category"   = $Category
    }

    $userDataDir = Join-Path ([System.IO.Path]::GetTempPath()) "autodoctor-chromium-profile"
    if (-not (Test-Path -LiteralPath $userDataDir)) {
        New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
    }

    $commonArgs = @(
        "--disable-gpu"
        "--allow-file-access-from-files"
        "--no-first-run"
        "--no-sandbox"
        "--disable-breakpad"
        "--disable-crash-reporter"
        "--user-data-dir=$userDataDir"
        "--run-all-compositor-stages-before-draw"
        "--virtual-time-budget=3000"
        "--print-to-pdf=$OutputPath"
        $targetUri
    )

    try {
        & $browserPath "--headless=new" @commonArgs | Out-Null
    }
    catch {
        & $browserPath "--headless" @commonArgs | Out-Null
    }

    if (Test-Path -LiteralPath $OutputPath) {
        Write-Host "PDF report created: $OutputPath" -ForegroundColor Green
        return $true
    }

    Write-Warning "Chromium completed without creating the PDF report: $OutputPath"
    return $false
}
