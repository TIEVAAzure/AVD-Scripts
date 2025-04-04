# Check if the script is running with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Restarting script with elevated privileges..."
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Define the source URL and the target executable name
$SourceUrl = "https://www.microsoft.com/en-us/download/details.aspx?id=58494"
$TargetExecutable = "PBIDesktopSetup_x64.exe"

# Define the local path to save the downloaded source code
$SourceFilePath = Join-Path -Path $env:TEMP -ChildPath "SourceCode.html"

# Download the source code
Write-Host "Downloading source code from $SourceUrl..."
Invoke-WebRequest -Uri $SourceUrl -OutFile $SourceFilePath

# Verify the source code was downloaded
if (-not (Test-Path -Path $SourceFilePath)) {
    Write-Error "Failed to download source code."
    exit 1
}

# Read the source code and find the URL for the target executable
$SourceCode = Get-Content -Path $SourceFilePath
$DownloadUrl = $SourceCode | Select-String -Pattern $TargetExecutable | ForEach-Object {
    if ($_ -match 'https?://[^\s"]*' + [regex]::Escape($TargetExecutable)) {
        $matches[0]
    }
}

if (-not $DownloadUrl) {
    Write-Error "Download URL for $TargetExecutable not found in the source code."
    exit 1
}

# Define the local path to save the downloaded file
$DownloadPath = Join-Path -Path $env:TEMP -ChildPath $TargetExecutable

# Download the executable
Write-Host "Downloading $TargetExecutable from $DownloadUrl..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $DownloadPath

# Verify the file was downloaded
if (-not (Test-Path -Path $DownloadPath)) {
    Write-Error "Failed to download $TargetExecutable."
    exit 1
}

# Install the application in silent mode without prompts
Write-Host "Installing $TargetExecutable in silent mode without prompts..."
Start-Process -FilePath $DownloadPath -ArgumentList "/quiet /norestart" -Wait

# Clean up the downloaded files
Write-Host "Cleaning up..."
Remove-Item -Path $DownloadPath -Force
Remove-Item -Path $SourceFilePath -Force

Write-Host "$TargetExecutable installation completed successfully."
