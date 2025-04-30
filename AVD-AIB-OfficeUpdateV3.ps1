#-----------------------------------------------
# Office Update Script with Online Version Check (Using UpdateChannel URL Mapping)
#-----------------------------------------------

# Exit Code Reference:
# 0  - Success: Office is already up-to-date.
# 1  - Error: Unable to read Office configuration from the registry.
# 2  - Error: UpdateChannel URL is not recognized.
# 3  - Error: Unable to convert version string to a version object.
# 4  - Error: Unable to fetch the update history page.
# 5  - Error: Beta Channel update checking is not supported by this script.
# 6  - Error: Channel is not supported by this script.
# 7  - Error: Could not extract online build information for the detected channel.
# 8  - Error: Unable to convert build strings to version objects.
# 9  - Error: Update did not complete within the timeout period.

#-----------------------------------------------

# Define arrays for the CDN base URLs and corresponding friendly channel names.
$CDNBaseUrls = @(
    "http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6",
    "http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60",
    "http://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be",
    "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114",
    "http://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf",
    "http://officecdn.microsoft.com/pr/5440fd1f-7ecb-4221-8110-145efaa6372f"
)
$CDNChannelName = @(
    "Monthly Enterprise Channel",
    "Current Channel",
    "Current Channel (Preview)",
    "Semi-Annual Enterprise Channel",
    "Semi-Annual Enterprise Channel (Preview)",
    "Beta Channel"
)

# Build a mapping hashtable from CDN URL to friendly channel name.
$channelMap = @{}
for ($i = 0; $i -lt $CDNBaseUrls.Count; $i++) {
    $channelMap[$CDNBaseUrls[$i]] = $CDNChannelName[$i]
}

# 1. Read installed Office version and UpdateChannel from the registry.
try {
    $regProps = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction Stop
    $ExistingVersionStr = $regProps.VersionToReport
    $updateChannelUrl = $regProps.UpdateChannel
} catch {
    Write-Host "Error: Unable to read Office configuration from the registry. Exiting with code 1."
    exit 1
}

# 2. Determine the friendly channel name from the UpdateChannel URL.
if ([string]::IsNullOrEmpty($updateChannelUrl)) {
    Write-Host "Warning: UpdateChannel registry value is empty. Defaulting to 'Current Channel'."
    $friendlyChannel = "Current Channel"
} elseif ($channelMap.ContainsKey($updateChannelUrl)) {
    $friendlyChannel = $channelMap[$updateChannelUrl]
} else {
    Write-Host "Error: UpdateChannel URL '$updateChannelUrl' is not recognized. Exiting with code 2."
    exit 2
}

# Convert installed version string to a System.Version object.
try {
    $ExistingVersion = [System.Version]$ExistingVersionStr
} catch {
    Write-Host "Error: Unable to convert version string '$ExistingVersionStr' to a version object. Exiting with code 3."
    exit 3
}

Write-Host "Office Update Process Started at $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')"
Write-Host "Installed Version: $ExistingVersionStr"
Write-Host "Detected Update Channel: $friendlyChannel"

# 3. Form the installed online build string from the Build and Revision parts.
$installedOnlineBuild = "$($ExistingVersion.Build).$($ExistingVersion.Revision)"
Write-Host "Installed Online Build: $installedOnlineBuild"

# 4. Retrieve the online update history page.
$url = 'https://learn.microsoft.com/en-us/officeupdates/update-history-microsoft365-apps-by-date'
try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Host "Error: Unable to fetch the update history page. Exiting with code 4."
    exit 4
}
$htmlContent = $response.Content

# 5. Choose a regex pattern based on the friendly channel.
switch ($friendlyChannel) {
    "Current Channel" { 
        $pattern = '(?s)<tr>.*?<td[^>]*>.*?(Current Channel(?: \(Preview\))?)\s*<br>.*?</td>\s*<td[^>]*>.*?<br>.*?<td[^>]*>\s*(?<onlineBuild>[\d\.]+)\s*<br>'
    }
    "Current Channel (Preview)" {
        $pattern = '(?s)<tr>.*?<td[^>]*>.*?(Current Channel(?: \(Preview\))?)\s*<br>.*?</td>\s*<td[^>]*>.*?<br>.*?<td[^>]*>\s*(?<onlineBuild>[\d\.]+)\s*<br>'
    }
    "Monthly Enterprise Channel" {
        $pattern = '(?s)<tr>.*?<td[^>]*>.*?Monthly Enterprise Channel\s*<br>.*?</td>\s*<td[^>]*>.*?<br>.*?<td[^>]*>\s*(?<onlineBuild>[\d\.]+)\s*<br>'
    }
    {$_ -match "Semi-Annual"} {
        $pattern = '(?s)<tr>.*?<td[^>]*>.*?Semi-Annual Enterprise Channel(?: \(Preview\))?\s*<br>.*?</td>\s*<td[^>]*>.*?<br>.*?<td[^>]*>\s*(?<onlineBuild>[\d\.]+)\s*<br>'
    }
    "Beta Channel" {
        Write-Host "Error: Beta Channel update checking is not supported by this script. Exiting with code 5."
        exit 5
    }
    Default {
        Write-Host "Error: Channel '$friendlyChannel' is not supported by this script. Exiting with code 6."
        exit 6
    }
}

if ($htmlContent -match $pattern) {
    $onlineBuild = $matches['onlineBuild']
    Write-Host "Latest online build for '$friendlyChannel': $onlineBuild"
} else {
    Write-Host "Error: Could not extract online build information for channel '$friendlyChannel'. Exiting with code 7."
    exit 7
}

# 6. Convert the installed and online build strings to version objects for comparison.
try {
    $installedVerObj = [System.Version]$installedOnlineBuild
    $onlineVerObj = [System.Version]$onlineBuild
} catch {
    Write-Host "Error: Unable to convert build strings to version objects. Exiting with code 8."
    exit 8
}

# 7. Compare and update if necessary.
if ($installedVerObj -lt $onlineVerObj) {
    Write-Host "An update is available: Installed build $installedOnlineBuild vs Online build $onlineBuild."
    Write-Host "Proceeding with update..."
    
    # Launch the update process.
    $updateCmd = "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe"
    $updateCmdParms = "/Update User displaylevel=false"
    Start-Process -FilePath $updateCmd -ArgumentList $updateCmdParms

    # Poll the registry for a version change (timeout after 10 minutes).
    $maxWaitSeconds = 600
    $pollInterval = 20
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
         Write-Host "Error: Update did not complete within $maxWaitSeconds seconds. Exiting with code 9."
         exit 9
    }
} else {
    Write-Host "Office is already up-to-date for channel '$friendlyChannel'. No update required. Exiting with code 0."
    exit 0
}
#-----------------------------------------------
