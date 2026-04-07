# ---------------------------------------------
# Memory Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "Memory Analysis" -Execute {

    # --- Memory Status ---
    $os = Invoke-Safe { Get-CimInstance Win32_OperatingSystem }

    $totalMem = 0
    $freeMem = 0
    $status = "Unknown"

    if ($os) {
        if ($null -ne $os.TotalVisibleMemorySize) {
            $totalMem = [math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 2)
        }

        if ($null -ne $os.FreePhysicalMemory) {
            $freeMem = [math]::Round(([double]$os.FreePhysicalMemory / 1MB), 2)
        }
    }

    if ($totalMem -gt 0) {
        if ($freeMem -lt 0) { $freeMem = 0 }
        if ($freeMem -gt $totalMem) { $freeMem = $totalMem }
        $status = if ($freeMem -lt 1) { "Low Memory" } else { "Normal" }
    }

    $memObj = [PSCustomObject]@{
        TotalMemoryGB = $totalMem
        FreeMemoryGB  = $freeMem
        Status        = $status
    }

    return $memObj
}
