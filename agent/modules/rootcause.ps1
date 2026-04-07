Register-AutoDoctorModule -Name "Root Cause Analysis" -Execute {

param(
    $MemoryObj,
    $CPUObj,
    $DiskObj,
    $NetworkObj,
    $ErrorObj
)

$issues = @()

# -----------------------------
# Extract disk data safely
# -----------------------------

$diskUsage = $DiskObj.DiskUsage
$smart     = $DiskObj.SMARTHealth
$diskBusy  = $DiskObj.HighDiskUsage

# -----------------------------
# Detect Issues
# -----------------------------

if ($MemoryObj -and $MemoryObj.TotalMemoryGB -gt 0 -and $MemoryObj.FreeMemoryGB -lt 1) {
    $issues += "Low RAM available"
}

if ($CPUObj -and $CPUObj.CurrentCPULoadPercent -gt 90) {
    $issues += "CPU saturation detected"
}

if ($diskUsage -and ($diskUsage | Where-Object FreeGB -lt 5)) {
    $issues += "Low disk space"
}

if ($diskBusy -and $diskBusy.Count -gt 0) {
    $issues += "Disk IO bottleneck detected"
}

if ($smart -and ($smart.PredictFailure -contains $true)) {
    $issues += "Potential disk failure detected"
}

if ($NetworkObj -and $NetworkObj.Connectivity.AvgLatencyMS -gt 200) {
    $issues += "High network latency"
}

if ($ErrorObj -and $ErrorObj.ErrorCount -gt 30) {
    $issues += "High error rate in event logs"
}

# -----------------------------
# Health Score
# -----------------------------

$score = 100

if ($MemoryObj -and $MemoryObj.TotalMemoryGB -gt 0 -and $MemoryObj.FreeMemoryGB -lt 1) { $score -= 20 }
if ($CPUObj -and $CPUObj.CurrentCPULoadPercent -gt 90) { $score -= 15 }
if ($diskUsage -and ($diskUsage | Where-Object FreeGB -lt 5)) { $score -= 20 }
if ($diskBusy -and $diskBusy.Count -gt 0) { $score -= 20 }
if ($smart -and ($smart.PredictFailure -contains $true)) { $score -= 40 }
if ($NetworkObj -and $NetworkObj.Connectivity.AvgLatencyMS -gt 200) { $score -= 10 }
if ($ErrorObj -and $ErrorObj.ErrorCount -gt 30) { $score -= 10 }

if ($score -lt 0) { $score = 0 }

# -----------------------------
# Root Cause Summary
# -----------------------------

$summary = if ($issues.Count -eq 0) {
    "No major issues detected"
} else {
    $issues -join "; "
}

# -----------------------------
# Standardized Output
# -----------------------------

return [PSCustomObject]@{
    HealthScore = $score
    HealthText  = "$score / 100"
    Summary     = $summary
    Details     = @{
        DetectedIssues = $issues
    }
}

}
