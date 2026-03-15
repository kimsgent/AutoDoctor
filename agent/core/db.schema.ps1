function Initialize-AutoDoctorSchema {

    param(
        [System.Data.SQLite.SQLiteConnection]$Connection
    )

    $commands = @()

    $commands += @"
CREATE TABLE IF NOT EXISTS diagnostics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT,
    hostname TEXT,
    module_name TEXT,
    status TEXT,
    runtime_seconds REAL,
    health_score INTEGER,
    summary TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
"@

    $commands += @"
CREATE INDEX IF NOT EXISTS idx_diag_timestamp
ON diagnostics(timestamp);
"@
    $commands += @"
CREATE INDEX IF NOT EXISTS idx_diagnostics_run
ON diagnostics(run_id);
"@


    $commands += @"
CREATE TABLE IF NOT EXISTS remediation (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT,
    hostname TEXT,
    status TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
"@

    $commands += @"
CREATE TABLE IF NOT EXISTS telemetry_modules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT,
    hostname TEXT,
    module_name TEXT,
    status TEXT,
    result_keys TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
"@

    $commands += @"
CREATE INDEX IF NOT EXISTS idx_telemetry_modules_run_module
ON telemetry_modules(run_id, module_name);
"@

    $commands += @"
CREATE TABLE IF NOT EXISTS system_info (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hostname TEXT,
    cpu_load REAL,
    memory_free_gb REAL,
    disk_free_gb REAL,
    network_latency_ms REAL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
"@

    $commands += @"
CREATE INDEX IF NOT EXISTS idx_system_info_timestamp
ON system_info(timestamp);
"@

    $commands += @"
CREATE INDEX IF NOT EXISTS idx_system_info_host_time
ON system_info(hostname, timestamp);
"@

    $commands += @"
CREATE TABLE IF NOT EXISTS alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT,
    hostname TEXT,
    alert_type TEXT,
    severity TEXT,
    message TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
"@

    $commands += @"
CREATE INDEX IF NOT EXISTS idx_alerts_timestamp
ON alerts(timestamp);
"@
    $commands += @"
CREATE INDEX IF NOT EXISTS idx_alerts_severity
ON alerts(severity);
"@

    foreach ($sql in $commands) {

        $cmd = $Connection.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.ExecuteNonQuery() | Out-Null

    }
}
