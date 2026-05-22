"""
AutoDoctor Windows Service Module
---------------------------------

This module implements the AutoDoctor Telemetry API as a Windows Service.

Responsibilities:
- Resolves runtime environment (paths, config, execution mode)
- Launches and supervises the AutoDoctor API process
- Ensures the API runs continuously in the background
- Handles clean startup, shutdown, and failure scenarios
- Provides logging for diagnostics and troubleshooting

Service Behavior:
- Starts the AutoDoctor API using either a bundled executable or system Python
- Runs silently in the background without user interaction
- Terminates the child process gracefully on service stop
- Falls back safely if configuration or runtime paths are missing

Operational Impact:
- Required for AutoDoctor monitoring, telemetry collection, and API access
- If stopped or disabled, no system metrics will be collected or exposed
- Dependent tools, dashboards, or integrations relying on AutoDoctor will fail

Configuration:
- Controlled via environment variables and autodoctor.ini
- Supports "bundled" and "system_python" execution modes

Logs:
- Written to: <AUTO_DOCTOR_HOME>/logs/autodoctor_api.log
"""

import win32serviceutil
import win32service
import win32event
import servicemanager
import subprocess
import sys
import os
import time
import traceback
import logging
import configparser


def should_start_service_dispatcher(argv=None):
    if argv is None:
        argv = sys.argv

    return getattr(sys, "frozen", False) and len(argv) == 1


def ensure_child_process_running(process, launch_cmd, grace_seconds=2.0):
    deadline = time.monotonic() + grace_seconds

    while time.monotonic() < deadline:
        exit_code = process.poll()

        if exit_code is not None:
            raise RuntimeError(
                "API process exited during startup with code "
                f"{exit_code}: {' '.join(launch_cmd)}"
            )

        time.sleep(0.1)

    exit_code = process.poll()

    if exit_code is not None:
        raise RuntimeError(
            "API process exited during startup with code "
            f"{exit_code}: {' '.join(launch_cmd)}"
        )


def get_runtime_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))

    return os.path.dirname(os.path.abspath(__file__))


def resolve_auto_root(api_dir):
    configured_root = os.environ.get("AUTO_DOCTOR_HOME")

    if configured_root:
        return os.path.abspath(configured_root)

    candidate_root = os.path.abspath(os.path.join(api_dir, "..", ".."))

    if os.path.isdir(os.path.join(candidate_root, "agent")):
        return candidate_root

    return os.path.join(
        os.environ.get("ProgramData", r"C:\ProgramData"),
        "AutoDoctor"
    )


def resolve_runtime_paths():
    runtime_dir = get_runtime_dir()
    api_dir = os.path.abspath(os.environ.get("AUTO_DOCTOR_API_DIR", runtime_dir))
    auto_root = resolve_auto_root(api_dir)
    config_ini = os.environ.get(
        "AUTO_DOCTOR_CONFIG_INI",
        os.path.join(auto_root, "config", "autodoctor.ini")
    )
    api_exe = os.environ.get(
        "AUTO_DOCTOR_API_EXE",
        os.path.join(api_dir, "autodoctor_api.exe")
    )
    run_script = os.path.join(api_dir, "run_autodoctor.py")

    return {
        "runtime_dir": runtime_dir,
        "api_dir": api_dir,
        "auto_root": auto_root,
        "config_ini": config_ini,
        "api_exe": os.path.abspath(api_exe),
        "run_script": run_script,
        "is_frozen": getattr(sys, "frozen", False),
    }


def resolve_service_mode(config_ini_path):
    default_mode = "bundled"

    if not config_ini_path or not os.path.isfile(config_ini_path):
        return default_mode

    parser = configparser.ConfigParser()

    try:
        parser.read(config_ini_path, encoding="utf-8")
        mode = parser.get("Service", "mode", fallback=default_mode).strip().lower()

        if mode in ("bundled", "system_python"):
            return mode
    except Exception:
        return default_mode

    return default_mode


class AutoDoctorAPIService(win32serviceutil.ServiceFramework):
    _svc_name_ = "AutoDoctorAPI"
    _svc_display_name_ = "AutoDoctor Telemetry API"
    _svc_description_ = (
        "Hosts the AutoDoctor Telemetry API, enabling continuous system monitoring, "
        "diagnostics collection, and external health queries. The service launches and "
        "manages the AutoDoctor API process in the background. If this service is stopped "
        "or disabled, AutoDoctor will be unable to collect or expose system telemetry, "
        "and any dependent monitoring, automation, or integration features may fail."
    )

    def __init__(self, args):
        win32serviceutil.ServiceFramework.__init__(self, args)
        # Manual reset event, initially non-signaled
        self.stop_event = win32event.CreateEvent(None, True, False, None)
        self.process = None

    # ------------------------------------------------
    # SERVICE START
    # ------------------------------------------------
    def SvcDoRun(self):

        servicemanager.LogInfoMsg("AutoDoctorAPI: service starting")
        self.ReportServiceStatus(win32service.SERVICE_START_PENDING)

        try:
            runtime_paths = resolve_runtime_paths()
            auto_root = runtime_paths["auto_root"]
            script_dir = runtime_paths["api_dir"]
            run_script = runtime_paths["run_script"]
            api_exe = runtime_paths["api_exe"]

            logs_dir = os.path.join(auto_root, "logs")
            os.makedirs(logs_dir, exist_ok=True)

            log_file = os.path.join(logs_dir, "autodoctor_api.log")

            logging.basicConfig(
                filename=log_file,
                level=logging.INFO,
                format="%(asctime)s [%(levelname)s] %(message)s",
            )

            logging.info("==== AutoDoctor API Service Startup ====")

            python_exe = os.path.join(os.path.dirname(sys.executable), "python.exe")

            if not os.path.exists(python_exe):
                python_exe = sys.executable

            child_env = os.environ.copy()
            child_env["AUTO_DOCTOR_HOME"] = auto_root
            child_env["AUTO_DOCTOR_API_DIR"] = script_dir
            child_env["AUTO_DOCTOR_CONFIG_INI"] = runtime_paths["config_ini"]
            service_mode = resolve_service_mode(runtime_paths["config_ini"])

            logging.info(f"AUTO_DOCTOR_HOME: {auto_root}")
            logging.info(f"is_frozen: {runtime_paths['is_frozen']}")
            logging.info(f"runtime_dir: {runtime_paths['runtime_dir']}")
            logging.info(f"script_dir: {script_dir}")
            logging.info(f"service_mode: {service_mode}")
            logging.info(f"api_executable: {api_exe}")
            logging.info(f"run_script: {run_script}")
            logging.info(f"python_executable: {python_exe}")
            logging.info(f"api_executable_exists: {os.path.isfile(api_exe)}")
            logging.info(f"script_exists: {os.path.isfile(run_script)}")

            launch_cmd = None

            # In system_python mode, prefer source startup so API runtime
            # follows the selected interpreter instead of bundled binaries.
            if service_mode == "system_python":
                if os.path.isfile(run_script):
                    launch_cmd = [python_exe, run_script]
                elif os.path.isfile(api_exe):
                    launch_cmd = [api_exe]
            elif os.path.isfile(api_exe):
                launch_cmd = [api_exe]
            elif os.path.isfile(run_script):
                launch_cmd = [python_exe, run_script]
            else:
                raise FileNotFoundError(
                    f"Neither autodoctor_api.exe nor run_autodoctor.py were found in {script_dir}"
                )

            # ------------------------------------------------
            # Start API process
            # ------------------------------------------------
            assert launch_cmd is not None
            self.process = subprocess.Popen(
                launch_cmd,
                cwd=script_dir,
                env=child_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )

            ensure_child_process_running(self.process, launch_cmd)
            logging.info("AutoDoctor API process started")

        except Exception as e:

            msg = "AutoDoctorAPI: Failed to start API process: " + repr(e)

            logging.error(msg)
            logging.error(traceback.format_exc())

            servicemanager.LogErrorMsg(msg)
            servicemanager.LogErrorMsg(traceback.format_exc())

            self.ReportServiceStatus(
                win32service.SERVICE_STOPPED,
                win32service.SERVICE_ERROR_NORMAL,
            )
            return

        # ------------------------------------------------
        # Service running
        # ------------------------------------------------

        self.ReportServiceStatus(win32service.SERVICE_RUNNING)

        servicemanager.LogInfoMsg("AutoDoctorAPI: service running")
        logging.info("Service status RUNNING")

        win32event.WaitForSingleObject(self.stop_event, win32event.INFINITE)

        logging.info("Stop signal received")

        self._cleanup_process()

        logging.info("AutoDoctor API stopped")
        servicemanager.LogInfoMsg("AutoDoctorAPI: service main loop exited")

    # ------------------------------------------------
    # SERVICE STOP
    # ------------------------------------------------
    def SvcStop(self):
        servicemanager.LogInfoMsg("AutoDoctorAPI: service stopping")

        # Notify SCM that we are stopping
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)

        # Signal main loop and terminate the child
        win32event.SetEvent(self.stop_event)
        self._cleanup_process()

        # Now report stopped
        self.ReportServiceStatus(win32service.SERVICE_STOPPED)
        servicemanager.LogInfoMsg("AutoDoctorAPI: service stopped")

    # ------------------------------------------------
    # INTERNAL HELPERS
    # ------------------------------------------------
    def _cleanup_process(self):
        """Terminate child process if running."""
        if self.process is None:
            return

        try:
            if self.process.poll() is None:
                # Still running; terminate and wait a bit
                self.process.terminate()
                try:
                    self.process.wait(timeout=15)
                except Exception:
                    # If it still refuses to die, kill it
                    self.process.kill()
        except Exception as e:
            servicemanager.LogErrorMsg(
                f"AutoDoctorAPI: error stopping child process: {repr(e)}"
            )
        finally:
            self.process = None


def main(argv=None):
    if argv is None:
        argv = sys.argv

    if should_start_service_dispatcher():
        servicemanager.Initialize()
        servicemanager.PrepareToHostSingle(AutoDoctorAPIService)
        servicemanager.StartServiceCtrlDispatcher()
        return 0

    return win32serviceutil.HandleCommandLine(AutoDoctorAPIService, argv=argv)


if __name__ == "__main__":
    sys.exit(main())
