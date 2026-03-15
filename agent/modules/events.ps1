# ---------------------------------------------
# Event Log Module for AutoDoctor
# ---------------------------------------------

Register-AutoDoctorModule -Name "Event Log Analysis" -Execute {

    # --- Recent System Errors ---
    $errors = Invoke-Safe {
        Get-WinEvent -LogName System -MaxEvents 500 |
        Where-Object LevelDisplayName -eq "Error" |
        Select-Object -First 30 TimeCreated, ProviderName, Id, Message
    }

    # Return structured object
    $eventObj = [PSCustomObject]@{
        RecentErrors = $errors
        ErrorCount   = if ($errors) { $errors.Count } else { 0 }
    }

    return $eventObj
}
