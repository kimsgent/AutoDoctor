import sqlite3
import os
from pathlib import Path

# ------------------------------------------------
# Resolve AutoDoctor DB path (same logic as config.ps1)
# ------------------------------------------------

def resolve_db_path():

    # 1. Explicit DB override
    env_db = os.getenv("AUTO_DOCTOR_DB_PATH")
    if env_db:
        return Path(env_db)

    # 2. Root override
    env_home = os.getenv("AUTO_DOCTOR_HOME")
    if env_home:
        return Path(env_home) / "db" / "autodoctor.db"

    # 3. Default ProgramData location
    program_data = os.getenv("PROGRAMDATA", r"C:\ProgramData")
    return Path(program_data) / "AutoDoctor" / "db" / "autodoctor.db"


DB_PATH = resolve_db_path()


def get_connection():

    if not DB_PATH.exists():
        raise RuntimeError(f"AutoDoctor database not found: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)

    # ------------------------------------------------
    # SQLite PERFORMANCE SETTINGS
    # ------------------------------------------------
    # NOTES:
    # WAL mode allows concurrent reads/writes which
    # is critical when the agent writes telemetry while
    # the dashboard queries the database.
    #
    # busy_timeout prevents immediate "database locked"
    # errors when concurrent operations occur.

    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA busy_timeout=5000;")

    # return rows as dictionaries
    conn.row_factory = sqlite3.Row

    return conn
