#Remove-AppxPackage -Package "Microsoft.LanguageExperiencePacken-GB_19041.62.219.0_neutral__8wekyb3d8bbwe" -AllUsers
#Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7
#Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "CleanupState" -Value 2# Uninstall Adobe Acrobat (if present)
# ==============================
# Config
# ==============================

# Adobe Reader DC — redirect link you provided
$AdobeUrl       = "https://get.adobe.com/uk/reader/download?os=Windows+11&name=Reader+2025.001.20937+MUI+for+Windows-64bit&lang=mui&nativeOs=Windows+10&accepted=&declined=&preInstalled=&site=enterprise"
$AdobeInstaller = "$env:TEMP\AcroReaderDCx64.exe"

# 8x8 Work 64-bit MSI (new build)
$EightByEightUrl = "https://work-desktop-assets.8x8.com/prod-publish/ga/work-64-msi-v8.28.2-3.msi"
$EightByEightInstaller = "$env:TEMP\8x8-work-64.msi"


# ==============================
# Uninstall old versions if present
# ==============================

Write-Host "Checking for existing Adobe/8x8 installs..."

$Apps = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" ,
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue

# Adobe removal
$AdobeApp = $Apps | Where-Object { $_.DisplayName -like "Adobe*Reader*" -or $_.DisplayName -like "Adobe Acrobat*" }
if ($AdobeApp) {
    Write-Host "Uninstalling $($AdobeApp.DisplayName) $($AdobeApp.DisplayVersion)..."
    Start-Process "cmd.exe" -ArgumentList "/c $($AdobeApp.UninstallString) /quiet /norestart" -Wait
} else {
    Write-Host "No existing Adobe Reader/Acrobat found — skipping."
}

# 8x8 removal
$EightByEightApp = $Apps | Where-Object { $_.DisplayName -like "8x8*" }
if ($EightByEightApp) {
    Write-Host "Uninstalling $($EightByEightApp.DisplayName)..."
    Start-Process "cmd.exe" -ArgumentList "/c $($EightByEightApp.UninstallString) /quiet /norestart" -Wait
} else {
    Write-Host "No existing 8x8 Work install found — skipping."
}


# ==============================
# Install Adobe Reader x64 — offline installer download via redirect
# ==============================

Write-Host "Downloading Adobe Reader DC from redirect URL..."
Invoke-WebRequest -Uri $AdobeUrl -OutFile $AdobeInstaller -UseBasicParsing -MaximumRedirection 5

Write-Host "Installing Adobe Reader DC (silent)..."
Start-Process -FilePath $AdobeInstaller -ArgumentList "/sAll /rs /rps /msi /norestart /quiet" -Wait

Remove-Item $AdobeInstaller -Force -ErrorAction SilentlyContinue


# ==============================
# Install 8x8 Work MSI
# ==============================

Write-Host "Downloading 8x8 Work 64-bit MSI..."
Invoke-WebRequest -Uri $EightByEightUrl -OutFile $EightByEightInstaller -UseBasicParsing

Write-Host "Installing 8x8 Work 8.28.2-3 (silent)..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$EightByEightInstaller`" /qn /norestart ALLUSERS=1" -Wait

Remove-Item $EightByEightInstaller -Force -ErrorAction SilentlyContinue


Write-Host "🎉 Image updated successfully — Adobe Reader + 8x8 updated!"
