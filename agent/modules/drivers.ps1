# ---------------------------------------------
# Driver Inventory Module
# ---------------------------------------------

Register-AutoDoctorModule -Name "Driver Inventory" -Execute {

$drivers = Invoke-Safe {
Get-WmiObject Win32_PnPSignedDriver |
Select-Object DeviceName,DriverVersion,DriverProviderName
}

return $drivers

}
