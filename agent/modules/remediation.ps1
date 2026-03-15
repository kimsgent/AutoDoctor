# ---------------------------------------------
# Self-Healing / Automatic Remediation Module
# ---------------------------------------------

Register-AutoDoctorModule -Name "Self-Healing Remediation" -Execute {

    Write-Host "Running automatic remediation..." -ForegroundColor Cyan

    # --- System Repair ---
    Write-Host "Performing DISM and SFC system repair..."
    try {
        DISM /Online /Cleanup-Image /RestoreHealth | Out-Null
        sfc /scannow | Out-Null
    }
    catch {
        Write-Warning "System repair encountered an error: $_"
    }

    # --- Malware Scan (Microsoft Defender) ---
    $DefenderScanResult = [PSCustomObject]@{
        Status    = "Not Run"
        Errors    = @()
        StartTime = $null
        EndTime   = $null
    }

    $defender = Get-Service WinDefend -ErrorAction SilentlyContinue
    if ($defender -and $defender.Status -eq "Running") {
        Write-Host "Running quick malware scan..."
        $DefenderScanResult.StartTime = Get-Date
        try {
            Start-MpScan -ScanType QuickScan
            $DefenderScanResult.Status = "Completed"
        }
        catch {
            $DefenderScanResult.Status = "Failed"
            $DefenderScanResult.Errors += $_
            Write-Warning "Defender scan failed: $_"
        }
        finally {
            $DefenderScanResult.EndTime = Get-Date
        }
    }
    else {
        Write-Warning "Windows Defender service is not running"
        $DefenderScanResult.Status = "Not Running"
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
    foreach ($svc in $services) {
        try { Stop-Service $svc -Force -ErrorAction SilentlyContinue } catch {}
    }

    $folders = @{
        "C:\Windows\SoftwareDistribution" = "SoftwareDistribution.old"
        "C:\Windows\System32\catroot2"    = "catroot2.old"
    }

    foreach ($key in $folders.Keys) {
        try { Rename-Item $key $folders[$key] -ErrorAction SilentlyContinue } catch {}
    }

    foreach ($svc in $services) {
        try { Start-Service $svc -ErrorAction SilentlyContinue } catch {}
    }

    Write-Host "Automatic remediation completed." -ForegroundColor Green

    # Return status object
    return [PSCustomObject]@{
        Status    = "Completed"
        Timestamp = Get-Date
    }
}
