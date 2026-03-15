# ---------------------------------------------
# System Uptime Module
# ---------------------------------------------

Register-AutoDoctorModule -Name "System Uptime" -Execute {

$uptime = Invoke-Safe {
(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
}

$uptimeObj = [PSCustomObject]@{
UptimeDays = [math]::Round($uptime.TotalDays,2)
}

return $uptimeObj

}
