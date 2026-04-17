# ---------------------------------------------
# Network Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "Network Analysis" -Execute {

    # --- Connectivity Test ---
    $networkTest = @()
    $networkRaw = Invoke-Safe { Test-Connection google.com -Count 6 }
    if ($networkRaw) {
        $networkTest = @($networkRaw)
    }

    $received = if ($networkTest.Count -gt 0) { @($networkTest | Where-Object { $_.StatusCode -eq 0 }) } else { @() }

    $avgLatency = if ($received.Count -gt 0) {
        ($received | Measure-Object ResponseTime -Average).Average
    } else { 0 }

    $connectivityStatus = if ($networkTest.Count -eq 0) {
        "Unavailable"
    } elseif ($received.Count -eq 0) {
        "Unreachable"
    } else {
        "Reachable"
    }

    $netObj = [PSCustomObject]@{
        PacketsSent     = $networkTest.Count
        PacketsReceived = $received.Count
        AvgLatencyMS    = [math]::Round([double]$avgLatency, 2)
        Status          = $connectivityStatus
    }

    # --- Network Adapters ---
    $adapters = @()
    $adaptersRaw = Invoke-Safe { Get-NetAdapter | Select-Object Name, Status, LinkSpeed }
    if ($adaptersRaw) {
        $adapters = @($adaptersRaw | ForEach-Object {
                [PSCustomObject]@{
                    Name      = [string]$_.Name
                    Status    = [string]$_.Status
                    LinkSpeed = [string]$_.LinkSpeed
                }
            })
    }

    # Return structured object
    $networkObj = [PSCustomObject]@{
        Connectivity = $netObj
        Adapters     = @($adapters)
    }

    return $networkObj
}
