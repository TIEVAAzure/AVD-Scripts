# ==================================================================================================
# AVD-AIB-3rdParty-Download.ps1
# --------------------------------------------------------------------------------------------------
# PURPOSE
#   Customer-specific bootstrapper that downloads and runs the customer AppInstalls orchestrator.
#
# WHERE IT LIVES
#   /Customer/<CUSTOMER>/AVD-AIB-3rdParty-Download.ps1
#
# WHAT IT DOES
#   1) Downloads /Customer/<CUSTOMER>/AVD-AIB-AppInstalls.ps1 from GitHub (raw)
#   2) Saves it to C:\Windows\Temp\AIB\AVD-AIB-AppInstalls.downloaded.ps1
#   3) Executes it in 64-bit PowerShell
#
# LOGGING
#   - Primary log: C:\Windows\Temp\AIB\AVD-AIB-3rdParty-Download.log
#   - AppInstalls creates its own log + per-script child logs
#
# EXIT CODES (CONTRACT)
#   0    = success
#   1    = failure
#   3010 = reboot required (treated as success by this orchestrator)
# ==================================================================================================

$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

# Ensure TLS 1.2 so GitHub raw downloads work on older images
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Log location (consistent across all AIB scripts)
$logRoot = "C:\Windows\Temp\AIB"
New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
$logPath = Join-Path $logRoot "AVD-AIB-3rdParty-Download.log"

function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
    $line | Tee-Object -FilePath $logPath -Append | Out-Null
}

function Download-WithRetry {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [string]$OutFile,
        [int]$Retries = 3,
        [int]$DelaySeconds = 3
    )

    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Log "Downloading ($i/$Retries): $Uri -> $OutFile"
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing

            # Basic sanity checks (prevents “downloaded HTML/404” from being executed)
            if (-not (Test-Path $OutFile)) { throw "Downloaded file not found." }
            if ((Get-Item $OutFile).Length -lt 50) { throw "Downloaded file too small (likely HTML/empty)." }

            $head = (Get-Content -Path $OutFile -TotalCount 5 | Out-String)
            if ($head -match '<html' -or $head -match '<!DOCTYPE' -or $head -match 'Not Found') {
                throw "Downloaded content looks like HTML/404."
            }

            Log "Download OK: $OutFile ($((Get-Item $OutFile).Length) bytes)"
            return
        }
        catch {
            Log "Download failed: $($_.Exception.Message)"
            if ($i -lt $Retries) { Start-Sleep -Seconds $DelaySeconds } else { throw }
        }
    }
}

try {
    # ----------------------------------------------------------------------------------------------
    # EDIT THIS PER CUSTOMER FOLDER
    # ----------------------------------------------------------------------------------------------
    $CustomerCode = "BWG"   # e.g. BWG, IMS

    # Cache-buster to avoid GitHub/CDN serving a stale copy mid-build
    $ts = Get-Date -Format "yyyyMMddHHmmss"

    $appInstallsUrl   = "https://raw.githubusercontent.com/TIEVAAzure/AVD-Scripts/refs/heads/main/Customer/$CustomerCode/AVD-AIB-AppInstalls.ps1?ts=$ts"
    $appInstallsLocal = Join-Path $logRoot "AVD-AIB-AppInstalls.downloaded.ps1"

    # Always run orchestration scripts in 64-bit PowerShell (System32)
    $ps64 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

    Log "Starting third-party app script bootstrapper"
    Log "CustomerCode: $CustomerCode"
    Log "AppInstalls URL: $appInstallsUrl"

    Write-Host ">>> [3rdParty-Download] Downloading AppInstalls for customer: $CustomerCode"
    Download-WithRetry -Uri $appInstallsUrl -OutFile $appInstallsLocal

    Write-Host ">>> [3rdParty-Download] Executing AppInstalls (64-bit): $appInstallsLocal"
    Log "Executing AppInstalls (64-bit): $appInstallsLocal"

    # Capture output once and tee it to:
    #   - Packer/AIB console (Write-Host output)
    #   - This script's log file
    $output = & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $appInstallsLocal 2>&1
    $code = $LASTEXITCODE

    $output | Tee-Object -FilePath $logPath -Append | Out-Null

    Log "AppInstalls exit code: $code"
    Write-Host ">>> [3rdParty-Download] AppInstalls exit code: $code"

    # 3010 = “reboot required” (treat as success in image pipelines)
    if ($code -ne 0 -and $code -ne 3010) {
        Write-Host "Third-party app scripts failed."
        $global:LASTEXITCODE = 1
        exit 1
    }

    Write-Host "Third-party app scripts completed successfully."
    $global:LASTEXITCODE = 0
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Write-Host "Third-party app scripts failed."
    $global:LASTEXITCODE = 1
    exit 1
}
