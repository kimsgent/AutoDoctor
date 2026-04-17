from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from database import get_connection
import queries
import os

import datetime
import json
import pathlib
import logging


BASE_DIR = os.path.dirname(os.path.abspath(__file__))  # server/api
DASHBOARD_DIR = os.path.join(BASE_DIR, "..", "dashboard")  # server/dashboard

auto_doctor_home = os.getenv("AUTO_DOCTOR_HOME")
external_dashboard_dir = (
    os.path.join(auto_doctor_home, "server", "dashboard")
    if auto_doctor_home else None
)

if external_dashboard_dir and os.path.isdir(external_dashboard_dir):
    DASHBOARD_DIR = external_dashboard_dir


def resolve_autodoctor_version():
    version_candidates = []

    if auto_doctor_home:
        version_candidates.append(os.path.join(auto_doctor_home, "VERSION"))

    version_candidates.append(os.path.abspath(os.path.join(BASE_DIR, "..", "..", "VERSION")))

    for candidate in version_candidates:
        try:
            with open(candidate, encoding="utf-8") as handle:
                for line in handle:
                    version = line.strip()
                    if version:
                        return version
        except OSError:
            continue

    return "0.0.0"


# ------------------------------------------------
# APPLICATION INITIALIZATION
# ------------------------------------------------
# NOTE:
# Title kept for dashboard compatibility.
# Version is read from the shared VERSION file.

app = FastAPI(title="AutoDoctor Telemetry API", version=resolve_autodoctor_version())


# ------------------------------------------------
# MOUNT DASHBOARD STATIC FILES
# ------------------------------------------------
app.mount("/dashboard", StaticFiles(directory=DASHBOARD_DIR, html=True), name="dashboard")

# ------------------------------------------------
# Path to dashboard metadata JSON
# ------------------------------------------------
META_FILE_ENV = os.getenv("AUTO_DOCTOR_META_JSON")
META_FILE = pathlib.Path(META_FILE_ENV) if META_FILE_ENV else None

logging.basicConfig(level=logging.INFO)
logging.info(f"AUTO_DOCTOR_META_JSON = {META_FILE_ENV}")
logging.info(f"META_FILE exists? {META_FILE.exists() if META_FILE else 'NO META_FILE'}")


def resolve_report_json_file():
    candidates = []

    if auto_doctor_home:
        candidates.append(pathlib.Path(auto_doctor_home) / "reports" / "AutoDoctor_Report.json")

    candidates.append(pathlib.Path(BASE_DIR).resolve().parents[1] / "reports" / "AutoDoctor_Report.json")

    for candidate in candidates:
        if candidate.exists():
            return candidate

    return candidates[0]


REPORT_JSON_FILE = resolve_report_json_file()

# ------------------------------------------------
# CORS CONFIGURATION
# ------------------------------------------------
# NOTES:
# Previous implementation used:
#
# allow_origins=["*"]
#
# which allows any website to call the API from
# a browser. This is unsafe if the service becomes
# network accessible.
#
# New design:
#
# Priority
# 1 ENV variable
# 2 safe localhost defaults
#
# Example ENV usage:
#
# AUTO_DOCTOR_CORS_ORIGINS=http://localhost:8000,http://dashboard.local
#


def resolve_cors_origins():

    env_origins = os.getenv("AUTO_DOCTOR_CORS_ORIGINS")

    if env_origins:
        return [o.strip() for o in env_origins.split(",")]

    return [
        "http://127.0.0.1",
        "http://localhost",
        "http://127.0.0.1:8000",
        "http://localhost:8000",
        "http://127.0.0.1:5500",
        "http://localhost:5500",
    ]


app.add_middleware(
    CORSMiddleware,
    allow_origins=resolve_cors_origins(),
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ------------------------------------------------
# OPTIONAL API KEY SECURITY
# ------------------------------------------------
# NOTES:
# Disabled by default.
#
# If environment variable is set:
#
# AUTO_DOCTOR_API_KEY=your-secret
#
# then requests must include header:
#
# X-AutoDoctor-Key: your-secret
#
# This protects the API in enterprise deployments.
#
# Agent communication is unaffected unless
# the admin intentionally enables this.

API_KEY = os.getenv("AUTO_DOCTOR_API_KEY")


async def verify_api_key(request: Request):

    if not API_KEY:
        return

    key = request.headers.get("X-AutoDoctor-Key")

    if key != API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")


# ------------------------------------------------
# DATABASE HELPER
# ------------------------------------------------
# NOTE:
# Centralized DB handling prevents duplicated code
# and ensures connections always close properly.


def run_query(query_func):

    conn = None

    try:

        conn = get_connection()

        return query_func(conn)

    except Exception as e:

        raise HTTPException(status_code=500, detail=str(e))

    finally:

        if conn:
            conn.close()


def load_dashboard_meta_payload():
    if META_FILE and META_FILE.exists():
        try:
            return json.loads(META_FILE.read_text(encoding="utf-8-sig"))
        except Exception:
            pass

    return {
        "run_id": "unknown",
        "host_name": os.getenv("COMPUTERNAME", "unknown"),
        "generated_time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }


# ------------------------------------------------
# API SERVICE HEALTH ENDPOINT
# ------------------------------------------------
# Used by AutoDoctor agent to verify API availability


@app.get("/health")
async def api_health():
    return {"status": "ok", "service": "AutoDoctor API", "version": app.version}


# ------------------------------------------------
# SYSTEM SNAPSHOT
# ------------------------------------------------


@app.get("/api/system/latest")
async def system_latest(request: Request):

    await verify_api_key(request)

    return run_query(queries.get_latest_system)


# ------------------------------------------------
# SYSTEM HISTORY
# ------------------------------------------------


@app.get("/api/system/history")
async def system_history(request: Request):

    await verify_api_key(request)

    return run_query(queries.get_system_history)


# ------------------------------------------------
# ALERT SUMMARY
# ------------------------------------------------


@app.get("/api/alerts")
async def alerts(request: Request):

    await verify_api_key(request)

    return run_query(queries.get_alert_summary)


# ------------------------------------------------
# HEALTH TREND
# ------------------------------------------------


@app.get("/api/health")
async def health(request: Request):

    await verify_api_key(request)

    return run_query(queries.get_health_trend)


# ------------------------------------------------
# MODULE STATUS
# ------------------------------------------------


@app.get("/api/modules")
async def modules(request: Request):

    await verify_api_key(request)

    return run_query(queries.get_module_status)


# ------------------------------------------------
# Meta endpoint
# ------------------------------------------------
@app.get("/api/dashboard/meta")
async def dashboard_meta(request: Request):
    await verify_api_key(request)  # optional security

    return load_dashboard_meta_payload()


@app.get("/api/dashboard/summary")
async def dashboard_summary(request: Request):
    await verify_api_key(request)

    if not REPORT_JSON_FILE.exists():
        return {
            "run_id": "unknown",
            "host_name": os.getenv("COMPUTERNAME", "unknown"),
            "generated_time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "health": {
                "numeric": 0,
                "display": "Health score not available",
                "summary": "No report data available",
                "main_concern": "No report data available",
            },
            "window": {},
            "metric_states": [],
            "why_health_changed": {
                "primary_driver": None,
                "supporting_factors": [],
                "stable_components": [],
                "score_findings": [],
            },
            "latest_findings": [],
            "findings_by_domain": [],
        }

    try:
        report = json.loads(REPORT_JSON_FILE.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to read report JSON: {exc}")

    meta = load_dashboard_meta_payload()
    return queries.build_dashboard_summary(report, meta=meta)
