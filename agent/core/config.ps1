# ------------------------------------------------
# AutoDoctor Global Configuration
# Centralized path configuration
#
# Override supported via:
# AUTO_DOCTOR_HOME
# AUTO_DOCTOR_DB_PATH
#
# Example:
# $env:AUTO_DOCTOR_HOME = "D:\Monitoring\AutoDoctor"
# ------------------------------------------------

# ------------------------------------------------
# Determine root directory
# Priority:
# 1 Environment variable
# 2 Project relative path (development mode)
# 3 Default ProgramData (production install)
# ------------------------------------------------

if ($env:AUTO_DOCTOR_HOME) {

    $Global:AutoDoctorRoot = $env:AUTO_DOCTOR_HOME

}
else {

    # Detect project root relative to this script
    $projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

    if (Test-Path (Join-Path $projectRoot "agent")) {

        # Development environment
        $Global:AutoDoctorRoot = $projectRoot

    }
    else {

        # Installed environment
        $Global:AutoDoctorRoot = Join-Path $env:ProgramData "AutoDoctor"

    }

}

# ------------------------------------------------
# Subdirectories
# ------------------------------------------------

$Global:AutoDoctorPaths = @{
    Root        = $Global:AutoDoctorRoot
    DB          = Join-Path $Global:AutoDoctorRoot "db"
    Cache       = Join-Path $Global:AutoDoctorRoot "cache"
    Reports     = Join-Path $Global:AutoDoctorRoot "reports"
    Telemetry   = Join-Path $Global:AutoDoctorRoot "telemetry"
    Diagnostics = Join-Path $Global:AutoDoctorRoot "diagnostics"
    Logs        = Join-Path $Global:AutoDoctorRoot "logs"
    Config      = Join-Path $Global:AutoDoctorRoot "config"
    Dashboard   = Join-Path $Global:AutoDoctorRoot "server"
}

# ------------------------------------------------
# Files
# ------------------------------------------------

$Global:AutoDoctorDBPath = if ($env:AUTO_DOCTOR_DB_PATH) {
    $env:AUTO_DOCTOR_DB_PATH
}
else {
    Join-Path $Global:AutoDoctorPaths.DB "autodoctor.db"
}

$Global:AutoDoctorReportHTML = Join-Path $Global:AutoDoctorPaths.Reports "AutoDoctor_Report.html"
$Global:AutoDoctorReportJSON = Join-Path $Global:AutoDoctorPaths.Reports "AutoDoctor_Report.json"
$Global:AutoDoctorReportMarkdown = Join-Path $Global:AutoDoctorPaths.Reports "AutoDoctor_Report.md"
$Global:AutoDoctorReportPDF = Join-Path $Global:AutoDoctorPaths.Reports "AutoDoctor_Report.pdf"
$Global:AutoDoctorLogFile = Join-Path $Global:AutoDoctorPaths.Logs "autodoctor.log"
$Global:AutoDoctorConfigINI = Join-Path $Global:AutoDoctorPaths.Config "autodoctor.ini"
$Global:AutoDoctorVersionFile = Join-Path $Global:AutoDoctorRoot "VERSION"
$Global:AutoDoctorMetaJSON = Join-Path $Global:AutoDoctorPaths.Dashboard "latest_run.json"


# ------------------------------------------------
# Ensure directories exist
# ------------------------------------------------

function Initialize-AutoDoctorPaths {

    foreach ($path in $Global:AutoDoctorPaths.Values) {

        if (!(Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

    }

}

# ------------------------------------------------
# Path helper
# ------------------------------------------------

function Get-AutoDoctorPath {
    param([string]$Name)
    return $Global:AutoDoctorPaths[$Name]
}

function Get-AutoDoctorVersion {
    if (Test-Path -LiteralPath $Global:AutoDoctorVersionFile) {
        foreach ($line in Get-Content -LiteralPath $Global:AutoDoctorVersionFile -ErrorAction SilentlyContinue) {
            $trimmed = $line.Trim()

            if ($trimmed) {
                return $trimmed
            }
        }
    }

    return "0.0.0"
}

function Get-AutoDoctorRegistryValue {
    param(
        [string]$Name,
        $Default = $null
    )

    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $subKey = $baseKey.OpenSubKey("Software\AutoDoctor")

        if (-not $subKey) {
            $baseKey.Close()
            return $Default
        }

        $value = $subKey.GetValue($Name, $Default)
        $subKey.Close()
        $baseKey.Close()

        return $value
    }
    catch {
        return $Default
    }
}

function Get-AutoDoctorIniValue {
    param(
        [string]$Section,
        [string]$Key,
        $Default = $null
    )

    if (-not (Test-Path -LiteralPath $Global:AutoDoctorConfigINI)) {
        return $Default
    }

    $currentSection = ""

    foreach ($line in Get-Content -LiteralPath $Global:AutoDoctorConfigINI -ErrorAction SilentlyContinue) {
        $trimmed = $line.Trim()

        if (-not $trimmed -or $trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) {
            continue
        }

        if ($trimmed -match "^\[(.+)\]$") {
            $currentSection = $matches[1].Trim()
            continue
        }

        if ($currentSection -ne $Section) {
            continue
        }

        if ($trimmed -match "^(?<name>[^=]+?)\s*=\s*(?<value>.*)$") {
            if ($matches["name"].Trim() -eq $Key) {
                return $matches["value"].Trim()
            }
        }
    }

    return $Default
}

function Resolve-AutoDoctorAPIConfig {
    # Do not use $host here. PowerShell automatic variable names are case-insensitive,
    # so assigning to $host will attempt to overwrite the read-only $Host variable.
    $apiHost = Get-AutoDoctorRegistryValue -Name "APIHost"
    $port = Get-AutoDoctorRegistryValue -Name "APIPort"

    if (-not $apiHost) {
        $apiHost = Get-AutoDoctorIniValue -Section "Server" -Key "host"
    }

    if (-not $port) {
        $port = Get-AutoDoctorIniValue -Section "Server" -Key "port"
    }

    $apiHost = if ($apiHost) { $apiHost } else { $env:AUTO_DOCTOR_API_HOST }
    $port = if ($port) { $port } else { $env:AUTO_DOCTOR_API_PORT }

    if (-not $apiHost) { $apiHost = "127.0.0.1" }
    if (-not $port) { $port = 8000 }

    try {
        $port = [int]$port
    }
    catch {
        $port = 8000
    }

    $apiHost = [string]$apiHost

    $probeHost = switch ($apiHost.ToLowerInvariant()) {
        "0.0.0.0" { "127.0.0.1" }
        "::" { "127.0.0.1" }
        "[::]" { "127.0.0.1" }
        "*" { "127.0.0.1" }
        "+" { "127.0.0.1" }
        default { $apiHost }
    }

    [PSCustomObject]@{
        Host       = $apiHost
        Port       = [int]$port
        ProbeHost  = $probeHost
        BaseUrl    = "http://{0}:{1}" -f $probeHost, $port
        HealthUrl  = "http://{0}:{1}/health" -f $probeHost, $port
        ConfigPath = $Global:AutoDoctorConfigINI
    }
}
