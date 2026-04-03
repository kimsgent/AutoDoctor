# ------------------------------------------------
# AutoDoctor Update Awareness
# ------------------------------------------------

function ConvertTo-AutoDoctorVersionObject {
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $trimmed = $VersionText.Trim().TrimStart("v", "V")

    if ($trimmed -match "(\d+(?:\.\d+){1,3})") {
        $trimmed = $matches[1]
    }
    else {
        return $null
    }

    try {
        return [version]$trimmed
    }
    catch {
        return $null
    }
}

function ConvertTo-AutoDoctorVersionString {
    param(
        [string]$VersionText
    )

    $versionObj = ConvertTo-AutoDoctorVersionObject -VersionText $VersionText
    if ($versionObj) {
        return $versionObj.ToString()
    }

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return ""
    }

    return $VersionText.Trim().TrimStart("v", "V")
}

function Get-AutoDoctorUpdateCachePath {
    $cacheDir = Get-AutoDoctorPath "Cache"

    if ([string]::IsNullOrWhiteSpace($cacheDir)) {
        $cacheDir = Join-Path $Global:AutoDoctorRoot "cache"
    }

    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    return Join-Path $cacheDir "update_check.json"
}

function Read-AutoDoctorUpdateCache {
    param(
        [string]$CachePath
    )

    if ([string]::IsNullOrWhiteSpace($CachePath) -or -not (Test-Path -LiteralPath $CachePath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $CachePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Write-AutoDoctorUpdateCache {
    param(
        [string]$CachePath,
        [string]$LatestVersion,
        [bool]$UpdateAvailable
    )

    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        return
    }

    $cachePayload = [PSCustomObject]@{
        last_checked     = (Get-Date).ToUniversalTime().ToString("o")
        latest_version   = $LatestVersion
        update_available = $UpdateAvailable
    }

    try {
        $json = $cachePayload | ConvertTo-Json -Depth 3
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($CachePath, $json, $utf8NoBom)
    }
    catch {
        # Silent by design.
    }
}

function Get-AutoDoctorUpdateInfo {
    $repoUrl = "https://github.com/kimsgent/autodoctor"
    $apiUrl = "https://api.github.com/repos/kimsgent/autodoctor/releases/latest"

    $currentVersionRaw = Get-AutoDoctorVersion
    $currentVersion = ConvertTo-AutoDoctorVersionString -VersionText $currentVersionRaw
    $currentVersionObj = ConvertTo-AutoDoctorVersionObject -VersionText $currentVersionRaw

    $defaultResult = [PSCustomObject]@{
        UpdateAvailable = $false
        CurrentVersion  = $currentVersion
        LatestVersion   = $null
        RepoUrl         = $repoUrl
    }

    $cachePath = Get-AutoDoctorUpdateCachePath
    $cached = Read-AutoDoctorUpdateCache -CachePath $cachePath

    if ($cached) {
        $lastChecked = $null
        if ($cached.last_checked) {
            try {
                $lastChecked = [datetime]$cached.last_checked
            }
            catch {
                $lastChecked = $null
            }
        }

        if ($lastChecked -and (((Get-Date).ToUniversalTime() - $lastChecked.ToUniversalTime()).TotalHours -lt 24)) {
            $cachedLatest = ConvertTo-AutoDoctorVersionString -VersionText ([string]$cached.latest_version)
            $cachedUpdateAvailable = $false
            $cachedLatestObj = ConvertTo-AutoDoctorVersionObject -VersionText $cachedLatest

            if ($currentVersionObj -and $cachedLatestObj) {
                $cachedUpdateAvailable = $currentVersionObj -lt $cachedLatestObj
            }
            elseif ($null -ne $cached.update_available) {
                $cachedUpdateAvailable = [bool]$cached.update_available
            }

            return [PSCustomObject]@{
                UpdateAvailable = $cachedUpdateAvailable
                CurrentVersion  = $currentVersion
                LatestVersion   = if ($cachedLatest) { $cachedLatest } else { $null }
                RepoUrl         = $repoUrl
            }
        }
    }

    try {
        $headers = @{
            "User-Agent" = "AutoDoctor"
            "Accept"     = "application/vnd.github+json"
        }

        $release = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop

        # /releases/latest normally returns stable releases; keep explicit guard.
        if ($release.prerelease -eq $true) {
            Write-AutoDoctorUpdateCache -CachePath $cachePath -LatestVersion "" -UpdateAvailable:$false
            return $defaultResult
        }

        $latestVersion = ConvertTo-AutoDoctorVersionString -VersionText ([string]$release.tag_name)
        $latestVersionObj = ConvertTo-AutoDoctorVersionObject -VersionText $latestVersion
        $updateAvailable = $false

        if ($currentVersionObj -and $latestVersionObj) {
            $updateAvailable = $currentVersionObj -lt $latestVersionObj
        }

        Write-AutoDoctorUpdateCache -CachePath $cachePath -LatestVersion $latestVersion -UpdateAvailable:$updateAvailable

        return [PSCustomObject]@{
            UpdateAvailable = $updateAvailable
            CurrentVersion  = $currentVersion
            LatestVersion   = if ($latestVersion) { $latestVersion } else { $null }
            RepoUrl         = $repoUrl
        }
    }
    catch {
        # Offline/API failures are intentionally silent.
        return $defaultResult
    }
}
