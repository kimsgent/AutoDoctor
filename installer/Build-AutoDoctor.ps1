<#
Builds the AutoDoctor API executable, service executable, and Inno Setup
installer from a single command. The shared app version is read from
AutoDoctor\VERSION so packaging metadata only needs one update.
#>

[CmdletBinding()]
param(
    [string]$PythonExe,
    [string]$PythonVersion = "3.12",
    [string]$ISCCPath,
    [switch]$SkipInstaller
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:BuildScriptDir = Split-Path -Parent $PSCommandPath

function Get-ProjectPaths {
    $projectRoot = (Resolve-Path (Join-Path $script:BuildScriptDir "..")).Path

    [PSCustomObject]@{
        ScriptDir      = $script:BuildScriptDir
        ProjectRoot    = $projectRoot
        VersionFile    = Join-Path $projectRoot "VERSION"
        BuildRoot      = Join-Path $projectRoot "build"
        DistDir        = Join-Path $projectRoot "build\dist"
        WorkDir        = Join-Path $projectRoot "build\work"
        InstallerDir   = Join-Path $projectRoot "installer"
        InstallerFile  = Join-Path $projectRoot "installer\AutoDoctorInstaller.iss"
        VersionResDir  = Join-Path $projectRoot "build\versioninfo"
        ApiScript      = Join-Path $projectRoot "server\api\run_autodoctor.py"
        ServiceScript  = Join-Path $projectRoot "server\api\autodoctor_service.py"
        IconPath       = Join-Path $projectRoot "server\dashboard\favicon.ico"
        InstallerOut   = Join-Path $projectRoot "installer\output"
    }
}

function Get-AutoDoctorVersion {
    param([string]$VersionFile)

    if (-not (Test-Path -LiteralPath $VersionFile)) {
        throw "Version file not found: $VersionFile"
    }

    foreach ($line in Get-Content -LiteralPath $VersionFile -ErrorAction Stop) {
        $trimmed = $line.Trim()

        if ($trimmed) {
            if ($trimmed -notmatch '^\d+(\.\d+){1,3}$') {
                throw "VERSION must be numeric dotted format, for example 1.1.0 or 1.1.0.0. Found: $trimmed"
            }

            return $trimmed
        }
    }

    throw "VERSION file is empty: $VersionFile"
}

function Get-VersionParts {
    param([string]$Version)

    $parts = @($Version.Split("."))

    while ($parts.Count -lt 4) {
        $parts += "0"
    }

    if ($parts.Count -gt 4) {
        throw "VERSION may contain at most four numeric parts: $Version"
    }

    return @($parts | ForEach-Object { [int]$_ })
}

function Resolve-PythonCommand {
    param(
        [string]$ExplicitPythonExe,
        [string]$RequestedVersion
    )

    # -------------------------------------------------
    # 1. Explicit interpreter (highest priority)
    # -------------------------------------------------
    if ($ExplicitPythonExe) {
        return [PSCustomObject]@{
            FilePath   = $ExplicitPythonExe
            PrefixArgs = @()
        }
    }

    # -------------------------------------------------
    # 2. Project virtual environment
    # -------------------------------------------------
    $venvPython = Join-Path $PSScriptRoot "..\server\api\.venv\Scripts\python.exe"
    $venvPython = [System.IO.Path]::GetFullPath($venvPython)

    if (Test-Path $venvPython) {
        return [PSCustomObject]@{
            FilePath   = $venvPython
            PrefixArgs = @()
        }
    }

    # -------------------------------------------------
    # 3. Python launcher
    # -------------------------------------------------
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        return [PSCustomObject]@{
            FilePath   = $pyLauncher.Source
            PrefixArgs = @("-$RequestedVersion")
        }
    }

    # -------------------------------------------------
    # 4. System python
    # -------------------------------------------------
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return [PSCustomObject]@{
            FilePath   = $python.Source
            PrefixArgs = @()
        }
    }

    throw "Python runtime not found. Create the project .venv or install Python $RequestedVersion."
}

function Resolve-ISCCPath {
    param([string]$ExplicitISCCPath)

    if ($ExplicitISCCPath) {
        return $ExplicitISCCPath
    }

    $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($iscc) {
        return $iscc.Source
    }

    $commonCandidates = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "C:\Users\Franklin\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
    )

    foreach ($candidate in $commonCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "ISCC.exe not found. Install Inno Setup 6 or pass -ISCCPath."
}

function Invoke-ExternalCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Description
    )

    Write-Host "==> $Description" -ForegroundColor Cyan
    Write-Host ("    {0} {1}" -f $FilePath, ($Arguments -join " ")) -ForegroundColor DarkGray

    & $FilePath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

function New-PyInstallerVersionFile {
    param(
        [string]$Path,
        [int[]]$VersionParts,
        [string]$FileDescription,
        [string]$InternalName,
        [string]$OriginalFilename,
        [string]$ProductName,
        [string]$ProductVersion
    )

    $versionTuple = ($VersionParts -join ", ")

    $content = @"
VSVersionInfo(
  ffi=FixedFileInfo(
    filevers=($versionTuple),
    prodvers=($versionTuple),
    mask=0x3f,
    flags=0x0,
    OS=0x40004,
    fileType=0x1,
    subtype=0x0,
    date=(0, 0)
  ),
  kids=[
    StringFileInfo([
      StringTable(
        '040904B0',
        [
          StringStruct('CompanyName', 'Project Indexly'),
          StringStruct('FileDescription', '$FileDescription'),
          StringStruct('FileVersion', '$ProductVersion'),
          StringStruct('InternalName', '$InternalName'),
          StringStruct('OriginalFilename', '$OriginalFilename'),
          StringStruct('ProductName', '$ProductName'),
          StringStruct('ProductVersion', '$ProductVersion')
        ]
      )
    ]),
    VarFileInfo([VarStruct('Translation', [1033, 1200])])
  ]
)
"@

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

$paths = Get-ProjectPaths
$version = Get-AutoDoctorVersion -VersionFile $paths.VersionFile
$versionParts = Get-VersionParts -Version $version
$fileVersion = ($versionParts -join ".")
$pythonCommand = Resolve-PythonCommand -ExplicitPythonExe $PythonExe -RequestedVersion $PythonVersion

if (-not $SkipInstaller) {
    $resolvedISCC = Resolve-ISCCPath -ExplicitISCCPath $ISCCPath
}

New-Item -ItemType Directory -Force -Path $paths.BuildRoot | Out-Null
New-Item -ItemType Directory -Force -Path $paths.DistDir | Out-Null
New-Item -ItemType Directory -Force -Path $paths.WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $paths.VersionResDir | Out-Null
New-Item -ItemType Directory -Force -Path $paths.InstallerOut | Out-Null

$apiVersionFile = Join-Path $paths.VersionResDir "autodoctor_api_version.txt"
$serviceVersionFile = Join-Path $paths.VersionResDir "autodoctor_service_version.txt"

New-PyInstallerVersionFile `
    -Path $apiVersionFile `
    -VersionParts $versionParts `
    -FileDescription "AutoDoctor API" `
    -InternalName "autodoctor_api" `
    -OriginalFilename "autodoctor_api.exe" `
    -ProductName "AutoDoctor" `
    -ProductVersion $version

New-PyInstallerVersionFile `
    -Path $serviceVersionFile `
    -VersionParts $versionParts `
    -FileDescription "AutoDoctor API Service Wrapper" `
    -InternalName "autodoctor_service" `
    -OriginalFilename "autodoctor_service.exe" `
    -ProductName "AutoDoctor" `
    -ProductVersion $version

$apiBuildArgs = @()
$apiBuildArgs += $pythonCommand.PrefixArgs
$apiBuildArgs += @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onefile",
    "--distpath", $paths.DistDir,
    "--workpath", $paths.WorkDir,
    "--specpath", $paths.BuildRoot,
    "--name", "autodoctor_api",
    "--icon", $paths.IconPath,
    "--version-file", $apiVersionFile,
    "--collect-submodules", "fastapi",
    "--collect-submodules", "starlette",
    "--collect-submodules", "uvicorn",
    "--hidden-import", "tzdata",
    $paths.ApiScript
)

Invoke-ExternalCommand `
    -FilePath $pythonCommand.FilePath `
    -Arguments $apiBuildArgs `
    -Description "Build autodoctor_api.exe"

$serviceDistDir = Join-Path $paths.DistDir "autodoctor_service"
$legacyServiceOnefile = Join-Path $paths.DistDir "autodoctor_service.exe"

if (Test-Path -LiteralPath $serviceDistDir) {
    Remove-Item -LiteralPath $serviceDistDir -Recurse -Force
}

if (Test-Path -LiteralPath $legacyServiceOnefile) {
    Remove-Item -LiteralPath $legacyServiceOnefile -Force
}

$serviceBuildArgs = @()
$serviceBuildArgs += $pythonCommand.PrefixArgs
$serviceBuildArgs += @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onedir",
    "--distpath", $paths.DistDir,
    "--workpath", $paths.WorkDir,
    "--specpath", $paths.BuildRoot,
    "--name", "autodoctor_service",
    "--icon", $paths.IconPath,
    "--version-file", $serviceVersionFile,
    "--hidden-import", "servicemanager",
    "--hidden-import", "win32timezone",
    "--hidden-import", "win32service",
    "--hidden-import", "win32serviceutil",
    "--hidden-import", "win32event",
    $paths.ServiceScript
)

Invoke-ExternalCommand `
    -FilePath $pythonCommand.FilePath `
    -Arguments $serviceBuildArgs `
    -Description "Build autodoctor_service (onedir)"

$installerPath = $null

if (-not $SkipInstaller) {
    $isccArgs = @(
        "/DMyAppVersion=$version",
        "/DMyAppFileVersion=$fileVersion",
        $paths.InstallerFile
    )

    Invoke-ExternalCommand `
        -FilePath $resolvedISCC `
        -Arguments $isccArgs `
        -Description "Compile AutoDoctor Inno Setup installer"

    $installerPath = Join-Path $paths.InstallerOut ("AutoDoctor_Installer_{0}.exe" -f $version)
}

Write-Host ""
Write-Host "Build completed successfully." -ForegroundColor Green
Write-Host ("Version:            {0}" -f $version)
Write-Host ("File version:       {0}" -f $fileVersion)
Write-Host ("API executable:     {0}" -f (Join-Path $paths.DistDir "autodoctor_api.exe"))
Write-Host ("Service executable: {0}" -f (Join-Path $paths.DistDir "autodoctor_service\autodoctor_service.exe"))

if ($installerPath) {
    Write-Host ("Installer:          {0}" -f $installerPath)
}
