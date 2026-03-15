# ---------------------------------------------
# System Information Module
# ---------------------------------------------

Register-AutoDoctorModule -Name "System Information" -Execute {

$sysInfo = Invoke-Safe {
Get-ComputerInfo |
Select-Object WindowsProductName, WindowsVersion, OsArchitecture, CsTotalPhysicalMemory
}

return $sysInfo

}
