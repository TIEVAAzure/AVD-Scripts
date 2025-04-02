#-----------------------------------------------
# Office Update Script with Online Version Check
#-----------------------------------------------

# 1. Get installed Office version and channel from the registry
try {
    $regProps = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction Stop
    $ExistingVersionStr = $regProps.VersionToReport
    # Some installations might not set a "Channel" value.
    $installedChannel = $regProps.Channel
} catch {
    Write-Host "Error reading Office configuration from registry: $_"
    exit 1
}

# If the channel is not defined, assume a default (e.g. "Current Channel")
if ([string]::IsNullOrEmpty($installedChannel)) {
    Write-Host "Channel registry value is empty; defaulting to 'Current Channel'."
    $installedChannel = "Current Channel"
}

# Convert the installed version to a System.Version object.
try {
    $ExistingVersion = [System.Version]$ExistingVersionStr
} catch {
    Write-Host "Error converting version string '$ExistingVersionStr' to a version object."
    exit 1
}

Write-Host "Office Update Process Started at $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')"
Write-Host "Installed Version: $ExistingVersionStr"
Write-Host "Installed Channel: $installedChannel"

# Extract the "channel version" (the third number) from the installed version.
# Example: if VersionToReport is "16.0.18429.20200", then channel version is 18429.
$installedChannelVersion = $ExistingVersion.Build
Write-Host "Installed Channel Version: $installedChannelVersion"

# 2. Retrieve online update history page and extract the latest version for the matching channel.
$url = 'https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft365-apps-by-date'
try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Host "Error fetching the update history page: $_"
    exit 1
}

$htmlContent = $response.Content

# Choose a regex pattern based on the installed channel.
# The pattern uses (?s) so that '.' matches newline.
switch -Wildcard ($installedChannel) {
    "Current Channel" {
        $pattern = '(?s)<tr>.*?<td[^>]*>.*?Current Channel\s*<br>.*?</td>\s*<td[^>]*>\s*(?<onlineVersion>\d+)\s*<br>.*?<td[^>]*>\s*(?<onlineBuild>[\d\.]+)\s*<br>'
    }
    "Monthly Enterprise Channel" {
        $pattern = '(?s)<tr>.*?<td[^>]*>.*?Monthly Enterprise Channel\s*<br>.*?</td>\s*<td[^>]*>\s*(?<onlineVersion>\d+)\s*<br>.*?<td[^>]*>\s*(?<onlineBuild>[\d\.]+)\s*<br>'
    }
    {$_ -like "*Semi-Annual*"} {
        $pattern = '(?s)<tr>.*?<td[^>]*>.*?Semi-Annual Enterprise Channel.*?<br>.*?</td>\s*<td[^>]*>\s*(?<onlineVersion>\d+)\s*<br>.*?<td[^>]*>\s*(?<onlineBuild>[\d\.]+)\s*<br>'
    }
    Default {
        Write-Host "Channel '$installedChannel' is not supported by this script."
        exit 1
    }
}

if ($htmlContent -match $pattern) {
    $onlineVersion = $matches['onlineVersion']
    $onlineBuild = $matches['onlineBuild']
    Write-Host "Latest online version for '$installedChannel': $onlineVersion (Build $onlineBuild)"
} else {
    Write-Host "Could not extract online version information for channel '$installedChannel'."
    exit 1
}

# 3. Compare the installed channel version with the online channel version.
$onlineChannelVersion = [int]$onlineVersion

if ($installedChannelVersion -lt $onlineChannelVersion) {
    Write-Host "An update is available: Installed channel version $installedChannelVersion vs Online $onlineChannelVersion."
    Write-Host "Proceeding with update..."
    
    # Define the update command and parameters.
    $updateCmd = "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
    $updateCmdParms = "/Update User displaylevel=false"
    
    # Start the update process.
    Start-Process -FilePath $updateCmd -ArgumentList $updateCmdParms

    # 4. Poll the registry for a version change (timeout after 10 minutes).
    $maxWaitSeconds = 600
    $pollInterval = 10
    $elapsed = 0
    $NewVersionStr = $ExistingVersionStr
    while (($NewVersionStr -eq $ExistingVersionStr) -and ($elapsed -lt $maxWaitSeconds)) {
         Start-Sleep -Seconds $pollInterval
         $elapsed += $pollInterval
         $timeLeft = $maxWaitSeconds - $elapsed
         Write-Host "Time left: $timeLeft seconds"
         try {
             $NewVersionStr = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name VersionToReport).VersionToReport
         } catch {
             Write-Host "Unable to read Office version from registry."
         }
    }
    if ($NewVersionStr -ne $ExistingVersionStr) {
         Write-Host "Update completed successfully at $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')."
         Write-Host "Version changed from $ExistingVersionStr to $NewVersionStr."
    } else {
         Write-Host "Update did not complete within $maxWaitSeconds seconds."
         Write-Host "Current version remains: $ExistingVersionStr."
    }
} else {
    Write-Host "Office is already up-to-date for channel '$installedChannel'. No update required."
    exit 0
}
