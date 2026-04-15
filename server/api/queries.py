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


def ensure_list(value):
    if value is None:
        return []

    if isinstance(value, list):
        return value

    return [value]


def map_domain(category):
    normalized = (category or "").strip().lower()

    if normalized == "cpu":
        return "CPU pressure"
    if normalized == "memory":
        return "Memory pressure"
    if normalized == "disk":
        return "Disk pressure"
    if normalized == "network":
        return "Network health"
    if normalized in ("software", "drivers"):
        return "Data quality"
    if normalized == "events":
        return "System events"

    return "General diagnostics"


def build_dashboard_summary(report, meta=None):
    meta = meta or {}
    root_details = (report or {}).get("RootCauseDetails") or {}
    metric_states = ensure_list(root_details.get("MetricStates"))
    score_breakdown = root_details.get("ScoreBreakdown") or {}
    score_categories = ensure_list(score_breakdown.get("Categories"))
    score_findings = ensure_list(score_breakdown.get("Findings"))
    findings = ensure_list(root_details.get("Findings"))

    grouped_findings = {}
    for finding in findings:
        domain = map_domain(finding.get("Category"))
        grouped_findings.setdefault(domain, []).append(finding)

    primary_driver = score_categories[0] if score_categories else None
    stable_components = [
        {"metric": item.get("Metric"), "state": item.get("State")}
        for item in metric_states
        if item.get("State") in ("Stable", "Decreasing")
    ]

    main_concern = None
    concerning_metric = next((item for item in metric_states if item.get("State") not in ("Stable", "Decreasing")), None)
    if concerning_metric:
        main_concern = f"{concerning_metric.get('Metric')} {concerning_metric.get('State')}"
    elif primary_driver:
        main_concern = primary_driver.get("Category")
    else:
        main_concern = "System stable"

    supporting_factors = []
    if primary_driver:
        supporting_factors.extend(
            [finding.get("Message") for finding in ensure_list(primary_driver.get("Findings"))[:3] if finding.get("Message")]
        )
    if not supporting_factors:
        supporting_factors.extend([finding.get("Message") for finding in findings[:3] if finding.get("Message")])

    window = ((root_details.get("HistoricalAnalysis") or {}).get("TrendWindow")) or {}

    return {
        "run_id": meta.get("run_id"),
        "host_name": meta.get("host_name"),
        "generated_time": meta.get("generated_time"),
        "health": {
            "numeric": ((report or {}).get("HealthScore") or {}).get("Numeric"),
            "display": ((report or {}).get("HealthScore") or {}).get("Display"),
            "summary": (report or {}).get("RootCauseAnalysis"),
            "main_concern": main_concern,
        },
        "window": {
            "label": window.get("WindowLabel"),
            "used_fallback": window.get("UsedFallback"),
            "historical_samples": window.get("HistoricalSamples"),
            "minimum_samples": window.get("MinimumSamples"),
            "fallback_reason": window.get("FallbackReason"),
        },
        "metric_states": metric_states,
        "why_health_changed": {
            "primary_driver": primary_driver,
            "supporting_factors": supporting_factors[:3],
            "stable_components": stable_components,
            "score_findings": score_findings[:6],
        },
        "latest_findings": findings[:6],
        "findings_by_domain": [
            {"domain": domain, "findings": items[:6]}
            for domain, items in grouped_findings.items()
        ],
    }
