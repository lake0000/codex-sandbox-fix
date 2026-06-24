$ErrorActionPreference = "Stop"

$codexHome = Join-Path $env:USERPROFILE ".codex"
$sandboxDir = Join-Path $codexHome ".sandbox"
$marker = Join-Path $sandboxDir "setup_marker.json"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$log = Join-Path $codexHome "repair-codex-sandbox-acl-$stamp.log"

function Write-RepairLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "s"), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

function Add-FullControl {
    param(
        [System.Security.AccessControl.FileSystemSecurity]$Acl,
        [string]$Identity,
        [bool]$IsDirectory
    )

    if ($IsDirectory) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Identity,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
    } else {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Identity,
            "FullControl",
            "None",
            "None",
            "Allow"
        )
    }

    [void]$Acl.SetAccessRule($rule)
}

Write-RepairLog "Starting Codex sandbox ACL repair"
Write-RepairLog "User: $env:USERDOMAIN\$env:USERNAME"
Write-RepairLog "Sandbox: $sandboxDir"
Write-RepairLog "Marker: $marker"

if (-not (Test-Path -LiteralPath $sandboxDir -PathType Container)) {
    throw "Sandbox directory not found: $sandboxDir"
}

if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
    throw "Sandbox setup marker not found: $marker"
}

$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$wellKnownAdmins = "BUILTIN\Administrators"
$wellKnownSystem = "NT AUTHORITY\SYSTEM"
$sandboxGroup = "$env:COMPUTERNAME\CodexSandboxUsers"

$dirAcl = Get-Acl -LiteralPath $sandboxDir
Add-FullControl -Acl $dirAcl -Identity $currentUser -IsDirectory $true
Add-FullControl -Acl $dirAcl -Identity $wellKnownAdmins -IsDirectory $true
Add-FullControl -Acl $dirAcl -Identity $wellKnownSystem -IsDirectory $true
try {
    Add-FullControl -Acl $dirAcl -Identity $sandboxGroup -IsDirectory $true
} catch {
    Write-RepairLog "CodexSandboxUsers grant skipped: $($_.Exception.Message)"
}
Set-Acl -LiteralPath $sandboxDir -AclObject $dirAcl
Write-RepairLog "Updated sandbox directory ACL"

$fileAcl = New-Object System.Security.AccessControl.FileSecurity
$fileAcl.SetOwner((New-Object System.Security.Principal.NTAccount($currentUser)))
Add-FullControl -Acl $fileAcl -Identity $currentUser -IsDirectory $false
Add-FullControl -Acl $fileAcl -Identity $wellKnownAdmins -IsDirectory $false
Add-FullControl -Acl $fileAcl -Identity $wellKnownSystem -IsDirectory $false
try {
    Add-FullControl -Acl $fileAcl -Identity $sandboxGroup -IsDirectory $false
} catch {
    Write-RepairLog "CodexSandboxUsers marker grant skipped: $($_.Exception.Message)"
}
Set-Acl -LiteralPath $marker -AclObject $fileAcl
Write-RepairLog "Updated setup marker ACL"

$content = Get-Content -LiteralPath $marker -Raw
Write-RepairLog "Marker is readable; length=$($content.Length)"
Write-RepairLog "Repair completed"

Write-Host "Codex sandbox ACL repair completed."
Write-Host "Log: $log"
