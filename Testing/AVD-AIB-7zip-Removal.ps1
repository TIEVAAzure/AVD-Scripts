<# =================================================================================================
AVD-AIB-7zip-Removal.ps1
---------------------------------------------------------------------------------------------------
PURPOSE
  Removes 7-Zip if installed (MSI, EXE, AppX/MSIX).

PACKER VISIBILITY
  Uses Write-Host for milestone output so progress is visible in AIB/Packer logs.

EXIT CODES (CONTRACT)
  0 = success (including "not installed" OR "reboot required")
  1 = failure
================================================================================================= #>

param()

$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# --------------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------------

function Get-7ZipInstall {
    # Search both 64-bit and WOW6432Node uninstall trees
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
        Write-Host ">>> 7-Zip: No uninstall string found for '$($App.DisplayName)'."
        return 0
    }

    # MSI uninstall (GUID present)
    if ($uninstall -match "{[0-9A-Fa-f-]+}") {
        $guid = $matches[0]
        Write-Host ">>> 7-Zip: Uninstalling via MSI GUID: $guid"
        $p = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        return $p.ExitCode
    }

    # EXE / command uninstall
    $cmdLine = $uninstall.Trim()

    # Belt & braces: if uninstall string does not look silent, append common silent switch.
    $looksSilent =
        ($cmdLine -match '(?i)\s/quiet\b') -or
        ($cmdLine -match '(?i)\s/silent\b') -or
        ($cmdLine -match '(?i)\s/verysilent\b') -or
        ($cmdLine -match '(?i)\s/qn\b') -or
        ($cmdLine -match '(?i)\s/s\b') -or
        ($cmdLine -match '(?i)\s/unattended\b')

    if (-not $looksSilent) {
        # 7-Zip EXE uninstallers commonly accept /S (NSIS-style)
        $cmdLine = "$cmdLine /S"
        Write-Host ">>> 7-Zip: Appending silent switch (/S) to uninstall command."
    }

    Write-Host ">>> 7-Zip: Uninstalling via uninstall command string"
    $p = Start-Process "cmd.exe" -ArgumentList "/c $cmdLine" -Wait -PassThru
    return $p.ExitCode
}

function Remove-7ZipAppx {
    # Installed for users (Store app etc.)
    $pkgs = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)7zip|7-zip' })
    if ($pkgs.Count -gt 0) {
        foreach ($p in $pkgs) {
            Write-Host ">>> 7-Zip: Removing AppX package: $($p.Name)"
            try { Remove-AppxPackage -AllUsers -Package $p.PackageFullName -ErrorAction Stop } catch { Write-Host ">>> 7-Zip: Warning removing AppX: $($_.Exception.Message)" }
        }
    } else {
        Write-Host ">>> 7-Zip: No AppX packages found."
    }

    # Provisioned in the image
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '(?i)7zip|7-zip' })
    if ($prov.Count -gt 0) {
        foreach ($pp in $prov) {
            Write-Host ">>> 7-Zip: Deprovisioning AppX package: $($pp.DisplayName)"
            try { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null } catch { Write-Host ">>> 7-Zip: Warning deprovisioning AppX: $($_.Exception.Message)" }
        }
    } else {
        Write-Host ">>> 7-Zip: No provisioned AppX packages found."
    }
}

# --------------------------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------------------------

try {
    Write-Host ">>> Starting 7-Zip removal..."
    Write-Host ">>> Checking for installed 7-Zip (registry + AppX)..."

    $existing = Get-7ZipInstall

    if ($existing) {
        Write-Host ">>> Found 7-Zip: $($existing.DisplayName) $($existing.DisplayVersion)"
        Write-Host ">>> Attempting uninstall..."

        $code = Uninstall-RegistryApp -App $existing

        if ($code -eq 3010) {
            Write-Host ">>> 7-Zip uninstall requested reboot (3010) - treating as success."
        }
        elseif ($code -ne 0) {
            Write-Host ">>> 7-Zip uninstall failed with exit code $code"
            Write-Host "7-Zip removal failed."
            exit 1
        }
        else {
            Write-Host ">>> 7-Zip uninstall command returned exit code 0"
        }
    }
    else {
        Write-Host ">>> 7-Zip not installed via registry."
    }

    Write-Host ">>> Checking/removing any 7-Zip AppX/MSIX packages..."
    Remove-7ZipAppx

    # Optional verification (non-fatal): re-check registry after uninstall
    $post = Get-7ZipInstall
    if ($post) {
        Write-Host ">>> Warning: 7-Zip still appears in registry after uninstall: $($post.DisplayName) $($post.DisplayVersion)"
        # If you want this to hard-fail, change the next two lines to: Write-Host "7-Zip removal failed."; exit 1
    } else {
        Write-Host ">>> Verification: 7-Zip not present in registry after uninstall."
    }

    Write-Host "7-Zip removal completed successfully."
    exit 0
}
catch {
    Write-Host ">>> 7-Zip removal failed: $($_.Exception.Message)"
    Write-Host "7-Zip removal failed."
    exit 1
}
