<# =================================================================================================
AVD-AIB-8x8-Update.ps1
---------------------------------------------------------------------------------------------------
PURPOSE
  Installs / upgrades 8x8 Work Desktop (64-bit) only if older version detected.

WHY THIS EXISTS
  - Keeps the golden image on a defined version baseline
  - Avoids reinstalling when already up to date

LOGGING
  - This script writes output to STDOUT (captured by AppInstalls into a child log + Packer console)

EXIT CODES (CONTRACT)
  0    = success
  1    = fail
  3010 = reboot required (treated as success by the orchestrator)
================================================================================================= #>

param(
    # Normalised version number (v8.28.2-3 -> 8.28.2.3)
    [string]$TargetVersion = "8.28.2.3",

    # Public MSI installer URL (update this during image cycles)
    [string]$DownloadUrl = "https://work-desktop-assets.8x8.com/prod-publish/ga/work-64-msi-v8.28.2-3.msi"
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Download staging location (version-tagged)
$InstallerPath = "$env:TEMP\8x8-work-64_$($TargetVersion).msi"

function Get-8x8WorkInstall {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like "8x8 Work*" -or
            $_.Publisher -like "*8x8*"
        } |
        Select-Object -First 1
}

function Uninstall-RegistryApp {
    param([Parameter(Mandatory)] $App)

    $uninstall = $App.UninstallString
    if (-not $uninstall) { return }

    if ($uninstall -match "{[0-9A-Fa-f-]+}") {
        $guid = $matches[0]
        Write-Host "Uninstalling via MSI: $guid"
        $p = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "MSI uninstall failed with exit code $($p.ExitCode)" }
    }
    else {
        Write-Host "Uninstalling via command string..."
        $cmd = "$uninstall /quiet /norestart"
        $p = Start-Process "cmd.exe" -ArgumentList "/c $cmd" -Wait -PassThru
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "EXE uninstall failed with exit code $($p.ExitCode)" }
    }
}

try {
    Write-Host "Checking installed 8x8 Work version..."

    $existing  = Get-8x8WorkInstall
    $targetVer = [version]$TargetVersion

    if ($existing) {
        $installedVer = [version]($existing.DisplayVersion -replace "[^0-9\.]", "")
        Write-Host "Installed version: $installedVer"

        if ($installedVer -ge $targetVer) {
            Write-Host "8x8 Work version is current. No update needed."
            Write-Host "8x8 Work update completed successfully."
            exit 0
        }

        Write-Host "Existing version is older. Uninstalling..."
        Uninstall-RegistryApp -App $existing
    }
    else {
        Write-Host "8x8 Work not currently installed."
    }

    if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue }

    Write-Host "Downloading 8x8 Work MSI..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing

    $size = (Get-Item $InstallerPath).Length
    if ($size -lt 20000000) { throw "Download failed or corrupted. Size=$size" }

    Write-Host "Installing 8x8 Work silently..."
    $p = Start-Process "msiexec.exe" -ArgumentList "/i `"$InstallerPath`" /qn /norestart ALLUSERS=1" -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "MSI install failed with exit code $($p.ExitCode)" }

    Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue

    Write-Host "8x8 Work update completed successfully."
    exit 0
}
catch {
    Write-Host "8x8 Work update failed: $($_.Exception.Message)"
    exit 1
}
