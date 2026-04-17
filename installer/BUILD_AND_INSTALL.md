# AutoDoctor Build and Install Guide

This packaging flow is designed for the current AutoDoctor runtime model:

- Development mode runs from the repo root.
- Installed mode runs from a writable root at `C:\ProgramData\AutoDoctor`.
- The agent, API, dashboard assets, logs, telemetry, reports, and SQLite DB stay under the same installed root.

This is intentional. AutoDoctor writes logs, reports, telemetry, metadata, and the database under its root, so installing into `Program Files` is less stable unless the codebase is redesigned around a split binary/data layout.

## Single Version Source

Update only this file when releasing a new build:

```text
AutoDoctor\VERSION
```

The build script, API health endpoint, telemetry payloads, and installer version all read from that single file.

## Prerequisites

Run all build steps on a Windows x64 machine.

- Python 3.12 x64
- PowerShell 5.1 or newer
- Inno Setup 6
- Visual C++ runtime if your Python environment needs it

Install build dependencies:

```powershell
py -3.12 -m pip install --upgrade pip
py -3.12 -m pip install pyinstaller fastapi uvicorn pywin32
```

## One-Command Build

Run the full PyInstaller + Inno Setup pipeline from the repository root:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\AutoDoctor\installer\Build-AutoDoctor.ps1
```

Optional variants:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\AutoDoctor\installer\Build-AutoDoctor.ps1 -SkipInstaller
```

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\AutoDoctor\installer\Build-AutoDoctor.ps1 -ISCCPath "C:\Users\Franklin\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
```

The script will:

- read `AutoDoctor\VERSION`
- generate Windows version resources for both EXEs
- build `autodoctor_api.exe`
- build `autodoctor_service` (one-dir service bundle)
- compile `AutoDoctorInstaller_<version>.exe` unless `-SkipInstaller` is used

## Manual Build Steps

If you want to run each stage yourself, use the commands below.
The one-command build script remains the recommended release path because it also applies Windows EXE version stamping and passes the same version into Inno Setup automatically.

## Build the PyInstaller EXEs

Run these commands from the repository root:

```powershell
py -3.12 -m PyInstaller `
  --noconfirm `
  --clean `
  --onefile `
  --distpath AutoDoctor\build\dist `
  --workpath AutoDoctor\build\work `
  --specpath AutoDoctor\build `
  --name autodoctor_api `
  --collect-submodules fastapi `
  --collect-submodules starlette `
  --collect-submodules uvicorn `
  AutoDoctor\server\api\run_autodoctor.py
```

```powershell
py -3.12 -m PyInstaller `
  --noconfirm `
  --clean `
  --onedir `
  --distpath AutoDoctor\build\dist `
  --workpath AutoDoctor\build\work `
  --specpath AutoDoctor\build `
  --name autodoctor_service `
  --hidden-import servicemanager `
  --hidden-import win32timezone `
  AutoDoctor\server\api\autodoctor_service.py
```

Expected output:

```text
AutoDoctor\build\dist\autodoctor_api.exe
AutoDoctor\build\dist\autodoctor_service\autodoctor_service.exe
AutoDoctor\build\dist\autodoctor_service\_internal\...
```

## Smoke Test Before Building the Installer

### 1. Test the compiled API directly

```powershell
$env:AUTO_DOCTOR_HOME = (Resolve-Path .\AutoDoctor).Path
$env:AUTO_DOCTOR_CONFIG_INI = Join-Path $env:AUTO_DOCTOR_HOME "config\autodoctor.ini"

Start-Process .\AutoDoctor\build\dist\autodoctor_api.exe
Start-Sleep -Seconds 3
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected result:

```text
status  : ok
service : AutoDoctor API
version : value from AutoDoctor\VERSION
```

Stop the process manually after the check if needed.

### 2. Seed the local development DB safely

This creates schema and a first non-remediating snapshot without running the self-healing module.

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\AutoDoctor\agent\Initialize-AutoDoctor.ps1
```

Verify the expected files now exist:

```powershell
Get-Item .\AutoDoctor\db\autodoctor.db
Get-Item .\AutoDoctor\server\latest_run.json
Get-ChildItem .\AutoDoctor\telemetry
```

### 3. Optional service-wrapper smoke test in console mode

This verifies that the compiled service wrapper can launch the compiled API executable.

```powershell
$env:AUTO_DOCTOR_HOME = (Resolve-Path .\AutoDoctor).Path
$env:AUTO_DOCTOR_API_DIR = (Resolve-Path .\AutoDoctor\build\dist\autodoctor_service).Path
$env:AUTO_DOCTOR_CONFIG_INI = Join-Path $env:AUTO_DOCTOR_HOME "config\autodoctor.ini"

.\AutoDoctor\build\dist\autodoctor_service\autodoctor_service.exe debug
```

In a second PowerShell window:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Use `Ctrl+C` in the first window to stop the debug session.

## Build the Installer with Inno Setup

The installer script is:

[`AutoDoctorInstaller.iss`](/Users/gentkims/IT-Diagnostic-Suite/AutoDoctor/installer/AutoDoctorInstaller.iss)

Compile it from PowerShell:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "/DMyAppVersion=$(Get-Content .\AutoDoctor\VERSION -TotalCount 1)" ".\AutoDoctor\installer\AutoDoctorInstaller.iss"
```

Expected output:

```text
AutoDoctor\installer\output\AutoDoctor_Installer_<version>.exe
```

## What the Installer Does

- Installs AutoDoctor under `C:\ProgramData\AutoDoctor`
- Copies:
  - PowerShell agent files
  - dashboard static files
  - Python API source files
  - compiled `autodoctor_api.exe`
  - compiled `autodoctor_service` service bundle (`autodoctor_service.exe` + runtime files)
- Generates `config\autodoctor.ini` dynamically with the final install path
- Creates/updates the `AutoDoctorAPI` Windows service
  - service mode option 1 (default): bundled runtime
  - service mode option 2 (advanced): system Python (`py -3` or `python`)
- Optionally runs `Initialize-AutoDoctor.ps1` to:
  - create schema
  - write first diagnostics
  - write first telemetry and system snapshot
  - write `latest_run.json`

## Service Mode Notes

During setup, the task page now includes `API service installation mode`:

- `Use bundled service runtime (recommended)`
- `Use system Python interpreter (advanced)`

If `system Python` is selected, setup validates:

- Python availability (`py -3` or `python`)
- required packages (`pywin32`, `fastapi`, `uvicorn`)

If validation fails, setup shows a blocking message with next steps:

- install Python for Windows: `https://www.python.org/downloads/windows/`
- install packages: `python -m pip install pywin32 fastapi uvicorn`

## Install and Verify

Run the generated installer as Administrator.

After installation, verify:

```powershell
Get-Service AutoDoctorAPI
Invoke-RestMethod http://127.0.0.1:8000/health
Get-Item C:\ProgramData\AutoDoctor\db\autodoctor.db
Get-Item C:\ProgramData\AutoDoctor\server\latest_run.json
```

Open the dashboard:

```text
http://127.0.0.1:8000/dashboard/
```

Run a full manual diagnostic cycle:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\AutoDoctor\agent\AutoDoctor.ps1"
```

Verify outputs:

```powershell
Get-ChildItem C:\ProgramData\AutoDoctor\reports
Get-ChildItem C:\ProgramData\AutoDoctor\telemetry
Get-Content C:\ProgramData\AutoDoctor\logs\autodoctor.log -Tail 50
```

## Upgrade Flow

To ship a new version:

1. Update source code.
2. Rebuild both PyInstaller executables.
3. Recompile the Inno Setup installer.
4. Run the new installer on the target machine.

The installer will:

1. Stop the existing `AutoDoctorAPI` service before copying files.
2. Replace binaries and scripts.
3. Refresh `autodoctor.ini`.
4. Update the existing service if present, otherwise install it.
5. Start the service again.

## Architecture Notes

- Build the packaged executables on a Windows x64 machine with Python 3.12 x64.
- The installer targets `x64compatible` systems in Inno Setup so it remains valid on 64-bit Windows environments that can run x64 applications, including compatible Windows on ARM configurations.
- If AutoDoctor later ships native ARM64 executables or architecture-specific binaries, revisit the installer architecture policy and the build pipeline together rather than treating the `.iss` file in isolation.

## Notes

- The installer intentionally uses `C:\ProgramData\AutoDoctor` as the install root because the current code writes runtime artifacts under the root path.
- The bootstrap script does not run remediation. It seeds safe initial data only.
- The full agent script still performs remediation and should be treated as an administrative diagnostic tool, not an installer bootstrap action.
