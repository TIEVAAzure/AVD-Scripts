<# =================================================================================================
AVD-AIB-FoxitPDFReader-Update.ps1
---------------------------------------------------------------------------------------------------
PURPOSE
  Installs / upgrades Foxit PDF Reader only if the installed version is older.

WHY THIS EXISTS
  - Golden images often need a known PDF reader baseline for app compatibility and security.
  - Some older Foxit versions do not upgrade cleanly in-place, so this script removes the old version first.

LOGGING
  - This script writes output to STDOUT (captured by AppInstalls into a child log + Packer console)

EXIT CODES (CONTRACT)
  0    = success
  1    = fail
  3010 = reboot required (treated as success by the orchestrator)
================================================================================================= #>

param(
    # Target version to compare against (update these during image cycles)
    [string]$TargetVersion = "2025.3.0.35737",

    # Direct offline EXE URL (update this during image cycles)
    [string]$DownloadUrl = "https://www.foxit.com/downloads/latest.html?product=Foxit-Reader&platform=Windows&version=&package_type=exe&language=ML&distID=&operating_type=64"
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Where we stage the installer
$InstallerPath = "$env:TEMP\FoxitPDFReader_$($TargetVersion).exe"

function Get-FoxitReaderInstall {
    # Search both 64-bit and WOW6432Node uninstall trees
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like "Foxit PDF Reader*" -or
            $_.DisplayName -like "Foxit Reader*"
        } |
        Select-Object -First 1
}

function Convert-ToVersion {
    param([string]$VersionString)

    if ([string]::IsNullOrWhiteSpace($VersionString)) {
        return $null
    }

    $clean = ($VersionString -replace '[^0-9\.]', '').Trim('.')
    if (-not $clean) {
        return $null
    }

    $parts = $clean.Split('.')
    while ($parts.Count -lt 4) {
        $parts += '0'
    }

    $normalized = ($parts[0..3] -join '.')

    try {
        return [version]$normalized
    }
    catch {
        return $null
    }
}

function Uninstall-RegistryApp {
    param([Parameter(Mandatory)] $App)

    $uninstall = $App.UninstallString
    if (-not $uninstall) {
        Write-Host "No UninstallString found for $($App.DisplayName). Skipping uninstall."
        return
    }

    Write-Host "Uninstall string detected: $uninstall"

    # If MSI GUID present, use msiexec /x
    if ($uninstall -match "{[0-9A-Fa-f-]+}") {
        $guid = $matches[0]
        Write-Host "Uninstalling via MSI: $guid"
        $p = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            throw "MSI uninstall failed with exit code $($p.ExitCode)"
        }
        return
    }

    # If Foxit old-style uninstaller exists, prefer that
    if ($uninstall -match 'unins[0-9]*\.exe') {
        Write-Host "Uninstalling via Foxit uninstaller"
        $p = Start-Process "cmd.exe" -ArgumentList "/c `"$uninstall /silent /norestart`"" -Wait -PassThru
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            throw "Foxit uninstall failed with exit code $($p.ExitCode)"
        }
        return
    }

    # Fallback: execute uninstall string via cmd.exe
    Write-Host "Uninstalling via command string"
    $cmd = "$uninstall /quiet /norestart"
    $p = Start-Process "cmd.exe" -ArgumentList "/c $cmd" -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "EXE uninstall failed with exit code $($p.ExitCode)"
    }
}

try {
    Write-Host "Checking installed Foxit PDF Reader version..."

    $existing  = Get-FoxitReaderInstall
    $targetVer = Convert-ToVersion -VersionString $TargetVersion
    $rebootRequired = $false

    if (-not $targetVer) {
        throw "Could not parse target version: $TargetVersion"
    }

    if ($existing) {
        $installedVer = Convert-ToVersion -VersionString $existing.DisplayVersion
        Write-Host "Installed product: $($existing.DisplayName)"
        Write-Host "Installed version: $($existing.DisplayVersion)"

        if ($installedVer -and $installedVer -ge $targetVer) {
            Write-Host "Installed version is up to date. No action required."
            Write-Host "Foxit PDF Reader update completed successfully."
            exit 0
        }

        Write-Host "Installed version is older. Uninstalling existing version first..."
        Uninstall-RegistryApp -App $existing

        Write-Host "Waiting briefly after uninstall..."
        Start-Sleep -Seconds 10
    }
    else {
        Write-Host "No existing Foxit PDF Reader found."
    }

    if (Test-Path $InstallerPath) {
        Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Downloading offline Foxit PDF Reader installer..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing

    $size = (Get-Item $InstallerPath).Length
    Write-Host "Downloaded installer size: $size bytes"
    if ($size -lt 30000000) {
        throw "Installer too small (likely corrupted). Size=$size"
    }

    Write-Host "Installing Foxit PDF Reader silently..."
    $p = Start-Process -FilePath $InstallerPath -ArgumentList "/quiet" -Wait -PassThru
    if ($p.ExitCode -eq 3010) {
        $rebootRequired = $true
    }
    elseif ($p.ExitCode -ne 0) {
        throw "Installer failed with exit code $($p.ExitCode)"
    }

    Write-Host "Waiting briefly after install..."
    Start-Sleep -Seconds 10

    Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue

    Write-Host "Foxit PDF Reader update completed successfully."
    if ($rebootRequired) {
        exit 3010
    }

    exit 0
}
catch {
    Write-Host "Foxit PDF Reader update failed: $($_.Exception.Message)"
    exit 1
}
