import uvicorn
import os
import configparser
import winreg
import sys

# ------------------------------------------------
# Resolve AutoDoctor root
# Priority:
# 1 Environment variable
# 2 Project relative path (development)
# 3 Default ProgramData (production install)
# ------------------------------------------------

AUTO_DOCTOR_HOME = os.environ.get("AUTO_DOCTOR_HOME")

if not AUTO_DOCTOR_HOME:

    script_dir = os.path.dirname(os.path.abspath(__file__))
    server_root = os.path.abspath(os.path.join(script_dir, ".."))      # .../server
    project_root = os.path.abspath(os.path.join(script_dir, "..", ".."))  # .../AutoDoctor

    # Ensure imports work for "api.app:app" and repo-local modules.
    if server_root not in sys.path:
        sys.path.insert(0, server_root)
    if project_root not in sys.path:
        sys.path.insert(0, project_root)

    if os.path.exists(os.path.join(project_root, "agent")):
        # Development environment
        AUTO_DOCTOR_HOME = project_root
    else:
        # Installed environment
        AUTO_DOCTOR_HOME = os.path.join(
            os.environ.get("ProgramData", r"C:\ProgramData"),
            "AutoDoctor"
        )
else:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    server_root = os.path.abspath(os.path.join(script_dir, ".."))
    if server_root not in sys.path:
        sys.path.insert(0, server_root)

# Export resolved home for dependent modules (database.py/app.py).
os.environ["AUTO_DOCTOR_HOME"] = AUTO_DOCTOR_HOME

AUTO_DOCTOR_PATHS = {
    "Root": AUTO_DOCTOR_HOME,
    "DB": os.path.join(AUTO_DOCTOR_HOME, "db"),
    "Reports": os.path.join(AUTO_DOCTOR_HOME, "reports"),
    "Telemetry": os.path.join(AUTO_DOCTOR_HOME, "telemetry"),
    "Diagnostics": os.path.join(AUTO_DOCTOR_HOME, "diagnostics"),
    "Logs": os.path.join(AUTO_DOCTOR_HOME, "logs"),
    "Config": os.path.join(AUTO_DOCTOR_HOME, "config"),
    "Dashboard": os.path.join(AUTO_DOCTOR_HOME, "server"),
}

AUTO_DOCTOR_DB_PATH = os.environ.get(
    "AUTO_DOCTOR_DB_PATH",
    os.path.join(AUTO_DOCTOR_PATHS["DB"], "autodoctor.db")
)

# ------------------------------------------------
# Ensure directories exist (equivalent to Initialize-AutoDoctorPaths)
# ------------------------------------------------
# Ensure dashboard folder exists
os.makedirs(AUTO_DOCTOR_PATHS["Dashboard"], exist_ok=True)

# Tell FastAPI where the latest_run.json will be
os.environ["AUTO_DOCTOR_META_JSON"] = os.path.join(
    AUTO_DOCTOR_PATHS["Dashboard"], "latest_run.json"
)

# ------------------------------------------------
# Read Windows Registry
# ------------------------------------------------
def get_registry_value(name, default=None):
    try:
        key = winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE,
            r"Software\AutoDoctor",
            0,
            winreg.KEY_READ | winreg.KEY_WOW64_64KEY,
        )
        value, _ = winreg.QueryValueEx(key, name)
        return value
    except Exception:
        return default


# ------------------------------------------------
# Read INI config
# ------------------------------------------------
def read_config_file():
    config_candidates = [
        os.environ.get("AUTO_DOCTOR_CONFIG_INI"),
        os.path.join(AUTO_DOCTOR_PATHS["Config"], "autodoctor.ini"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "autodoctor.ini"),
    ]

    config = configparser.ConfigParser()

    for ini_path in config_candidates:
        if not ini_path or not os.path.exists(ini_path):
            continue

        config.read(ini_path)

        host = config.get("Server", "host", fallback=None)
        port = config.getint("Server", "port", fallback=None)

        return host, port

    return None, None


# ------------------------------------------------
# Resolve configuration
# Priority:
# 1 Registry
# 2 INI
# 3 Environment
# 4 Defaults
# ------------------------------------------------
host = get_registry_value("APIHost", None)
port = get_registry_value("APIPort", None)

if not host or not port:
    ini_host, ini_port = read_config_file()
    host = host or ini_host
    port = port or ini_port

host = host or os.environ.get("AUTO_DOCTOR_API_HOST", "127.0.0.1")
port = int(port or os.environ.get("AUTO_DOCTOR_API_PORT", 8000))


def load_asgi_app():
    try:
        from api.app import app
    except ModuleNotFoundError as exc:
        if exc.name != "api":
            raise

        from app import app

    return app


# ------------------------------------------------
# Start FastAPI
# ------------------------------------------------
if __name__ == "__main__":
    uvicorn.run(
        load_asgi_app(),
        host=host,
        port=port,
        log_level="info",
        reload=False
    )
