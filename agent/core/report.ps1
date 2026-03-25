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
                }
                else {
                    return $null
                }
            }
            return $value
        }
        catch { return $null }
    }

    return $mod.Result
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
</style>
"@

    # -----------------------------
    # HEALTH SCORE PANEL
    # -----------------------------
    $rootModule = $ModuleResults | Where-Object Module -eq "Root Cause Analysis"
    $score = if ($rootModule) { $rootModule.Result.HealthScore } else { 0 }
    $displayText = if ($rootModule) { $rootModule.Result.HealthText } else { "$score / 100" }

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
        $totalMem = $memoryModule.Result.TotalMemoryGB
        $freeMem = $memoryModule.Result.FreeMemoryGB
        $memUsedPercent = [math]::Round((($totalMem - $freeMem) / $totalMem) * 100, 1)
        $memChart = @"
<div class='card'>
<h2>Memory Pressure</h2>
<p>Used: $memUsedPercent %</p>
<div class='chartbar'>
<div class='chartfill' style='width:${memUsedPercent}%'></div>
</div>
</div>
"@
    }
    else { $memChart = "" }

    # -----------------------------
    # CPU PANEL
    # -----------------------------
    $cpuModule = $ModuleResults | Where-Object { $_.Module -eq "CPU Analysis" }

    if ($cpuModule) {

        $cpuPercent = $cpuModule.Result.CurrentCPULoadPercent

        $cpuChartData = ""
        if ($cpuModule.Result.TopProcesses) {
            $cpuChartData = ($cpuModule.Result.TopProcesses | ForEach-Object {
                    "<p>$($_.ProcessName): $([math]::Round($_.CPU,2))</p>"
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

    }
    else { $cpuChart = "" }

    # -----------------------------
    # DISK PANEL
    # -----------------------------
    $diskModule = $ModuleResults | Where-Object { $_.Module -eq "Disk Analysis" }
    if ($diskModule) {
        $diskChartData = @()
        if ($diskModule.Result.DiskIOSummary) {
            $diskChartData += ($diskModule.Result.DiskIOSummary | ForEach-Object {
                    "<p>$($_.Disk): $($_.PercentBusy)% busy</p>"
                }) -join "`n"
        }
        $diskChart = @"
<div class='card full'>
<h2>Disk IO Activity</h2>
$diskChartData
</div>
"@
    }
    else { $diskChart = "" }

    # -----------------------------
    # JOIN MODULE SECTIONS
    # -----------------------------
    if (-not $Sections) { $Sections = @("<p>No module results available.</p>") }
    $body = ($Sections | ForEach-Object { "<div class='card full'>$_</div>" }) -join "`n"

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
$memChart
$cpuChart
$diskChart
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
    $totalMem = if ($memoryModule) { $memoryModule.Result.TotalMemoryGB } else { 0 }
    $freeMem = if ($memoryModule) { $memoryModule.Result.FreeMemoryGB } else { 0 }
    $memUsedPercent = if ($totalMem -and $freeMem) { [math]::Round((($totalMem - $freeMem) / $totalMem) * 100, 1) } else { 0 }

    # -------------------------
    # CPU per-core (with fallback)
    # -------------------------
    $cpuCoreData = @()

    try {
        $cpuCounters = Get-Counter "\Processor(*)\% Processor Time" -ErrorAction Stop

        if ($cpuCounters) {
            $cpuCoreData = $cpuCounters.CounterSamples |
                Where-Object { $_.InstanceName -ne "_Total" } |
                ForEach-Object {
                    [PSCustomObject]@{
                        Core        = $_.InstanceName
                        PercentUsed = [math]::Round($_.CookedValue, 1)
                    }
                }
        }
    }
    catch {
        Write-Warning "CPU per-core PerfCounter failed, fallback to WMI"

        try {
            $cpuPerf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor

            if ($cpuPerf) {
                $cpuCoreData = $cpuPerf |
                    Where-Object { $_.Name -ne "_Total" } |
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

    try {
        $diskIO = Get-Counter "\PhysicalDisk(*)\% Disk Time" -ErrorAction Stop

        if ($diskIO) {
            $diskIOSummaryData = $diskIO.CounterSamples | ForEach-Object {
                [PSCustomObject]@{
                    Disk        = $_.InstanceName
                    PercentBusy = [math]::Round($_.CookedValue, 2)
                }
            }
        }
    }
    catch {
        Write-Warning "Disk PerfCounter failed, fallback to WMI"

        try {
            $diskPerf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk

            if ($diskPerf) {
                $diskIOSummaryData = $diskPerf | Where-Object { $_.Name -ne "_Total" } | ForEach-Object {
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
    }
    else {
        "No Root Cause Analysis executed"
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
    }
    else {
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
    }
    else {
        [PSCustomObject]@{
            ScriptRuntimeSeconds = "N/A"
        }
    }

    $automaticRemediation = if ($remediationResult) {
        if ($remediationResult.Result) { $remediationResult.Result } else { "No remediation actions executed" }
    }
    else { "No remediation module executed" }

    # -------------------------
    # Build JSON object
    # -------------------------
    $JSONReport = [PSCustomObject]@{
        SystemInfo           = ($ModuleResults | Where-Object Module -eq "System Information").Result
        SystemUptime         = ($ModuleResults | Where-Object Module -eq "System Uptime").Result
        CPU                  = @{
            TopProcesses = ($ModuleResults | Where-Object Module -eq "CPU Analysis").Result.TopProcesses
            LoadStatus   = ($ModuleResults | Where-Object Module -eq "CPU Analysis").Result
            PerCoreUsage = $cpuCoreData
        }
        Memory               = @{
            TotalGB     = $totalMem
            FreeGB      = $freeMem
            UsedPercent = $memUsedPercent
        }
        Disk                 = @{
            Usage       = ($ModuleResults | Where-Object Module -eq "Disk Analysis").Result.DiskUsage
            SMARTHealth = ($ModuleResults | Where-Object Module -eq "Disk Analysis").Result.SMARTHealth
            IO          = $diskIOSummaryData
        }
        Network              = @{
            Connectivity = ($ModuleResults | Where-Object Module -eq "Network Analysis").Result.Connectivity
            Adapters     = ($ModuleResults | Where-Object Module -eq "Network Analysis").Result.Adapters
        }
        EventLogs            = ($ModuleResults | Where-Object Module -eq "Event Log Analysis").Result.RecentErrors
        StartupPrograms      = ($ModuleResults | Where-Object Module -eq "Startup Analysis").Result.StartupPrograms
        InstalledSoftware    = ($ModuleResults | Where-Object Module -eq "Installed Software").Result
        WindowsUpdate        = ($ModuleResults | Where-Object Module -eq "Windows Update Status").Result
        Drivers              = ($ModuleResults | Where-Object Module -eq "Driver Inventory").Result
        RootCauseAnalysis    = $rootCauseAnalysis
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
