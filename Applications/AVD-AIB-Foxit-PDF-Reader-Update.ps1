<# =================================================================================================
AVD-AIB-FoxitPDFReader-Update.ps1
---------------------------------------------------------------------------------------------------
PURPOSE
  Installs / upgrades Foxit PDF Reader only if the installed version is older.

NOTES
  - For Foxit, in-place upgrade is preferred over uninstall/reinstall to avoid interactive uninstall prompts.
  - This script writes output to STDOUT for capture by AppInstalls / Packer.

EXIT CODES
  0    = success
  1    = fail
  3010 = reboot required
================================================================================================= #>

param(
    [string]$TargetVersion = "2025.3.0.35737",

    # Replace with your actual Foxit package URL or use LocalInstallerPath
    [string]$DownloadUrl = "https://www.foxit.com/downloads/latest.html?product=Foxit-Reader&platform=Windows&version=&package_type=exe&language=ML&distID=&operating_type=64",

    # Optional pre-staged installer path
    [string]$LocalInstallerPath = "",

    [int64]$MinimumInstallerBytes = 30000000
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$UniqueName = "FoxitPDFReader_{0}_{1}.exe" -f $TargetVersion, ([guid]::NewGuid().ToString("N"))
$InstallerPath = if ($LocalInstallerPath) { $LocalInstallerPath } else { Join-Path $env:TEMP $UniqueName }

function Get-FoxitReaderInstall {
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

    if ([string]::IsNullOrWhiteSpace($VersionString)) { return $null }

    $clean = ($VersionString -replace '[^0-9\.]', '').Trim('.')
    if (-not $clean) { return $null }

    $parts = $clean.Split('.')
    while ($parts.Count -lt 4) { $parts += '0' }

    $normalized = ($parts[0..3] -join '.')

    try {
        return [version]$normalized
    }
    catch {
        Write-Host "Failed to parse version string: $VersionString"
        return $null
    }
}

try {
    Write-Host "Checking installed Foxit PDF Reader version..."

    $existing  = Get-FoxitReaderInstall
    $targetVer = Convert-ToVersion -VersionString $TargetVersion

    if (-not $targetVer) {
        throw "TargetVersion '$TargetVersion' could not be parsed."
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

        Write-Host "Installed version is older. Proceeding with in-place upgrade."
    }
    else {
        Write-Host "No existing Foxit PDF Reader installation found. Proceeding with install."
    }

    if (-not $LocalInstallerPath) {
        if (Test-Path $InstallerPath) {
            Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Downloading offline Foxit PDF Reader installer..."
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing

        $size = (Get-Item $InstallerPath).Length
        Write-Host "Downloaded installer size: $size bytes"

        if ($size -lt $MinimumInstallerBytes) {
            throw "Installer too small (likely corrupted). Size=$size"
        }
    }
    else {
        if (-not (Test-Path $InstallerPath)) {
            throw "Local installer path not found: $InstallerPath"
        }

        $size = (Get-Item $InstallerPath).Length
        Write-Host "Using pre-staged installer: $InstallerPath"

        if ($size -lt $MinimumInstallerBytes) {
            throw "Local installer too small (likely incorrect file). Size=$size"
        }
    }

    Write-Host "Installing / upgrading Foxit PDF Reader silently..."
    $p = Start-Process -FilePath $InstallerPath -ArgumentList "/quiet /norestart" -Wait -PassThru

    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "Installer failed with exit code $($p.ExitCode)"
    }

    Start-Sleep -Seconds 15

    if (-not $LocalInstallerPath) {
        Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Foxit PDF Reader update completed successfully."
    exit $p.ExitCode
}
catch {
    Write-Host "Foxit PDF Reader update failed: $($_.Exception.Message)"
    exit 1
}
