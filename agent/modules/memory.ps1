# ---------------------------------------------
# Memory Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "Memory Analysis" -Execute {

    # --- Memory Status ---
    $os = Invoke-Safe { Get-CimInstance Win32_OperatingSystem }

    $totalMem = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 2) } else { 0 }
    $freeMem  = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { 0 }

    $memObj = [PSCustomObject]@{
        TotalMemoryGB = $totalMem
        FreeMemoryGB  = $freeMem
        Status        = if ($freeMem -lt 1) { "Low Memory" } else { "Normal" }
    }

    return $memObj
}
