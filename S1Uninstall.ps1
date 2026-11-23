# SentinelOne Universal Uninstall
# Designed for Intune
# Does NOT require the original SentinelOne installer
# Assumes SentinelOne Tamper Protection has already been disabled.

$ErrorActionPreference = "Stop"

$LogPath = "C:\ProgramData\SentinelOne-Uninstall.log"

function Write-Log {
    param([string]$Message)

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File `
        -FilePath $LogPath `
        -Append `
        -Encoding utf8
}

Write-Log "============================================"
Write-Log "Starting SentinelOne uninstall"
Write-Log "Running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

# ---------------------------------------------------------
# Locate all installed SentinelOne agent versions
# ---------------------------------------------------------

$SentinelBasePath = "C:\Program Files\SentinelOne"

if (-not (Test-Path $SentinelBasePath)) {
    Write-Log "SentinelOne directory does not exist."
    Write-Log "SentinelOne appears to already be removed."
    exit 0
}

$AgentDirectories = Get-ChildItem `
    -Path $SentinelBasePath `
    -Directory `
    -Recurse `
    -ErrorAction Stop |
    Where-Object {
        $_.Name -like "Sentinel Agent*" -or $_.Name -eq "SentinelOne"
    } |
    Sort-Object Name -Descending

if (-not $AgentDirectories) {
    Write-Log "No Sentinel Agent directories found."
    exit 0
}

Write-Log "Found $($AgentDirectories.Count) SentinelOne agent directory/directories."

# ---------------------------------------------------------
# Try every installed SentinelOne version
# ---------------------------------------------------------

$UninstallAttempted = $false
$UninstallFailed = $false

foreach ($AgentDirectory in $AgentDirectories) {

    Write-Log "Found SentinelOne directory: $($AgentDirectory.FullName)"

    $Uninstaller = Join-Path $AgentDirectory.FullName "uninstall.exe"

    if (-not (Test-Path $Uninstaller)) {
        Write-Log "uninstall.exe not found in $($AgentDirectory.FullName)"
        continue
    }

    Write-Log "Found uninstall executable: $Uninstaller"
    Write-Log "Beginning uninstall."

    $UninstallAttempted = $true

    try {

        $Process = Start-Process `
            -FilePath $Uninstaller `
            -ArgumentList "/uninstall /norestart /q" `
            -Wait `
            -PassThru

        Write-Log "Uninstaller exited with code $($Process.ExitCode)"
        if ($Process.ExitCode -notin @(0, 3010)) {
            $UninstallFailed = $true
        }

    }
    catch {

        Write-Log "ERROR running uninstall.exe"
        Write-Log $_.Exception.Message
        $UninstallFailed = $true

    }

    # Give SentinelOne some time to clean itself up
    Start-Sleep -Seconds 10
}

# ---------------------------------------------------------
# Verification
# ---------------------------------------------------------

Start-Sleep -Seconds 10

$RemainingAgents = @()
if (Test-Path $SentinelBasePath) {
    $RemainingAgents = Get-ChildItem `
        -Path $SentinelBasePath `
        -Directory `
        -Recurse `
        -ErrorAction Stop |
        Where-Object {
            if ($_.Name -like "Sentinel Agent*") {
                Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Force -ErrorAction Stop | Select-Object -First 1
            }
        }
}

if (-not $RemainingAgents) {

    if ($UninstallFailed) {
        Write-Log "Uninstall could not be confirmed as successful."
        exit 1
    }

    if (-not $UninstallAttempted) {
        Write-Log "No files remain in Sentinel Agent directories."
        exit 0
    }

    Write-Log "SUCCESS: No files remain in Sentinel Agent directories."
    Write-Log "Returning hard reboot code to Intune."
    exit 1641

}

Write-Log "Sentinel Agent directories still contain files after uninstall attempt."

foreach ($Agent in $RemainingAgents) {
    Write-Log "Remaining: $($Agent.FullName)"
}

if (-not $UninstallAttempted) {
    Write-Log "No usable uninstall.exe was located."
}

Write-Log "Uninstall could not be confirmed."

exit 1