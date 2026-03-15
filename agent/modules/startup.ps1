# ---------------------------------------------
# Startup Program Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "Startup Analysis" -Execute {

    # --- Retrieve startup programs ---
    $startup = Invoke-Safe {
        Get-CimInstance Win32_StartupCommand | Select-Object Name, Location
    }

    # Return structured object
    $startupObj = [PSCustomObject]@{
        StartupPrograms = $startup
        Count           = if ($startup) { $startup.Count } else { 0 }
    }

    return $startupObj
}
