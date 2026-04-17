# ---------------------------------------------
# CPU Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "CPU Analysis" -Execute {

    # --- Process Analysis ---
    $topCPU = @()
    $topCpuRaw = Invoke-Safe {
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 ProcessName, CPU
    }

    if ($topCpuRaw) {
        $topCPU = @($topCpuRaw | ForEach-Object {
                $cpuSeconds = 0
                if ($null -ne $_.CPU) {
                    $cpuSeconds = [math]::Round([double]$_.CPU, 2)
                }

                [PSCustomObject]@{
                    ProcessName = [string]$_.ProcessName
                    CPU         = $cpuSeconds
                }
            })
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

    if ($cpuCounterSample -and $cpuCounterSample.CounterSamples -and $cpuCounterSample.CounterSamples.Count -gt 0) {
        $sampleValue = $cpuCounterSample.CounterSamples[0].CookedValue
        if ($null -ne $sampleValue) {
            $cpuPercent = [math]::Round([double]$sampleValue, 2)
        }
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

    if ($cpuPercent -lt 0) { $cpuPercent = 0 }
    if ($cpuPercent -gt 100) { $cpuPercent = 100 }
    $cpuPercent = [math]::Round([double]$cpuPercent, 2)

    $cpuObj = [PSCustomObject]@{
        CurrentCPULoadPercent = $cpuPercent
        TopProcesses          = @($topCPU)
    }

    return $cpuObj
}
