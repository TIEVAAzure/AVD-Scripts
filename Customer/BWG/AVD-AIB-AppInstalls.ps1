# Customer-AVD\IMS\AVD-AIB-AppInstalls.ps1 (DROP-IN)
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

function Assert-ValidPsFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    if ((Get-Item $Path).Length -lt 50) { throw "File too small (likely HTML/empty): $Path" }

    $head = Get-Content -Path $Path -TotalCount 5 -ErrorAction SilentlyContinue | Out-String
    if ($head -match '<!DOCTYPE html' -or $head -match '<html' -or $head -match '404') {
        throw "Downloaded content looks like HTML/404, not a PowerShell script."
    }

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
        } catch {
            Log "Download failed: $($_.Exception.Message)"
            if ($i -lt $Retries) { Start-Sleep -Seconds $DelaySeconds } else { throw }
        }
    }
}

$baseUrl = "https://raw.githubusercontent.com/TIEVAAzure/AVD-Scripts/refs/heads/main/Applications"

$AppScripts = @(
    "AVD-AIB-7zip-Removal.ps1"
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

        & $ps64 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath *>> $childLog

        $code = $LASTEXITCODE
        Log "$fileName exit code: $code"

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
