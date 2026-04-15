# ------------------------------------------------
# AutoDoctor SQLite Initialization
# ------------------------------------------------

# DB path comes from config.ps1 which is loaded by autodoctor.ps1

if (!(Test-Path $Global:AutoDoctorPaths.DB)) {
    New-Item -Path $Global:AutoDoctorPaths.DB -ItemType Directory -Force | Out-Null
}

# -----------------------------------------------------------------------------
# LOAD SQLITE ASSEMBLY
# -----------------------------------------------------------------------------

try {

    $sqliteDll = Join-Path $PSScriptRoot "..\lib\System.Data.SQLite.dll"

    if (!(Test-Path $sqliteDll)) {
        throw "SQLite library not found: $sqliteDll"
    }

    Add-Type -Path $sqliteDll

}
catch {

    $msg = "AutoDoctor database engine failed to load SQLite. $($_.Exception.Message)"

    Write-Error $msg

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" |
    Out-File $Global:AutoDoctorLogFile -Append

    throw
}

function Initialize-AutoDoctorDatabase {
    $connection = $null

    try {
        $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$Global:AutoDoctorDBPath;Version=3;")
        $connection.Open()

        . "$PSScriptRoot\db.schema.ps1"

        Initialize-AutoDoctorSchema -Connection $connection
    }
    finally {
        if ($connection) {
            $connection.Close()
        }
    }
}
