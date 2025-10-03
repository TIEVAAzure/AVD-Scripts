#Remove-AppxPackage -Package "Microsoft.LanguageExperiencePacken-GB_19041.62.219.0_neutral__8wekyb3d8bbwe" -AllUsers
#Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7
#Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "CleanupState" -Value 2# Uninstall Adobe Acrobat (if present)
$App = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" ,
                        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" |
        Where-Object { $_.DisplayName -eq "Adobe Acrobat (64-bit)" }

if ($App) {
    Write-Host "Uninstalling $($App.DisplayName) $($App.DisplayVersion)..."
    & $App.UninstallString /quiet /norestart
}

# Adobe Acrobat Reader DC (free) — 64-bit, MUI offline installer
$Url       = "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2500120756/AcroRdrDCx642500120756_MUI.exe"
$Installer = "$env:TEMP\AcroRdrDCx64.exe"

# Download
Write-Host "Downloading Adobe Reader..."
Invoke-WebRequest -Uri $Url -OutFile $Installer

# Silent install (no UI, no reboot)
Write-Host "Installing Adobe Reader..."
Start-Process -FilePath $Installer -ArgumentList "/sAll /rs /rps /msi /norestart /quiet" -Wait

# Clean up
Remove-Item $Installer -Force

Write-Host "✅ Adobe Acrobat Reader (x64, free) installed."
