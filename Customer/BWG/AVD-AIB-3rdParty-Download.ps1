# AVD-AIB-3rdParty-Download.ps1 (DROP-IN)
# Downloads and executes AppInstalls for this customer/image.
# exit 0 = pass, exit 1 = fail

$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

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

            if (-not (Test-Path $OutFile)) { throw "Downloaded file not found." }
            if ((Get-Item $OutFile).Length -lt 50) { throw "Downloaded file too small (likely HTML/empty)." }

            $head = (Get-Content -Path $OutFile -TotalCount 5 | Out-String)
            if ($head -match '<html' -or $head -match '<!DOCTYPE' -or $head -match 'Not Found') {
                throw "Downloaded content looks like HTML/404."
            }

            Log "Download OK: $OutFile ($((Get-Item $OutFile).Length) bytes)"
            return
        } catch {
            Log "Download failed: $($_.Exception.Message)"
            if ($i -lt $Retries) { Start-Sleep -Seconds $DelaySeconds } else { throw }
        }
    }
}

try {
    # Set your customer path here
    $appInstallsUrl = "https://raw.githubusercontent.com/TIEVAAzure/AVD-Scripts/main/Customer/BWG/AVD-AIB-AppInstalls.ps1?ts=$(Get-Date -Format yyyyMMddHHmmss)"

    $localPath = Join-Path $logRoot "AVD-AIB-AppInstalls.downloaded.ps1"
    Download-WithRetry -Uri $appInstallsUrl -OutFile $localPath

    $ps64 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    Log "Executing AppInstalls (64-bit): $localPath"

    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $localPath
    $code = $LASTEXITCODE

    Log "AppInstalls exit code: $code"

    if ($code -ne 0) {
        Write-Host "Third-party app uninstalls failed."
        $global:LASTEXITCODE = 1
        exit 1
    }

    Write-Host "Third-party app uninstalls completed successfully."
    $global:LASTEXITCODE = 0
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Write-Host "Third-party app uninstalls failed."
    $global:LASTEXITCODE = 1
    exit 1
}
