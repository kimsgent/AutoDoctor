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

    # --- Disk IO ---
    $diskIO = Invoke-Safe { Get-Counter "\PhysicalDisk(*)\% Disk Time" }

    $diskIOSummary = if ($diskIO) {
        $diskIO.CounterSamples | ForEach-Object {
            [PSCustomObject]@{
                Disk        = $_.InstanceName
                PercentBusy = [math]::Round($_.CookedValue,2)
            }
        }
    } else { @() }

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
