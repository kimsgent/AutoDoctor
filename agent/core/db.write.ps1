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

        $cpuLoad = if ($TelemetryData.System.CPU.CurrentLoad) {
            [math]::Round($TelemetryData.System.CPU.CurrentLoad, 2)
        }
        else { $null }

        $memFree = if ($TelemetryData.System.Memory.FreeGB) {
            [math]::Round($TelemetryData.System.Memory.FreeGB, 2)
        }
        else { $null }

        $diskFree = if ($TelemetryData.System.Disk) {
            [math]::Round(($TelemetryData.System.Disk | Measure-Object FreeSpaceGB -Sum).Sum, 2)
        }
        else { $null }

        $netLatency = 0
        $netModule = $ModuleResults | Where-Object { $_.Module -eq "Network Analysis" }

        if ($netModule -and $netModule.Result -and $netModule.Result.Connectivity) {
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
        $cmd.Parameters.AddWithValue("@cpu", $cpuLoad) | Out-Null
        $cmd.Parameters.AddWithValue("@mem", $memFree) | Out-Null
        $cmd.Parameters.AddWithValue("@disk", $diskFree) | Out-Null
        $cmd.Parameters.AddWithValue("@net", $netLatency) | Out-Null
        $cmd.ExecuteNonQuery() | Out-Null

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

    $issues = $rootModule.Result.Details.DetectedIssues

    if (-not $issues -or $issues.Count -eq 0) { return }

    try {

        $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$Global:AutoDoctorDBPath;Version=3;")
        $connection.Open()

        $transaction = $connection.BeginTransaction()

        foreach ($issue in $issues) {

            $severity = "Warning"

            if ($issue -match "disk failure") { $severity = "Critical" }
            elseif ($issue -match "Low disk space") { $severity = "Critical" }

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
            $cmd.Parameters.AddWithValue("@type", "RootCause") | Out-Null
            $cmd.Parameters.AddWithValue("@severity", $severity) | Out-Null
            $cmd.Parameters.AddWithValue("@message", $issue) | Out-Null

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
