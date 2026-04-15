# ---------------------------------------------
# Disk Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "Disk Analysis" -Execute {

    # --- Disk Space ---
    $disk = @()
    $diskRaw = Invoke-Safe {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop |
        ForEach-Object {
            $sizeGb = if ($null -ne $_.Size) { [math]::Round([double]$_.Size / 1GB, 2) } else { $null }
            $freeGb = if ($null -ne $_.FreeSpace) { [math]::Round([double]$_.FreeSpace / 1GB, 2) } else { $null }

            if ($null -eq $sizeGb -or $null -eq $freeGb -or $sizeGb -le 0) {
                return
            }

            [PSCustomObject]@{
                Name   = ([string]$_.DeviceID).TrimEnd(":")
                FreeGB = $freeGb
                UsedGB = [math]::Round(($sizeGb - $freeGb), 2)
            }
        }
    }

    if (-not $diskRaw) {
        $diskRaw = Invoke-Safe {
            Get-PSDrive -PSProvider FileSystem |
            Where-Object {
                $_.Name -match '^[A-Za-z]$' -and
                $_.Root -match '^[A-Za-z]:\\$' -and
                -not $_.DisplayRoot -and
                $null -ne $_.Free -and
                $null -ne $_.Used -and
                (($_.Used + $_.Free) -gt 0)
            } |
            Select-Object Name,
            @{Name = "FreeGB"; Expression = { [math]::Round([double]$_.Free / 1GB, 2) } },
            @{Name = "UsedGB"; Expression = { [math]::Round([double]$_.Used / 1GB, 2) } }
        }
    }

    if ($diskRaw) {
        $disk = @($diskRaw | ForEach-Object {
                [PSCustomObject]@{
                    Name   = [string]$_.Name
                    FreeGB = if ($null -ne $_.FreeGB) { [math]::Round([double]$_.FreeGB, 2) } else { $null }
                    UsedGB = if ($null -ne $_.UsedGB) { [math]::Round([double]$_.UsedGB, 2) } else { $null }
                }
            } | Where-Object {
                $null -ne $_.FreeGB -and
                $null -ne $_.UsedGB -and
                (($_.FreeGB + $_.UsedGB) -gt 0)
            })
    }

    # --- SMART Health ---
    $smart = @()
    $smartRaw = Invoke-Safe {
        Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus
    }

    if ($smartRaw) {
        $smart = @($smartRaw | Select-Object InstanceName, PredictFailure)
    }

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
        $diskIOSummary = @($diskIO.CounterSamples | ForEach-Object {
            [PSCustomObject]@{
                Disk        = $_.InstanceName
                PercentBusy = [math]::Round([double]$_.CookedValue,2)
            }
        })
    }
    elseif ($diskPerfFallback) {
        $diskIOSummary = @($diskPerfFallback | Where-Object { $_.Name -ne "_Total" } | ForEach-Object {
            [PSCustomObject]@{
                Disk        = $_.Name
                PercentBusy = [math]::Round([double]$_.PercentDiskTime,2)
            }
        })
    }

    $diskIOSummary = @($diskIOSummary |
            Where-Object {
                $instanceName = [string]$_.Disk
                $instanceName -and $instanceName -notmatch '^(?i)_?(total|gesamt)$'
            } |
            ForEach-Object {
                [PSCustomObject]@{
                    Disk        = [string]$_.Disk
                    PercentBusy = [math]::Round([double]$_.PercentBusy, 2)
                }
            })

    $diskBusy = @($diskIOSummary | Where-Object { $_.PercentBusy -gt 80 })

    # Return structured object
    $diskObj = [PSCustomObject]@{
        DiskUsage     = @($disk)
        SMARTHealth   = @($smart)
        DiskIOSummary = @($diskIOSummary)
        HighDiskUsage = @($diskBusy)
    }

    return $diskObj
}
