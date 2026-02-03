# AVD-AIB-3rdParty-Download.ps1 (DROP-IN)
# Downloads the customer AppInstalls script and executes it in 64-bit PowerShell.
# Critical: propagates correct exit code to AIB/Packer (no stale $LASTEXITCODE).

$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

# Force TLS 1.2 for GitHub raw
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$scriptUrl = "https://raw.githubusercontent.com/TIEVAAzure/AVD-Scripts/refs/heads/main/Customer/IMS/AVD-AIB-AppInstalls.ps1"

$logRoot = "C:\Windows\Temp\AIB"
New-Item -Path $logRoot -ItemType Directory -Force | Out-Null

$scriptPath = Join-Path $logRoot "AVD-AIB-AppInstalls.downloaded.ps1"
$logPath    = Join-Path $logRoot "AVD-AIB-3rdParty-Download.log"

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

try {
    Log "Starting 3rd-party bootstrap"
    Download-WithRetry -Uri $scriptUrl -OutFile $scriptPath

    # Always run child in 64-bit PowerShell
    $ps64 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

    Log "Executing AppInstalls (64-bit): $ps64 -File $scriptPath"
    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath

    $code = $LASTEXITCODE
    Log "AppInstalls exit code: $code"

    # Ensure Packer sees the right code
    $global:LASTEXITCODE = $code
    exit $code
}
catch {
    Log "FATAL: $($_.Exception.Message)"
    $global:LASTEXITCODE = 1
    exit 1
}
