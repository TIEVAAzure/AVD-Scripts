# AVD Update of installed Office Apps on AVD image (Simplified Approach)

# Get current Office version from registry
$ExistingVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name VersionToReport).VersionToReport

$updateCmd = "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
$updateCmdParms = "/Update User displaylevel=false"

Write-Host "Office Update Process Started at $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')"
Write-Host "Existing version: $ExistingVersion"

# Start the update process
Start-Process -FilePath $updateCmd -ArgumentList $updateCmdParms

# Define maximum wait time (e.g., 10 minutes) and polling interval
$maxWaitSeconds = 600
$pollInterval = 10
$elapsed = 0
$NewVersion = $ExistingVersion

# Poll the registry for a version change
while (($NewVersion -eq $ExistingVersion) -and ($elapsed -lt $maxWaitSeconds)) {
    Start-Sleep -Seconds $pollInterval
    $elapsed += $pollInterval
    try {
        $NewVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name VersionToReport).VersionToReport
    }
    catch {
        Write-Host "Unable to read Office version from registry."
    }
}

if ($NewVersion -ne $ExistingVersion) {
    Write-Host "Update completed successfully at $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')."
    Write-Host "Version changed from $ExistingVersion to $NewVersion."
}
else {
    Write-Host "Update did not complete within $maxWaitSeconds seconds."
    Write-Host "Current version remains: $ExistingVersion."
}
