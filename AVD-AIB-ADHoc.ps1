#Remove-AppxPackage -Package "Microsoft.LanguageExperiencePacken-GB_19041.62.219.0_neutral__8wekyb3d8bbwe" -AllUsers
#Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7
#Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "CleanupState" -Value 2# Uninstall Adobe Acrobat (if present)
# ==============================
# AVD Image Update: Adobe Reader DC (x64, MUI) + 8x8 Work
# ==============================
# --- CONFIG ---

# Adobe Reader DC offline installer (use your fixed URL here)
$AdobeUrl       = "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2500120937/AcroRdrDCx642500120937_MUI.exe"
$AdobeInstaller = "$env:TEMP\AcroReaderDCx64.exe"

# 8x8 Work 64-bit MSI
$EightByEightUrl       = "https://work-desktop-assets.8x8.com/prod-publish/ga/work-64-msi-v8.28.2-3.msi"
$EightByEightInstaller = "$env:TEMP\8x8-work-64.msi"

# Optional: ensure TLS 1.2 for Invoke-WebRequest on older systems
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

# ==============================
# Helper: generic uninstall via UninstallString
# ==============================
function Invoke-UninstallString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UninstallString,
        [string]$DisplayName = "Application"
    )

    Write-Host "Uninstalling $DisplayName ..."
    
    # Wrap the uninstall string and append silent flags
    $cmd = "$UninstallString /quiet /norestart"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait
}

# ==============================
# 1. Detect installed apps once
# ==============================
Write-Host "Checking for existing Adobe and 8x8 installs..."

$Apps = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" ,
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue

# ==============================
# 2. Uninstall existing Adobe Reader / Acrobat
# ==============================
$AdobeApps = $Apps | Where-Object {
    $_.DisplayName -like "Adobe*Reader*" -or
    $_.DisplayName -like "Adobe Acrobat*"
}

if ($AdobeApps) {
    foreach ($app in $AdobeApps) {
        Invoke-UninstallString -UninstallString $app.UninstallString -DisplayName $app.DisplayName
    }
} else {
    Write-Host "No existing Adobe Reader/Acrobat found. Skipping Adobe uninstall."
}

# ==============================
# 3. Uninstall existing 8x8 Work
# ==============================
$EightByEightApps = $Apps | Where-Object {
    $_.DisplayName -like "8x8*" -or
    $_.Publisher   -like "*8x8*"
}

if ($EightByEightApps) {
    foreach ($app in $EightByEightApps) {
        Invoke-UninstallString -UninstallString $app.UninstallString -DisplayName $app.DisplayName
    }
} else {
    Write-Host "No existing 8x8 Work install found. Skipping 8x8 uninstall."
}

# ==============================
# 4. Download and install Adobe Reader DC (offline)
# ==============================

# Clean any previous installer
if (Test-Path $AdobeInstaller) {
    Remove-Item $AdobeInstaller -Force -ErrorAction SilentlyContinue
}

Write-Host "Downloading Adobe Reader DC (offline installer) from $AdobeUrl ..."
Invoke-WebRequest -Uri $AdobeUrl -OutFile $AdobeInstaller -UseBasicParsing

# Sanity check: make sure it is not a tiny / corrupt file
if (Test-Path $AdobeInstaller) {
    $size = (Get-Item $AdobeInstaller).Length
    Write-Host "Downloaded Adobe installer size: $size bytes"

    if ($size -lt 50000000) {
        Write-Host "Download looks too small to be the full offline installer. Aborting."
        exit 1
    }
} else {
    Write-Host "Adobe installer file was not created. Aborting."
    exit 1
}

Write-Host "Installing Adobe Reader DC (silent)..."
Start-Process -FilePath $AdobeInstaller -ArgumentList "/sAll /rs /rps /msi /norestart /quiet" -Wait

Remove-Item $AdobeInstaller -Force -ErrorAction SilentlyContinue

# ==============================
# 5. Download and install 8x8 Work MSI
# ==============================

# Clean any previous MSI
if (Test-Path $EightByEightInstaller) {
    Remove-Item $EightByEightInstaller -Force -ErrorAction SilentlyContinue
}

Write-Host "Downloading 8x8 Work 64-bit MSI from $EightByEightUrl ..."
Invoke-WebRequest -Uri $EightByEightUrl -OutFile $EightByEightInstaller -UseBasicParsing

if (Test-Path $EightByEightInstaller) {
    $size8x8 = (Get-Item $EightByEightInstaller).Length
    Write-Host "Downloaded 8x8 MSI size: $size8x8 bytes"
} else {
    Write-Host "8x8 MSI file was not created. Aborting."
    exit 1
}

Write-Host "Installing 8x8 Work 8.28.2-3 (silent)..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$EightByEightInstaller`" /qn /norestart ALLUSERS=1" -Wait

Remove-Item $EightByEightInstaller -Force -ErrorAction SilentlyContinue

Write-Host "Image updated successfully - Adobe Reader DC and 8x8 Work have been installed."
