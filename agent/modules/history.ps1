function ConvertTo-AutoDoctorNullableDouble {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    try {
        $number = [double]$Value

        if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) {
            return $null
        }

        return [math]::Round($number, 2)
    }
    catch {
        return $null
    }
}

function ConvertTo-AutoDoctorNullableDateTime {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return [datetimeoffset]::Parse([string]$Value).UtcDateTime
    }
    catch {
        try {
            return [datetime]::Parse([string]$Value).ToUniversalTime()
        }
        catch {
            return $null
        }
    }
}

function Get-AutoDoctorMemoryUsagePercent {
    param(
        $TotalMemoryGB,
        $FreeMemoryGB
    )

    $total = ConvertTo-AutoDoctorNullableDouble -Value $TotalMemoryGB
    $free = ConvertTo-AutoDoctorNullableDouble -Value $FreeMemoryGB

    if ($null -eq $total -or $total -le 0 -or $null -eq $free) {
        return $null
    }

    if ($free -lt 0) { $free = 0 }
    if ($free -gt $total) { $free = $total }

    return [math]::Round((($total - $free) / $total) * 100, 2)
}

function Get-AutoDoctorDiskUsagePercent {
    param($DiskCollection)

    if (-not $DiskCollection) {
        return $null
    }

    $usageValues = @($DiskCollection | ForEach-Object {
            $size = $null
            $free = $null
            $used = $null

            if ($_.PSObject.Properties.Match("SizeGB").Count -gt 0) {
                $size = ConvertTo-AutoDoctorNullableDouble -Value $_.SizeGB
            }
            elseif ($_.PSObject.Properties.Match("Size").Count -gt 0) {
                $rawSize = ConvertTo-AutoDoctorNullableDouble -Value $_.Size
                if ($null -ne $rawSize) {
                    $size = [math]::Round($rawSize / 1GB, 2)
                }
            }

            if ($_.PSObject.Properties.Match("FreeSpaceGB").Count -gt 0) {
                $free = ConvertTo-AutoDoctorNullableDouble -Value $_.FreeSpaceGB
            }
            elseif ($_.PSObject.Properties.Match("FreeGB").Count -gt 0) {
                $free = ConvertTo-AutoDoctorNullableDouble -Value $_.FreeGB
            }
            elseif ($_.PSObject.Properties.Match("FreeSpace").Count -gt 0) {
                $rawFree = ConvertTo-AutoDoctorNullableDouble -Value $_.FreeSpace
                if ($null -ne $rawFree) {
                    $free = [math]::Round($rawFree / 1GB, 2)
                }
            }

            if ($_.PSObject.Properties.Match("UsedGB").Count -gt 0) {
                $used = ConvertTo-AutoDoctorNullableDouble -Value $_.UsedGB
            }

            if ($null -eq $size -and $null -ne $free -and $null -ne $used) {
                $size = $free + $used
            }

            if ($null -eq $size -or $size -le 0) {
                return
            }

            if ($null -eq $free -and $null -ne $used) {
                $free = $size - $used
            }

            if ($null -eq $free) {
                return
            }

            [math]::Round((($size - $free) / $size) * 100, 2)
        })

    if ($usageValues.Count -eq 0) {
        return $null
    }

    return [double](($usageValues | Measure-Object -Maximum).Maximum)
}

function Get-AutoDoctorHistoryMetricConfig {
    return @{
        CPU     = @{
            Threshold           = 80.0
            BaselineMultiplier  = 1.5
            MinimumDelta        = 10.0
            TrendDeltaThreshold = 12.0
            MinimumTrendSamples = 4
            BetterDirection     = "Lower"
        }
        Memory  = @{
            Threshold           = 85.0
            BaselineMultiplier  = 1.5
            MinimumDelta        = 8.0
            TrendDeltaThreshold = 8.0
            MinimumTrendSamples = 4
            BetterDirection     = "Lower"
        }
        Disk    = @{
            Threshold           = 90.0
            BaselineMultiplier  = 1.5
            MinimumDelta        = 5.0
            TrendDeltaThreshold = 4.0
            MinimumTrendSamples = 4
            BetterDirection     = "Lower"
        }
        Network = @{
            Threshold           = 100.0
            BaselineMultiplier  = 1.5
            MinimumDelta        = 20.0
            TrendDeltaThreshold = 10.0
            MinimumTrendSamples = 4
            BetterDirection     = "Lower"
        }
    }
}

function New-AutoDoctorHistoryTrendPoint {
    param(
        [Parameter(Mandatory = $true)]$Timestamp,
        [Parameter(Mandatory = $true)][double]$Value,
        [bool]$IsCurrent = $false,
        [string]$Source = "History"
    )

    return [PSCustomObject]@{
        Timestamp       = [string]$Timestamp
        ParsedTimestamp = ConvertTo-AutoDoctorNullableDateTime -Value $Timestamp
        Value           = [math]::Round($Value, 2)
        IsCurrent       = $IsCurrent
        Source          = $Source
    }
}

function Get-AutoDoctorHistoryCurrentSnapshot {
    param(
        $CPUObj,
        $MemoryObj,
        $DiskObj,
        $NetworkObj
    )

    $timestamp = (Get-Date).ToString("o")
    $networkLatency = $null

    if ($NetworkObj) {
        if ($NetworkObj.PSObject.Properties.Match("Connectivity").Count -gt 0 -and $NetworkObj.Connectivity) {
            $networkLatency = ConvertTo-AutoDoctorNullableDouble -Value $NetworkObj.Connectivity.AvgLatencyMS
        }
        elseif ($NetworkObj.PSObject.Properties.Match("AvgLatencyMS").Count -gt 0) {
            $networkLatency = ConvertTo-AutoDoctorNullableDouble -Value $NetworkObj.AvgLatencyMS
        }
    }

    return [PSCustomObject]@{
        Timestamp       = $timestamp
        ParsedTimestamp = ConvertTo-AutoDoctorNullableDateTime -Value $timestamp
        Source          = "CurrentRun"
        CPU             = if ($CPUObj) { ConvertTo-AutoDoctorNullableDouble -Value $CPUObj.CurrentCPULoadPercent } else { $null }
        Memory          = if ($MemoryObj) {
            Get-AutoDoctorMemoryUsagePercent -TotalMemoryGB $MemoryObj.TotalMemoryGB -FreeMemoryGB $MemoryObj.FreeMemoryGB
        }
        else { $null }
        Disk            = if ($DiskObj) { Get-AutoDoctorDiskUsagePercent -DiskCollection $DiskObj.DiskUsage } else { $null }
        Network         = $networkLatency
    }
}

function Get-AutoDoctorHistorySnapshotFromTelemetryFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    try {
        $telemetryData = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        return $null
    }

    if (-not $telemetryData) {
        return $null
    }

    $timestamp = $telemetryData.GeneratedAt

    if (-not $timestamp -and $telemetryData.System) {
        $timestamp = $telemetryData.System.Timestamp
    }

    if (-not $timestamp) {
        $timestamp = (Get-Item -LiteralPath $Path).LastWriteTime.ToString("o")
    }

    $networkLatency = $null

    if ($telemetryData.PSObject.Properties.Match("Network").Count -gt 0 -and $telemetryData.Network) {
        if ($telemetryData.Network.PSObject.Properties.Match("Connectivity").Count -gt 0 -and $telemetryData.Network.Connectivity) {
            $networkLatency = ConvertTo-AutoDoctorNullableDouble -Value $telemetryData.Network.Connectivity.AvgLatencyMS
        }
    }

    if ($null -eq $networkLatency -and
        $telemetryData.PSObject.Properties.Match("System").Count -gt 0 -and
        $telemetryData.System -and
        $telemetryData.System.PSObject.Properties.Match("NetworkLatencyMS").Count -gt 0) {

        $networkLatency = ConvertTo-AutoDoctorNullableDouble -Value $telemetryData.System.NetworkLatencyMS
    }

    return [PSCustomObject]@{
        Timestamp       = [string]$timestamp
        ParsedTimestamp = ConvertTo-AutoDoctorNullableDateTime -Value $timestamp
        Source          = [System.IO.Path]::GetFileName($Path)
        CPU             = if ($telemetryData.System -and $telemetryData.System.CPU) {
            ConvertTo-AutoDoctorNullableDouble -Value $telemetryData.System.CPU.CurrentLoad
        }
        else { $null }
        Memory          = if ($telemetryData.System -and $telemetryData.System.Memory) {
            Get-AutoDoctorMemoryUsagePercent -TotalMemoryGB $telemetryData.System.Memory.TotalGB -FreeMemoryGB $telemetryData.System.Memory.FreeGB
        }
        else { $null }
        Disk            = if ($telemetryData.System) { Get-AutoDoctorDiskUsagePercent -DiskCollection $telemetryData.System.Disk } else { $null }
        Network         = $networkLatency
    }
}

function Get-AutoDoctorHistorySnapshots {
    param(
        [int]$Limit = 10
    )

    $effectiveLimit = [math]::Min([math]::Max($Limit, 1), 10)
    $telemetryPath = Get-AutoDoctorPath "Telemetry"

    if (-not $telemetryPath -or -not (Test-Path -LiteralPath $telemetryPath)) {
        return @()
    }

    $telemetryFiles = Get-ChildItem -LiteralPath $telemetryPath -Filter "Telemetry_*.json" -File |
        Sort-Object LastWriteTimeUtc -Descending

    if ($Global:AutoDoctorRunID) {
        $telemetryFiles = @($telemetryFiles | Where-Object { $_.Name -notlike ("Telemetry_{0}_*" -f $Global:AutoDoctorRunID) })
    }

    $snapshots = foreach ($file in ($telemetryFiles | Select-Object -First $effectiveLimit)) {
        $snapshot = Get-AutoDoctorHistorySnapshotFromTelemetryFile -Path $file.FullName

        if ($snapshot -and $snapshot.ParsedTimestamp) {
            $snapshot
        }
    }

    return @($snapshots | Sort-Object ParsedTimestamp -Descending)
}

function Get-AutoDoctorHistoryWindowContext {
    param(
        [array]$Snapshots,
        [int]$HistoryDepth = 5,
        [int]$WindowHours = 24,
        [int]$MinimumSamples = 3
    )

    $effectiveDepth = [math]::Min([math]::Max($HistoryDepth, 1), 10)
    $effectiveWindowHours = [math]::Max($WindowHours, 1)
    $effectiveMinimumSamples = [math]::Max($MinimumSamples, 1)
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-$effectiveWindowHours)

    $recentSnapshots = @($Snapshots |
            Where-Object { $_.ParsedTimestamp -and $_.ParsedTimestamp -ge $cutoff } |
            Sort-Object ParsedTimestamp -Descending |
            Select-Object -First $effectiveDepth)

    if ($recentSnapshots.Count -ge $effectiveMinimumSamples) {
        return [PSCustomObject]@{
            Snapshots       = @($recentSnapshots)
            WindowHours     = $effectiveWindowHours
            MinimumSamples  = $effectiveMinimumSamples
            HistoryDepth    = $effectiveDepth
            UsedFallback    = $false
            WindowLabel     = "Based on last ${effectiveWindowHours}h"
            SampleCount     = $recentSnapshots.Count
            FallbackReason  = $null
        }
    }

    $fallbackSnapshots = @($Snapshots | Sort-Object ParsedTimestamp -Descending | Select-Object -First $effectiveDepth)

    return [PSCustomObject]@{
        Snapshots       = @($fallbackSnapshots)
        WindowHours     = $effectiveWindowHours
        MinimumSamples  = $effectiveMinimumSamples
        HistoryDepth    = $effectiveDepth
        UsedFallback    = $true
        WindowLabel     = "Based on last ${effectiveDepth} runs"
        SampleCount     = $fallbackSnapshots.Count
        FallbackReason  = if ($recentSnapshots.Count -gt 0) {
            "Only $($recentSnapshots.Count) samples found within ${effectiveWindowHours}h"
        }
        else {
            "No telemetry samples found within ${effectiveWindowHours}h"
        }
    }
}

function Get-AutoDoctorDatabaseNetworkTrend {
    param(
        [int]$Limit = 10,
        [int]$WindowHours = 24
    )

    $effectiveLimit = [math]::Min([math]::Max($Limit, 1), 10)
    $effectiveWindowHours = [math]::Max($WindowHours, 1)

    if (-not $Global:AutoDoctorDBPath -or -not (Test-Path -LiteralPath $Global:AutoDoctorDBPath)) {
        return @()
    }

    $connection = $null

    try {
        $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$Global:AutoDoctorDBPath;Version=3;")
        $connection.Open()

        $queries = @(
            @{
                Sql        = "SELECT timestamp, network FROM telemetry_trends WHERE timestamp >= datetime('now', 'utc', @windowClause) ORDER BY datetime(timestamp) DESC LIMIT @limit;"
                ValueField = "network"
            },
            @{
                Sql        = "SELECT timestamp, network_latency_ms AS network FROM system_info WHERE timestamp >= datetime('now', 'utc', @windowClause) ORDER BY datetime(timestamp) DESC LIMIT @limit;"
                ValueField = "network"
            }
        )

        foreach ($query in $queries) {
            try {
                $command = $connection.CreateCommand()
                $command.CommandText = $query.Sql
                $command.Parameters.AddWithValue("@windowClause", "-$effectiveWindowHours hours") | Out-Null
                $command.Parameters.AddWithValue("@limit", $effectiveLimit) | Out-Null

                $reader = $command.ExecuteReader()
                $rows = @()

                while ($reader.Read()) {
                    $value = ConvertTo-AutoDoctorNullableDouble -Value $reader[$query.ValueField]
                    $timestamp = [string]$reader["timestamp"]
                    $parsedTimestamp = ConvertTo-AutoDoctorNullableDateTime -Value $timestamp

                    if ($null -eq $value -or $null -eq $parsedTimestamp) {
                        continue
                    }

                    $rows += New-AutoDoctorHistoryTrendPoint -Timestamp $timestamp -Value $value -IsCurrent:$false -Source "Database"
                }

                $reader.Close()

                if ($rows.Count -gt 0) {
                    return @($rows | Sort-Object ParsedTimestamp -Descending | Select-Object -First $effectiveLimit)
                }
            }
            catch {
                continue
            }
        }
    }
    catch {
        return @()
    }
    finally {
        if ($connection) {
            $connection.Close()
        }
    }

    return @()
}

function Get-AutoDoctorMetricTrend {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        $CurrentSnapshot,
        [array]$HistoricalSnapshots
    )

    $trend = @()

    if ($CurrentSnapshot -and $CurrentSnapshot.PSObject.Properties.Match($Name).Count -gt 0) {
        $currentValue = ConvertTo-AutoDoctorNullableDouble -Value $CurrentSnapshot.$Name

        if ($null -ne $currentValue) {
            $trend += New-AutoDoctorHistoryTrendPoint -Timestamp $CurrentSnapshot.Timestamp -Value $currentValue -IsCurrent:$true -Source $CurrentSnapshot.Source
        }
    }

    foreach ($snapshot in @($HistoricalSnapshots)) {
        if (-not $snapshot -or $snapshot.PSObject.Properties.Match($Name).Count -eq 0) {
            continue
        }

        $value = ConvertTo-AutoDoctorNullableDouble -Value $snapshot.$Name

        if ($null -eq $value -or $null -eq $snapshot.ParsedTimestamp) {
            continue
        }

        $source = if ($snapshot.Source) { [string]$snapshot.Source } else { "History" }
        $trend += New-AutoDoctorHistoryTrendPoint -Timestamp $snapshot.Timestamp -Value $value -IsCurrent:$false -Source $source
    }

    return @($trend | Sort-Object ParsedTimestamp -Descending)
}

function Get-AutoDoctorConsecutiveThresholdBreaches {
    param(
        [array]$Trend,
        [double]$Threshold
    )

    $breachCount = 0

    foreach ($entry in @($Trend)) {
        if ($null -eq $entry -or $null -eq $entry.Value) {
            break
        }

        if ([double]$entry.Value -ge $Threshold) {
            $breachCount++
            continue
        }

        break
    }

    return $breachCount
}

function Get-AutoDoctorTrendBaseline {
    param([array]$Trend)

    $historicalValues = @($Trend |
            Where-Object { -not $_.IsCurrent } |
            ForEach-Object { ConvertTo-AutoDoctorNullableDouble -Value $_.Value } |
            Where-Object { $null -ne $_ })

    if ($historicalValues.Count -eq 0) {
        return [PSCustomObject]@{
            Values    = @()
            Average   = $null
            Minimum   = $null
            Maximum   = $null
            SampleCnt = 0
        }
    }

    return [PSCustomObject]@{
        Values    = @($historicalValues)
        Average   = [double](($historicalValues | Measure-Object -Average).Average)
        Minimum   = [double](($historicalValues | Measure-Object -Minimum).Minimum)
        Maximum   = [double](($historicalValues | Measure-Object -Maximum).Maximum)
        SampleCnt = $historicalValues.Count
    }
}

function Get-AutoDoctorTrendDirection {
    param(
        [array]$Trend,
        [hashtable]$MetricConfig
    )

    $ordered = @($Trend | Sort-Object ParsedTimestamp)

    if ($ordered.Count -lt [int]$MetricConfig.MinimumTrendSamples) {
        return [PSCustomObject]@{
            Direction = "Stable"
            Slope     = 0
            TotalDelta = 0
        }
    }

    $firstValue = ConvertTo-AutoDoctorNullableDouble -Value $ordered[0].Value
    $lastValue = ConvertTo-AutoDoctorNullableDouble -Value $ordered[-1].Value

    if ($null -eq $firstValue -or $null -eq $lastValue) {
        return [PSCustomObject]@{
            Direction = "Stable"
            Slope     = 0
            TotalDelta = 0
        }
    }

    $totalDelta = [math]::Round(($lastValue - $firstValue), 2)
    $slope = [math]::Round(($totalDelta / [math]::Max($ordered.Count - 1, 1)), 2)

    if ([math]::Abs($totalDelta) -lt [double]$MetricConfig.TrendDeltaThreshold) {
        return [PSCustomObject]@{
            Direction = "Stable"
            Slope     = $slope
            TotalDelta = $totalDelta
        }
    }

    if ($totalDelta -gt 0) {
        return [PSCustomObject]@{
            Direction = "Increasing"
            Slope     = $slope
            TotalDelta = $totalDelta
        }
    }

    return [PSCustomObject]@{
        Direction = "Decreasing"
        Slope     = $slope
        TotalDelta = $totalDelta
    }
}

function New-AutoDoctorHistoryIssue {
    param(
        [Parameter(Mandatory = $true)][string]$Metric,
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message,
        [double]$CurrentValue = 0,
        [double]$Threshold = 0,
        [double]$BaselineAverage = 0,
        [int]$ConsecutiveRuns = 0,
        [string]$WindowLabel = "",
        [int]$SampleCount = 0
    )

    return [PSCustomObject]@{
        Category        = $Metric
        Metric          = $Metric
        Type            = $Type
        Severity        = $Severity
        Message         = $Message
        Source          = "History"
        CurrentValue    = [math]::Round($CurrentValue, 2)
        Threshold       = if ($Threshold -gt 0) { [math]::Round($Threshold, 2) } else { $null }
        BaselineAverage = if ($BaselineAverage -gt 0) { [math]::Round($BaselineAverage, 2) } else { $null }
        ConsecutiveRuns = $ConsecutiveRuns
        WindowLabel     = $WindowLabel
        SampleCount     = $SampleCount
    }
}

function Get-AutoDoctorTrendSummaryEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Metric,
        [array]$Trend,
        [hashtable]$MetricConfig,
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)]$WindowContext
    )

    $current = if ($Trend.Count -gt 0) { ConvertTo-AutoDoctorNullableDouble -Value $Trend[0].Value } else { $null }
    $baseline = Get-AutoDoctorTrendBaseline -Trend $Trend
    $directionInfo = Get-AutoDoctorTrendDirection -Trend $Trend -MetricConfig $MetricConfig
    $deltaFromBaseline = if ($null -ne $current -and $null -ne $baseline.Average) {
        [math]::Round(($current - $baseline.Average), 2)
    }
    else {
        $null
    }

    return [PSCustomObject]@{
        Metric             = $Metric
        Current            = $current
        Baseline           = if ($null -ne $baseline.Average) { [math]::Round($baseline.Average, 2) } else { $null }
        BaselineAverage    = if ($null -ne $baseline.Average) { [math]::Round($baseline.Average, 2) } else { $null }
        Threshold          = [math]::Round([double]$MetricConfig.Threshold, 2)
        DeltaFromBaseline  = $deltaFromBaseline
        Direction          = $directionInfo.Direction
        DirectionIcon      = switch ($directionInfo.Direction) {
            "Increasing" { "up" }
            "Decreasing" { "down" }
            default { "flat" }
        }
        State              = $State
        Status             = $State
        SampleCount        = $Trend.Count
        Samples            = $Trend.Count
        WindowLabel        = $WindowContext.WindowLabel
        UsedFallback       = [bool]$WindowContext.UsedFallback
        SampleContext      = ("{0} sample{1}" -f $Trend.Count, $(if ($Trend.Count -eq 1) { "" } else { "s" }))
        Sparkline          = @($Trend | Sort-Object ParsedTimestamp | ForEach-Object { ConvertTo-AutoDoctorNullableDouble -Value $_.Value })
        BetterDirection    = [string]$MetricConfig.BetterDirection
    }
}

function Get-AutoDoctorMetricState {
    param(
        [Parameter(Mandatory = $true)][string]$MetricName,
        [array]$Trend,
        [hashtable]$MetricConfig,
        [Parameter(Mandatory = $true)]$WindowContext
    )

    $currentValue = if ($Trend.Count -gt 0) { ConvertTo-AutoDoctorNullableDouble -Value $Trend[0].Value } else { $null }
    $baseline = Get-AutoDoctorTrendBaseline -Trend $Trend
    $directionInfo = Get-AutoDoctorTrendDirection -Trend $Trend -MetricConfig $MetricConfig
    $threshold = [double]$MetricConfig.Threshold
    $baselineAverage = $baseline.Average
    $baselineThreshold = if ($null -ne $baselineAverage) { [math]::Round(($baselineAverage * [double]$MetricConfig.BaselineMultiplier), 2) } else { $null }
    $deltaFromBaseline = if ($null -ne $currentValue -and $null -ne $baselineAverage) {
        [math]::Round(($currentValue - $baselineAverage), 2)
    }
    else {
        $null
    }
    $consecutiveBreaches = if ($null -ne $currentValue) {
        Get-AutoDoctorConsecutiveThresholdBreaches -Trend $Trend -Threshold $threshold
    }
    else {
        0
    }

    $baselineDeviation = $false

    if ($null -ne $currentValue -and
        $null -ne $baselineAverage -and
        $baseline.SampleCnt -ge 3 -and
        $baselineAverage -gt 0 -and
        $currentValue -gt $baselineThreshold -and
        [math]::Abs($deltaFromBaseline) -ge [double]$MetricConfig.MinimumDelta) {
        $baselineDeviation = $true
    }

    $state = "Stable"

    if ($consecutiveBreaches -ge 3) {
        $state = "Sustained"
    }
    elseif ($baselineDeviation) {
        $state = "Baseline Deviation"
    }
    elseif ($consecutiveBreaches -eq 1) {
        $state = "Transient"
    }
    elseif ($directionInfo.Direction -eq "Increasing") {
        $state = "Increasing"
    }
    elseif ($directionInfo.Direction -eq "Decreasing") {
        $state = "Decreasing"
    }

    return [PSCustomObject]@{
        Metric              = $MetricName
        Current             = $currentValue
        Baseline            = if ($null -ne $baselineAverage) { [math]::Round($baselineAverage, 2) } else { $null }
        BaselineAverage     = if ($null -ne $baselineAverage) { [math]::Round($baselineAverage, 2) } else { $null }
        Threshold           = [math]::Round($threshold, 2)
        BaselineThreshold   = $baselineThreshold
        DeltaFromBaseline   = $deltaFromBaseline
        Direction           = $directionInfo.Direction
        DirectionIcon       = switch ($directionInfo.Direction) {
            "Increasing" { "up" }
            "Decreasing" { "down" }
            default { "flat" }
        }
        State               = $state
        SampleCount         = $Trend.Count
        HistoricalSamples   = $baseline.SampleCnt
        WindowLabel         = $WindowContext.WindowLabel
        UsedFallback        = [bool]$WindowContext.UsedFallback
        ConsecutiveBreaches = $consecutiveBreaches
        DeltaThreshold      = [double]$MetricConfig.MinimumDelta
        TrendSlope          = $directionInfo.Slope
        TrendDelta          = $directionInfo.TotalDelta
        Sparkline           = @($Trend | Sort-Object ParsedTimestamp | ForEach-Object { ConvertTo-AutoDoctorNullableDouble -Value $_.Value })
    }
}

function Invoke-AutoDoctorHistoryAnalysis {
    param(
        [int]$HistoryDepth = 5,
        [int]$WindowHours = 24,
        [int]$MinimumSamples = 3,
        $CPUObj,
        $MemoryObj,
        $DiskObj,
        $NetworkObj
    )

    $effectiveDepth = [math]::Min([math]::Max($HistoryDepth, 1), 10)
    $metricConfig = Get-AutoDoctorHistoryMetricConfig

    $currentSnapshot = Get-AutoDoctorHistoryCurrentSnapshot -CPUObj $CPUObj -MemoryObj $MemoryObj -DiskObj $DiskObj -NetworkObj $NetworkObj
    $allHistoricalSnapshots = Get-AutoDoctorHistorySnapshots -Limit 10
    $windowContext = Get-AutoDoctorHistoryWindowContext -Snapshots $allHistoricalSnapshots -HistoryDepth $effectiveDepth -WindowHours $WindowHours -MinimumSamples $MinimumSamples
    $historicalSnapshots = @($windowContext.Snapshots)

    $cpuTrend = Get-AutoDoctorMetricTrend -Name "CPU" -CurrentSnapshot $currentSnapshot -HistoricalSnapshots $historicalSnapshots
    $memoryTrend = Get-AutoDoctorMetricTrend -Name "Memory" -CurrentSnapshot $currentSnapshot -HistoricalSnapshots $historicalSnapshots
    $diskTrend = Get-AutoDoctorMetricTrend -Name "Disk" -CurrentSnapshot $currentSnapshot -HistoricalSnapshots $historicalSnapshots
    $networkTrend = Get-AutoDoctorMetricTrend -Name "Network" -CurrentSnapshot $currentSnapshot -HistoricalSnapshots $historicalSnapshots

    if (@($networkTrend | Where-Object { $null -ne $_.Value }).Count -le 1) {
        $networkHistory = Get-AutoDoctorDatabaseNetworkTrend -Limit $effectiveDepth -WindowHours $windowContext.WindowHours
        $networkTrend = @(@($networkTrend | Where-Object IsCurrent) + @($networkHistory) | Sort-Object ParsedTimestamp -Descending | Select-Object -First ($effectiveDepth + 1))
    }

    $trends = @{
        CPU     = @($cpuTrend)
        Memory  = @($memoryTrend)
        Disk    = @($diskTrend)
        Network = @($networkTrend)
    }

    $metricStates = @()
    $trendSummary = @()
    $sustainedIssues = @()
    $transientIssues = @()
    $baselineDeviations = @()
    $gradualTrends = @()

    foreach ($metricName in @("CPU", "Memory", "Disk", "Network")) {
        $state = Get-AutoDoctorMetricState -MetricName $metricName -Trend $trends[$metricName] -MetricConfig $metricConfig[$metricName] -WindowContext $windowContext
        $metricStates += $state
        $trendSummary += Get-AutoDoctorTrendSummaryEntry -Metric $metricName -Trend $trends[$metricName] -MetricConfig $metricConfig[$metricName] -State $state.State -WindowContext $windowContext

        if ($state.State -eq "Sustained") {
            $sustainedIssues += New-AutoDoctorHistoryIssue `
                -Metric $metricName `
                -Type "Sustained" `
                -Severity "Critical" `
                -Message ("Sustained {0} issue detected: {1} consecutive runs exceeded {2}" -f $metricName.ToLowerInvariant(), $state.ConsecutiveBreaches, $state.Threshold) `
                -CurrentValue $state.Current `
                -Threshold $state.Threshold `
                -BaselineAverage $state.Baseline `
                -ConsecutiveRuns $state.ConsecutiveBreaches `
                -WindowLabel $state.WindowLabel `
                -SampleCount $state.SampleCount
        }
        elseif ($state.State -eq "Transient") {
            $transientIssues += New-AutoDoctorHistoryIssue `
                -Metric $metricName `
                -Type "Transient" `
                -Severity "Warning" `
                -Message ("Transient {0} spike detected: current value {1} exceeded threshold {2}" -f $metricName.ToLowerInvariant(), $state.Current, $state.Threshold) `
                -CurrentValue $state.Current `
                -Threshold $state.Threshold `
                -BaselineAverage $state.Baseline `
                -ConsecutiveRuns $state.ConsecutiveBreaches `
                -WindowLabel $state.WindowLabel `
                -SampleCount $state.SampleCount
        }
        elseif ($state.State -eq "Baseline Deviation") {
            $baselineDeviations += New-AutoDoctorHistoryIssue `
                -Metric $metricName `
                -Type "Baseline" `
                -Severity "Critical" `
                -Message ("{0} anomaly vs baseline detected: current value {1} exceeds rolling average {2}" -f $metricName, $state.Current, $state.Baseline) `
                -CurrentValue $state.Current `
                -Threshold $state.BaselineThreshold `
                -BaselineAverage $state.Baseline `
                -WindowLabel $state.WindowLabel `
                -SampleCount $state.SampleCount
        }

        if ($state.State -eq "Increasing" -or $state.State -eq "Decreasing") {
            $gradualTrends += [PSCustomObject]@{
                Metric            = $metricName
                Direction         = $state.Direction
                State             = $state.State
                Current           = $state.Current
                Baseline          = $state.Baseline
                DeltaFromBaseline = $state.DeltaFromBaseline
                TrendSlope        = $state.TrendSlope
                TrendDelta        = $state.TrendDelta
                WindowLabel       = $state.WindowLabel
                SampleCount       = $state.SampleCount
            }
        }
    }

    return [PSCustomObject]@{
        CPUTrend           = @($cpuTrend)
        MemoryTrend        = @($memoryTrend)
        DiskTrend          = @($diskTrend)
        NetworkTrend       = @($networkTrend)
        MetricStates       = @($metricStates)
        TrendSummary       = @($trendSummary)
        SustainedIssues    = @($sustainedIssues)
        TransientIssues    = @($transientIssues)
        BaselineDeviations = @($baselineDeviations)
        GradualTrends      = @($gradualTrends)
        TrendWindow        = [PSCustomObject]@{
            HistoryDepthUsed   = $effectiveDepth
            HistoricalSamples  = $historicalSnapshots.Count
            CurrentRunIncluded = $true
            WindowHours        = $windowContext.WindowHours
            MinimumSamples     = $windowContext.MinimumSamples
            UsedFallback       = [bool]$windowContext.UsedFallback
            WindowLabel        = $windowContext.WindowLabel
            FallbackReason     = $windowContext.FallbackReason
        }
    }
}
