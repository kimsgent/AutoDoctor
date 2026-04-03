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

function Add-Section {

    param(
        [string]$Title,
        $Content
    )

    $html = "<h2>$Title</h2>"

    if ($null -eq $Content) {
        $html += "<p>No data available</p>"
        return $html
    }

    # Handle arrays
    if ($Content -is [array]) {

        # Array of objects -> render table
        if ($Content[0] -is [psobject] -and $Content[0].PSObject.Properties.Count -gt 0) {
            $table = $Content | ConvertTo-Html -Fragment
            $html += $table
        }
        else {
            # Array of strings -> bullet list
            $html += "<ul>"
            foreach ($item in $Content) {
                $html += "<li>$item</li>"
            }
            $html += "</ul>"
        }

        return $html
    }

    # Handle objects -> render table
    if ($Content -is [psobject]) {
        $table = $Content | ConvertTo-Html -Fragment
        $html += $table
        return $html
    }

    # Default -> simple paragraph
    $html += "<p>$Content</p>"

    return $html
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
Get-ChildItem "$PSScriptRoot\modules\*.ps1" | ForEach-Object {
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
            $Sections += Add-Section "Memory Status" $mod.Result
        }

        # -----------------------------
        "Disk Analysis" {
            $Sections += Add-Section "Disk Usage" $mod.Result.DiskUsage
            $Sections += Add-Section "Disk SMART Health" $mod.Result.SMARTHealth
            $Sections += Add-Section "Disk IO Summary" $mod.Result.DiskIOSummary
        }

        # -----------------------------
        "Network Analysis" {
            $Sections += Add-Section "Network Connectivity" $mod.Result.Connectivity
            $Sections += Add-Section "Network Adapters" $mod.Result.Adapters
        }

        # -----------------------------
        "Event Log Analysis" {
            $Sections += Add-Section "Recent System Errors" $mod.Result.RecentErrors
        }

        # -----------------------------
        "Startup Analysis" {
            $Sections += Add-Section "Startup Programs" $mod.Result.StartupPrograms
        }

        # -----------------------------
        "System Information" {
            $Sections += Add-Section "System Information" $mod.Result
        }

        # -----------------------------
        "System Uptime" {
            $Sections += Add-Section "System Uptime" $mod.Result
        }

        # -----------------------------
        "Windows Update Status" {
            $Sections += Add-Section "Windows Update Status" $mod.Result
        }

        # -----------------------------
        "Windows Patch History" {
            $Sections += Add-Section "Recent Security/Critical/Cumulative Updates" $mod.Result.SecurityUpdates
            $Sections += Add-Section "Recent Feature Updates" $mod.Result.FeatureUpdates
        }

        # -----------------------------
        "Driver Inventory" {
            $Sections += Add-Section "Driver Inventory" $mod.Result
        }

        # -----------------------------
        "Installed Software" {
            $Sections += Add-Section "Installed Software" $mod.Result
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

$Sections += Add-Section "Root Cause Analysis" $issuesText
$Sections += Add-Section "System Health Score" $healthText
$Sections += Add-Section "Execution Statistics" $execText

# -----------------------------
# AUTOMATIC REMEDIATION
# -----------------------------
$remediationResult = Get-SafeModuleResult -ModuleResults $moduleResults -ModuleName "Self-Healing Remediation"
$remediationText = if ($remediationResult) { $remediationResult } else { "No remediation actions executed" }
$Sections += Add-Section "Automatic Remediation" $remediationText

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
New-AutoDoctorJsonReport -ModuleResults $ModuleResults -OutputPath $JSONReport


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
