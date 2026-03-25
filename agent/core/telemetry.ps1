<#
.SYNOPSIS
    AutoDoctor Telemetry Module
.DESCRIPTION
    Defines explicit telemetry collection functions for AutoDoctor.
    Dot-sourcing this file should only load functions; it should not
    immediately collect telemetry or write files as a side effect.
#>

function Get-AutoDoctorTelemetryFilePath {
    $telemetryDir = Get-AutoDoctorPath "Telemetry"

    if (-not $telemetryDir) {
        throw "Telemetry path not configured."
    }

    if (-not (Test-Path -LiteralPath $telemetryDir)) {
        New-Item -ItemType Directory -Path $telemetryDir -Force | Out-Null
    }

    return Join-Path $telemetryDir ("Telemetry_{0}_{1}.json" -f $Global:AutoDoctorRunID, (Get-Date -Format "HHmmss"))
}

function Get-SystemTelemetry {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $bios = Get-CimInstance Win32_BIOS
        $cpu = Get-CimInstance Win32_Processor
        $computerSystem = Get-CimInstance Win32_ComputerSystem
        $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
        $network = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }

        $model = $computerSystem.Model
        $manufacturer = $computerSystem.Manufacturer
        $isVM = $false

        if ($model -match "Virtual|VMware|KVM|VirtualBox|Hyper-V" -or
            $manufacturer -match "VMware|Microsoft|Xen|QEMU|innotek") {
            $isVM = $true
        }

        $environmentType = if ($isVM) { "VirtualMachine" } else { "PhysicalMachine" }

        # -----------------------------
        # CPU fallback
        # -----------------------------
        $cpuLoad = $null
        try {
            $cpuLoad = (Get-Counter "\Processor(_Total)\% Processor Time").CounterSamples[0].CookedValue
        }
        catch {
            try {
                $cpuLoad = $cpu.LoadPercentage
            } catch { $cpuLoad = $null }
        }

        # -----------------------------
        # Memory fallback
        # -----------------------------
        $memFree = $null
        try {
            if ($null -ne $os.FreePhysicalMemory) {
                $memFree = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            }
        }
        catch {}

        if ($null -eq $memFree) {
            try {
                $memPerf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
                if ($null -ne $memPerf.AvailableMBytes) {
                    $memFree = [math]::Round($memPerf.AvailableMBytes / 1024, 2)
                }
            }
            catch { $memFree = $null }
        }

        # -----------------------------
        # Disk fallback
        # -----------------------------
        $diskObjects = $null
        try {
            if ($disks) {
                $diskObjects = $disks | ForEach-Object {
                    [PSCustomObject]@{
                        DeviceID    = $_.DeviceID
                        SizeGB      = [math]::Round($_.Size / 1GB, 2)
                        FreeSpaceGB = [math]::Round($_.FreeSpace / 1GB, 2)
                        PercentFree = if ($_.Size -gt 0) {
                            [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
                        } else { $null }
                    }
                }
            }
        }
        catch {}

        if ($null -eq $diskObjects) {
            try {
                $diskObjects = Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Free } | ForEach-Object {
                    [PSCustomObject]@{
                        DeviceID    = $_.Name
                        SizeGB      = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
                        FreeSpaceGB = [math]::Round($_.Free / 1GB, 2)
                        PercentFree = if (($_.Used + $_.Free) -gt 0) {
                            [math]::Round(($_.Free / ($_.Used + $_.Free)) * 100, 1)
                        } else { $null }
                    }
                }
            }
            catch { $diskObjects = @() }
        }

        return [PSCustomObject]@{
            Timestamp   = (Get-Date).ToString("o")
            OS          = @{
                Caption      = $os.Caption
                Version      = $os.Version
                Build        = $os.BuildNumber
                Architecture = $os.OSArchitecture
                LastBootUp   = $os.LastBootUpTime
            }
            BIOS        = @{
                Manufacturer = $bios.Manufacturer
                Version      = $bios.SMBIOSBIOSVersion
                ReleaseDate  = $bios.ReleaseDate
            }
            Environment = @{
                Type         = $environmentType
                Model        = $model
                Manufacturer = $manufacturer
            }
            CPU         = @{
                Name        = $cpu.Name
                Cores       = $cpu.NumberOfCores
                Logical     = $cpu.NumberOfLogicalProcessors
                MaxClockMHz = $cpu.MaxClockSpeed
                CurrentLoad = if ($null -ne $cpuLoad) { [math]::Round($cpuLoad, 2) } else { $null }
            }
            Memory      = @{
                TotalGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
                FreeGB  = $memFree
            }
            Disk        = $diskObjects
            Network     = $network | ForEach-Object {
                [PSCustomObject]@{
                    Description = $_.Description
                    MACAddress  = $_.MACAddress
                    IPAddresses = $_.IPAddress
                    DHCPEnabled = $_.DHCPEnabled
                }
            }
        }
    }
    catch {
        Write-Warning "Error collecting system telemetry: $_"
        return @{}
    }
}

function Get-ModuleTelemetry {
    param([array]$ModuleResults)

    return $ModuleResults | ForEach-Object {
        [PSCustomObject]@{
            ModuleName = $_.Module
            Status     = if ($null -ne $_.Result) { "Success" } else { "Failed/Empty" }
            ResultKeys = if ($null -ne $_.Result) { @($_.Result.PSObject.Properties.Name) } else { @() }
        }
    }
}

function Get-ExecutionStats {
    param([array]$ModuleResults)

    if (-not $ModuleResults) {
        return @{
            ScriptRuntimeSeconds = 0
            ModuleCount          = 0
            ModulesSucceeded     = 0
            ModulesFailed        = 0
        }
    }

    $runtimeMod = $ModuleResults | Where-Object { $_.Module -eq "Engine Runtime" }
    $scriptRuntime = if ($runtimeMod) { $runtimeMod.Result.ScriptRuntimeSeconds } else { 0 }
    $modulesOther = $ModuleResults | Where-Object { $_.Module -ne "Engine Runtime" }

    return @{
        ScriptRuntimeSeconds = $scriptRuntime
        ModuleCount          = $modulesOther.Count
        ModulesSucceeded     = ($modulesOther | Where-Object { $null -eq $_.Error }).Count
        ModulesFailed        = ($modulesOther | Where-Object { $null -ne $_.Error }).Count
    }
}

function New-AutoDoctorTelemetryData {
    param([array]$ModuleResults = $global:ModuleResults)

    $normalizedModuleResults = @($ModuleResults | ForEach-Object { $_ })
    $global:ModuleResults = $normalizedModuleResults

    $telemetryData = [PSCustomObject]@{
        RunID             = $Global:AutoDoctorRunID
        GeneratedAt       = (Get-Date).ToString("o")
        Hostname          = $env:COMPUTERNAME
        User              = $env:USERNAME
        AutoDoctorVersion = Get-AutoDoctorVersion
        ExecutionStats    = Get-ExecutionStats -ModuleResults $normalizedModuleResults
        DatabaseSync      = @{
            Enabled            = $true
            LastWriteUTC       = (Get-Date).ToUniversalTime().ToString("o")
            DiagnosticsWritten = $true
            AlertsWritten      = $true
            Error              = $null
        }
        System            = Get-SystemTelemetry
        Modules           = Get-ModuleTelemetry -ModuleResults $normalizedModuleResults
    }

    $global:TelemetryData = $telemetryData

    return $telemetryData
}

function Save-AutoDoctorTelemetryFile {
    param(
        [Parameter(Mandatory = $true)]$TelemetryData,
        [string]$TelemetryFile = (Get-AutoDoctorTelemetryFilePath)
    )

    $json = $TelemetryData | ConvertTo-Json -Depth 6 -Compress:$false
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText($TelemetryFile, $json, $utf8NoBom)
    Write-Host "Telemetry saved: $TelemetryFile" -ForegroundColor Green

    return $TelemetryFile
}

function Invoke-AutoDoctorTelemetryUpload {
    param(
        [Parameter(Mandatory = $true)]$TelemetryData,
        [Parameter(Mandatory = $true)][string]$UploadEndpoint
    )

    Invoke-RestMethod `
        -Uri $UploadEndpoint `
        -Method Post `
        -Body ($TelemetryData | ConvertTo-Json -Depth 6 -Compress:$true) `
        -ContentType "application/json"

    Write-Host "Telemetry uploaded successfully to $UploadEndpoint" -ForegroundColor Cyan
}

function Invoke-AutoDoctorTelemetryCollection {
    param(
        [array]$ModuleResults = $global:ModuleResults,
        [switch]$Upload,
        [string]$UploadEndpoint = "https://telemetry.autodoctor.example/upload"
    )

    try {
        $telemetryData = New-AutoDoctorTelemetryData -ModuleResults $ModuleResults
        $telemetryFile = Save-AutoDoctorTelemetryFile -TelemetryData $telemetryData

        if ($Upload) {
            try {
                Invoke-AutoDoctorTelemetryUpload -TelemetryData $telemetryData -UploadEndpoint $UploadEndpoint
            }
            catch {
                Write-Warning "Telemetry upload failed: $_"
            }
        }

        return [PSCustomObject]@{
            TelemetryData = $telemetryData
            TelemetryFile = $telemetryFile
        }
    }
    catch {
        $global:TelemetryData = $null
        Write-Warning "Telemetry collection failed: $_"
        return $null
    }
}
