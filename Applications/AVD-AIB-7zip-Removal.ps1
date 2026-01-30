# ============================================================================
# AVD Golden Image Script: Remove 7-Zip (ALL install types)
#
# Why this exists (AVD context)
#   - Your image may have 7-Zip installed via:
#       * MSI (classic Windows Installer)
#       * EXE (NSIS/Inno uninstaller)
#       * Microsoft Store / AppX / MSIX (per-user packaged)
#       * Provisioned AppX (auto-installs for new profiles)
#       * winget-managed installs (often MSIX-ish)
#
# Key AVD behaviours
#   - Works when run as SYSTEM during image baking (recommended)
#   - Removes AppX for ALL local profiles + deprovisions so it doesn't return
#   - Silent by default; no parameters
#
# Exit codes
#   0    = success OR not detected (safe/idempotent for pipelines)
#   3010 = success but reboot required
# ============================================================================

$ErrorActionPreference = 'SilentlyContinue'

function Log { param([string]$m) Write-Host "[AVD-7Zip-Remove] $m" }

# ---------------------------------------------------------------------------
# REGISTRY: read uninstall entries from BOTH 32-bit and 64-bit registry views.
# This avoids false negatives when the script runs in 32-bit PowerShell.
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

            # Very tolerant match: catches "7-Zip", "7 Zip", "7zip", "7-Zip File Manager"
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

    # HKLM = machine-wide installs
    $all += Get-UninstallEntriesFromRegistry -Hive LocalMachine -View Registry64
    $all += Get-UninstallEntriesFromRegistry -Hive LocalMachine -View Registry32

    # HKCU = current user installs (may not matter in SYSTEM context, but harmless)
    $all += Get-UninstallEntriesFromRegistry -Hive CurrentUser -View Registry64
    $all += Get-UninstallEntriesFromRegistry -Hive CurrentUser -View Registry32

    # De-dupe on common fields
    $all | Sort-Object DisplayName, UninstallString, QuietUninstallString -Unique
}

# ---------------------------------------------------------------------------
# MSI uninstall: use msiexec product code when available
# ---------------------------------------------------------------------------
function Invoke-MSIUninstall {
    param([string]$ProductCode)

    Log "MSI uninstall: $ProductCode"
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $ProductCode /qn /norestart" -Wait -PassThru
    $p.ExitCode
}

# ---------------------------------------------------------------------------
# EXE uninstall: parse uninstall string and enforce silent switch (/S)
# ---------------------------------------------------------------------------
function Invoke-EXEUninstall {
    param([string]$UninstallString)

    if ([string]::IsNullOrWhiteSpace($UninstallString)) { return $null }

    $exe  = $null
    $args = ""

    $s = $UninstallString.Trim()

    # Handle quoted paths: "C:\Path\Uninstall.exe" /S
    if ($s.StartsWith('"')) {
        $second = $s.IndexOf('"', 1)
        if ($second -gt 1) {
            $exe  = $s.Substring(1, $second - 1)
            $args = $s.Substring($second + 1).Trim()
        }
    } else {
        # Unquoted: C:\Path\Uninstall.exe /S
        $parts = $s.Split(' ', 2)
        $exe = $parts[0]
        if ($parts.Count -gt 1) { $args = $parts[1] }
    }

    if (-not $exe -or -not (Test-Path $exe)) {
        Log "EXE uninstaller not found: $exe"
        return $null
    }

    # Enforce silent mode for typical 7-Zip uninstallers (NSIS commonly supports /S)
    if ($args -notmatch '(^|\s)/S(\s|$)') {
        $args = ($args, "/S") -join ' '
        $args = $args.Trim()
    }

    Log "EXE uninstall: $exe $args"
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
    $p.ExitCode
}

# ---------------------------------------------------------------------------
# APPX/MSIX removal:
#   - Remove for ALL existing profiles (important for AVD images)
#   - Remove provisioned package so it won't auto-install for new users
# ---------------------------------------------------------------------------
function Remove-7ZipAppx_AllProfilesAndProvisioned {
    $did = $false

    # 1) Remove provisioned packages (preinstalled for new user profiles)
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match '(?i)\b7[\s\-]?zip\b' -or $_.PackageName -match '(?i)\b7[\s\-]?zip\b'
    }

    foreach ($p in $prov) {
        Log "AppX deprovision (image-wide): $($p.DisplayName)"
        Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue | Out-Null
        $did = $true
    }

    # 2) Remove installed AppX packages for ALL existing local user profiles
    # This matters in golden images where a build account may have installed Store apps
    $allPkgs = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '(?i)\b7[\s\-]?zip\b' -or $_.PackageFamilyName -match '(?i)\b7[\s\-]?zip\b'
    }

    foreach ($pkg in $allPkgs) {
        Log "AppX uninstall (all users): $($pkg.Name)"
        # Remove-AppxPackage does not accept -AllUsers, so we remove by PackageFullName
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
        $did = $true
    }

    $did
}

# ---------------------------------------------------------------------------
# winget uninstall (best-effort):
# Useful when 7-Zip is installed as a packaged app not easily caught above.
# ---------------------------------------------------------------------------
function Remove-7ZipWinget_BestEffort {
    $did = $false

    $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
    if (-not $winget) { return $false }

    $candidates = @(
        @{ Type="id";   Value="7zip.7zip" },
        @{ Type="name"; Value="7-Zip" },
        @{ Type="name"; Value="7zip" }
    )

    foreach ($c in $candidates) {
        try {
            Log "winget uninstall attempt ($($c.Type)=$($c.Value))"
            $args = @(
                "uninstall",
                "--silent",
                "--accept-source-agreements",
                "--accept-package-agreements",
                "--$($c.Type)", $c.Value
            )

            $p = Start-Process -FilePath $winget -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0) { $did = $true }
        } catch { }
    }

    $did
}

# ---------------------------------------------------------------------------
# Fallback paths:
# Catches broken/unregistered EXE installs that still dropped an uninstaller on disk.
# ---------------------------------------------------------------------------
function Remove-7ZipFallbackPaths {
    $did = $false

    $fallbacks = @(
        "$env:ProgramFiles\7-Zip\Uninstall.exe",
        "$env:ProgramFiles\7-Zip\Uninstall7Zip.exe",
        "$env:ProgramFiles(x86)\7-Zip\Uninstall.exe",
        "$env:ProgramFiles(x86)\7-Zip\Uninstall7Zip.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    foreach ($f in $fallbacks) {
        Log "Fallback uninstaller found: $f"
        Invoke-EXEUninstall -UninstallString "`"$f`"" | Out-Null
        $did = $true
    }

    $did
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Log "Starting removal..."

$foundAnything = $false
$exitCodes = @()

# 1) Classic MSI/EXE installs from registry
$entries = Get-7ZipUninstallEntries
foreach ($e in $entries) {
    $foundAnything = $true
    Log "Found (registry): $($e.DisplayName) [$($e.Hive) $($e.View)]"

    # Prefer QuietUninstallString (already silent) else UninstallString
    $u = if ($e.QuietUninstallString) { $e.QuietUninstallString } else { $e.UninstallString }

    # If a ProductCode GUID exists, it’s almost certainly MSI -> use msiexec
    if ($u -match '\{[0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12}\}') {
        $exitCodes += Invoke-MSIUninstall -ProductCode $matches[0]
    } else {
        $exitCodes += Invoke-EXEUninstall -UninstallString $u
    }
}

# 2) Store/AppX/MSIX removal (all profiles + deprovision)
if (Remove-7ZipAppx_AllProfilesAndProvisioned) { $foundAnything = $true }

# 3) winget removal (best-effort)
if (Remove-7ZipWinget_BestEffort) { $foundAnything = $true }

# 4) fallback uninstaller paths
if (Remove-7ZipFallbackPaths) { $foundAnything = $true }

# Exit handling: idempotent
if (-not $foundAnything) {
    Log "7-Zip not detected – nothing to do"
    exit 0
}

# Bubble up “reboot required” if any MSI uninstall requested it
if ($exitCodes -contains 3010) {
    Log "Completed – reboot required"
    exit 3010
}

Log "Completed"
exit 0
