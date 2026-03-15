# ---------------------------------------------
# Network Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "Network Analysis" -Execute {

    # --- Connectivity Test ---
    $networkTest = Invoke-Safe { Test-Connection google.com -Count 6 }

    $received = if ($networkTest) { $networkTest | Where-Object { $_.StatusCode -eq 0 } } else { @() }

    $avgLatency = if ($networkTest) {
        ($networkTest | Measure-Object ResponseTime -Average).Average
    } else { 0 }

    $netObj = [PSCustomObject]@{
        PacketsSent     = if ($networkTest) { $networkTest.Count } else { 0 }
        PacketsReceived = $received.Count
        AvgLatencyMS    = [math]::Round($avgLatency, 2)
    }

    # --- Network Adapters ---
    $adapters = Invoke-Safe { Get-NetAdapter | Select-Object Name, Status, LinkSpeed }

    # Return structured object
    $networkObj = [PSCustomObject]@{
        Connectivity   = $netObj
        Adapters       = $adapters
    }

    return $networkObj
}
