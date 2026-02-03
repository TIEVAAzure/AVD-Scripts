# Customer-AVD\IMS\AVD-AIB-AppInstalls.ps1 (DROP-IN)
# Controls which 3rd-party app scripts run during the build.
# Critical: runs each script in 64-bit PowerShell and returns correct exit code.

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
            if ((Get-Item $OutFile).Length -lt 20) { throw "Downloaded file too small (likely HTML/empty)." }

            Log "Download OK: $OutFile ($((Get-Item $OutFile).Length) bytes)"
            return
        } catch {
            Log "Download failed: $($_.Exception.Message)"
            if ($i -lt $Retries) { Start-Sleep -Seconds $DelaySeconds } else { throw }
        }
    }
}

# Base raw URL to the Applications folder
$baseUrl = "https://raw.githubusercontent.com/TIEVAAzure/AVD-Scripts/refs/heads/main/Applications"

# List of app script files in the Applications folder
# (EDIT THIS LIST per customer/image)
$AppScripts = @(
    "AVD-AIB-8x8-Update.ps1"
    "AVD-AIB-AdobeReaderDC-Update.ps1"
    # "AVD-AIB-7zip-Removal.ps1"   # <- add here if/when you want it in this run
)

$ps64 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

try {
    Log "Starting AppInstalls"
    Log "App scripts: $($AppScripts -join ', ')"

    foreach ($fileName in $AppScripts) {
        $scriptUrl  = "$baseUrl/$fileName"
        $scriptPath = Join-Path $logRoot $fileName
        $childLog   = Join-Path $logRoot ("{0}.log" -f $fileName)

        Download-WithRetry -Uri $scriptUrl -OutFile $scriptPath

        Log "Running: $fileName (64-bit)"
        Log "Child log: $childLog"

        # Run directly so $LASTEXITCODE is correct (do NOT Start-Process here)
        & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath *>> $childLog

        $code = $LASTEXITCODE
        Log "$fileName exit code: $code"

        # 3010 = reboot required (treat as success in image pipelines)
        if ($code -ne 0 -and $code -ne 3010) {
            Log "Stopping – script $fileName failed with exit code $code"
            $global:LASTEXITCODE = $code
            exit $code
        }
    }

    Log "All third-party scripts completed OK"
    $global:LASTEXITCODE = 0
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    $global:LASTEXITCODE = 1
    exit 1
}
