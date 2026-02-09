# ==================================================================================================
# AVD-AIB-AppInstalls.ps1
# --------------------------------------------------------------------------------------------------
# PURPOSE
#   Customer-specific orchestrator that runs one or more app scripts from /Applications.
#
# WHERE IT LIVES
#   /Customer/<CUSTOMER>/AVD-AIB-AppInstalls.ps1
#
# WHAT IT DOES
#   1) Downloads each named script from /Applications (raw GitHub URL)
#   2) Saves it into C:\Windows\Temp\AIB\<ScriptName>.ps1
#   3) Executes each script in 64-bit PowerShell
#   4) Stops at first failure
#
# PACKER/AIB VISIBILITY (IMPORTANT)
#   - This script prints ">>> Running app script: <name>" to console so Packer logs show progress.
#   - Each child script output is teed to both console and its own child log.
#
# LOGGING
#   - Orchestrator log: C:\Windows\Temp\AIB\AVD-AIB-AppInstalls.log
#   - Child logs:       C:\Windows\Temp\AIB\<ScriptName>.log
#
# EXIT CODES (CONTRACT)
#   0    = success
#   1    = failure
#   3010 = reboot required (treated as success by this orchestrator)
# ==================================================================================================

$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$logRoot = "C:\Windows\Temp\AIB"
New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
$logPath = Join-Path $logRoot "AVD-AIB-AppInstalls.log"

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

# Shared Applications folder (NOT customer-specific)
$baseUrl = "https://raw.githubusercontent.com/TIEVAAzure/AVD-Scripts/main/Applications"

# --------------------------------------------------------------------------------------------------
# EDIT THIS LIST PER CUSTOMER / IMAGE
# Keep these script names in sync with /Applications
# --------------------------------------------------------------------------------------------------
$AppScripts = @(
    "AVD-AIB-7zip-Removal.ps1"
    # "AVD-AIB-AdobeReaderDC-Update.ps1"
    # "AVD-AIB-8x8-Update.ps1"
)

# Always run child scripts using 64-bit PowerShell
$ps64 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

try {
    Log "Starting App scripts orchestrator"
    Log ("App scripts list: " + ($AppScripts -join ", "))

    foreach ($fileName in $AppScripts) {
        $scriptUrl  = "$baseUrl/$fileName"
        $scriptPath = Join-Path $logRoot $fileName
        $childLog   = Join-Path $logRoot ("{0}.log" -f $fileName)

        # Download the child script fresh each run
        Download-WithRetry -Uri $scriptUrl -OutFile $scriptPath

        # Packer-visible header (so you can see what’s running)
        Write-Host ""
        Write-Host "============================================================"
        Write-Host ">>> Running app script: $fileName"
        Write-Host ">>> Child log: $childLog"
        Write-Host "============================================================"
        Write-Host ""

        Log "Running: $fileName (64-bit)"
        Log "Child log: $childLog"

        # Capture child output once and tee it to:
        #   - console (Packer)
        #   - child log file
        $output = & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath 2>&1
        $code = $LASTEXITCODE

        $output | Tee-Object -FilePath $childLog -Append | Out-Null

        Log "$fileName exit code: $code"
        Write-Host ">>> $fileName exit code: $code"

        if ($code -ne 0 -and $code -ne 3010) {
            Log "Stopping - $fileName failed with exit code $code"
            Write-Host "App scripts failed."
            $global:LASTEXITCODE = 1
            exit 1
        }
    }

    Log "All application scripts completed OK"
    Write-Host "App scripts completed successfully."
    $global:LASTEXITCODE = 0
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Write-Host "App scripts failed."
    $global:LASTEXITCODE = 1
    exit 1
}
