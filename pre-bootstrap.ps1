[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$NfsServer,

    [Parameter(Mandatory)]
    [string]$NfsExport,

    [string]$MountDrive = "S",

    [string[]]$BootstrapArgs,

    [switch]$RunBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "[INFO] Windows pre-bootstrap starting"

# ------------------------------------------------------------
# Administrator check
# ------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p  = New-Object Security.Principal.WindowsPrincipal($id)

if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Administrator privileges required."
}

Write-Host "[INFO] Administrator privileges confirmed"

# ------------------------------------------------------------
# Detect and ensure NFS client feature (robust across Server SKUs)
# ------------------------------------------------------------
if (-not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
    throw "Get-WindowsOptionalFeature is not available on this system."
}

$nfsFeatures = Get-WindowsOptionalFeature -Online |
    Where-Object { $_.FeatureName -match 'NFS' }

if (-not $nfsFeatures) {
    throw "No NFS-related Windows features found on this system."
}

$enabledClientFeature = $nfsFeatures |
    Where-Object {
        $_.State -eq 'Enabled' -and
        (
            $_.FeatureName -match 'ClientForNFS' -or
            $_.FeatureName -match 'ServerAndClient'
        )
    } |
    Select-Object -First 1

if ($enabledClientFeature) {
    Write-Host ("[INFO] NFS client already enabled via feature: {0}" -f $enabledClientFeature.FeatureName)
}
else {
    $candidate =
        $nfsFeatures | Where-Object { $_.FeatureName -match 'ClientForNFS' } |
        Select-Object -First 1

    if (-not $candidate) {
        throw "No suitable NFS client feature found to enable."
    }

    Enable-WindowsOptionalFeature -Online -FeatureName $candidate.FeatureName -All
    Write-Host ("[INFO] Enabled NFS client feature: {0}" -f $candidate.FeatureName)
}

# ------------------------------------------------------------
# Configure NFS UID/GID mapping (Server-correct syntax)
# ------------------------------------------------------------
nfsadmin client stop
nfsadmin mapping localhost config anonuid=0 anongid=0
nfsadmin client start

Write-Host "[INFO] NFS UID/GID mapping configured (anonuid=0, anongid=0)"

# ------------------------------------------------------------
# Mount NFS share persistently (PowerShell-safe)
# ------------------------------------------------------------
$target = "{0}:{1}" -f $NfsServer, $NfsExport
$drive  = "{0}:" -f $MountDrive

if (-not (Test-Path $drive)) {
    mount.exe -o anon,persistent=yes $target $drive
    Write-Host ("[INFO] Mounted {0} at {1}" -f $target, $drive)
}
else {
    Write-Host ("[INFO] Drive {0} already exists" -f $drive)
}

# ------------------------------------------------------------
# Optional: run stage-1 bootstrap (win-bootstrap.ps1)
# ------------------------------------------------------------
if ($RunBootstrap) {
    $bootstrapScript = Join-Path $drive "win-bootstrap.ps1"

    if (-not (Test-Path $bootstrapScript)) {
        throw ("Bootstrap script not found: {0}" -f $bootstrapScript)
    }

    Write-Host "[INFO] Launching win-bootstrap.ps1"

    $args = @(
        "-ExecutionPolicy","Bypass",
        "-File",$bootstrapScript
    )

    if ($BootstrapArgs) {
        $args += $BootstrapArgs
    }

    powershell.exe @args
}

Write-Host "[INFO] Pre-bootstrap completed successfully"
