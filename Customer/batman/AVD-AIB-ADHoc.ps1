Remove-AppxPackage -Package "Microsoft.LanguageExperiencePacken-GB_19041.62.219.0_neutral__8wekyb3d8bbwe" -AllUsers
Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7
############################################################
# Hide problematic Windows Update causing AIB reboot loop
############################################################

try {
    $KBToHide = "KB5084068"

    Write-Output "Attempting to hide Windows Update: $KBToHide"

    # Ensure NuGet provider is available for module install
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

    # Trust PSGallery to avoid prompt
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

    # Install and import PSWindowsUpdate
    Install-Module -Name PSWindowsUpdate -Force -AllowClobber

    Import-Module PSWindowsUpdate

    # Hide the problematic update
    Hide-WindowsUpdate -KBArticleID $KBToHide -AcceptAll -Verbose

    Write-Output "Checking if $KBToHide is still visible after hide attempt..."

    $Result = Get-WindowsUpdate -MicrosoftUpdate | Where-Object {
        $_.KB -match "5084068"
    }

    if ($Result) {
        Write-Output "$KBToHide is still visible after hide attempt:"
        Write-Output $Result
    }
    else {
        Write-Output "$KBToHide is no longer visible to PSWindowsUpdate."
    }

    Write-Output "Completed Windows Update hide section."
}
catch {
    Write-Output "Failed to hide Windows Update $KBToHide"
    Write-Output $_
}
