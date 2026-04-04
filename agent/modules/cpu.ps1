# ---------------------------------------------
# CPU Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "CPU Analysis" -Execute {

    # --- Process Analysis ---
    $topCPU = Invoke-Safe {
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 ProcessName, CPU
    }

    # --- CPU Load (English PerfCounter -> localized PerfCounter -> WMI) ---
    $cpuPercent = 0
    $cpuCounterPath = "\Processor(_Total)\% Processor Time"
    $cpuCounterSample = $null

    try {
        $cpuCounterSample = Get-Counter -Counter $cpuCounterPath -ErrorAction Stop
    }
    catch {
        $localizedCpuPath = Get-LocalizedCounterPath -CanonicalName "Processor" -CounterPath $cpuCounterPath

        if ($localizedCpuPath) {
            try {
                $cpuCounterSample = Get-Counter -Counter $localizedCpuPath -ErrorAction Stop
            }
            catch {
                $cpuCounterSample = $null
            }
        }
    }

    if ($cpuCounterSample) {
        $cpuPercent = [math]::Round($cpuCounterSample.CounterSamples[0].CookedValue, 2)
    }
    else {
        Write-Warning "PerfCounter failed, fallback to WMI"
        $cpuLoad = Invoke-Safe { Get-CimInstance Win32_Processor }

        if ($cpuLoad) {
            if ($cpuLoad -is [array]) {
                $avgCpu = $cpuLoad | Measure-Object -Property LoadPercentage -Average
                if ($avgCpu -and $null -ne $avgCpu.Average) {
                    $cpuPercent = [math]::Round($avgCpu.Average, 2)
                }
            }
            elseif ($null -ne $cpuLoad.LoadPercentage) {
                $cpuPercent = [math]::Round($cpuLoad.LoadPercentage, 2)
            }
        }
    }

    $cpuObj = [PSCustomObject]@{
        CurrentCPULoadPercent = $cpuPercent
        TopProcesses = $topCPU
    }

    return $cpuObj
}
