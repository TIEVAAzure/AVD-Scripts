# AVD-AIB-3rdParty-Download.ps1 (DROP-IN)
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$scriptUrl = "https://raw.githubusercontent.com/TIEVAAzure/AVD-Scripts/refs/heads/main/Customer/BWG/AVD-AIB-AppInstalls.ps1"

$logRoot = "C:\Windows\Temp\AIB"
New-Item -Path $logRoot -ItemType Directory -Force | Out-Null

$scriptPath = Join-Path $logRoot "AVD-AIB-AppInstalls.downloaded.ps1"
$logPath    = Join-Path $logRoot "AVD-AIB-3rdParty-Download.log"

function Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
    $line | Tee-Object -FilePath $logPath -Append | Out-Null
}

function Assert-ValidPsFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    if ((Get-Item $Path).Length -lt 50) { throw "File too small: $Path" }

    $head = Get-Content -Path $Path -TotalCount 5 -ErrorAction SilentlyContinue | Out-String
    if ($head -match '<!DOCTYPE html' -or $head -match '<html' -or $head -match '404') {
        throw "Downloaded content looks like HTML/404, not a PowerShell script."
    }

    # Parser validation – catches unterminated strings/missing braces BEFORE execution
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
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

            Assert-ValidPsFile -Path $OutFile
            Log "Download OK + parse OK: $OutFile ($((Get-Item $OutFile).Length) bytes)"
            return
        }
        catch {
            Log "Download/validate failed: $($_.Exception.Message)"
            if ($i -lt $Retries) { Start-Sleep -Seconds $DelaySeconds } else { throw }
        }
    }
}

try {
    Log "Starting 3rd-party bootstrap"
    Download-WithRetry -Uri $scriptUrl -OutFile $scriptPath

    $ps64 = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    Log "Executing AppInstalls (64-bit): $ps64 -File $scriptPath"

    & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath

    $code = $LASTEXITCODE
    Log "AppInstalls exit code: $code"
    $global:LASTEXITCODE = $code
    exit $code
}
catch {
    Log "FATAL: $($_.Exception.Message)"
    $global:LASTEXITCODE = 1
    exit 1
}
