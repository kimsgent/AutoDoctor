# ---------------------------------------------
# Self-Healing / Automatic Remediation Module (Formatted Output)
# ---------------------------------------------

Register-AutoDoctorModule -Name "Self-Healing Remediation" -Execute {

    Write-Host "Running automatic remediation..." -ForegroundColor Cyan

    # --- Pre-Remediation Restore Point ---
    $RestorePointResult = [PSCustomObject]@{
        Status       = "Not Attempted"
        ReturnValue  = $null
        Method       = ""
        Message      = ""
        Timestamp    = Get-Date
    }

    # Method 1: Enable System Restore if needed (works in German: "Systemwiederherstellung")
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive" -ErrorAction Stop
        Write-Host "System Restore enabled on system drive." -ForegroundColor Yellow
    }
    catch {
        Write-Warning "Could not enable System Restore: $_"
    }

    # Method 2: Checkpoint-Computer (preferred, PowerShell native)
    $rpSuccess = $false
    try {
        $description = "AutoDoctor Pre-Remediation Snapshot $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        $RestorePointResult.Status = "Created"
        $RestorePointResult.Method = "Checkpoint-Computer"
        $RestorePointResult.Message = "Restore point created via Checkpoint-Computer."
        $rpSuccess = $true
        Write-Host $RestorePointResult.Message -ForegroundColor Green
    }
    catch {
        Write-Warning "Checkpoint-Computer failed: $_"
    }

    # Fallback Method 3: WMIC (reliable CLI alternative)
    if (-not $rpSuccess) {
        try {
            $rpName = "AutoDoctor Pre-Remediation Snapshot $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            $wmicOutput = wmic.exe /Namespace:\\root\default Path SystemRestore Call CreateRestorePoint "$rpName", 100, 7 2>&1
            if ($wmicOutput -match "ReturnValue\s*=\s*0") {
                $RestorePointResult.Status = "Created"
                $RestorePointResult.Method = "WMIC"
                $RestorePointResult.ReturnValue = 0
                $RestorePointResult.Message = "Restore point created via WMIC."
                Write-Host $RestorePointResult.Message -ForegroundColor Green
            } else {
                $RestorePointResult.Status = "Failed"
                $RestorePointResult.Message = "WMIC failed: $wmicOutput"
                Write-Warning $RestorePointResult.Message
            }
        }
        catch {
            $RestorePointResult.Status = "Error"
            $RestorePointResult.Message = "WMIC error: $_"
            Write-Warning $RestorePointResult.Message
        }
    }

    if ($RestorePointResult.Status -eq "Not Attempted" -or $RestorePointResult.Status -eq "Failed") {
        $RestorePointResult.Status = "Skipped"
        $RestorePointResult.Message = "Restore point creation failed or System Restore disabled. Proceeding with remediation."
        Write-Warning $RestorePointResult.Message
    }

    # --- System Repair ---
    Write-Host "Performing DISM and SFC system repair..."
    try {
        DISM /Online /Cleanup-Image /RestoreHealth | Out-Null
        sfc /scannow | Out-Null
        $RepairMessage = "DISM/SFC completed successfully."
    }
    catch {
        $RepairMessage = "System repair encountered an error: $_"
        Write-Warning $RepairMessage
    }

    # --- Malware Scan (Microsoft Defender) ---
    $DefenderScanResult = [PSCustomObject]@{
        Status    = "Not Run"
        Errors    = @()
        StartTime = $null
        EndTime   = $null
        Message   = ""
    }

    $defender = Get-Service WinDefend -ErrorAction SilentlyContinue
    if ($defender -and $defender.Status -eq "Running") {
        Write-Host "Running quick malware scan..."
        $DefenderScanResult.StartTime = Get-Date
        try {
            Start-MpScan -ScanType QuickScan
            $DefenderScanResult.Status = "Completed"
            $DefenderScanResult.Message = "Defender scan completed successfully."
        }
        catch {
            $DefenderScanResult.Status = "Failed"
            $DefenderScanResult.Errors += $_
            $DefenderScanResult.Message = "Defender scan failed: $_"
            Write-Warning $DefenderScanResult.Message
        }
        finally {
            $DefenderScanResult.EndTime = Get-Date
        }
    }
    else {
        $DefenderScanResult.Status = "Not Running"
        $DefenderScanResult.Message = "Windows Defender service is not running."
        Write-Warning $DefenderScanResult.Message
    }

    # --- Temporary File Cleanup ---
    Write-Host "Cleaning temporary files..."
    $tempPaths = @("$env:TEMP", "C:\Windows\Temp")
    foreach ($path in $tempPaths) {
        try {
            Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Failed to clean ${path}: $_"
        }
    }

    # --- Windows Update Reset ---
    Write-Host "Resetting Windows Update services..."
    $services = @("wuauserv", "bits", "cryptsvc")
    foreach ($svc in $services) { Stop-Service $svc -Force -ErrorAction SilentlyContinue }
    $folders = @{
        "C:\Windows\SoftwareDistribution" = "SoftwareDistribution.old"
        "C:\Windows\System32\catroot2"    = "catroot2.old"
    }
    foreach ($key in $folders.Keys) {
        try { Rename-Item $key $folders[$key] -ErrorAction SilentlyContinue } catch {}
    }
    foreach ($svc in $services) { Start-Service $svc -ErrorAction SilentlyContinue }

    Write-Host "Automatic remediation completed." -ForegroundColor Green

    # --- Return comprehensive status object with flattened messages ---
    return [PSCustomObject]@{
        Status        = "Completed"
        Timestamp     = Get-Date
        RestorePoint  = ($RestorePointResult.Message -join "`n")
        SystemRepair  = $RepairMessage
        DefenderScan  = ($DefenderScanResult.Message -join "`n")
    }
}
