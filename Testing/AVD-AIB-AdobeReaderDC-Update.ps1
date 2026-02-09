<# =================================================================================================
AVD-AIB-AdobeReaderDC-Update.ps1
---------------------------------------------------------------------------------------------------
PURPOSE
  Installs / upgrades Adobe Acrobat Reader DC (64-bit MUI) only if the installed version is older.

WHY THIS EXISTS
  - Golden images often need a known Adobe baseline for app compatibility and security.
  - Adobe offline installer URLs are version-specific, so we compare installed version to TargetVersion.

LOGGING
  - This script writes output to STDOUT (captured by AppInstalls into a child log + Packer console)

EXIT CODES (CONTRACT)
  0    = success
  1    = fail
  3010 = reboot required (treated as success by the orchestrator)
================================================================================================= #>

param(
    # Target version to compare against (update these during image cycles)
    [string]$TargetVersion = "2025.001.20937",

    # Direct offline EXE URL (update this during image cycles)
    [string]$DownloadUrl = "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2500120937/AcroRdrDCx642500120937_MUI.exe"
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Where we stage the installer
$InstallerPath = "$env:TEMP\AcroRdrDCx64_$($TargetVersion).exe"

function Get-AdobeReaderInstall {
    # Search both 64-bit and WOW6432Node uninstall trees
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like "Adobe Acrobat Reader*64-bit*" -or
            $_.DisplayName -like "Adobe Acrobat Reader*DC*"     -or
            $_.DisplayName -like "Adobe Acrobat (64-bit)"
        } |
        Select-Object -First 1
}

function Uninstall-RegistryApp {
    param([Parameter(Mandatory)] $App)

    $uninstall = $App.UninstallString
    if (-not $uninstall) {
        Write-Host "No UninstallString found for $($App.DisplayName). Skipping uninstall."
        return
    }

    # If MSI GUID present, use msiexec /x
    if ($uninstall -match "{[0-9A-Fa-f-]+}") {
        $guid = $matches[0]
        Write-Host "Uninstalling via MSI: $guid"
        $p = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "MSI uninstall failed with exit code $($p.ExitCode)" }
    }
    else {
        # Fallback: execute uninstall string via cmd.exe
        Write-Host "Uninstalling via command string"
        $cmd = "$uninstall /quiet /norestart"
        $p = Start-Process "cmd.exe" -ArgumentList "/c $cmd" -Wait -PassThru
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "EXE uninstall failed with exit code $($p.ExitCode)" }
    }
}

try {
    Write-Host "Checking installed Adobe Reader / Acrobat version..."

    $existing  = Get-AdobeReaderInstall
    $targetVer = [version]$TargetVersion

    if ($existing) {
        $installedVer = [version]($existing.DisplayVersion -replace "[^0-9\.]", "")
        Write-Host "Installed version: $installedVer"

        if ($installedVer -ge $targetVer) {
            Write-Host "Installed version is up to date. No action required."
            Write-Host "Adobe Reader update completed successfully."
            exit 0
        }

        Write-Host "Installed version is older. Uninstalling..."
        Uninstall-RegistryApp -App $existing
    }
    else {
        Write-Host "No existing Adobe Reader found."
    }

    if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue }

    Write-Host "Downloading offline Adobe Reader installer..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing

    $size = (Get-Item $InstallerPath).Length
    if ($size -lt 50000000) { throw "Installer too small (likely corrupted). Size=$size" }

    Write-Host "Installing Adobe Reader silently..."
    $p = Start-Process -FilePath $InstallerPath -ArgumentList "/sAll /rs /rps /msi /norestart /quiet" -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "Installer failed with exit code $($p.ExitCode)" }

    Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue

    Write-Host "Adobe Reader update completed successfully."
    exit 0
}
catch {
    Write-Host "Adobe Reader update failed: $($_.Exception.Message)"
    exit 1
}
