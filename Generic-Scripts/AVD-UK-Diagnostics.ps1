# =============================================================================
# AVD UK Locale Diagnostics
# =============================================================================
# Purpose:
#   Gathers every locale, timezone, regional format, and registry setting on
#   the current VM and compares each against expected UK (en-GB) values.
#   Flags mismatches as FAIL so you can see exactly what the custom image
#   did or didn't carry over.
#
# Usage:
#   Run on the session host VM (can run as admin or user — admin needed for
#   Default User profile check in section 4).
#
#   .\AVD-UK-Diagnostics.ps1
#
# Output:
#   - Colour-coded console (Green=PASS, Red=FAIL, Yellow=WARN)
#   - Full log: C:\temp\AVD-UK-Diagnostics.log
# =============================================================================

$LogPath = "C:\temp\AVD-UK-Diagnostics.log"

if (-not (Test-Path "C:\temp")) {
    New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
}

# Clear previous log
if (Test-Path $LogPath) { Remove-Item $LogPath -Force }

# Tracking
$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:Failures  = [System.Collections.Generic.List[PSCustomObject]]::new()

# =============================================================================
# HELPERS
# =============================================================================

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LogPath -Value $Message
}

function Write-Section {
    param([string]$Title)
    $line = "=" * 70
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Log ""
    Write-Log $line
    Write-Log "  $Title"
    Write-Log $line
}

function Test-Setting {
    param(
        [string]$Name,
        [string]$Expected,
        [string]$Actual,
        [string]$Category = ""
    )

    $ActualTrimmed   = if ($Actual) { $Actual.Trim() } else { "(empty / not set)" }
    $ExpectedTrimmed = $Expected.Trim()
    $Match = ($ActualTrimmed -eq $ExpectedTrimmed)

    if ($Match) {
        $script:PassCount++
        $Status = "PASS"
        $Colour = "Green"
    } else {
        $script:FailCount++
        $Status = "FAIL"
        $Colour = "Red"
        $script:Failures.Add([PSCustomObject]@{
            Category = $Category
            Setting  = $Name
            Expected = $ExpectedTrimmed
            Actual   = $ActualTrimmed
        })
    }

    $Line = "  [$Status] $Name"
    $Detail = "         Expected: $ExpectedTrimmed  |  Actual: $ActualTrimmed"

    Write-Host $Line -ForegroundColor $Colour
    if (-not $Match) {
        Write-Host $Detail -ForegroundColor Yellow
    } else {
        Write-Host $Detail -ForegroundColor Gray
    }

    Write-Log "$Line"
    Write-Log "$Detail"
}

function Test-SettingContains {
    param(
        [string]$Name,
        [string]$Expected,
        [string]$Actual,
        [string]$Category = ""
    )

    $Match = ($Actual -and $Actual -like "*$Expected*")

    if ($Match) {
        $script:PassCount++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        Write-Host "         Contains: $Expected  |  Value: $Actual" -ForegroundColor Gray
        Write-Log "  [PASS] $Name"
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        Write-Host "         Expected to contain: $Expected  |  Actual: $Actual" -ForegroundColor Yellow
        Write-Log "  [FAIL] $Name"
        $script:Failures.Add([PSCustomObject]@{
            Category = $Category
            Setting  = $Name
            Expected = "contains '$Expected'"
            Actual   = if ($Actual) { $Actual } else { "(empty / not set)" }
        })
    }

    Write-Log "         Expected to contain: $Expected  |  Actual: $Actual"
}

# =============================================================================
# HEADER
# =============================================================================
$Banner = @"
================================================================
  AVD UK Locale Diagnostics
  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Host    : $env:COMPUTERNAME
  User    : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
  PS Ver  : $($PSVersionTable.PSVersion)
================================================================
"@

Write-Host $Banner -ForegroundColor White
Write-Log $Banner

# =============================================================================
# 1. SYSTEM-LEVEL (machine-wide)
# =============================================================================
Write-Section "1. SYSTEM-LEVEL SETTINGS"

# System locale
try {
    $sysLocale = (Get-WinSystemLocale).Name
} catch { $sysLocale = "ERROR: $($_.Exception.Message)" }
Test-Setting -Name "System Locale" -Expected "en-GB" -Actual $sysLocale -Category "System"

# Timezone
try {
    $tz = (Get-TimeZone).Id
} catch { $tz = "ERROR: $($_.Exception.Message)" }
Test-Setting -Name "Timezone" -Expected "GMT Standard Time" -Actual $tz -Category "System"

# Timezone display name (informational)
try {
    $tzDisplay = (Get-TimeZone).DisplayName
    Write-Host "  [INFO] Timezone display: $tzDisplay" -ForegroundColor Gray
    Write-Log "  [INFO] Timezone display: $tzDisplay"
} catch {}

# NLS Default LCID
try {
    $nlsDefault = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -Name "Default" -ErrorAction Stop).Default
} catch { $nlsDefault = "(not found)" }
Test-Setting -Name "NLS Default LCID" -Expected "0809" -Actual $nlsDefault -Category "System"

# NLS InstallLanguage
try {
    $nlsInstall = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -Name "InstallLanguage" -ErrorAction Stop).InstallLanguage
} catch { $nlsInstall = "(not found)" }
Test-Setting -Name "NLS InstallLanguage" -Expected "0809" -Actual $nlsInstall -Category "System"

# =============================================================================
# 2. CURRENT USER (PowerShell cmdlets)
# =============================================================================
Write-Section "2. CURRENT USER SETTINGS (cmdlets)"

# Culture
try {
    $culture = Get-Culture
    $cultureName = $culture.Name
} catch { $cultureName = "ERROR: $($_.Exception.Message)" }
Test-Setting -Name "Culture" -Expected "en-GB" -Actual $cultureName -Category "User"

# Date/Time patterns from culture
try {
    $shortDate = $culture.DateTimeFormat.ShortDatePattern
} catch { $shortDate = "ERROR" }
Test-Setting -Name "Short Date Pattern" -Expected "dd/MM/yyyy" -Actual $shortDate -Category "User"

try {
    $longDate = $culture.DateTimeFormat.LongDatePattern
} catch { $longDate = "ERROR" }
Test-Setting -Name "Long Date Pattern" -Expected "dd MMMM yyyy" -Actual $longDate -Category "User"

try {
    $shortTime = $culture.DateTimeFormat.ShortTimePattern
} catch { $shortTime = "ERROR" }
Test-Setting -Name "Short Time Pattern" -Expected "HH:mm" -Actual $shortTime -Category "User"

try {
    $longTime = $culture.DateTimeFormat.LongTimePattern
} catch { $longTime = "ERROR" }
Test-Setting -Name "Long Time Pattern" -Expected "HH:mm:ss" -Actual $longTime -Category "User"

# UI Language Override
try {
    $uiLang = Get-WinUILanguageOverride
    $uiLangTag = if ($uiLang) { $uiLang.LanguageTag } else { "(not set)" }
} catch { $uiLangTag = "ERROR: $($_.Exception.Message)" }
Test-Setting -Name "UI Language Override" -Expected "en-GB" -Actual $uiLangTag -Category "User"

# User Language List
try {
    $langList = Get-WinUserLanguageList
    $langTags = ($langList | ForEach-Object { $_.LanguageTag }) -join ", "
} catch { $langTags = "ERROR: $($_.Exception.Message)" }
Test-SettingContains -Name "User Language List" -Expected "en-GB" -Actual $langTags -Category "User"

# Home Location
try {
    $geo = Get-WinHomeLocation
    $geoId = [string]$geo.GeoId
} catch { $geoId = "ERROR: $($_.Exception.Message)" }
Test-Setting -Name "Home Location GeoID" -Expected "242" -Actual $geoId -Category "User"

# =============================================================================
# 3. CURRENT USER REGISTRY (HKCU:\Control Panel\International)
# =============================================================================
Write-Section "3. CURRENT USER REGISTRY (HKCU)"

$HkcuIntlPath = "HKCU:\Control Panel\International"
$HkcuGeoPath  = "HKCU:\Control Panel\International\Geo"

$RegistryChecks = @(
    @{ Name = "HKCU Locale";           Key = $HkcuIntlPath; Value = "Locale";          Expected = "00000809" }
    @{ Name = "HKCU LocaleName";       Key = $HkcuIntlPath; Value = "LocaleName";      Expected = "en-GB" }
    @{ Name = "HKCU sShortDate";       Key = $HkcuIntlPath; Value = "sShortDate";      Expected = "dd/MM/yyyy" }
    @{ Name = "HKCU sLongDate";        Key = $HkcuIntlPath; Value = "sLongDate";       Expected = "dd MMMM yyyy" }
    @{ Name = "HKCU sShortTime";       Key = $HkcuIntlPath; Value = "sShortTime";      Expected = "HH:mm" }
    @{ Name = "HKCU sTimeFormat";      Key = $HkcuIntlPath; Value = "sTimeFormat";     Expected = "HH:mm:ss" }
    @{ Name = "HKCU iTime (24-hour)";  Key = $HkcuIntlPath; Value = "iTime";           Expected = "1" }
    @{ Name = "HKCU sCurrency";        Key = $HkcuIntlPath; Value = "sCurrency";       Expected = "£" }
    @{ Name = "HKCU iFirstDayOfWeek";  Key = $HkcuIntlPath; Value = "iFirstDayOfWeek"; Expected = "0" }
    @{ Name = "HKCU sCountry";         Key = $HkcuIntlPath; Value = "sCountry";        Expected = "United Kingdom" }
    @{ Name = "HKCU Geo Nation";       Key = $HkcuGeoPath;  Value = "Nation";          Expected = "242" }
)

foreach ($Check in $RegistryChecks) {
    try {
        $RegValue = (Get-ItemProperty -Path $Check.Key -Name $Check.Value -ErrorAction Stop).($Check.Value)
        $RegValueStr = [string]$RegValue
    } catch {
        $RegValueStr = "(not found)"
    }
    Test-Setting -Name $Check.Name -Expected $Check.Expected -Actual $RegValueStr -Category "User Registry"
}

# =============================================================================
# 4. DEFAULT USER PROFILE (what new users inherit)
# =============================================================================
Write-Section "4. DEFAULT USER PROFILE (C:\Users\Default)"

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdmin) {
    $script:WarnCount++
    Write-Host "  [WARN] Not running as admin — cannot load Default User hive. Skipping section 4." -ForegroundColor Yellow
    Write-Log "  [WARN] Not running as admin — skipping Default User profile check."
} else {
    $DefaultUserDat = "C:\Users\Default\NTUSER.DAT"
    $HiveMount      = "HKLM\TempAVDDiag"
    $HiveMountPS    = "HKLM:\TempAVDDiag"

    $HiveLoaded = $false

    try {
        $LoadResult = & reg load $HiveMount $DefaultUserDat 2>&1
        Write-Host "  [INFO] Hive loaded: $LoadResult" -ForegroundColor Gray
        Write-Log "  [INFO] Hive loaded: $LoadResult"
        $HiveLoaded = $true

        $DefIntlPath = "$HiveMountPS\Control Panel\International"
        $DefGeoPath  = "$HiveMountPS\Control Panel\International\Geo"

        $DefaultChecks = @(
            @{ Name = "Default Locale";          Key = $DefIntlPath; Value = "Locale";          Expected = "00000809" }
            @{ Name = "Default LocaleName";      Key = $DefIntlPath; Value = "LocaleName";      Expected = "en-GB" }
            @{ Name = "Default sShortDate";      Key = $DefIntlPath; Value = "sShortDate";      Expected = "dd/MM/yyyy" }
            @{ Name = "Default sLongDate";       Key = $DefIntlPath; Value = "sLongDate";       Expected = "dd MMMM yyyy" }
            @{ Name = "Default sShortTime";      Key = $DefIntlPath; Value = "sShortTime";      Expected = "HH:mm" }
            @{ Name = "Default sTimeFormat";     Key = $DefIntlPath; Value = "sTimeFormat";     Expected = "HH:mm:ss" }
            @{ Name = "Default iTime (24-hour)"; Key = $DefIntlPath; Value = "iTime";           Expected = "1" }
            @{ Name = "Default sCurrency";       Key = $DefIntlPath; Value = "sCurrency";       Expected = "£" }
            @{ Name = "Default iFirstDayOfWeek"; Key = $DefIntlPath; Value = "iFirstDayOfWeek"; Expected = "0" }
            @{ Name = "Default Geo Nation";      Key = $DefGeoPath;  Value = "Nation";          Expected = "242" }
        )

        foreach ($Check in $DefaultChecks) {
            try {
                $RegValue = (Get-ItemProperty -Path $Check.Key -Name $Check.Value -ErrorAction Stop).($Check.Value)
                $RegValueStr = [string]$RegValue
            } catch {
                $RegValueStr = "(not found)"
            }
            Test-Setting -Name $Check.Name -Expected $Check.Expected -Actual $RegValueStr -Category "Default Profile"
        }

    } catch {
        Write-Host "  [FAIL] Could not load Default User hive: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "  [FAIL] Could not load Default User hive: $($_.Exception.Message)"
    } finally {
        if ($HiveLoaded) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            Start-Sleep -Seconds 2
            $UnloadResult = & reg unload $HiveMount 2>&1
            Write-Host "  [INFO] Hive unloaded: $UnloadResult" -ForegroundColor Gray
            Write-Log "  [INFO] Hive unloaded: $UnloadResult"
        }
    }
}

# =============================================================================
# 5. BONUS: CURRENT DATE/TIME RENDERING
# =============================================================================
Write-Section "5. LIVE DATE/TIME RENDERING"

$now = Get-Date
Write-Host "  Current date (system) : $($now.ToString('dd/MM/yyyy'))" -ForegroundColor White
Write-Host "  Current time (system) : $($now.ToString('HH:mm:ss'))" -ForegroundColor White
Write-Host "  .NET short date       : $($now.ToShortDateString())" -ForegroundColor White
Write-Host "  .NET short time       : $($now.ToShortTimeString())" -ForegroundColor White
Write-Host "  Culture used by .NET  : $([System.Globalization.CultureInfo]::CurrentCulture.Name)" -ForegroundColor White

Write-Log "  Current date (system) : $($now.ToString('dd/MM/yyyy'))"
Write-Log "  Current time (system) : $($now.ToString('HH:mm:ss'))"
Write-Log "  .NET short date       : $($now.ToShortDateString())"
Write-Log "  .NET short time       : $($now.ToShortTimeString())"
Write-Log "  Culture used by .NET  : $([System.Globalization.CultureInfo]::CurrentCulture.Name)"

# =============================================================================
# 6. SUMMARY
# =============================================================================
Write-Section "SUMMARY"

$Total = $script:PassCount + $script:FailCount
Write-Host ""
Write-Host "  Total checks : $Total" -ForegroundColor White
Write-Host "  PASS         : $($script:PassCount)" -ForegroundColor Green
Write-Host "  FAIL         : $($script:FailCount)" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
Write-Host "  WARNINGS     : $($script:WarnCount)" -ForegroundColor $(if ($script:WarnCount -gt 0) { "Yellow" } else { "Green" })

Write-Log ""
Write-Log "  Total: $Total  |  PASS: $($script:PassCount)  |  FAIL: $($script:FailCount)  |  WARN: $($script:WarnCount)"

if ($script:Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "  ---- FAILED SETTINGS ----" -ForegroundColor Red
    Write-Log ""
    Write-Log "  ---- FAILED SETTINGS ----"

    foreach ($f in $script:Failures) {
        $msg = "  [$($f.Category)] $($f.Setting): expected '$($f.Expected)' but got '$($f.Actual)'"
        Write-Host $msg -ForegroundColor Yellow
        Write-Log $msg
    }

    Write-Host ""
    Write-Host "  ---- RECOMMENDATIONS ----" -ForegroundColor Yellow
    Write-Log ""
    Write-Log "  ---- RECOMMENDATIONS ----"

    # Categorise the failures
    $SystemFails  = $script:Failures | Where-Object { $_.Category -eq "System" }
    $UserFails    = $script:Failures | Where-Object { $_.Category -in @("User", "User Registry") }
    $DefaultFails = $script:Failures | Where-Object { $_.Category -eq "Default Profile" }

    if ($SystemFails.Count -gt 0) {
        $rec = "  - SYSTEM settings failed: re-run the image script as SYSTEM, or apply via Intune (SYSTEM context). Requires REBOOT."
        Write-Host $rec -ForegroundColor Yellow
        Write-Log $rec
    }

    if ($UserFails.Count -gt 0) {
        $rec = "  - USER settings failed: the user profile was created before the image was configured, or Set-Culture/intl.cpl didn't persist through sysprep. Fix with a USER-context Intune script (sign-out required)."
        Write-Host $rec -ForegroundColor Yellow
        Write-Log $rec
    }

    if ($DefaultFails.Count -gt 0) {
        $rec = "  - DEFAULT PROFILE settings failed: the Default User hive wasn't updated. New users will still get wrong settings. Re-bake the image or add a SYSTEM-context Intune script to patch the Default hive."
        Write-Host $rec -ForegroundColor Yellow
        Write-Log $rec
    }

} else {
    Write-Host ""
    Write-Host "  All settings match expected UK (en-GB) values!" -ForegroundColor Green
    Write-Log ""
    Write-Log "  All settings match expected UK (en-GB) values!"
}

Write-Host ""
Write-Host "  Full log: $LogPath" -ForegroundColor Gray
Write-Log ""
Write-Log "  Full log: $LogPath"
