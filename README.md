# Codex Sandbox Fix

`codex-sandbox-fix` is a Codex Skill for diagnosing and repairing a specific Windows Codex App Agent sandbox failure.

It is intended for cases where Codex repeatedly says it cannot update the Agent sandbox, or tool commands fail with errors such as:

```text
windows sandbox: orchestrator_helper_launch_canceled
windows sandbox: orchestrator_helper_incomplete
sandbox setup marker missing or incompatible
```

The repair documented here targets a confirmed root cause: the sandbox marker file exists, but the current Windows user cannot read it because the ACL on `.codex\.sandbox` or `setup_marker.json` is broken.

## What This Skill Does

This Skill helps Codex:

- diagnose whether the issue is really a sandbox marker ACL problem
- inspect the Codex sandbox directory and logs
- verify local sandbox users and groups
- repair ACLs for `.codex\.sandbox` and `setup_marker.json`
- validate that Codex can run sandboxed commands again

It deliberately avoids destructive fixes such as deleting the whole `.codex` directory, because that can remove login state, settings, plugins, skills, and conversation history.

## Install

Install this repository as a Codex Skill:

```powershell
python "$env:USERPROFILE\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py" `
  --repo lake0000/codex-sandbox-fix `
  --path . `
  --name codex-sandbox-fix
```

Then restart Codex so the new Skill is discovered.

If you already have this repository locally, you can also copy it into:

```text
%USERPROFILE%\.codex\skills\codex-sandbox-fix
```

## How To Use

After installing and restarting Codex, ask Codex:

```text
Use $codex-sandbox-fix to diagnose and repair Codex Windows Agent sandbox update failures.
```

Codex will read `SKILL.md`, then load `references/windows-sandbox-acl.md` when it needs the detailed diagnosis and repair procedure.

## Manual Diagnosis

Check whether the sandbox marker can be read:

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

If the file exists but returns `Access is denied`, this Skill's ACL repair path is likely relevant.

Check recent sandbox logs:

```powershell
Get-Content -Path "$env:USERPROFILE\.codex\.sandbox\sandbox.$((Get-Date).ToString('yyyy-MM-dd')).log" -Tail 100
```

Check sandbox group membership:

```powershell
Get-LocalGroupMember -Group CodexSandboxUsers -ErrorAction SilentlyContinue |
  Select-Object Name,ObjectClass,PrincipalSource,SID
```

## Repair Script

The bundled repair script is:

```text
scripts/repair-codex-sandbox-acl.ps1
```

Run it from an elevated PowerShell session, or launch it with:

```powershell
Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  "$env:USERPROFILE\.codex\skills\codex-sandbox-fix\scripts\repair-codex-sandbox-acl.ps1"
) -Wait
```

The script grants access on the sandbox directory and marker file to:

- the current Windows user
- `BUILTIN\Administrators`
- `NT AUTHORITY\SYSTEM`
- the local `CodexSandboxUsers` group, when present

It writes a repair log to:

```text
%USERPROFILE%\.codex\repair-codex-sandbox-acl-<timestamp>.log
```

## Verify The Fix

After repair:

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

The command should print JSON instead of `Access is denied`.

Then run a simple command in Codex, such as:

```powershell
Get-Location
```

Finally, inspect the latest sandbox log and look for successful setup/run entries:

```powershell
Get-Content -Path "$env:USERPROFILE\.codex\.sandbox\sandbox.$((Get-Date).ToString('yyyy-MM-dd')).log" -Tail 40
```

Healthy logs commonly include `errors=[]` and `SUCCESS`.

## Files

- `SKILL.md`: main Codex Skill instructions and trigger description
- `agents/openai.yaml`: UI metadata for Codex
- `references/windows-sandbox-acl.md`: detailed diagnosis and repair reference
- `scripts/repair-codex-sandbox-acl.ps1`: PowerShell ACL repair script
- `codex-sandbox-fix.md`: original troubleshooting record

## Safety Notes

- Do not run the repair script unless the diagnosis points to marker ACL corruption.
- Do not delete the entire `.codex` directory as a first fix.
- If `setup_marker.json` is missing, restart Codex App or let official sandbox setup regenerate it first.
- If `CodexSandboxUsers`, `CodexSandboxOffline`, or `CodexSandboxOnline` are missing, the issue is broader than marker ACL corruption.
