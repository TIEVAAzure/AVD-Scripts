# AVD Update of installed Office Apps on avd image
#
$errorState = 0
$updatecmd =  "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
$updatecmdParms = "/Update User"
try {
    Start-Process -FilePath $updatecmd -ArgumentList $updatecmdParms -Wait
}
catch {
    $errorState = 1
    Write-Host "AVD AIB OfficeUpdate : Completed with errors"
    Write-Host $_
    Write-Host $_.ErrorDetails

}
finally {
    if ($errorState -eq 0) {
        Write-Host "AVD AIB OfficeUpdate : Update completed without errors"
    }
}