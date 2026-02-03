# AVD-AIB-7zip-Removal.ps1 (DROP-IN)
$ErrorActionPreference = 'Continue'
$global:LASTEXITCODE = 0

function Log([string]$m) { Write-Host "[AVD-7Zip-Removal] $m" }

function Get-UninstallEntries {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $items = foreach ($p in $paths) {
        Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
    }

    $items | Where-Object {
        $_.DisplayName -match '(?i)\b7[\s\-]?zip\b'
    } | Sort-Object DisplayName -Unique
}

function Run-MsiUninstall([string]$productCode) {
    Log "MSI uninstall: $productCode"
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart" -Wait -PassThru
    $global:LASTEXITCODE = $p.ExitCode
    return $p.ExitCode
}

function Run-ExeUninstall([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }

    $exe = $null
    $args = ""

    $s = $cmd.Trim()
    if ($s.StartsWith('"')) {
        $second = $s.IndexOf('"', 1)
        if ($second -gt 1) {
            $exe  = $s.Substring(1, $second - 1)
            $args = $s.Substring($second + 1).Trim()
        }
    } else {
        $parts = $s.Split(' ', 2)
        $exe = $parts[0]
        if ($parts.Count -gt 1) { $args = $parts[1] }
    }

    if (-not $exe -or -not (Test-Path $exe)) {
        Log "EXE uninstaller not found: $exe"
        return $null
    }

    # Best-effort silent flag
    if ($args -notmatch '(^|\s)/S(\s|$)') {
        $args = ($args, "/S") -join ' '
        $args = $args.Trim()
    }

    Log "EXE uninstall: $exe $args"
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
    $global:LASTEXITCODE = $p.ExitCode
    return $p.ExitCode
}

function Remove-Appx7Zip {
    try {
        $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -match '(?i)7zip|7-zip' }
        foreach ($p in $pkgs) {
            Log "Removing AppX (AllUsers): $($p.Name)"
            Remove-AppxPackage -AllUsers -Package $p.PackageFullName -ErrorAction SilentlyContinue
        }

        $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match '(?i)7zip|7-zip' }
        foreach ($p in $prov) {
            Log "Deprovisioning AppX: $($p.DisplayName)"
            Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        Log "AppX cleanup warning: $($_.Exception.Message)"
    }
}

try {
    Log "Starting 7-Zip removal"

    $found  = $false
    $reboot = $false

    $entries = Get-UninstallEntries
    if ($entries) {
        $found = $true
        foreach ($e in $entries) {
            Log "Detected: $($e.DisplayName) $($e.DisplayVersion)"

            $uninstall = $e.QuietUninstallString
            if ([string]::IsNullOrWhiteSpace($uninstall)) { $uninstall = $e.UninstallString }

            $code = $null
            if ($uninstall -match '\{[0-9A-Fa-f\-]{36}\}') {
                $code = Run-MsiUninstall -productCode $Matches[0]
            } else {
                $code = Run-ExeUninstall -cmd $uninstall
            }

            if ($code -eq 3010) { $reboot = $true }
        }
    } else {
        Log "No 7-Zip uninstall entries found."
    }

    Remove-Appx7Zip

    if (-not $found) {
        Log "7-Zip not detected (no-op)."
        $global:LASTEXITCODE = 0
        exit 0
    }

    if ($reboot) {
        Log "7-Zip removed; reboot required (3010)."
        $global:LASTEXITCODE = 3010
        exit 3010
    }

    Log "7-Zip removed successfully."
    $global:LASTEXITCODE = 0
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    $global:LASTEXITCODE = 1
    exit 1
}
