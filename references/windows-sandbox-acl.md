# Windows Sandbox ACL Repair Reference

## Symptom Pattern

The affected Codex App instance may show an "unable to update Agent sandbox" style error. Commands may fail with:

```text
windows sandbox: orchestrator_helper_launch_canceled: ShellExecuteExW failed to launch setup helper: 1223
windows sandbox: orchestrator_helper_incomplete: setup helper exited successfully before setup completed
```

The sandbox log may repeatedly include:

```text
sandbox setup required: sandbox setup marker missing or incompatible
```

This can happen even when `codex-windows-sandbox-setup.exe` appears to complete successfully.

## Root Cause Confirmed In This Repair

The marker existed at:

```text
%USERPROFILE%\.codex\.sandbox\setup_marker.json
```

but the current Windows user could not read it:

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

returned:

```text
Access to the path ... setup_marker.json is denied.
```

Codex then interpreted the marker as missing or incompatible and retried sandbox setup before each tool command.

## Diagnostic Commands

Inspect Codex directories:

```powershell
Get-ChildItem -Force -Path "$env:USERPROFILE\.codex" |
  Select-Object Name,Length,LastWriteTime,Mode
```

Important paths:

```text
.sandbox
.sandbox-bin
.sandbox-secrets
sandbox.<date>.log
```

Read the marker:

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

A healthy marker looks similar to:

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

Read recent sandbox logs:

```powershell
Get-Content -Path "$env:USERPROFILE\.codex\.sandbox\sandbox.$((Get-Date).ToString('yyyy-MM-dd')).log" -Tail 100
```

Check local sandbox group membership:

```powershell
Get-LocalGroupMember -Group CodexSandboxUsers -ErrorAction SilentlyContinue |
  Select-Object Name,ObjectClass,PrincipalSource,SID
```

Expected members usually include:

```text
CodexSandboxOffline
CodexSandboxOnline
```

## Repair Script Usage

Save or use the bundled script:

```text
scripts/repair-codex-sandbox-acl.ps1
```

Run it from an elevated PowerShell session. If invoking from a normal PowerShell session, use:

```powershell
Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  "$env:USERPROFILE\.codex\skills\codex-sandbox-fix\scripts\repair-codex-sandbox-acl.ps1"
) -Wait
```

The script writes a timestamped log to:

```text
%USERPROFILE%\.codex\repair-codex-sandbox-acl-<timestamp>.log
```

## Post-Repair Verification

Confirm the marker is readable:

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

Confirm `.sandbox-bin` receives a command runner:

```powershell
Get-ChildItem -Force -Path "$env:USERPROFILE\.codex\.sandbox-bin"
```

It should contain a file similar to:

```text
codex-command-runner-0.139.0.exe
```

Run any simple command through Codex, such as:

```powershell
Get-Location
```

Check the latest sandbox log:

```powershell
Get-Content -Path "$env:USERPROFILE\.codex\.sandbox\sandbox.$((Get-Date).ToString('yyyy-MM-dd')).log" -Tail 40
```

Healthy output often includes:

```text
setup refresh: processed 1 write roots (read roots delegated); errors=[]
setup binary completed
helper launch resolution: using copied command-runner path ...
SUCCESS: ...
```

## Notes

- Avoid installing third-party "codex sandbox repair" packages for this issue unless the source is trusted and necessary.
- Avoid deleting the full `.codex` directory because that can remove login state, configuration, plugins, skills, and conversation history.
- If `setup_marker.json` does not exist, let Codex App regenerate sandbox setup first. Then inspect ACLs if regeneration still fails.
- If `CodexSandboxUsers`, `CodexSandboxOffline`, or `CodexSandboxOnline` are missing, the issue is broader than marker ACL corruption.
