# ---------------------------------------------
# Installed Software Module
# ---------------------------------------------

Register-AutoDoctorModule -Name "Installed Software" -Execute {

$apps = Invoke-Safe {
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
Select-Object DisplayName, DisplayVersion
}

return $apps

}
