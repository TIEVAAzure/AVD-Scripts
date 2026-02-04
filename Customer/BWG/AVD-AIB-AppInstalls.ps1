# AVD-AIB-AppInstalls.ps1 (DROP-IN)
# Runs selected third-party app scripts during AIB build.
# exit 0 = pass, exit 1 = fail

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

# Raw base URL to Applications folder
$baseUrl = "https://raw.githubusercontent.com/TIEVAAzure/AVD-Scripts/main/Applications"

# Edit per image/customer
$AppScripts = @(
    "AVD-AIB-7zip-Removal.ps1"
)

$ps64 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

try {
    Log "Starting AppInstalls"
    Log ("App scripts: " + ($AppScripts -join ", "))

    foreach ($fileName in $AppScripts) {
        $scriptUrl  = "$baseUrl/$fileName"
        $scriptPath = Join-Path $logRoot $fileName
        $childLog   = Join-Path $logRoot ("{0}.log" -f $fileName)

        Download-WithRetry -Uri $scriptUrl -OutFile $scriptPath

        Log "Running: $fileName (64-bit)"
        Log "Child log: $childLog"

        & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath *>> $childLog
        $code = $LASTEXITCODE

        Log "$fileName exit code: $code"

        if ($code -ne 0) {
            Log "Stopping - $fileName failed with exit code $code"
            Write-Host "App installs failed."
            $global:LASTEXITCODE = 1
            exit 1
        }
    }

    Log "All third-party scripts completed OK"
    Write-Host "App uninstalls completed successfully."
    $global:LASTEXITCODE = 0
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Write-Host "App uninstalls failed."
    $global:LASTEXITCODE = 1
    exit 1
}
