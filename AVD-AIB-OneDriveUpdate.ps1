# AVD Update of installed OneDrive in Machinewide installtion mode on avd image
#
$ExistingVersion = (Get-ItemProperty -path hklm:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration -Name VersionToReport).VersionToReport
$ErrorState = 0
$InstallerName =  "OnedriveSetup.exe"
$UnInstallParams = "/Uninstall /Allusers /Silent"
$InstallParams = "/allusers /Silent"
$ProcessName = "OneDriveSetup"
$LocalAVDPath = "c:\temp\avd\"
$OneDriveInstaller = "https://go.microsoft.com/fwlink/?linkid=844652"
$LogHeader = "AVD-AIB OneDrive Update"
$VersionFolder = "HKLM:/Software/Microsoft/Onedrive"
$VersionKey = "Version"
# Maximum wait time for Onedrive update is 1 hour in seconds
$MaxWait = 60*60
$ExistingVersion = (Get-ItemProperty -path $VersionFolder -Name $VersionKey -ErrorAction SilentlyContinue).$VersionKey

##### 
# Create Temp structure if not exists
##### 

if ((Test-Path c:\temp) -eq $false) {
    Write-Host "$LogHeader - INFO : Creating temp directory"
    $res=New-Item -Path c:\temp -ItemType Directory
}
else {
    Write-Host "$LogHeader - INFO : C:\temp already exists"
}
if ((Test-Path $LocalAVDpath) -eq $false) {
    Write-Host "$LogHeader - INFO : Creating directory: $LocalAVDpath"
    $res=New-Item -Path $LocalAVDpath -ItemType Directory
}
else {
    Write-Host "$LogHeader -  : $LocalWVDpath already exists"
}



### DL the onedrive installer
Write-Host "$LogHeader - INFO : Downloading OneDriveSetup.exe from URI : $OneDriveInstaller "
Invoke-WebRequest -Uri $OneDriveInstaller -OutFile "$LocalAVDpath$InstallerName"


# Did the installer download?
if ((Test-Path $LocalAVDpath$InstallerName) -eq $true) {
    # Installer is there, now Uninstall and then reinstall in machine wide mode
    Write-Host "$LogHeader - INFO : Running Uninstall"
    Start-Process -FilePath $LocalAVDpath$InstallerName -ArgumentList $UnInstallParams
    # Wait 10 seconds check for process running
    Start-Sleep 10
    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep 60
        $UpdateProcessRunningStill = ((get-process $ProcessName -ea SilentlyContinue) -ne $Null)
    } while (($StopWatch.Elapsed.TotalSeconds -gt $MaxWait) -or ($true -eq $UpdateProcessRunningStill)) 
    if ($false -eq $UpdateProcessRunningStill) {
        # Uninstall completed, Lets Install
        Write-Host "$LogHeader - INFO : Running Install"
        Start-Process -FilePath $LocalAVDpath$InstallerName -ArgumentList $InstallParams
        # Wait 10 seconds check for process running
        Start-Sleep 10
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep 60
            $UpdateProcessRunningStill = ((get-process $ProcessName -ea SilentlyContinue) -ne $Null)
        } while (($StopWatch.Elapsed.TotalSeconds -gt $MaxWait) -or ($true -eq $UpdateProcessRunningStill)) 
        if ($true -eq $UpdateProcessRunningStill) {
            $ErrorState = 3 
        }
    }
    else {
        $ErrorState = 2
    }
}
else {
    $ErrorState = 1
}


switch ($ErrorState) 
{
    0   {
            $NewVersion = (Get-ItemProperty -path $VersionFolder -Name $VersionKey -ErrorAction SilentlyContinue).$VersionKey
            Write-Host "$LogHeader - INFO : Update Complete"
            Write-Host "$LogHeader - INFO : "
            Write-host "$logHeader - INFO : Version was -> $ExistingVersion"
            Write-Host "$LogHeader - INFO : Version is  -> $NewVersion"

            exit 0
        }
    1   {
            Write-Host "$LogHeader - ERROR : Installer File ($InstallerName) did not download correctly"
            exit 1
        }
    2   {
            Write-Host "$Logheader - ERROR : Uninstall never completed"
            exit 2
        }
    default {
            Write-Host "$LogHeader - ERROR : Something went wrong"
            exit 3
        }
}
