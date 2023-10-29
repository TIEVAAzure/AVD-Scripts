# AVD Update of installed Office Apps on avd image
#
$ExistingVersion = (Get-ItemProperty -path hklm:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration -Name VersionToReport).VersionToReport
$updatecmd =  "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
$updatecmdParms = "/Update User displaylevel=false"
# Maximum wait time for offfice to update is 1 hour in seconds
$MaxWait = 60*60
$ProcessToCheck = "OfficeClickToRun"
$LogHeader="AVD-AIB Office Update"
Write-Host "$LogHeader - INFO : Office Update Process Started"
# Get currrent Process data
# Logic Explained
# Current Process is running indicating we got office installed,
# Start the officeC2R which will immediately (no way to test) comms w the running process, which will then within 5 minutes start a 2nd proces
# This 2nd process will do the update and once its gone update is complete.
# Monitoring every 30 secs AFTER 2 procs have been found to verify that multiple processes are running, will tell us that the update is still running, 
# IF there is never 2 procs running, there is no update happeing (same version probably)
# ELSE once we are back to one process, the version number should have changed and the PID of the remaining process should have changed
# 
# We wIll try to start the update for 10 Minutes
$UpdateComplete = $False
$ErrorState = 0
$TryingToStart = [System.Diagnostics.Stopwatch]::StartNew()
do {
    [Array]$InitalProcesses=Get-Process $ProcessToCheck -ErrorAction SilentlyContinue
    if ($InitalProcesses.Count -eq 1) {
        Write-Host "$LogHeader - INFO : Starting officeC2RClient"
        # Should be TRY/Catched
        Start-Process -FilePath $updatecmd -ArgumentList $updatecmdParms
        $UpdaterRunTime = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep 3
            $UpdaterDoneRunning = ((get-process "OfficeC2RClient" -ea SilentlyContinue) -eq $Null)
        } until (($UpdaterDoneRunning) -or ($UpdaterRunTime.Elapsed.TotalSeconds -gt 60*10))
        if ($true -eq $UpdaterDoneRunning) {
            Write-Host "$LogHeader - INFO : Waiting for multiple instances of $ProcessToCheck"
            # First we check to see that 2 processes ARE runnning - max wait 5 minutes THEN we monitor for 1
            $InitialAsyncTime = [System.Diagnostics.Stopwatch]::StartNew()
            do {
                Start-Sleep 1
                [Array]$AsyncProcs = Get-Process $ProcessToCheck -ErrorAction SilentlyContinue
            } Until (($InitialAsyncTime.Elapsed.TotalSeconds -gt 60*5) -or ($AsyncProcs.Count -gt 1))
            if ($AsyncProcs.Count -gt 1) {
                Write-Host "$LogHeader - INFO : Multiple Instancs of $ProccessToChek Present, monitoring.."
                # Updater completed, now monitor the process count for the async update
                $TimesToWait = 6
                $AsyncCount = 0
                $NegCount = 6
                $Count = 0
                $AsyncRunTime = [System.Diagnostics.Stopwatch]::StartNew()
                do {
                    Start-Sleep 10
                    [Array]$AsyncProcs = Get-Process $ProcessToCheck -ErrorAction SilentlyContinue
                    if ($ASyncProcs.Count -eq 0) {
                        # No proc running, ALERT
                        $NegCount--
                        if ($NegCount -lt 0) {
                            $ErrorState = 3
                        }
                    }
                    if ($AsyncProcs.Count -eq 1) {
                        $count++
                        if ($Count -gt $TimesToWait) {
                            $UpdateComplete = $true
                            $ErrorState = 0
                        }
                    }
                    else {
                        $AsyncCount ++
                    }
                    if ($AsyncRunTime.Elapsed.TotalSeconds -gt $MaxWait) {
                        $ErrorState = 4
                    }
                } until (($true -eq $UpdateComplete) -or ($ErrorState -ne 0))
            }
            else {
                Write-Host "$LogHeader - ERROR : Multiple Process never spawned of $ProcessToCheck"
                $ErrorState = 5
            }
        }
        else {
            # Updater was still running for 10 minutes, we abort as it should run for a few seconds only
            Write-Host "$LogHeader - ERROR : OfficeC2RClient ran to long (10 mins)"
            $ErrorState = 2
        }
    }
    elseif ($TryingToStart.Elapsed.TotalSeconds -gt 60*10) {
        # Ran out of time
        $ErrorState = 1
    }
} until (($ErrorState -ne 0) -or ($true -eq $UpdateComplete))
#
# Report Results
switch ($ErrorState) {
    0   {
        $NewVersion = (Get-ItemProperty -path hklm:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration -Name VersionToReport).VersionToReport
        Write-host "$LogHeader - INFO : Update Completed succesfully"
        Write-Host "$LogHeader - INFO : Runtime $($TryingToStart.Elapsed)"
        Write-host "$LogHeader - INFO : Version was : $ExistingVersion"
        Write-Host "$LogHeader - INFO : Version is  : $NewVersion"
        Write-Host "$LogHeader - INFO : Update completed without errors and had $AsyncCount Iterations"
    }
    1   {
        # We ran out of time making sure there was just 1 instance running
        Write-host "$LogHeader - ERROR : Update Aborted"
        Write-Host "$LogHEader - ERROR : Ran out of time waiting for 1 instance of $ProcessToCheck to be present"
        
    }
    2   {
        # Updater was running for 10 mins without spinning of Async tasks
        Write-host "$LogHeader - ERROR : Update Aborted"
        Write-Host "$LogHEader - ERROR : Ran out of time waiting for multiple instance of $ProcessToCheck to be present"
    }
    3   {
        # Mid Update, no instances of $ProcessToCheck 
        Write-host "$LogHeader - ERROR : Update Aborted"
        Write-Host "$LogHEader - ERROR : Mid update all instances of $ProcessToCheck disappeared for more then 60 Seconds"
    }
    4   {
        # Update didnt complete in maxwait time after starting
        Write-host "$LogHeader - ERROR : Update Aborted"
        Write-Host "$LogHEader - ERROR : Update took longer than maximum allowed time - which is $MaxWait seconds "
    }
    5   {
        # Multiple instances of $ProcessToCheck never occured
        Write-host "$LogHeader - ERROR : Update Aborted"
        Write-Host "$LogHEader - ERROR : Multiple instances of $ProcessToCheck never spawned withing 5 minutes "

    }
    Default {}
}
Exit $ErrorState

