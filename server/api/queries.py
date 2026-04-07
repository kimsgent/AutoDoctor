def get_latest_system(conn):
    cur = conn.cursor()

    cur.execute("""
    SELECT hostname, cpu_load, memory_free_gb, disk_free_gb, network_latency_ms, timestamp
    FROM system_info
    ORDER BY timestamp DESC
    LIMIT 1
    """)

    row = cur.fetchone()
    return dict(row) if row else {}


def get_system_history(conn):

    cur = conn.cursor()

    cur.execute("""
    SELECT timestamp, cpu_load, memory_free_gb, disk_free_gb, network_latency_ms
    FROM system_info
    ORDER BY timestamp ASC
    LIMIT 500
    """)

    rows = cur.fetchall()

    return [dict(r) for r in rows]


def get_alert_summary(conn):

    cur = conn.cursor()

    cur.execute("""
    SELECT severity, COUNT(*) as count
    FROM alerts
    GROUP BY severity
    """)

    return [dict(r) for r in cur.fetchall()]


def get_health_trend(conn):

    cur = conn.cursor()

    cur.execute("""
    SELECT timestamp, health_score
    FROM diagnostics
    WHERE health_score IS NOT NULL
      AND module_name = 'Root Cause Analysis'
    ORDER BY timestamp ASC
    LIMIT 500
    """)

    return [dict(r) for r in cur.fetchall()]


def get_module_status(conn):

    cur = conn.cursor()

    cur.execute("""
    SELECT module_name,
           SUM(CASE WHEN status='Success' THEN 1 ELSE 0 END) as success,
           SUM(CASE WHEN status!='Success' THEN 1 ELSE 0 END) as failed
    FROM telemetry_modules
    GROUP BY module_name
    """)

    return [dict(r) for r in cur.fetchall()]
