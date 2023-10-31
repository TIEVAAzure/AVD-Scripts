# AVD remove Teams Machine wide installer
#
# Utilise the Teams Installer left on the machine from the buildin avd-aib scripts which is located in c:\teams
#
$teamsMsi = 'teams.msi'
$drive = 'C:\'
$appName = 'teams'
$LocalPath = $drive + $appName
$outputPath = $LocalPath + '\' + $teamsMsi
$LogHeader = "AVD-AIB Teams MachineWide Uninstaller"
$ErrorState = 0
#
#
#
write-host "$outputpath"
Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") INFO  : Started"
if ((Test-Path $outputPath) -eq $true) {
    # Installer is there, now Uninstall 
    try {
        Start-Process -FilePath msiexec.exe -Args "/x $outputPath  /quiet /norestart /log teams.log" -Wait
        $ErrorState=$LASTEXITCODE    
    }
    catch {
        $ErrorState= -10
    }
}
else {
    $ErrorState = -11
}

switch ($ErrorState) {
    0       {
        Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") INFO  : Uninstall Completed Succesfully"
    }
    -10     {
        Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") ERROR : Uninstaller Crashed it would appear"
    }
    -11     {
        Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") ERROR : Installer ($outputPath) not present on system"
    }
    Default {
        Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") ERROR : Installer exited with a Non Zero Result"
    }
}
Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") INFO  : Completed"
Exit $ErrorState


