# ---------------------------------------------
# Windows Update Status Module
# ---------------------------------------------

Register-AutoDoctorModule -Name "Windows Update Status" -Execute {

$updatesvc = Invoke-Safe { Get-Service wuauserv }

$updateStatus = [PSCustomObject]@{
WindowsUpdateService = if ($updatesvc) { $updatesvc.Status } else { "Unknown" }
}

return $updateStatus

}
