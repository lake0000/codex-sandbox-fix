# Codex App Agent 沙盒无法更新问题修复记录

## 问题现象

Codex App 显示类似“无法更新 Agent 沙盒”的错误，导致 Agent 或工具命令不能正常使用。

在 Codex 内运行命令时，可能出现以下错误：

```text
windows sandbox: orchestrator_helper_launch_canceled: ShellExecuteExW failed to launch setup helper: 1223
windows sandbox: orchestrator_helper_incomplete: setup helper exited successfully before setup completed
```

沙盒日志中可能反复出现：

```text
sandbox setup required: sandbox setup marker missing or incompatible
```

即使 `codex-windows-sandbox-setup.exe` 显示执行完成，Codex 仍会继续判断沙盒需要更新。

## 本次定位到的根因

本机的沙盒目录存在：

```text
C:\Users\<用户名>\.codex\.sandbox
```

沙盒 marker 文件也存在：

```text
C:\Users\<用户名>\.codex\.sandbox\setup_marker.json
```

但是当前用户无法读取该文件，执行：

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

会报错：

```text
Access to the path ... setup_marker.json is denied.
```

这会导致 Codex 误判：

```text
sandbox setup marker missing or incompatible
```

于是每次命令执行前都尝试更新 Agent 沙盒，最终表现为沙盒 helper 启动失败或 setup helper 提前退出。

本次确认的关键状态：

- `CodexSandboxUsers` 本地组存在
- `CodexSandboxOffline` 和 `CodexSandboxOnline` 本地用户存在
- `codex-windows-sandbox-setup.exe` 存在
- `.sandbox-bin` 起初为空
- `setup_marker.json` 存在但 ACL 损坏，当前用户不可读

## 诊断命令

### 1. 查看 Codex 沙盒目录

```powershell
Get-ChildItem -Force -Path "$env:USERPROFILE\.codex" |
  Select-Object Name,Length,LastWriteTime,Mode
```

重点关注：

```text
.sandbox
.sandbox-bin
.sandbox-secrets
sandbox.<date>.log
```

### 2. 读取沙盒 marker

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

正常情况下应看到类似：

```json
{
  "version": 5,
  "offline_username": "CodexSandboxOffline",
  "online_username": "CodexSandboxOnline",
  "created_at": "...",
  "proxy_ports": [],
  "allow_local_binding": false,
  "read_roots": [],
  "write_roots": []
}
```

如果这里显示 `Access is denied`，基本可以确认是 marker ACL 问题。

### 3. 查看沙盒日志

```powershell
Get-Content -Path "$env:USERPROFILE\.codex\.sandbox\sandbox.$((Get-Date).ToString('yyyy-MM-dd')).log" -Tail 100
```

异常日志通常包含：

```text
sandbox setup required: sandbox setup marker missing or incompatible
```

修复后正常日志通常包含：

```text
setup refresh: processed 1 write roots (read roots delegated); errors=[]
setup binary completed
helper copy: using in-memory cache for command-runner
SUCCESS: ...
```

### 4. 检查本地沙盒用户组

```powershell
Get-LocalGroupMember -Group CodexSandboxUsers -ErrorAction SilentlyContinue |
  Select-Object Name,ObjectClass,PrincipalSource,SID
```

正常应包含：

```text
CodexSandboxOffline
CodexSandboxOnline
```

## 修复方法

使用管理员权限修复 `.sandbox` 目录和 `setup_marker.json` 的 ACL，使当前用户、管理员、SYSTEM 和 `CodexSandboxUsers` 能正常访问。

保存以下脚本为：

```text
repair-codex-sandbox-acl.ps1
```

脚本内容：

```powershell
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
```

以管理员权限执行：

```powershell
Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  "$env:USERPROFILE\.codex\repair-codex-sandbox-acl.ps1"
) -Wait
```

## 修复后验证

### 1. marker 可读

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

应能正常输出 JSON，不能再出现 `Access is denied`。

### 2. `.sandbox-bin` 重新生成 command runner

```powershell
Get-ChildItem -Force -Path "$env:USERPROFILE\.codex\.sandbox-bin"
```

应看到类似：

```text
codex-command-runner-0.139.0.exe
```

### 3. 普通命令可以通过沙盒执行

在 Codex 中运行任意简单命令，例如：

```powershell
Get-Location
```

不应再出现：

```text
orchestrator_helper_launch_canceled
orchestrator_helper_incomplete
```

### 4. 日志显示成功

```powershell
Get-Content -Path "$env:USERPROFILE\.codex\.sandbox\sandbox.$((Get-Date).ToString('yyyy-MM-dd')).log" -Tail 40
```

正常应看到：

```text
setup refresh: processed 1 write roots (read roots delegated); errors=[]
setup binary completed
helper launch resolution: using copied command-runner path ...
SUCCESS: ...
```

## 注意事项

- 不建议安装第三方 `codex sandbox` skill 来修复本问题。本次搜索没有找到 OpenAI 官方的 Codex Windows Agent 沙盒修复 skill。
- 不建议直接删除整个 `.codex` 目录，这会影响登录状态、配置、插件、skills、历史会话等。
- 如果 ACL 修复后 Codex App UI 仍显示旧错误，先完全退出并重启 Codex App。
- 如果 `setup_marker.json` 不存在，而不是不可读，可以尝试重启 Codex App 让官方 `codex-windows-sandbox-setup.exe` 重新生成；如果仍失败，再检查 `.sandbox` 目录 ACL。
- 如果 `CodexSandboxUsers`、`CodexSandboxOffline`、`CodexSandboxOnline` 不存在，问题就不是单纯 marker ACL，需要重新安装或让 Codex App 以管理员权限触发沙盒初始化。

## 本次修复结论

本次问题不是 Codex App 安装包缺失，也不是沙盒用户组缺失，而是：

```text
.codex\.sandbox\setup_marker.json ACL 损坏，当前用户无法读取
```

修复 marker 和 `.sandbox` 目录 ACL 后：

- `setup_marker.json` 可读
- `.sandbox-bin` 成功生成 command runner
- 普通沙盒命令执行成功
- 日志显示 `errors=[]` 和 `SUCCESS`

问题已解决。
