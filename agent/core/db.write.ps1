function ConvertTo-AutoDoctorDbValue {
    param($Value)

    if ($null -eq $Value) {
        return [DBNull]::Value
    }

    return $Value
}

function ConvertTo-AutoDoctorDbDouble {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    try {
        return [double]$Value
    }
    catch {
        return $null
    }
}

function Get-AutoDoctorStandardDeviation {
    param([double[]]$Values)

    if (-not $Values -or $Values.Count -lt 2) {
        return $null
    }

    $average = [double](($Values | Measure-Object -Average).Average)
    $variance = (($Values | ForEach-Object { [math]::Pow(($_ - $average), 2) } | Measure-Object -Average).Average)

    return [math]::Round([math]::Sqrt($variance), 2)
}

function Update-AutoDoctorTelemetryBaselines {
    param(
        [Parameter(Mandatory = $true)][System.Data.SQLite.SQLiteConnection]$Connection,
        [Parameter(Mandatory = $true)][System.Data.SQLite.SQLiteTransaction]$Transaction,
        [Parameter(Mandatory = $true)][string]$Hostname,
        [int]$WindowHours = 24
    )

    $metricDefinitions = @(
        @{ Name = "cpu"; Column = "cpu" }
        @{ Name = "memory"; Column = "memory" }
        @{ Name = "disk"; Column = "disk" }
        @{ Name = "network"; Column = "network" }
    )

    foreach ($metric in $metricDefinitions) {
        $query = $Connection.CreateCommand()
        $query.Transaction = $Transaction
        $query.CommandText = @"
SELECT $($metric.Column) AS metric_value
FROM telemetry_trends
WHERE timestamp >= datetime('now','utc', @windowClause)
  AND $($metric.Column) IS NOT NULL
ORDER BY datetime(timestamp) DESC;
"@
        $query.Parameters.AddWithValue("@windowClause", "-$WindowHours hours") | Out-Null

        $reader = $query.ExecuteReader()
        $values = @()

        while ($reader.Read()) {
            $value = ConvertTo-AutoDoctorDbDouble -Value $reader["metric_value"]

            if ($null -ne $value) {
                $values += [double]$value
            }
        }

        $reader.Close()

        if ($values.Count -eq 0) {
            continue
        }

        $avgValue = [math]::Round((($values | Measure-Object -Average).Average), 2)
        $minValue = [math]::Round((($values | Measure-Object -Minimum).Minimum), 2)
        $maxValue = [math]::Round((($values | Measure-Object -Maximum).Maximum), 2)
        $stdDev = Get-AutoDoctorStandardDeviation -Values $values

        $cmd = $Connection.CreateCommand()
        $cmd.Transaction = $Transaction
        $cmd.CommandText = @"
INSERT OR REPLACE INTO telemetry_baselines
(hostname,metric,window_hours,sample_count,avg_value,min_value,max_value,stddev,updated_at)
VALUES
(@hostname,@metric,@windowHours,@sampleCount,@avgValue,@minValue,@maxValue,@stdDev,datetime('now','utc'));
"@
        $cmd.Parameters.AddWithValue("@hostname", $Hostname) | Out-Null
        $cmd.Parameters.AddWithValue("@metric", $metric.Name) | Out-Null
        $cmd.Parameters.AddWithValue("@windowHours", $WindowHours) | Out-Null
        $cmd.Parameters.AddWithValue("@sampleCount", $values.Count) | Out-Null
        $cmd.Parameters.AddWithValue("@avgValue", (ConvertTo-AutoDoctorDbValue -Value $avgValue)) | Out-Null
        $cmd.Parameters.AddWithValue("@minValue", (ConvertTo-AutoDoctorDbValue -Value $minValue)) | Out-Null
        $cmd.Parameters.AddWithValue("@maxValue", (ConvertTo-AutoDoctorDbValue -Value $maxValue)) | Out-Null
        $cmd.Parameters.AddWithValue("@stdDev", (ConvertTo-AutoDoctorDbValue -Value $stdDev)) | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null
    }
}

function Write-AutoDoctorDiagnostics {

    param([array]$ModuleResults)

    try {

        $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$Global:AutoDoctorDBPath;Version=3;")
        $connection.Open()

        $transaction = $connection.BeginTransaction()

        foreach ($mod in $ModuleResults) {

            if ($mod.Module -eq "Engine Runtime") { continue }

            $status = if ($mod.Error) { "Failed" } else { "Success" }

            $cmd = $connection.CreateCommand()
            $cmd.Transaction = $transaction

            $cmd.CommandText = @"
INSERT INTO diagnostics
(run_id,hostname,module_name,status,runtime_seconds,health_score,summary,timestamp)
VALUES
(@runid,@hostname,@module,@status,@runtime,@score,@summary,datetime('now','utc'));
"@

            $cmd.Parameters.AddWithValue("@runid", $Global:AutoDoctorRunID) | Out-Null
            $cmd.Parameters.AddWithValue("@hostname", $env:COMPUTERNAME) | Out-Null
            $cmd.Parameters.AddWithValue("@module", $mod.Module) | Out-Null
            $cmd.Parameters.AddWithValue("@status", $status) | Out-Null
            $cmd.Parameters.AddWithValue("@runtime", $mod.RuntimeSeconds) | Out-Null
            $cmd.Parameters.AddWithValue("@score", $mod.Result.HealthScore) | Out-Null
            $cmd.Parameters.AddWithValue("@summary", $mod.Result.Summary) | Out-Null

            $cmd.ExecuteNonQuery() | Out-Null
        }

        $transaction.Commit()
        $connection.Close()
    }
    catch {
        if ($transaction) { $transaction.Rollback() }
        Write-Warning "Diagnostics DB write failed: $($_.Exception.Message)"
    }
}

function Write-AutoDoctorRemediation {

    param([array]$ModuleResults)

    try {

        $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$Global:AutoDoctorDBPath;Version=3;")
        $connection.Open()

        $transaction = $connection.BeginTransaction()

        foreach ($mod in $ModuleResults) {

            if ($mod.Module -ne "Self-Healing Remediation") { continue }

            $cmd = $connection.CreateCommand()
            $cmd.Transaction = $transaction

            $cmd.CommandText = @"
INSERT INTO remediation
(run_id,hostname,status,timestamp)
VALUES
(@runid,@hostname,@status,datetime('now','utc'));
"@

            $cmd.Parameters.AddWithValue("@runid", $Global:AutoDoctorRunID) | Out-Null
            $cmd.Parameters.AddWithValue("@hostname", $env:COMPUTERNAME) | Out-Null
            $cmd.Parameters.AddWithValue("@status", $mod.Result.Status) | Out-Null

            $cmd.ExecuteNonQuery() | Out-Null
        }

        $transaction.Commit()
        $connection.Close()
    }
    catch {
        if ($transaction) { $transaction.Rollback() }
        Write-Warning "Remediation DB write failed: $($_.Exception.Message)"
    }
}

function Write-AutoDoctorTelemetry {
    param(
        $TelemetryData = $global:TelemetryData,
        [array]$ModuleResults = $global:ModuleResults
    )

    if (-not $TelemetryData) { return }
    $telemetryRunID = if ($TelemetryData.RunID) { $TelemetryData.RunID } else { $Global:AutoDoctorRunID }

    try {
        $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$Global:AutoDoctorDBPath;Version=3;")
        $connection.Open()
        $transaction = $connection.BeginTransaction()

        # -----------------------------
        # Write module telemetry
        # -----------------------------
        foreach ($mod in $TelemetryData.Modules) {
            $cmd = $connection.CreateCommand()
            $cmd.Transaction = $transaction
            $cmd.CommandText = @"
INSERT INTO telemetry_modules
(run_id,hostname,module_name,status,result_keys,timestamp)
VALUES
(@runid,@hostname,@module,@status,@keys,datetime('now','utc'));
"@
            $cmd.Parameters.AddWithValue("@runid", $telemetryRunID) | Out-Null
            $cmd.Parameters.AddWithValue("@hostname", $TelemetryData.Hostname) | Out-Null
            $cmd.Parameters.AddWithValue("@module", $mod.ModuleName) | Out-Null
            $cmd.Parameters.AddWithValue("@status", $mod.Status) | Out-Null
            $cmd.Parameters.AddWithValue("@keys", ($mod.ResultKeys -join ",")) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
        }

        # -----------------------------
        # Derive system snapshot metrics
        # -----------------------------

        $cpuLoad = if ($null -ne $TelemetryData.System.CPU.CurrentLoad) {
            [math]::Round($TelemetryData.System.CPU.CurrentLoad, 2)
        } else { $null }

        $memFree = if ($null -ne $TelemetryData.System.Memory.FreeGB) {
            [math]::Round($TelemetryData.System.Memory.FreeGB, 2)
        } else { $null }

        $memTotal = if ($null -ne $TelemetryData.System.Memory.TotalGB) {
            [math]::Round($TelemetryData.System.Memory.TotalGB, 2)
        } else { $null }

        $memUsedPercent = if ($null -ne $memTotal -and $memTotal -gt 0 -and $null -ne $memFree) {
            [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 2)
        } else { $null }

        $diskFree = if ($null -ne $TelemetryData.System.Disk) {
            [math]::Round(
                ($TelemetryData.System.Disk | Measure-Object FreeSpaceGB -Sum).Sum,
                2
            )
        } else { $null }

        $diskUsedPercent = if ($null -ne $TelemetryData.System.Disk) {
            $diskUsageValues = @($TelemetryData.System.Disk | ForEach-Object {
                    if ($null -ne $_.SizeGB -and [double]$_.SizeGB -gt 0 -and $null -ne $_.FreeSpaceGB) {
                        [math]::Round((([double]$_.SizeGB - [double]$_.FreeSpaceGB) / [double]$_.SizeGB) * 100, 2)
                    }
                })

            if ($diskUsageValues.Count -gt 0) {
                [double](($diskUsageValues | Measure-Object -Maximum).Maximum)
            }
            else {
                $null
            }
        } else { $null }

        $netLatency = $null
        $netModule = $ModuleResults | Where-Object { $_.Module -eq "Network Analysis" }

        if ($null -ne $netModule -and
            $null -ne $netModule.Result -and
            $null -ne $netModule.Result.Connectivity -and
            $null -ne $netModule.Result.Connectivity.AvgLatencyMS) {

            $netLatency = $netModule.Result.Connectivity.AvgLatencyMS
        }

        # -----------------------------
        # Write system info
        # -----------------------------
        $cmd = $connection.CreateCommand()
        $cmd.Transaction = $transaction
        $cmd.CommandText = @"
INSERT INTO system_info
(hostname,cpu_load,memory_free_gb,disk_free_gb,network_latency_ms,timestamp)
VALUES
(@hostname,@cpu,@mem,@disk,@net,datetime('now','utc'));
"@
        $cmd.Parameters.AddWithValue("@hostname", $TelemetryData.Hostname) | Out-Null
        $cmd.Parameters.AddWithValue("@cpu", (ConvertTo-AutoDoctorDbValue -Value $cpuLoad)) | Out-Null
        $cmd.Parameters.AddWithValue("@mem", (ConvertTo-AutoDoctorDbValue -Value $memFree)) | Out-Null
        $cmd.Parameters.AddWithValue("@disk", (ConvertTo-AutoDoctorDbValue -Value $diskFree)) | Out-Null
        $cmd.Parameters.AddWithValue("@net", (ConvertTo-AutoDoctorDbValue -Value $netLatency)) | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null

        $cmd = $connection.CreateCommand()
        $cmd.Transaction = $transaction
        $cmd.CommandText = @"
INSERT INTO telemetry_trends
(timestamp,cpu,memory,disk,network)
VALUES
(datetime('now','utc'),@cpu,@memory,@disk,@network);
"@
        $cmd.Parameters.AddWithValue("@cpu", (ConvertTo-AutoDoctorDbValue -Value $cpuLoad)) | Out-Null
        $cmd.Parameters.AddWithValue("@memory", (ConvertTo-AutoDoctorDbValue -Value $memUsedPercent)) | Out-Null
        $cmd.Parameters.AddWithValue("@disk", (ConvertTo-AutoDoctorDbValue -Value $diskUsedPercent)) | Out-Null
        $cmd.Parameters.AddWithValue("@network", (ConvertTo-AutoDoctorDbValue -Value $netLatency)) | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null

        Update-AutoDoctorTelemetryBaselines -Connection $connection -Transaction $transaction -Hostname $TelemetryData.Hostname

        $transaction.Commit()
        $connection.Close()
    }
    catch {
        if ($transaction) { $transaction.Rollback() }
        Write-Warning "Telemetry DB write failed: $($_.Exception.Message)"
    }
}

function Write-AutoDoctorAlerts {

    param([array]$ModuleResults)

    $rootModule = $ModuleResults | Where-Object Module -eq "Root Cause Analysis"

    if (-not $rootModule) { return }

    $findings = if ($rootModule.Result.Details.Findings) {
        @($rootModule.Result.Details.Findings)
    }
    else {
        @()
    }

    $issues = if ($findings.Count -gt 0) {
        $findings
    }
    elseif ($rootModule.Result.Details.DetectedIssues) {
        @($rootModule.Result.Details.DetectedIssues)
    }
    else {
        @()
    }

    if (-not $issues -or $issues.Count -eq 0) { return }

    try {

        $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$Global:AutoDoctorDBPath;Version=3;")
        $connection.Open()

        $transaction = $connection.BeginTransaction()

        foreach ($issue in $issues) {

            $severity = "Warning"
            $message = $issue
            $alertType = "RootCause"

            if ($issue -is [psobject]) {
                if ($issue.Severity) { $severity = [string]$issue.Severity }
                if ($issue.Message) { $message = [string]$issue.Message }
                if ($issue.Category) { $alertType = [string]$issue.Category }
            }
            else {
                if ($issue -match "disk failure") { $severity = "Critical" }
                elseif ($issue -match "Low disk space") { $severity = "Critical" }
            }

            $cmd = $connection.CreateCommand()
            $cmd.Transaction = $transaction

            $cmd.CommandText = @"
INSERT INTO alerts
(run_id,hostname,alert_type,severity,message,timestamp)
VALUES
(@runid,@hostname,@type,@severity,@message,datetime('now','utc'));
"@

            $cmd.Parameters.AddWithValue("@runid", $Global:AutoDoctorRunID) | Out-Null
            $cmd.Parameters.AddWithValue("@hostname", $env:COMPUTERNAME) | Out-Null
            $cmd.Parameters.AddWithValue("@type", $alertType) | Out-Null
            $cmd.Parameters.AddWithValue("@severity", $severity) | Out-Null
            $cmd.Parameters.AddWithValue("@message", $message) | Out-Null

            $cmd.ExecuteNonQuery() | Out-Null
        }

        $transaction.Commit()
        $connection.Close()
    }
    catch {
        if ($transaction) { $transaction.Rollback() }
        Write-Warning "Alert DB write failed: $($_.Exception.Message)"
    }
}
