# ============================================================================
# AVD Golden Image Script: Remove 7-Zip (ALL install types) - DROP-IN
#   0    = success OR not detected
#   3010 = success but reboot required
# ============================================================================

$ErrorActionPreference = 'Continue'
$global:LASTEXITCODE = 0

function Log { param([string]$m) Write-Host "[AVD-7Zip-Remove] $m" }

# ---------------------------------------------------------------------------
# REGISTRY: read uninstall entries from BOTH 32-bit and 64-bit registry views.
# ---------------------------------------------------------------------------
function Get-UninstallEntriesFromRegistry {
    param(
        [Microsoft.Win32.RegistryHive]$Hive,
        [Microsoft.Win32.RegistryView]$View
    )

    $results = @()
    $subKeyPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"

    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
        $key  = $base.OpenSubKey($subKeyPath)
        if (-not $key) { return @() }

        foreach ($name in $key.GetSubKeyNames()) {
            $sk = $key.OpenSubKey($name)
            if (-not $sk) { continue }

            $displayName = [string]$sk.GetValue("DisplayName")
            if ([string]::IsNullOrWhiteSpace($displayName)) { continue }

            if ($displayName -match '(?i)\b7[\s\-]?zip\b') {
                $results += [pscustomobject]@{
                    DisplayName          = $displayName
                    DisplayVersion       = [string]$sk.GetValue("DisplayVersion")
                    Publisher            = [string]$sk.GetValue("Publisher")
                    UninstallString      = [string]$sk.GetValue("UninstallString")
                    QuietUninstallString = [string]$sk.GetValue("QuietUninstallString")
                    Hive                 = $Hive.ToString()
                    View                 = $View.ToString()
                }
            }
        }
    } catch { }

    $results
}

function Get-7ZipUninstallEntries {
    $all = @()
    $all += Get-UninstallEntriesFromRegistry -Hive LocalMachine -View Registry64
    $all += Get-UninstallEntriesFromRegistry -Hive LocalMachine -View Registry32
    $all += Get-UninstallEntriesFromRegistry -Hive CurrentUser  -View Registry64
    $all += Get-UninstallEntriesFromRegistry -Hive CurrentUser  -View Registry32
    $all | Sort-Object DisplayName, UninstallString, QuietUninstallString -Unique
}

function Invoke-MSIUninstall {
    param([string]$ProductCode)

    Log "MSI uninstall: $ProductCode"
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $ProductCode /qn /norestart" -Wait -PassThru
    $global:LASTEXITCODE = $p.ExitCode
    return $p.ExitCode
}

function Invoke-EXEUninstall {
    param([string]$UninstallString)

    if ([string]::IsNullOrWhiteSpace($UninstallString)) { return $null }

    $exe  = $null
    $args = ""

    $s = $UninstallString.Trim()

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

    if ($args -notmatch '(^|\s)/S(\s|$)') {
        $args = ($args, "/S") -join ' '
        $args = $args.Trim()
    }

    Log "EXE uninstall: $exe $args"
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
    $global:LASTEXITCODE = $p.ExitCode
    return $p.ExitCode
}

# --- APPX/MSIX removal (keep your original behaviour, but don’t hard-fail) ---
function Remove-7ZipAppxEverywhere {
    try {
        $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -match '(?i)7zip|7-zip|7zip' }
        foreach ($p in $pkgs) {
            Log "Removing AppX (AllUsers): $($p.Name)"
            Remove-AppxPackage -AllUsers -Package $p.PackageFullName -ErrorAction SilentlyContinue
        }

        $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match '(?i)7zip|7-zip|7zip' }
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
    $foundAnything = $false
    $rebootNeeded  = $false

    # 1) Registry-based uninstalls (MSI/EXE)
    $entries = Get-7ZipUninstallEntries
    if ($entries.Count -gt 0) {
        $foundAnything = $true
        foreach ($e in $entries) {
            Log "Detected: $($e.DisplayName) ($($e.DisplayVersion)) [$($e.Hive)/$($e.View)]"

            $code = $null

            # MSI product code sometimes lives in the uninstall key name; attempt to extract {GUID}
            if ($e.UninstallString -match '\{[0-9A-Fa-f\-]{36}\}') {
                $productCode = $Matches[0]
                $code = Invoke-MSIUninstall -ProductCode $productCode
            }
            elseif (-not [string]::IsNullOrWhiteSpace($e.QuietUninstallString)) {
                $code = Invoke-EXEUninstall -UninstallString $e.QuietUninstallString
            }
            elseif (-not [string]::IsNullOrWhiteSpace($e.UninstallString)) {
                $code = Invoke-EXEUninstall -UninstallString $e.UninstallString
            }

            if ($code -eq 3010) { $rebootNeeded = $true }
        }
    } else {
        Log "No 7-Zip uninstall entries found in registry."
    }

    # 2) AppX/MSIX removal for all users + deprovision
    Remove-7ZipAppxEverywhere

    if (-not $foundAnything) {
        Log "7-Zip not detected (safe no-op)."
        $global:LASTEXITCODE = 0
        exit 0
    }

    if ($rebootNeeded) {
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
    # You can choose to fail the image build here by exiting 1,
    # but defaulting to fail-fast is usually better for golden images.
    $global:LASTEXITCODE = 1
    exit 1
}
