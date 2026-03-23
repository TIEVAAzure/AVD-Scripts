# =============================================================================
# AVD UK Custom Image Template — Locale, Timezone & Regional Settings
# =============================================================================
# Purpose:
#   Bakes UK regional settings into a custom AVD image so every session host
#   (and every user who signs in) inherits en-GB defaults automatically.
#
# When to run:
#   During custom image build, BEFORE sysprep / generalization.
#   Must run as Administrator (SYSTEM context).
#
# What this configures:
#   - System locale            : en-GB
#   - Input / UI language      : en-GB
#   - Timezone                 : GMT Standard Time (Europe/London)
#   - Default user profile     : en-GB regional formats (date, time, currency)
#   - Welcome screen / new user: copies settings to default & system accounts
#   - NLS registry overrides   : LCID 0809 (en-GB)
#
# Intune / image-builder notes:
#   If deploying via Intune as a platform script instead of image bake:
#     Run this script using the logged on credentials : NO  (SYSTEM)
#     Run script in 64-bit PowerShell host            : YES
#     Enforce script signature check                  : NO
# =============================================================================

#Requires -RunAsAdministrator

$LogPath = "C:\temp\AVD-UK-CustomImage.log"

if (-not (Test-Path "C:\temp")) {
    New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogPath -Value $Entry
    Write-Output $Entry
}

# =============================================================================
# HEADER
# =============================================================================
Write-Log "================================================================="
Write-Log "AVD UK Custom Image Configuration — Started"
Write-Log "================================================================="
Write-Log "Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Hostname   : $env:COMPUTERNAME"
Write-Log "PS Version : $($PSVersionTable.PSVersion)"
Write-Log "OS         : $((Get-CimInstance Win32_OperatingSystem).Caption)"

# =============================================================================
# 1. SYSTEM LOCALE
# =============================================================================
Write-Log "-----------------------------------------------------------------"
Write-Log "1. Setting system locale to en-GB..."

try {
    Set-WinSystemLocale -SystemLocale "en-GB"
    Write-Log "   Set-WinSystemLocale: SUCCESS"
} catch {
    Write-Log "   Set-WinSystemLocale FAILED: $($_.Exception.Message)" "ERROR"
}

# NLS registry — ensures non-Unicode programs also use en-GB
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" `
        -Name "Default"         -Value "0809"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" `
        -Name "InstallLanguage" -Value "0809"
    Write-Log "   NLS registry (LCID 0809): SUCCESS"
} catch {
    Write-Log "   NLS registry FAILED: $($_.Exception.Message)" "ERROR"
}

# =============================================================================
# 2. TIMEZONE
# =============================================================================
Write-Log "-----------------------------------------------------------------"
Write-Log "2. Setting timezone to GMT Standard Time..."

try {
    Set-TimeZone -Id "GMT Standard Time"
    Write-Log "   Timezone set to: $((Get-TimeZone).Id)"
} catch {
    Write-Log "   Set-TimeZone FAILED: $($_.Exception.Message)" "ERROR"
}

# =============================================================================
# 3. UI LANGUAGE & INPUT
# =============================================================================
Write-Log "-----------------------------------------------------------------"
Write-Log "3. Configuring UI language and input..."

try {
    Set-WinUILanguageOverride -Language "en-GB"
    Write-Log "   UI language override: SUCCESS"
} catch {
    Write-Log "   Set-WinUILanguageOverride FAILED: $($_.Exception.Message)" "ERROR"
}

try {
    $LangList = New-WinUserLanguageList "en-GB"
    $LangList[0].Handwriting = $true
    Set-WinUserLanguageList $LangList -Force
    Write-Log "   User language list: SUCCESS"
} catch {
    Write-Log "   Set-WinUserLanguageList FAILED: $($_.Exception.Message)" "ERROR"
}

# =============================================================================
# 4. CULTURE & HOME LOCATION
# =============================================================================
Write-Log "-----------------------------------------------------------------"
Write-Log "4. Setting culture and home location..."

try {
    Set-Culture -CultureInfo "en-GB"
    Write-Log "   Culture: SUCCESS (date=dd/MM/yyyy, time=HH:mm, currency=GBP)"
} catch {
    Write-Log "   Set-Culture FAILED: $($_.Exception.Message)" "ERROR"
}

try {
    Set-WinHomeLocation -GeoId 242
    Write-Log "   Home location: SUCCESS (GeoID 242 = United Kingdom)"
} catch {
    Write-Log "   Set-WinHomeLocation FAILED: $($_.Exception.Message)" "ERROR"
}

# =============================================================================
# 5. DEFAULT USER PROFILE (new users inherit these settings)
# =============================================================================
Write-Log "-----------------------------------------------------------------"
Write-Log "5. Configuring Default User profile (new user defaults)..."

$DefaultUserDat = "C:\Users\Default\NTUSER.DAT"
$HiveMount      = "HKLM\TempAVDDefaultUser"
$HiveMountPS    = "HKLM:\TempAVDDefaultUser"

try {
    $LoadResult = & reg load $HiveMount $DefaultUserDat 2>&1
    Write-Log "   Hive loaded: $LoadResult"

    $RegConfig = @{
        "Control Panel\International" = @{
            "Locale"           = "00000809"
            "LocaleName"       = "en-GB"
            "sCountry"         = "United Kingdom"
            "sLanguage"        = "ENG"
            "iFirstDayOfWeek"  = "0"             # Monday
            "sShortDate"       = "dd/MM/yyyy"
            "sLongDate"        = "dd MMMM yyyy"
            "sShortTime"       = "HH:mm"
            "sTimeFormat"      = "HH:mm:ss"
            "iTime"            = "1"             # 24-hour
            "iTLZero"          = "1"             # leading zero
            "sCurrency"        = "£"
            "sMonDecimalSep"   = "."
            "sMonThousandSep"  = ","
            "sDecimal"         = "."
            "sThousand"        = ","
            "sMeasure"         = "0"             # Metric
        }
        "Control Panel\International\Geo" = @{
            "Nation"           = "242"
        }
    }

    foreach ($RegPath in $RegConfig.Keys) {
        $FullPath = "$HiveMountPS\$RegPath"
        if (-not (Test-Path $FullPath)) {
            New-Item -Path $FullPath -Force | Out-Null
        }
        foreach ($Name in $RegConfig[$RegPath].Keys) {
            Set-ItemProperty -Path $FullPath -Name $Name -Value $RegConfig[$RegPath][$Name]
        }
        Write-Log "   $RegPath : SUCCESS"
    }
} catch {
    Write-Log "   Default user profile FAILED: $($_.Exception.Message)" "ERROR"
} finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 2
    $UnloadResult = & reg unload $HiveMount 2>&1
    Write-Log "   Hive unloaded: $UnloadResult"
}

# =============================================================================
# 6. WELCOME SCREEN & SYSTEM ACCOUNTS
# =============================================================================
Write-Log "-----------------------------------------------------------------"
Write-Log "6. Copying settings to welcome screen and system accounts..."

# This ensures the lock screen, OOBE, and new user accounts all get en-GB
try {
    # Copy current user settings to welcome screen and new user accounts
    # Uses the international settings XML approach
    $XmlPath = "C:\temp\AVD-UK-IntlSettings.xml"

    $XmlContent = @"
<gs:GlobalizationServices xmlns:gs="urn:longhornGlobalizationUnattend">
    <gs:UserList>
        <gs:User UserID="Current" CopySettingsToDefaultUserAcct="true" CopySettingsToSystemAcct="true"/>
    </gs:UserList>
    <gs:LocationPreferences>
        <gs:GeoID Value="242"/>
    </gs:LocationPreferences>
    <gs:MUILanguagePreferences>
        <gs:MUILanguage Value="en-GB"/>
        <gs:MUIFallback Value="en-US"/>
    </gs:MUILanguagePreferences>
    <gs:SystemLocale Name="en-GB"/>
    <gs:InputPreferences>
        <gs:InputLanguageID Action="add" ID="0809:00000809"/>
        <gs:InputLanguageID Action="remove" ID="0409:00000409"/>
    </gs:InputPreferences>
    <gs:UserLocale>
        <gs:Locale Name="en-GB" SetAsCurrent="true" ResetAllSettings="true"/>
    </gs:UserLocale>
</gs:GlobalizationServices>
"@

    Set-Content -Path $XmlPath -Value $XmlContent -Encoding UTF8
    Write-Log "   International settings XML written to $XmlPath"

    $ControlResult = & control.exe intl.cpl,,/f:"$XmlPath" 2>&1
    Write-Log "   control intl.cpl result: $ControlResult"
    Write-Log "   Welcome screen & system accounts: SUCCESS"
} catch {
    Write-Log "   Welcome screen config FAILED: $($_.Exception.Message)" "ERROR"
}

# =============================================================================
# 7. SET KEYBOARD LAYOUT
# =============================================================================
Write-Log "-----------------------------------------------------------------"
Write-Log "7. Setting default keyboard layout to UK..."

try {
    $RegKeyboardPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout"
    # Preload UK keyboard (0809:00000809)
    $PreloadPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\00000809"
    if (Test-Path $PreloadPath) {
        Write-Log "   UK keyboard layout (00000809) is available"
    }

    # Set default input for new users
    $DefaultPreload = "$HiveMountPS\Keyboard Layout\Preload" -replace "TempAVDDefaultUser", "Default"
    Write-Log "   Keyboard layout: handled via intl.cpl XML (section 6)"
} catch {
    Write-Log "   Keyboard layout FAILED: $($_.Exception.Message)" "ERROR"
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Log "================================================================="
Write-Log "AVD UK Custom Image Configuration — Complete"
Write-Log "================================================================="
Write-Log "  System Locale  : $(try { (Get-WinSystemLocale).Name } catch { 'ERROR' })"
Write-Log "  Timezone       : $(try { (Get-TimeZone).Id } catch { 'ERROR' })"
Write-Log "  UI Language    : $(try { (Get-WinUILanguageOverride).LanguageTag } catch { 'not set / default' })"
Write-Log "  Culture        : $(try { (Get-Culture).Name } catch { 'ERROR' })"
Write-Log "  Home Location  : $(try { (Get-WinHomeLocation).HomeLocation } catch { 'ERROR' })"
Write-Log "  Log file       : $LogPath"
Write-Log "================================================================="
Write-Log "Next steps:"
Write-Log "  - If building a custom image: proceed with sysprep / generalization"
Write-Log "  - If running via Intune: users must sign out and back in"
Write-Log "================================================================="
