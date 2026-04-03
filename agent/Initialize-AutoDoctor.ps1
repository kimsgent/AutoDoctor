<#
Initializes AutoDoctor paths, schema, and a first non-remediating telemetry run.
This is intended for installer/bootstrap use so the dashboard has data immediately
without running the full self-healing workflow during setup.
#>

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Start-Process powershell `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\core\config.ps1"
Initialize-AutoDoctorPaths

if (-not $Global:AutoDoctorLogFile) {
    throw "AutoDoctorLogFile path not initialized"
}

. "$PSScriptRoot\core\localization.ps1"
Initialize-AutoDoctorLocalization | Out-Null

. "$PSScriptRoot\core\db.ps1"
. "$PSScriptRoot\core\db.write.ps1"
. "$PSScriptRoot\core\engine.ps1"

Initialize-AutoDoctorDatabase

function Invoke-Safe {
    param([scriptblock]$Script)

    try {
        & $Script
    }
    catch {
        Write-Warning $_.Exception.Message
        return $null
    }
}

try {
    $ScriptStart = Get-Date
    $Global:AutoDoctorRunID = "{0}-{1}-bootstrap" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $env:COMPUTERNAME

    # Ensure a clean module registry for repeated bootstrap runs.
    $Global:AutoDoctorModules = @()

    Get-ChildItem "$PSScriptRoot\modules\*.ps1" |
        Sort-Object Name |
        Where-Object { $_.BaseName -ne "remediation" } |
        ForEach-Object { . $_.FullName }

    $global:ModuleResults = Invoke-AutoDoctorModules -ScriptStart $ScriptStart

    Write-AutoDoctorDiagnostics -ModuleResults $global:ModuleResults

    . "$PSScriptRoot\core\telemetry.ps1"

    $telemetryResult = Invoke-AutoDoctorTelemetryCollection -ModuleResults $global:ModuleResults

    if (-not $telemetryResult) {
        Write-Warning "Telemetry collection did not produce data during bootstrap. Database sync skipped."
    }
    else {
        Write-AutoDoctorTelemetry -ModuleResults $global:ModuleResults
    }

    Write-AutoDoctorAlerts -ModuleResults $global:ModuleResults

    $meta = @{
        run_id         = $Global:AutoDoctorRunID
        host_name      = $env:COMPUTERNAME
        generated_time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    $metaJson = $meta | ConvertTo-Json
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Global:AutoDoctorMetaJSON, $metaJson, $utf8NoBom)

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Installer bootstrap completed successfully." |
        Out-File $Global:AutoDoctorLogFile -Append
}
catch {
    $msg = "Installer bootstrap failed: $($_.Exception.Message)"

    Write-Warning $msg

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" |
        Out-File $Global:AutoDoctorLogFile -Append

    throw
}
