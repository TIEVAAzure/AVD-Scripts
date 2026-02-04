<# 
.SYNOPSIS
    Removes 7-Zip if installed (MSI, EXE, AppX/MSIX).

.DESCRIPTION
    - exit 0 = success OR not installed
    - exit 1 = failure
    - Designed for AVD AIB / Packer (explicit LASTEXITCODE control)
#>

param()

$ErrorActionPreference = 'Continue'
$global:LASTEXITCODE = 0
$global:LastExitCode  = 0

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ------------------------------------------------------------------
function Get-7ZipInstall {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '(?i)\b7[\s\-]?zip\b' } |
        Select-Object -First 1
}

function Uninstall-RegistryApp {
    param([Parameter(Mandatory)] $App)

    $uninstall = $App.QuietUninstallString
    if (-not $uninstall) { $uninstall = $App.UninstallString }

    if (-not $uninstall) {
        Write-Host "No uninstall string found for $($App.DisplayName)"
        return 0
    }

    # MSI uninstall
    if ($uninstall -match "{[0-9A-Fa-f-]+}") {
        $guid = $matches[0]
        Write-Host "Uninstalling 7-Zip via MSI ($guid)"
        $p = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        $global:LASTEXITCODE = $p.ExitCode
        $global:LastExitCode  = $p.ExitCode
        return $p.ExitCode
    }

    # EXE / command uninstall
    Write-Host "Uninstalling 7-Zip via uninstall command"
    $p = Start-Process "cmd.exe" -ArgumentList "/c $uninstall" -Wait -PassThru
    $global:LASTEXITCODE = $p.ExitCode
    $global:LastExitCode  = $p.ExitCode
    return $p.ExitCode
}

function Remove-7ZipAppx {
    try {
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)7zip|7-zip' } |
            ForEach-Object {
                Write-Host "Removing AppX package: $($_.Name)"
                Remove-AppxPackage -AllUsers -Package $_.PackageFullName -ErrorAction SilentlyContinue
            }

        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '(?i)7zip|7-zip' } |
            ForEach-Object {
                Write-Host "Deprovisioning AppX package: $($_.DisplayName)"
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
    }
    catch {
        Write-Host "Warning during AppX cleanup: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------
Write-Host "Checking for installed 7-Zip..."

$existing = Get-7ZipInstall

if ($existing) {
    Write-Host "Found 7-Zip: $($existing.DisplayName) $($existing.DisplayVersion)"
    $code = Uninstall-RegistryApp -App $existing

    if ($code -ne 0) {
        Write-Host "7-Zip uninstall failed with exit code $code"
        $global:LASTEXITCODE = 1
        $global:LastExitCode  = 1
        exit 1
    }
}
else {
    Write-Host "7-Zip not installed."
}

# Always attempt AppX/MSIX cleanup as well
Remove-7ZipAppx

Write-Host "7-Zip removal completed successfully."
$global:LASTEXITCODE = 0
$global:LastExitCode  = 0
exit 0
