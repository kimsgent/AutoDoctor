<#
===============================================================================
WINDOWS AUTO-DOCTOR SCRIPT
Enterprise Diagnostic, Root-Cause Analysis & Support Bundle Generator
===============================================================================

DESCRIPTION
Advanced IT troubleshooting automation that diagnoses common Windows problems,
prioritizes fixes, performs safe remediation, and generates a portable
support bundle useful for remote support and helpdesk escalation.

FEATURES
• Root cause analysis for slow systems
• DISM + SFC system repair
• Windows Update repair
• Network diagnostics
• Event log analysis
• CPU / RAM / Disk bottleneck detection
• Startup impact analysis
• Temporary file cleanup
• Malware scan via Microsoft Defender
• System health scoring
• Automatic remediation
• Portable support bundle generation
• HTML dashboard report

OUTPUT DIRECTORY
C:\Temp\AutoDoctor_Report\
C:\ProgramData\AutoDoctor\

FILES GENERATED
AutoDoctor_Report.html
AutoDoctor_Report.json
AutoDoctor_error.log
Telemetry.json
Autodoctor.db

HOW TO RUN

1. Save as:
   AutoDoctor.ps1

2. Open PowerShell as Administrator

3. Allow temporary execution:
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

4. Run script:
   .\AutoDoctor.ps1
===============================================================================
#>



# -----------------------------------------------------------------------------
# AUTO ADMIN ELEVATION
# -----------------------------------------------------------------------------

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {

    Start-Process powershell `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs

    exit
}

# ------------------------------------------------
# LOAD CONFIGURATION
# ------------------------------------------------

. "$PSScriptRoot\core\config.ps1"

Initialize-AutoDoctorPaths

if (-not $Global:AutoDoctorLogFile) {
    throw "AutoDoctorLogFile path not initialized"
}

. "$PSScriptRoot\core\localization.ps1"
Initialize-AutoDoctorLocalization | Out-Null

. "$PSScriptRoot\core\update.ps1"
$Global:AutoDoctorUpdateInfo = Get-AutoDoctorUpdateInfo

if ($Global:AutoDoctorUpdateInfo -and $Global:AutoDoctorUpdateInfo.UpdateAvailable -and $Global:AutoDoctorUpdateInfo.LatestVersion) {
    Write-Host ("Update available: v{0} (current: v{1})" -f $Global:AutoDoctorUpdateInfo.LatestVersion, $Global:AutoDoctorUpdateInfo.CurrentVersion) -ForegroundColor Red
}

# -----------------------------------------------------------------------------
# DATABASE INITIALIZATION
# -----------------------------------------------------------------------------

. "$PSScriptRoot\core\db.ps1"
. "$PSScriptRoot\core\db.write.ps1"

Initialize-AutoDoctorDatabase

# -----------------------------------------------------------------------------
# GLOBAL SETTINGS
# -----------------------------------------------------------------------------

Clear-Host
Write-Host "=== Windows AutoDoctor Starting ===" -ForegroundColor Green
Write-Host "Script Path: $PSCommandPath"

$ErrorActionPreference = "Stop"

trap {
    # Always log the error
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] General error: $($_.Exception.Message)" |
    Out-File $Global:AutoDoctorLogFile -Append

    # Specific check for DateTime issues
    if ($_.Exception.Message -like "*DateTime*") {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] DateTime error: $($_.Exception.Message)" |
        Out-File $Global:AutoDoctorLogFile -Append
    }

    continue
}

function Invoke-Safe {
    param([scriptblock]$Script)

    try {
        & $Script
    }
    catch {
        Write-Warning $_.Exception.Message
        return $null
    }
}

function ConvertTo-AutoDoctorSectionId {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "section"
    }

    $normalized = $Value.ToLowerInvariant()
    $normalized = [regex]::Replace($normalized, "[^a-z0-9]+", "-")
    $normalized = $normalized.Trim("-")

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return "section"
    }

    return $normalized
}

function Add-Section {

    param(
        [string]$Title,
        $Content,
        [string]$SectionId,
        [string]$Category = "general",
        [string]$Tier = "detail",
        [string]$DataPath,
        [switch]$Expanded,
        [switch]$Collapsible
    )

    $contentHtml = ""
    $contentType = "text"
    $resolvedSectionId = if ($SectionId) { $SectionId } else { ConvertTo-AutoDoctorSectionId -Value $Title }

    if ($null -eq $Content) {
        $contentHtml = "<p>No data available</p>"
        return [PSCustomObject]@{
            SectionId   = $resolvedSectionId
            Title       = $Title
            Category    = $Category
            Tier        = $Tier
            ContentType = $contentType
            DataPath    = $DataPath
            ContentHtml = $contentHtml
            Expanded    = [bool]$Expanded
            Collapsible = [bool]$Collapsible
            FullWidth   = $true
        }
    }

    # Handle arrays
    if ($Content -is [array]) {

        # Array of objects -> render table
        if ($Content[0] -is [psobject] -and $Content[0].PSObject.Properties.Count -gt 0) {
            $contentHtml = @($Content | ConvertTo-Html -Fragment) -join "`n"
            $contentType = "table"
        }
        else {
            # Array of strings -> bullet list
            $contentType = "list"
            $contentHtml += "<ul>"
            foreach ($item in $Content) {
                $contentHtml += "<li>$item</li>"
            }
            $contentHtml += "</ul>"
        }
    }
    elseif ($Content -is [psobject]) {
        # Handle objects -> render table
        $contentHtml = @($Content | ConvertTo-Html -Fragment) -join "`n"
        $contentType = "table"
    }
    else {
        # Default -> simple paragraph
        $contentHtml = "<p>$Content</p>"
    }

    return [PSCustomObject]@{
        SectionId   = $resolvedSectionId
        Title       = $Title
        Category    = $Category
        Tier        = $Tier
        ContentType = $contentType
        DataPath    = $DataPath
        ContentHtml = $contentHtml
        Expanded    = [bool]$Expanded
        Collapsible = [bool]$Collapsible
        FullWidth   = $true
    }
}

$Sections = @()

# -----------------------------------------------------------------------------
# REPORT PATHS (from centralized config)
# -----------------------------------------------------------------------------

$ReportDir = Get-AutoDoctorPath "Reports"
$HTMLReport = $Global:AutoDoctorReportHTML
$JSONReport = $Global:AutoDoctorReportJSON

# Load report
. "$PSScriptRoot\core\report.ps1"

# Load core engine
. "$PSScriptRoot\core\engine.ps1"

# Load modules
$moduleLoadOrder = @(
    "systeminfo.ps1",
    "uptime.ps1",
    "memory.ps1",
    "cpu.ps1",
    "disk.ps1",
    "network.ps1",
    "events.ps1",
    "startup.ps1",
    "software.ps1",
    "drivers.ps1",
    "windowsupdate.ps1",
    "windowspatches.ps1",
    "validation.ps1",
    "history.ps1",
    "anomaly.ps1",
    "correlation.ps1",
    "rootcause.ps1",
    "remediation.ps1"
)

Get-ChildItem "$PSScriptRoot\modules\*.ps1" |
Sort-Object {
    $index = $moduleLoadOrder.IndexOf($_.Name)
    if ($index -ge 0) { $index } else { [int]::MaxValue }
}, Name | ForEach-Object {
    try {
        . $_.FullName
    }
    catch {
        Write-Warning "Failed to load module $($_.Name)"
    }
}

# -----------------------------
# SCRIPT START TIME
# -----------------------------
$ScriptStart = Get-Date

# ------------------------------------------------
# Generate RunID for this execution
# ------------------------------------------------

$Global:AutoDoctorRunID = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $env:COMPUTERNAME

Write-Host "AutoDoctor RunID: $Global:AutoDoctorRunID"


# -----------------------------
# Execute modules
# -----------------------------
$moduleResults = Invoke-AutoDoctorModules -ScriptStart $ScriptStart
$global:ModuleResults = @($moduleResults | ForEach-Object { $_ })

# -----------------------------
# GENERATE SECTIONS FROM MODULES
# -----------------------------
$Sections = @()

foreach ($mod in $moduleResults) {

    switch ($mod.Module) {


        # -----------------------------
        "Memory Analysis" {
            $Sections += Add-Section "Memory Status" $mod.Result -SectionId "memory-status" -Category "memory" -DataPath "Memory" -Collapsible
        }

        # -----------------------------
        "Disk Analysis" {
            $Sections += Add-Section "Disk Usage" $mod.Result.DiskUsage -SectionId "disk-usage" -Category "disk" -DataPath "Disk.Usage" -Collapsible
            $Sections += Add-Section "Disk SMART Health" $mod.Result.SMARTHealth -SectionId "disk-smart-health" -Category "disk" -DataPath "Disk.SMARTHealth" -Collapsible
            $Sections += Add-Section "Disk IO Summary" $mod.Result.DiskIOSummary -SectionId "disk-io-summary" -Category "disk" -DataPath "Disk.IO" -Collapsible
        }

        # -----------------------------
        "Network Analysis" {
            $Sections += Add-Section "Network Connectivity" $mod.Result.Connectivity -SectionId "network-connectivity" -Category "network" -DataPath "Network.Connectivity" -Collapsible
            $Sections += Add-Section "Network Adapters" $mod.Result.Adapters -SectionId "network-adapters" -Category "network" -DataPath "Network.Adapters" -Collapsible
        }

        # -----------------------------
        "Event Log Analysis" {
            $Sections += Add-Section "Recent System Errors" $mod.Result.RecentErrors -SectionId "recent-system-errors" -Category "events" -DataPath "EventLogs" -Collapsible
        }

        # -----------------------------
        "Startup Analysis" {
            $Sections += Add-Section "Startup Programs" $mod.Result.StartupPrograms -SectionId "startup-programs" -Category "startup" -DataPath "StartupPrograms" -Collapsible
        }

        # -----------------------------
        "System Information" {
            $Sections += Add-Section "System Information" $mod.Result -SectionId "system-information" -Category "system" -DataPath "SystemInfo" -Collapsible
        }

        # -----------------------------
        "System Uptime" {
            $Sections += Add-Section "System Uptime" $mod.Result -SectionId "system-uptime" -Category "system" -DataPath "SystemUptime" -Collapsible
        }

        # -----------------------------
        "Windows Update Status" {
            $Sections += Add-Section "Windows Update Status" $mod.Result -SectionId "windows-update-status" -Category "updates" -DataPath "WindowsUpdate" -Collapsible
        }

        # -----------------------------
        "Windows Patch History" {
            $Sections += Add-Section "Recent Security/Critical/Cumulative Updates" $mod.Result.SecurityUpdates -SectionId "recent-security-updates" -Category "updates" -DataPath "WindowsPatchHistory.SecurityUpdates" -Collapsible
            $Sections += Add-Section "Recent Feature Updates" $mod.Result.FeatureUpdates -SectionId "recent-feature-updates" -Category "updates" -DataPath "WindowsPatchHistory.FeatureUpdates" -Collapsible
        }

        # -----------------------------
        "Driver Inventory" {
            $Sections += Add-Section "Driver Inventory" $mod.Result -SectionId "driver-inventory" -Category "drivers" -DataPath "Drivers" -Collapsible
        }

        # -----------------------------
        "Installed Software" {
            $Sections += Add-Section "Installed Software" $mod.Result -SectionId "installed-software" -Category "software" -DataPath "InstalledSoftware" -Collapsible
        }
    }
}

# -----------------------------
# ROOT CAUSE & HEALTH SCORE
# -----------------------------
$rootModule = $moduleResults | Where-Object Module -eq "Root Cause Analysis"

$issuesText = $rootModule.Result.Summary
$healthText = $rootModule.Result.HealthText
$engineRuntime = ($moduleResults | Where-Object Module -eq "Engine Runtime").Result.ScriptRuntimeSeconds

$execText = if ($engineRuntime) {
    "Script Runtime (s): $engineRuntime"
}
else {
    "Execution stats not available"
}

if ($rootModule -and $rootModule.Result -and $rootModule.Result.Details) {
    if (@($rootModule.Result.Details.ValidationIssues).Count -gt 0) {
        $Sections += Add-Section "Data Integrity Findings" $rootModule.Result.Details.ValidationIssues -SectionId "data-integrity-findings" -Category "validation" -DataPath "RootCauseDetails.ValidationIssues" -Collapsible
    }
}

$Sections += Add-Section "Execution Statistics" $execText -SectionId "execution-statistics" -Category "execution" -DataPath "ExecutionStats" -Collapsible

# -----------------------------
# AUTOMATIC REMEDIATION
# -----------------------------
$remediationResult = Get-SafeModuleResult -ModuleResults $moduleResults -ModuleName "Self-Healing Remediation"
$remediationText = if ($remediationResult) { $remediationResult } else { "No remediation actions executed" }
$Sections += Add-Section "Automatic Remediation" $remediationText -SectionId "automatic-remediation" -Category "remediation" -DataPath "AutomaticRemediation" -Collapsible

# -----------------------------------------------------------------------------
# DIAGNOSTICS STORAGE
# -----------------------------------------------------------------------------

try {

    if (-not $ModuleResults) {
        Write-Warning "AutoDoctor: No module results found. Diagnostics and remediation will not be generated."
    }
    else {
        # Write diagnostics
        Write-AutoDoctorDiagnostics -ModuleResults $ModuleResults

        # Write remediation results
        Write-AutoDoctorRemediation -ModuleResults $ModuleResults
    }

}
catch {

    $msg = $_.Exception.Message

    Write-Warning "AutoDoctor diagnostics/remediation failed: $msg"

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Diagnostics/Remediation failure: $msg" |
    Out-File $Global:AutoDoctorLogFile -Append
}

# -----------------------------------------------------------------------------
# ENVIRONMENT DETECTION
# -----------------------------------------------------------------------------

try {

    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $model = $computerSystem.Model

    $isVM = $false

    if ($model -match "Virtual|VMware|KVM|VirtualBox|Hyper-V") {
        $isVM = $true
    }

    if ($isVM) {

        $msg = "AutoDoctor running in virtual environment ($model). Some telemetry metrics may be unavailable."

        Write-Warning $msg

        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" |
        Out-File $Global:AutoDoctorLogFile -Append
    }

}
catch {

    $msg = "Environment detection failed: $($_.Exception.Message)"

    Write-Warning $msg

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" |
    Out-File $Global:AutoDoctorLogFile -Append
}

# -----------------------------------------------------------------------------
# TELEMETRY COLLECTION
# -----------------------------------------------------------------------------

try {
    . "$PSScriptRoot\core\telemetry.ps1"

    $apiHealthy = $false
    $apiConfig = Resolve-AutoDoctorAPIConfig

    try {
        $response = Invoke-RestMethod -Uri $apiConfig.HealthUrl -Method Get -TimeoutSec 5

        if ($response.status -eq "ok") {
            $apiHealthy = $true
            Write-Host "AutoDoctor API is healthy at $($apiConfig.HealthUrl)." -ForegroundColor Green
        }
        else {
            Write-Warning "AutoDoctor API not ready: $($response | ConvertTo-Json -Compress)"
        }
    }
    catch {
        Write-Warning "Telemetry API check failed for $($apiConfig.HealthUrl): $_"
    }

    $telemetryResult = Invoke-AutoDoctorTelemetryCollection -ModuleResults $moduleResults

    if (-not $telemetryResult) {
        Write-Warning "Telemetry collection did not produce data. Database sync skipped."
    }
    else {
        if ($apiHealthy) {
            Write-Host "Sending telemetry to API..." -ForegroundColor Cyan
        }

        Write-AutoDoctorTelemetry -ModuleResults $moduleResults
    }
}
catch {
    Write-Warning "Telemetry module failed: $_"

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Telemetry module failed: $($_.Exception.Message)" |
    Out-File $Global:AutoDoctorLogFile -Append
}
# -----------------------------------------------------------------------------
# ALERTS COLLECTION
# -----------------------------------------------------------------------------

try {

    if (-not $ModuleResults) {
        Write-Warning "AutoDoctor: No module results found. Alerts will not be generated."
    }
    else {
        # Write alerts to DB once
        Write-AutoDoctorAlerts -ModuleResults $ModuleResults
    }

}
catch {
    $msg = $_.Exception.Message
    Write-Warning "AutoDoctor alerts generation failed: $msg"

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Alerts generation failure: $msg" |
    Out-File $Global:AutoDoctorLogFile -Append
}

# -----------------------------------------------------------------------------
# GENERATE REPORT
# -----------------------------------------------------------------------------

# Define report paths
$ReportDir = Get-AutoDoctorPath "Reports"
$HTMLReport = $Global:AutoDoctorReportHTML
$JSONReport = $Global:AutoDoctorReportJSON
$MarkdownReport = $Global:AutoDoctorReportMarkdown
$PDFReport = $Global:AutoDoctorReportPDF

# Ensure report directory exists
if (!(Test-Path -LiteralPath $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

# -----------------------------
# HTML Dashboard
# -----------------------------
# Sections already generated from modules
New-AutoDoctorReport -Sections $Sections -ModuleResults $ModuleResults -OutputPath $HTMLReport

# -----------------------------
# JSON Structured Report
# -----------------------------
New-AutoDoctorJsonReport -ModuleResults $ModuleResults -Sections $Sections -OutputPath $JSONReport

# -----------------------------
# Markdown report
# -----------------------------
New-AutoDoctorMarkdownReport -ModuleResults $ModuleResults -Sections $Sections -OutputPath $MarkdownReport

# -----------------------------
# PDF report
# -----------------------------
Export-AutoDoctorPdfReport -HtmlPath $HTMLReport -OutputPath $PDFReport -PrintMode "full" -Preset "admin"


# ------------------------------------------------
# Ensure dashboard folder exists
# ------------------------------------------------
if (-not (Test-Path $Global:AutoDoctorPaths.Dashboard)) {
    New-Item -ItemType Directory -Path $Global:AutoDoctorPaths.Dashboard | Out-Null
}

# ------------------------------------------------
# Save meta to JSON for FastAPI / dashboard
# ------------------------------------------------
$meta = @{
    run_id         = $Global:AutoDoctorRunID
    host_name      = $env:COMPUTERNAME
    generated_time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$metaJson = $meta | ConvertTo-Json

# Write UTF-8 without BOM so Python JSON readers do not fail parsing.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Global:AutoDoctorMetaJSON, $metaJson, $utf8NoBom)
