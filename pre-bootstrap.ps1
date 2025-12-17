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
# Install NFS client (idempotent)
# ------------------------------------------------------------
$feature = Get-WindowsOptionalFeature -Online -FeatureName ServicesForNFS-ClientOnly
if ($feature.State -ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -FeatureName ServicesForNFS-ClientOnly -All
    Write-Host "[INFO] NFS client installed"
} else {
    Write-Host "[INFO] NFS client already installed"
}

# ------------------------------------------------------------
# Configure NFS UID/GID mapping
# ------------------------------------------------------------
nfsadmin client stop
nfsadmin client localhost config anonuid=0 anongid=0
nfsadmin client start
Write-Host "[INFO] NFS UID/GID mapping configured"

# ------------------------------------------------------------
# Mount NFS share (persistent)
# ------------------------------------------------------------
$target = "{0}:{1}" -f $NfsServer, $NfsExport
$drive  = "{0}:" -f $MountDrive

if (-not (Test-Path $drive)) {
    mount -o anon,persistent=yes $target $drive
    Write-Host ("[INFO] Mounted {0} at {1}" -f $target, $drive)
} else {
    Write-Host ("[INFO] Drive {0} already mounted" -f $drive)
}

# ------------------------------------------------------------
# Optional: run stage-1 bootstrap
# ------------------------------------------------------------
if ($RunBootstrap) {
    $bootstrapScript = Join-Path $drive "win-bootstrap.ps1"

    if (-not (Test-Path $bootstrapScript)) {
        throw ("Bootstrap script not found: {0}" -f $bootstrapScript)
    }

    Write-Host ("[INFO] Launching win-bootstrap.ps1")

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
