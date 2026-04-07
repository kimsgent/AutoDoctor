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

function Initialize-AutoDoctorCounterCaches {
    if (-not ($Global:AutoDoctorCounterPathCache -is [hashtable])) {
        $Global:AutoDoctorCounterPathCache = @{}
    }

    if (-not ($Global:AutoDoctorCounterNameCache -is [hashtable])) {
        $Global:AutoDoctorCounterNameCache = @{}
    }

    if (-not ($Global:AutoDoctorCounterSetByNameCache -is [hashtable])) {
        $Global:AutoDoctorCounterSetByNameCache = @{}
    }
}

function Update-AutoDoctorCounterSetByNameCache {
    Initialize-AutoDoctorCounterCaches

    $Global:AutoDoctorCounterSetByNameCache = @{}

    foreach ($counterSet in @($Global:AutoDoctorCounterSetCache)) {
        if ($counterSet -and -not [string]::IsNullOrWhiteSpace($counterSet.CounterSetName)) {
            $Global:AutoDoctorCounterSetByNameCache[$counterSet.CounterSetName] = $counterSet
        }
    }
}

function Get-AutoDoctorComparableText {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $normalized = $Value.ToLowerInvariant()
    $normalized = $normalized.Replace("ä", "ae").Replace("ö", "oe").Replace("ü", "ue").Replace("ß", "ss")
    $normalized = $normalized.Normalize([System.Text.NormalizationForm]::FormD)

    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $normalized.ToCharArray()) {
        $unicodeCategory = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
        if ($unicodeCategory -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }

    $normalized = $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC)
    $normalized = $normalized -replace '[^a-z0-9/% ]', ' '
    $normalized = $normalized -replace '\s+', ' '

    return $normalized.Trim()
}

function Parse-AutoDoctorCounterPath {
    param(
        [string]$CounterPath
    )

    if ([string]::IsNullOrWhiteSpace($CounterPath)) {
        return $null
    }

    $path = $CounterPath.Trim()
    if ($path -notmatch '^\\(?<ObjectName>[^\\(]+)(?<InstanceSegment>\([^)]+\))?\\(?<CounterName>.+)$') {
        return $null
    }

    return [PSCustomObject]@{
        ObjectName      = $Matches.ObjectName.Trim()
        InstanceSegment = if ($Matches.InstanceSegment) { $Matches.InstanceSegment.Trim() } else { "" }
        CounterName     = $Matches.CounterName.Trim()
    }
}

function Normalize-AutoDoctorCounterInstanceSegment {
    param(
        [string]$InstanceSegment
    )

    if ([string]::IsNullOrWhiteSpace($InstanceSegment)) {
        return ""
    }

    $trimmedSegment = $InstanceSegment.Trim()
    if ($trimmedSegment -notmatch '^\((?<InstanceName>.+)\)$') {
        return $trimmedSegment
    }

    $instanceName = $Matches.InstanceName.Trim()
    $comparableInstance = Get-AutoDoctorComparableText -Value $instanceName

    if ($instanceName -eq "*" -or
        $comparableInstance -in @('_total', '_gesamt', 'total', 'gesamt', 'totale', 'totaal')) {
        return "(*)"
    }

    return "($instanceName)"
}

function Get-AutoDoctorCounterSetNameRegex {
    param(
        [string]$NormalizedCanonicalName
    )

    switch ($NormalizedCanonicalName) {
        'Processor' {
            return @(
                '^(processor|prozessor|processeur|procesador|processore|processador|cpu)$'
            )
        }
        'PhysicalDisk' {
            return @(
                '^physical ?disk$',
                'physikal.*datentrager',
                'disque.*physique',
                'disco.*fisic',
                'dysk.*fizycz'
            )
        }
        'Memory' {
            return @(
                '^(memory|arbeitsspeicher|memoire|memoria)$'
            )
        }
        'Network' {
            return @(
                'network.*interface',
                'netzwerk.*schnittstelle',
                'interface.*reseau',
                'interfaz.*red',
                'interfaccia.*rete'
            )
        }
        default {
            $comparable = Get-AutoDoctorComparableText -Value $NormalizedCanonicalName
            if (-not [string]::IsNullOrWhiteSpace($comparable)) {
                return @([regex]::Escape($comparable))
            }

            return @()
        }
    }
}

function Get-AutoDoctorCounterNameRegex {
    param(
        [string]$CanonicalCounterName
    )

    $comparableCounterName = Get-AutoDoctorComparableText -Value $CanonicalCounterName

    switch -Regex ($comparableCounterName) {
        '^\%\s*processor\s*time$' {
            return @(
                'processor.*time',
                'prozessor.*zeit',
                'processeur.*temps',
                'procesador.*tiempo',
                'processore.*tempo',
                'processador.*tempo',
                'cpu.*(time|zeit|temps|tiempo|tempo)'
            )
        }
        '^\%\s*disk\s*time$' {
            return @(
                'disk.*time',
                'datentr.*zeit',
                'disque.*temps',
                'disco.*tiempo',
                'disco.*tempo',
                'dysk.*czas',
                '^zeit\s*%?$'
            )
        }
        '^available\s*bytes$' {
            return @(
                'available.*bytes',
                'verf(?:u|ue)gbar.*bytes',
                'disponible.*bytes',
                'libre.*bytes'
            )
        }
        '^bytes\s*total\s*/\s*sec$' {
            return @(
                'bytes.*total.*/s',
                'bytes.*gesamt.*/s',
                'total.*bytes.*/s',
                'bytes.*(sec|/s)'
            )
        }
        default {
            $tokens = $comparableCounterName -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($tokens.Count -eq 0) {
                return @()
            }

            $escapedTokens = $tokens | ForEach-Object { [regex]::Escape($_) }
            return @($escapedTokens -join '.*')
        }
    }
}

function Get-AutoDoctorCounterCandidatePaths {
    param(
        [object]$CounterSet
    )

    if (-not $CounterSet) {
        return @()
    }

    $candidatePaths = @()

    if ($CounterSet.Paths) {
        $candidatePaths += @($CounterSet.Paths)
    }

    if ($candidatePaths.Count -eq 0 -and $CounterSet.PathsWithInstances) {
        $candidatePaths += @($CounterSet.PathsWithInstances)
    }

    $candidatePaths = $candidatePaths |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    return @($candidatePaths)
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

function Find-AutoDoctorCounterSetByProbe {
    param(
        [array]$CounterSets,
        [string]$NormalizedCanonicalName,
        [string]$ProbeCounterName
    )

    if (-not $CounterSets -or [string]::IsNullOrWhiteSpace($ProbeCounterName)) {
        return $null
    }

    $probeCounterPatterns = @(Get-AutoDoctorCounterNameRegex -CanonicalCounterName $ProbeCounterName)
    if ($probeCounterPatterns.Count -eq 0) {
        return $null
    }

    $counterSetPatterns = @(Get-AutoDoctorCounterSetNameRegex -NormalizedCanonicalName $NormalizedCanonicalName)
    $bestSet = $null
    $bestScore = -1

    foreach ($counterSet in @($CounterSets)) {
        if (-not $counterSet) {
            continue
        }

        $setNameComparable = Get-AutoDoctorComparableText -Value $counterSet.CounterSetName
        $setNameBonus = 0

        foreach ($setPattern in $counterSetPatterns) {
            if (-not [string]::IsNullOrWhiteSpace($setPattern) -and $setNameComparable -match $setPattern) {
                $setNameBonus = 5
                break
            }
        }

        $candidatePaths = Get-AutoDoctorCounterCandidatePaths -CounterSet $counterSet
        foreach ($candidatePath in $candidatePaths) {
            $parsedPath = Parse-AutoDoctorCounterPath -CounterPath $candidatePath
            if (-not $parsedPath) {
                continue
            }

            $candidateCounterComparable = Get-AutoDoctorComparableText -Value $parsedPath.CounterName
            $isMatch = $false

            foreach ($probePattern in $probeCounterPatterns) {
                if (-not [string]::IsNullOrWhiteSpace($probePattern) -and $candidateCounterComparable -match $probePattern) {
                    $isMatch = $true
                    break
                }
            }

            if (-not $isMatch) {
                continue
            }

            $score = 100 + $setNameBonus
            if (-not [string]::IsNullOrWhiteSpace($parsedPath.InstanceSegment)) {
                $score += 1
            }

            if ($score -gt $bestScore) {
                $bestScore = $score
                $bestSet = $counterSet
            }
        }
    }

    return $bestSet
}

function Find-AutoDoctorLocalizedCounterComponents {
    param(
        [object]$CounterSet,
        [string]$LocalizedCounterSet,
        [string]$CanonicalCounterName
    )

    if (-not $CounterSet -or [string]::IsNullOrWhiteSpace($CanonicalCounterName)) {
        return $null
    }

    $localizedSetComparable = Get-AutoDoctorComparableText -Value $LocalizedCounterSet
    $canonicalCounterComparable = Get-AutoDoctorComparableText -Value $CanonicalCounterName
    $canonicalCounterCompact = $canonicalCounterComparable -replace '\s+', ''
    $counterPatterns = @(Get-AutoDoctorCounterNameRegex -CanonicalCounterName $CanonicalCounterName)

    $bestPath = $null
    $bestScore = -1

    foreach ($candidatePath in (Get-AutoDoctorCounterCandidatePaths -CounterSet $CounterSet)) {
        $parsedPath = Parse-AutoDoctorCounterPath -CounterPath $candidatePath
        if (-not $parsedPath) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($localizedSetComparable)) {
            $candidateObjectComparable = Get-AutoDoctorComparableText -Value $parsedPath.ObjectName
            if ($candidateObjectComparable -ne $localizedSetComparable) {
                continue
            }
        }

        $candidateCounterComparable = Get-AutoDoctorComparableText -Value $parsedPath.CounterName
        $candidateCounterCompact = $candidateCounterComparable -replace '\s+', ''
        $score = 0

        if (-not [string]::IsNullOrWhiteSpace($canonicalCounterComparable) -and
            $candidateCounterComparable -eq $canonicalCounterComparable) {
            $score = 250
        }
        elseif (-not [string]::IsNullOrWhiteSpace($canonicalCounterCompact) -and
            $candidateCounterCompact -eq $canonicalCounterCompact) {
            $score = 240
        }
        else {
            for ($index = 0; $index -lt $counterPatterns.Count; $index++) {
                $pattern = $counterPatterns[$index]
                if (-not [string]::IsNullOrWhiteSpace($pattern) -and $candidateCounterComparable -match $pattern) {
                    $score = 200 - $index
                    break
                }
            }

            if ($score -eq 0) {
                if ($canonicalCounterComparable -match '\bbytes\b' -and $candidateCounterComparable -match '\bbytes\b') {
                    $score += 20
                }
                if ($canonicalCounterComparable -match '%|percent|prozent|pourcent|porcentaje' -and
                    $candidateCounterComparable -match '%|percent|prozent|pourcent|porcentaje') {
                    $score += 15
                }
                if ($canonicalCounterComparable -match '/s|sec' -and $candidateCounterComparable -match '/s|sec|sek|seg') {
                    $score += 15
                }
                if ($canonicalCounterComparable -match '\btime\b' -and
                    $candidateCounterComparable -match 'time|zeit|temps|tiempo|tempo|czas') {
                    $score += 10
                }
                if ($canonicalCounterComparable -match '\btotal\b' -and
                    $candidateCounterComparable -match 'total|gesamt|tot') {
                    $score += 8
                }
            }
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestPath = $parsedPath
        }
    }

    if ($bestScore -le 0) {
        return $null
    }

    return $bestPath
}

function Convert-AutoDoctorCounterPath {
    param(
        [string]$CounterPath,
        [string]$CanonicalCounterSet,
        [string]$LocalizedCounterSet,
        [object]$CounterSet
    )

    if ([string]::IsNullOrWhiteSpace($CounterPath) -or
        [string]::IsNullOrWhiteSpace($CanonicalCounterSet) -or
        [string]::IsNullOrWhiteSpace($LocalizedCounterSet) -or
        -not $CounterSet) {
        return $null
    }

    $parsedPath = Parse-AutoDoctorCounterPath -CounterPath $CounterPath
    if (-not $parsedPath) {
        return $null
    }

    $expectedObjectComparable = Get-AutoDoctorComparableText -Value $CanonicalCounterSet
    $actualObjectComparable = Get-AutoDoctorComparableText -Value $parsedPath.ObjectName
    if ($actualObjectComparable -ne $expectedObjectComparable) {
        return $null
    }

    Initialize-AutoDoctorCounterCaches

    $counterNameCacheKey = "{0}|{1}" -f `
        (Get-AutoDoctorComparableText -Value $LocalizedCounterSet), `
        (Get-AutoDoctorComparableText -Value $parsedPath.CounterName)

    $localizedCounterComponent = $null

    if ($Global:AutoDoctorCounterNameCache.ContainsKey($counterNameCacheKey)) {
        $cachedCounterComponent = $Global:AutoDoctorCounterNameCache[$counterNameCacheKey]

        if ($cachedCounterComponent -eq $script:AutoDoctorCounterNullSentinel) {
            return $null
        }

        $localizedCounterComponent = $cachedCounterComponent
    }
    else {
        $localizedCounterComponent = Find-AutoDoctorLocalizedCounterComponents `
            -CounterSet $CounterSet `
            -LocalizedCounterSet $LocalizedCounterSet `
            -CanonicalCounterName $parsedPath.CounterName

        if (-not $localizedCounterComponent) {
            $Global:AutoDoctorCounterNameCache[$counterNameCacheKey] = $script:AutoDoctorCounterNullSentinel
            return $null
        }

        $Global:AutoDoctorCounterNameCache[$counterNameCacheKey] = $localizedCounterComponent
    }

    if (-not $localizedCounterComponent -or
        [string]::IsNullOrWhiteSpace($localizedCounterComponent.ObjectName) -or
        [string]::IsNullOrWhiteSpace($localizedCounterComponent.CounterName)) {
        return $null
    }

    $instanceSegment = Normalize-AutoDoctorCounterInstanceSegment -InstanceSegment $parsedPath.InstanceSegment
    if ([string]::IsNullOrWhiteSpace($instanceSegment)) {
        $instanceSegment = Normalize-AutoDoctorCounterInstanceSegment -InstanceSegment $localizedCounterComponent.InstanceSegment
    }

    return "\" + $localizedCounterComponent.ObjectName + $instanceSegment + "\" + $localizedCounterComponent.CounterName
}

function Initialize-AutoDoctorLocalization {
    [CmdletBinding()]
    param()

    Initialize-AutoDoctorCounterCaches

    if ($Global:AutoDoctorCounterMap -is [hashtable] -and $Global:AutoDoctorCounterMap.Count -gt 0) {
        if ($Global:AutoDoctorCounterSetCache -and $Global:AutoDoctorCounterSetByNameCache.Count -eq 0) {
            Update-AutoDoctorCounterSetByNameCache
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

    Update-AutoDoctorCounterSetByNameCache

    $probeCounters = @{
        Processor    = '% Processor Time'
        PhysicalDisk = '% Disk Time'
        Memory       = 'Available Bytes'
        Network      = 'Bytes Total/sec'
    }

    foreach ($canonical in $defaultMap.Keys) {
        $setNamePatterns = @(Get-AutoDoctorCounterSetNameRegex -NormalizedCanonicalName $canonical)
        $matchedSet = @($Global:AutoDoctorCounterSetCache) |
            Where-Object {
                $candidateSetName = Get-AutoDoctorComparableText -Value $_.CounterSetName
                foreach ($pattern in $setNamePatterns) {
                    if (-not [string]::IsNullOrWhiteSpace($pattern) -and $candidateSetName -match $pattern) {
                        return $true
                    }
                }
                return $false
            } |
            Select-Object -First 1

        if ($matchedSet -and $matchedSet.CounterSetName) {
            $counterMap[$canonical] = $matchedSet.CounterSetName
            continue
        }

        $probeSet = Find-AutoDoctorCounterSetByProbe `
            -CounterSets @($Global:AutoDoctorCounterSetCache) `
            -NormalizedCanonicalName $canonical `
            -ProbeCounterName $probeCounters[$canonical]

        if ($probeSet -and $probeSet.CounterSetName) {
            $counterMap[$canonical] = $probeSet.CounterSetName
            continue
        }

        $englishDefault = $defaultMap[$canonical]
        if ($Global:AutoDoctorCounterSetByNameCache.ContainsKey($englishDefault)) {
            $counterMap[$canonical] = $englishDefault
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

    Initialize-AutoDoctorCounterCaches

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

    if ([string]::IsNullOrWhiteSpace($localizedCounterSet)) {
        $Global:AutoDoctorCounterPathCache[$cacheKey] = $script:AutoDoctorCounterNullSentinel
        return $null
    }

    $counterSet = $null
    if ($Global:AutoDoctorCounterSetByNameCache.ContainsKey($localizedCounterSet)) {
        $counterSet = $Global:AutoDoctorCounterSetByNameCache[$localizedCounterSet]
    }
    elseif ($Global:AutoDoctorCounterSetCache) {
        $counterSet = @($Global:AutoDoctorCounterSetCache) |
            Where-Object { $_.CounterSetName -eq $localizedCounterSet } |
            Select-Object -First 1

        if ($counterSet) {
            $Global:AutoDoctorCounterSetByNameCache[$localizedCounterSet] = $counterSet
        }
    }

    if (-not $counterSet) {
        $Global:AutoDoctorCounterPathCache[$cacheKey] = $script:AutoDoctorCounterNullSentinel
        return $null
    }

    $localizedPath = Convert-AutoDoctorCounterPath `
        -CounterPath $CounterPath `
        -CanonicalCounterSet $canonicalCounterSet `
        -LocalizedCounterSet $localizedCounterSet `
        -CounterSet $counterSet

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
