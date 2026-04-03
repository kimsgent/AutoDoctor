# ------------------------------------------------
# AutoDoctor Performance Counter Localization
# ------------------------------------------------

Set-Variable -Name AutoDoctorCounterNullSentinel -Scope Script -Value "__AUTODOCTOR_NULL_COUNTER_PATH__" -Option ReadOnly -Force

function Resolve-AutoDoctorCanonicalCounterName {
    param(
        [string]$CanonicalName
    )

    if ([string]::IsNullOrWhiteSpace($CanonicalName)) {
        return $null
    }

    switch -Regex ($CanonicalName.Trim()) {
        '(?i)^Processor$'           { return 'Processor' }
        '(?i)^PhysicalDisk$'        { return 'PhysicalDisk' }
        '(?i)^Memory$'              { return 'Memory' }
        '(?i)^Network(\s+Interface)?$' { return 'Network' }
        default                     { return $CanonicalName.Trim() }
    }
}

function Get-AutoDoctorCounterObjectToken {
    param(
        [string]$CanonicalName
    )

    $normalizedName = Resolve-AutoDoctorCanonicalCounterName -CanonicalName $CanonicalName

    switch ($normalizedName) {
        'Network' { return 'Network Interface' }
        default   { return $normalizedName }
    }
}

function Test-AutoDoctorCounterPath {
    param(
        [string]$CounterPath
    )

    if ([string]::IsNullOrWhiteSpace($CounterPath)) {
        return $false
    }

    try {
        Get-Counter -Counter $CounterPath -MaxSamples 1 -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Convert-AutoDoctorCounterPath {
    param(
        [string]$CounterPath,
        [string]$CanonicalCounterSet,
        [string]$LocalizedCounterSet
    )

    if ([string]::IsNullOrWhiteSpace($CounterPath) -or
        [string]::IsNullOrWhiteSpace($CanonicalCounterSet) -or
        [string]::IsNullOrWhiteSpace($LocalizedCounterSet)) {
        return $null
    }

    $path = $CounterPath.Trim()

    if (-not $path.StartsWith("\")) {
        return $null
    }

    $secondSlash = $path.IndexOf('\', 1)
    if ($secondSlash -lt 0) {
        return $null
    }

    $counterObjectSegment = $path.Substring(1, $secondSlash - 1)
    $counterSuffix = $path.Substring($secondSlash)

    $instanceSuffix = ""
    $counterObjectName = $counterObjectSegment

    $instanceStart = $counterObjectSegment.IndexOf("(")
    if ($instanceStart -ge 0) {
        $counterObjectName = $counterObjectSegment.Substring(0, $instanceStart)
        $instanceSuffix = $counterObjectSegment.Substring($instanceStart)
    }

    if ($counterObjectName -ne $CanonicalCounterSet) {
        return $null
    }

    return "\" + $LocalizedCounterSet + $instanceSuffix + $counterSuffix
}

function Initialize-AutoDoctorLocalization {
    [CmdletBinding()]
    param()

    if ($Global:AutoDoctorCounterMap -is [hashtable] -and $Global:AutoDoctorCounterMap.Count -gt 0) {
        if (-not ($Global:AutoDoctorCounterPathCache -is [hashtable])) {
            $Global:AutoDoctorCounterPathCache = @{}
        }

        return $Global:AutoDoctorCounterMap
    }

    $defaultMap = @{
        Processor    = "Processor"
        PhysicalDisk = "PhysicalDisk"
        Memory       = "Memory"
        Network      = "Network Interface"
    }

    $counterMap = @{}
    foreach ($key in $defaultMap.Keys) {
        $counterMap[$key] = $defaultMap[$key]
    }

    if (-not ($Global:AutoDoctorCounterPathCache -is [hashtable])) {
        $Global:AutoDoctorCounterPathCache = @{}
    }

    try {
        if (-not $Global:AutoDoctorCounterSetCache) {
            $Global:AutoDoctorCounterSetCache = Get-Counter -ListSet * -ErrorAction Stop
        }
    }
    catch {
        Write-Warning "Unable to enumerate performance counter sets for localization: $($_.Exception.Message)"
        $Global:AutoDoctorCounterMap = $counterMap
        return $Global:AutoDoctorCounterMap
    }

    $patterns = @{
        Processor    = '(?i)^(Processor|Prozessor)$'
        PhysicalDisk = '(?i)^(PhysicalDisk|Physikalischer\s+Datenträger)$'
        Memory       = '(?i)^(Memory|Arbeitsspeicher)$'
        Network      = '(?i)^(Network Interface|Netzwerkschnittstelle)$'
    }

    foreach ($canonical in $patterns.Keys) {
        $matchedSet = $Global:AutoDoctorCounterSetCache |
            Where-Object { $_.CounterSetName -match $patterns[$canonical] } |
            Select-Object -First 1

        if ($matchedSet -and $matchedSet.CounterSetName) {
            $counterMap[$canonical] = $matchedSet.CounterSetName
            continue
        }

        $englishDefault = $defaultMap[$canonical]
        $englishSet = $Global:AutoDoctorCounterSetCache |
            Where-Object { $_.CounterSetName -eq $englishDefault } |
            Select-Object -First 1

        if ($englishSet -and $englishSet.CounterSetName) {
            $counterMap[$canonical] = $englishSet.CounterSetName
        }
    }

    $Global:AutoDoctorCounterMap = $counterMap
    return $Global:AutoDoctorCounterMap
}

function Get-LocalizedCounterPath {
    [CmdletBinding()]
    param(
        [string]$CanonicalName,
        [string]$CounterPath
    )

    $normalizedName = Resolve-AutoDoctorCanonicalCounterName -CanonicalName $CanonicalName
    if ([string]::IsNullOrWhiteSpace($normalizedName) -or [string]::IsNullOrWhiteSpace($CounterPath)) {
        return $null
    }

    if (-not ($Global:AutoDoctorCounterPathCache -is [hashtable])) {
        $Global:AutoDoctorCounterPathCache = @{}
    }

    $cacheKey = "{0}|{1}" -f $normalizedName, $CounterPath

    if ($Global:AutoDoctorCounterPathCache.ContainsKey($cacheKey)) {
        $cachedPath = $Global:AutoDoctorCounterPathCache[$cacheKey]
        if ($cachedPath -eq $script:AutoDoctorCounterNullSentinel) {
            return $null
        }

        return $cachedPath
    }

    # Requirement: try English path first.
    if (Test-AutoDoctorCounterPath -CounterPath $CounterPath) {
        $Global:AutoDoctorCounterPathCache[$cacheKey] = $CounterPath
        return $CounterPath
    }

    $counterMap = Initialize-AutoDoctorLocalization
    if (-not ($counterMap -is [hashtable]) -or -not $counterMap.ContainsKey($normalizedName)) {
        $Global:AutoDoctorCounterPathCache[$cacheKey] = $script:AutoDoctorCounterNullSentinel
        return $null
    }

    $canonicalCounterSet = Get-AutoDoctorCounterObjectToken -CanonicalName $normalizedName
    $localizedCounterSet = [string]$counterMap[$normalizedName]

    if ([string]::IsNullOrWhiteSpace($localizedCounterSet) -or $localizedCounterSet -eq $canonicalCounterSet) {
        $Global:AutoDoctorCounterPathCache[$cacheKey] = $script:AutoDoctorCounterNullSentinel
        return $null
    }

    $localizedPath = Convert-AutoDoctorCounterPath `
        -CounterPath $CounterPath `
        -CanonicalCounterSet $canonicalCounterSet `
        -LocalizedCounterSet $localizedCounterSet

    if ([string]::IsNullOrWhiteSpace($localizedPath)) {
        $Global:AutoDoctorCounterPathCache[$cacheKey] = $script:AutoDoctorCounterNullSentinel
        return $null
    }

    if (Test-AutoDoctorCounterPath -CounterPath $localizedPath) {
        Write-Verbose "Using localized counter: $localizedCounterSet"
        $Global:AutoDoctorCounterPathCache[$cacheKey] = $localizedPath
        return $localizedPath
    }

    $Global:AutoDoctorCounterPathCache[$cacheKey] = $script:AutoDoctorCounterNullSentinel
    return $null
}
