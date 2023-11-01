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
    Set-Location $LocalPath
    # Installer is there, now Uninstall 
    Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") INFO  : Dealying start by 5mins"
    Start-Sleep (5*60)
    try {
        $Process = Start-Process -FilePath msiexec.exe -Args "/x $outputPath  /quiet /norestart /log teams.log" -Wait -PassThru
        $ErrorState=$Process.ExitCode
    }
    catch {
        $ErrorState = -10
    }
}
else {
    $ErrorState = -11
}

switch ($ErrorState) {
    0       {
        Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") INFO  : Uninstall Completed Succesfully ($ErrorState)"
    }
    -10     {
        Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") ERROR : Uninstaller Crashed it would appear ($ErrorState)"
    }
    -11     {
        Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") ERROR : Installer ($outputPath) not present on system ($ErrorState)"
    }
    Default {
        Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") ERROR : Installer exited with a Non Zero Result ($ErrorState)"
    }
}
Write-Host "$LogHeader - $(Get-Date -Format "yyyy/MM/dd HH:mm:ss") INFO  : Completed ($ErrorState)"
Exit $ErrorState
