# ------------------------------------------------
# AutoDoctor Module Engine
# ------------------------------------------------

$Global:AutoDoctorModules = @()

function Register-AutoDoctorModule {

    param(
        [string]$Name,
        [scriptblock]$Execute
    )

    $Global:AutoDoctorModules += [PSCustomObject]@{
        Name    = $Name
        Execute = $Execute
    }

}

function Invoke-AutoDoctorModules {

    param(
        [datetime]$ScriptStart
    )

    $results = @()

    foreach ($module in $Global:AutoDoctorModules) {

        $moduleStart = Get-Date

        try {

            # Retrieve prior module outputs
            $memoryObj  = ($results | Where-Object Module -eq "Memory Analysis").Result
            $cpuObj     = ($results | Where-Object Module -eq "CPU Analysis").Result
            $diskObj    = ($results | Where-Object Module -eq "Disk Analysis").Result
            $networkObj = ($results | Where-Object Module -eq "Network Analysis").Result
            $errorObj   = ($results | Where-Object Module -eq "Event Log Analysis").Result

            # Build parameter set dynamically
            $params = @{
                MemoryObj   = $memoryObj
                CPUObj      = $cpuObj
                DiskObj     = $diskObj
                NetworkObj  = $networkObj
                ErrorObj    = $errorObj
                ScriptStart = $ScriptStart
            }

            # Execute module
            $result = & $module.Execute @params

            $moduleRuntime = [math]::Round(((Get-Date) - $moduleStart).TotalSeconds, 2)

            $results += [PSCustomObject]@{
                Module         = $module.Name
                Result         = $result
                RuntimeSeconds = $moduleRuntime
                Error          = $null
            }

        }
        catch {

            $moduleRuntime = [math]::Round(((Get-Date) - $moduleStart).TotalSeconds, 2)

            $results += [PSCustomObject]@{
                Module         = $module.Name
                Result         = $null
                RuntimeSeconds = $moduleRuntime
                Error          = $_.Exception.Message
            }

            Write-Warning "AutoDoctor module failed: $($module.Name)"
            Write-Warning $_.Exception.Message

        }

    }

    # ------------------------------------------------
    # Calculate TOTAL script runtime
    # ------------------------------------------------

    $ScriptEnd = Get-Date
    $ScriptRuntime = [math]::Round(($ScriptEnd - $ScriptStart).TotalSeconds, 2)

    # Store runtime as a synthetic result so existing code doesn't break
    $results += [PSCustomObject]@{
        Module         = "Engine Runtime"
        Result = [PSCustomObject]@{
            ScriptRuntimeSeconds = $ScriptRuntime
        }
        RuntimeSeconds = $ScriptRuntime
        Error          = $null
    }

    return $results
}
