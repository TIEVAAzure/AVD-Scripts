# AVD Update of installed Office Apps on avd image
#
$ExistingVersion = (Get-ItemProperty -path hklm:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration -Name VersionToReport).VersionToReport
$errorState = 0
$updatecmd =  "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
$updatecmdParms = "/Update User displaylevel=false"
# Maximum wait time for offfice to update is 1 hour in seconds
$MaxWait = 60*60
$LogHeader="AVD-AIB Office Update"
Write-Host "$LogHeader - INFO : Office Update Process Started"
try {
    Start-Process -FilePath $updatecmd -ArgumentList $updatecmdParms
    # Wait 10 seconds check for process running
    Start-Sleep 10
    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep 60
        Write-Host "$LogHeader - INFO : Checking Update Process status"
        $UpdateProcessRunningStill = ((get-process "OfficeC2RClient" -ea SilentlyContinue) -ne $Null)
        Write-Host "$LogHeader - INFO : Update Process still active? : $UpdateProcessRunningStill"
    } while (($StopWatch.Elapsed.TotalSeconds -gt $MaxWait) -or ($true -eq $UpdateProcessRunningStill)) 
}
catch {
    $ErrorState = 1
    Write-Host "$LogHeader - ERROR : Completed with errors Unable to launch updater"
    Write-Host $_
    Write-Host $_.ErrorDetails

}
finally {
    if ($errorState -eq 0) {
        if (-not $UpdateProcessRunningStill) {
            $NewVersion = (Get-ItemProperty -path hklm:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration -Name VersionToReport).VersionToReport
            Write-host "$LogHeader - INFO : Update Completed succesfully"
            Write-host "$LogHeader - INFO : Run time :  $($StopWatch.Elapsed)"
            Write-host "$LogHeader - INFO : Version was : $ExistingVersion"
            Write-Host "$LogHeader - INFO : Version is  : $NewVersion"
            Write-Host "$LogHeader - INFO : Update completed without errors"
        }
        else {
            Write-host "$LogHeader - ERROR :  : Update did NOT Complete"
            $ErrrorState = 2
        }
    }
}
Exit $ErrorState
