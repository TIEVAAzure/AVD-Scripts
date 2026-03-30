<# =================================================================================================
AVD-AIB-FoxitPDFReader-Update.ps1
---------------------------------------------------------------------------------------------------
PURPOSE
  Installs / upgrades Foxit PDF Reader only if the installed version is older than the target.

WHY THIS EXISTS
  - Golden images often need a known PDF reader baseline for app compatibility and security.
  - Foxit package URLs can change, so this script compares installed version to TargetVersion first.

LOGGING
  - This script writes output to STDOUT (captured by AppInstalls into a child log + Packer console)

EXIT CODES (CONTRACT)
  0    = success
  1    = fail
  3010 = reboot required (treated as success by the orchestrator)
================================================================================================= #>

param(
    # Target version to compare against
    [string]$TargetVersion = "2025.3.0.35737",

    # Enterprise/offline installer path or URL
    # Replace with your Foxit enterprise EXE package URL if downloading directly
    [string]$DownloadUrl = "https://REPLACE-WITH-YOUR-FOXIT-ENTERPRISE-PACKAGE/FoxitPDFReader2025.3.0.35737_enu_Setup_Prom.exe",

    # Optional local installer override (useful in AIB if you pre-stage the installer)
    [string]$LocalInstallerPath = "",

    # Minimum expected size to catch bad downloads
    [int64]$MinimumInstallerBytes = 30000000
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$InstallerPath = if ($LocalInstallerPath) {
    $LocalInstallerPath
} else {
    Join-Path $env:TEMP "FoxitPDFReader_$($TargetVersion).exe"
}

function Get-FoxitReaderInstall {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -match "^Foxit PDF Reader" -or
            $_.DisplayName -match "^Foxit Reader"
        } |
        Sort-Object DisplayVersion -Descending |
        Select-Object -First 1
}

function Convert-ToVersion {
    param([string]$VersionString)

    if ([string]::IsNullOrWhiteSpace($VersionString)) {
        return $null
    }

    # Keep digits and dots only, then normalise to System.Version friendly format
    $clean = ($VersionString -replace '[^0-9\.]', '').Trim('.')
    if (-not $clean) { return $null }

    $parts = $clean.Split('.')
    while ($parts.Count -lt 4) {
        $parts += '0'
    }

    $normalised = ($parts[0..3] -join '.')
    try {
        return [version]$normalised
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
        return 0
    }

    if ($uninstall -match "{[0-9A-Fa-f-]+}") {
        $guid = $matches[0]
        Write-Host "Uninstalling via MSI: $guid"
        $p = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            throw "MSI uninstall failed with exit code $($p.ExitCode)"
        }
        return $p.ExitCode
    }
    else {
        Write-Host "Uninstalling via command string"

        # Some uninstall strings are already quoted / parameterised, so run via cmd.exe
        $cmd = "$uninstall /quiet /norestart"
        $p = Start-Process "cmd.exe" -ArgumentList "/c $cmd" -Wait -PassThru
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            throw "EXE uninstall failed with exit code $($p.ExitCode)"
        }
        return $p.ExitCode
    }
}

try {
    Write-Host "Checking installed Foxit PDF Reader version..."

    $existing   = Get-FoxitReaderInstall
    $targetVer  = Convert-ToVersion -VersionString $TargetVersion
    $rebootCode = 0

    if (-not $targetVer) {
        throw "TargetVersion '$TargetVersion' could not be parsed into a valid version."
    }

    if ($existing) {
        $installedVer = Convert-ToVersion -VersionString $existing.DisplayVersion
        Write-Host "Detected installed product: $($existing.DisplayName)"
        Write-Host "Installed version raw: $($existing.DisplayVersion)"
        Write-Host "Installed version parsed: $installedVer"

        if ($installedVer -and $installedVer -ge $targetVer) {
            Write-Host "Installed version is up to date. No action required."
            Write-Host "Foxit PDF Reader update completed successfully."
            exit 0
        }

        Write-Host "Installed version is older or could not be reliably parsed. Uninstalling existing version..."
        $rebootCode = Uninstall-RegistryApp -App $existing
    }
    else {
        Write-Host "No existing Foxit PDF Reader installation found."
    }

    if (-not $LocalInstallerPath) {
        if (Test-Path $InstallerPath) {
            Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Downloading Foxit PDF Reader installer..."
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing

        $size = (Get-Item $InstallerPath).Length
        Write-Host "Downloaded installer size: $size bytes"
        if ($size -lt $MinimumInstallerBytes) {
            throw "Installer too small (likely corrupted or not the real package). Size=$size"
        }
    }
    else {
        if (-not (Test-Path $InstallerPath)) {
            throw "Local installer path not found: $InstallerPath"
        }

        $size = (Get-Item $InstallerPath).Length
        Write-Host "Using pre-staged installer: $InstallerPath"
        Write-Host "Installer size: $size bytes"
        if ($size -lt $MinimumInstallerBytes) {
            throw "Local installer too small (likely wrong file). Size=$size"
        }
    }

    Write-Host "Installing Foxit PDF Reader silently..."
    # Foxit EXE silent install
    $p = Start-Process -FilePath $InstallerPath -ArgumentList "/quiet" -Wait -PassThru

    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "Installer failed with exit code $($p.ExitCode)"
    }

    if (-not $LocalInstallerPath) {
        Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
    }

    $finalCode = if ($p.ExitCode -eq 3010 -or $rebootCode -eq 3010) { 3010 } else { 0 }

    Write-Host "Foxit PDF Reader update completed successfully."
    exit $finalCode
}
catch {
    Write-Host "Foxit PDF Reader update failed: $($_.Exception.Message)"
    exit 1
}
