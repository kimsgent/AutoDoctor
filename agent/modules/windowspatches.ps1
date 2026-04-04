# ---------------------------------------------
# Windows Patch History Module
# ---------------------------------------------

Register-AutoDoctorModule -Name "Windows Patch History" -Execute {

    $result = [PSCustomObject]@{
        SecurityUpdates = @()
        FeatureUpdates  = @()
    }

    $historyEntries = @()

    try {
        $session = New-Object -ComObject "Microsoft.Update.Session"
        $searcher = $session.CreateUpdateSearcher()
        $historyCount = $searcher.GetTotalHistoryCount()

        if ($historyCount -gt 0) {
            $historyEntries = @($searcher.QueryHistory(0, $historyCount))
        }
    }
    catch {
        Write-Warning "Windows Update history retrieval failed: $($_.Exception.Message)"
        return $result
    }

    $normalizedHistory = @(
        $historyEntries | ForEach-Object {
            $entry = $_
            $kb = $null
            if ([string]$entry.Title -match "KB\d+") {
                $kb = $matches[0]
            }

            [PSCustomObject]@{
                Title       = [string]$entry.Title
                Description = [string]$entry.Description
                KB          = $kb
                InstalledOn = [datetime]$entry.Date
                Result      = [int]$entry.ResultCode
                Operation   = [int]$entry.Operation
            }
        }
    )

    # Keep only OS/security-style updates and exclude product/app updates.
    $securityIncludePattern = '(?i)(Security|Sicherheits|Critical|Kritisch|Cumulative|Kumulativ)'
    $securityExcludePattern = '(?i)(Driver|Treiber|Defender|Security\s+Intelligence|Definition\s+Update|Definitionsupdate|Visual\s+Studio|Office|Microsoft\s+365|SQL\s+Server|Edge|Chrome|Firefox|Adobe)'
    $featureIncludePattern = '(?i)(Feature\s+update|Funktionsupdate|Windows\s?(10|11).*(version|Version|H2|H1|LTSC))'
    $featureExcludePattern = '(?i)(Cumulative|Kumulativ|Security|Sicherheits|Preview|Vorschau|Driver|Treiber|Defender|Definition\s+Update|Definitionsupdate)'
    $windowsOnlyPattern = '(?i)(Microsoft\s+Windows|Windows(\s+Server)?|Windows\s?(10|11))'

    $securityUpdates = @(
        $normalizedHistory |
            Where-Object {
                $_.Operation -eq 1 -and
                $_.Result -eq 2 -and
                $_.Title -match $securityIncludePattern -and
                $_.Title -notmatch $securityExcludePattern -and
                $null -ne $_.KB
            } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 10
    )

    $featureUpdates = @(
        $normalizedHistory |
            Where-Object {
                $_.Operation -eq 1 -and
                $_.Result -eq 2 -and
                $_.Title -match $windowsOnlyPattern -and
                $_.Title -match $featureIncludePattern -and
                $_.Title -notmatch $featureExcludePattern
            } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 5
    )

    if ($featureUpdates.Count -eq 0) {
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            if ($os) {
                $installedOn = $null

                if ($os.InstallDate) {
                    try {
                        if ($os.InstallDate -is [datetime]) {
                            $installedOn = [datetime]$os.InstallDate
                        }
                        else {
                            $installedOn = [System.Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate)
                        }
                    }
                    catch {
                        $installedOn = $null
                    }
                }

                $featureUpdates = @(
                    [PSCustomObject]@{
                        Title       = "Windows Feature Update"
                        Version     = [string]$os.Version
                        Build       = [string]$os.BuildNumber
                        InstalledOn = $installedOn
                    }
                )
            }
        }
        catch {
            $featureUpdates = @()
        }
    }

    $result.SecurityUpdates = $securityUpdates
    $result.FeatureUpdates = $featureUpdates

    return $result
}
