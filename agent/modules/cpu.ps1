# ---------------------------------------------
# CPU Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "CPU Analysis" -Execute {

    # --- Process Analysis ---
    $topCPU = Invoke-Safe {
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 ProcessName, CPU
    }

    # --- CPU Load ---
    $cpuLoad = Invoke-Safe { Get-CimInstance Win32_Processor }
    $cpuPercent = if ($cpuLoad) { $cpuLoad.LoadPercentage } else { 0 }

    $cpuObj = [PSCustomObject]@{
        CurrentCPULoadPercent = $cpuPercent
        TopProcesses = $topCPU
    }

    return $cpuObj
}
