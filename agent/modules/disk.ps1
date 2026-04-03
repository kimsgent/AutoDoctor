# ---------------------------------------------
# Disk Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "Disk Analysis" -Execute {

    # --- Disk Space ---
    $disk = Invoke-Safe {
        Get-PSDrive -PSProvider FileSystem | Select-Object Name,
        @{Name = "FreeGB"; Expression = { [math]::Round($_.Free / 1GB, 2) } },
        @{Name = "UsedGB"; Expression = { [math]::Round(($_.Used) / 1GB, 2) } }
    }

    # --- SMART Health ---
    $smart = Invoke-Safe {
        Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus
    } | Select-Object InstanceName, PredictFailure

    # --- Disk IO (English PerfCounter -> localized PerfCounter -> WMI) ---
    $diskCounterPath = "\PhysicalDisk(*)\% Disk Time"
    $diskIO = $null
    $diskPerfFallback = $null

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

        if ($null -eq $diskIO) {
            Write-Warning "PerfCounter failed, fallback to WMI"
            $diskPerfFallback = Invoke-Safe {
                Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop
            }
        }
    }

    $diskIOSummary = @()

    if ($diskIO) {
        $diskIOSummary = $diskIO.CounterSamples | ForEach-Object {
            [PSCustomObject]@{
                Disk        = $_.InstanceName
                PercentBusy = [math]::Round($_.CookedValue,2)
            }
        }
    }
    elseif ($diskPerfFallback) {
        $diskIOSummary = $diskPerfFallback | Where-Object { $_.Name -ne "_Total" } | ForEach-Object {
            [PSCustomObject]@{
                Disk        = $_.Name
                PercentBusy = [math]::Round($_.PercentDiskTime,2)
            }
        }
    }

    $diskBusy = $diskIOSummary | Where-Object { $_.PercentBusy -gt 80 }

    # Return structured object
    $diskObj = [PSCustomObject]@{
        DiskUsage      = $disk
        SMARTHealth    = $smart
        DiskIOSummary  = $diskIOSummary
        HighDiskUsage  = $diskBusy
    }

    return $diskObj
}
