---
name: codex-sandbox-fix
description: 'Diagnose and repair Codex App Windows Agent sandbox update failures. Use when Codex shows unable to update Agent sandbox, windows sandbox orchestrator helper launch errors, orchestrator_helper_incomplete, sandbox setup marker missing or incompatible, or when setup_marker.json under .codex\.sandbox exists but the current Windows user cannot read it because of ACL corruption.'
---

# Codex Sandbox Fix

## Overview

Use this skill to diagnose Codex App sandbox setup failures on Windows, especially cases where the sandbox marker file exists but is unreadable because `.codex\.sandbox` or `setup_marker.json` has broken ACLs.

Before changing permissions, read `references/windows-sandbox-acl.md`. Use the bundled `scripts/repair-codex-sandbox-acl.ps1` only after the diagnosis confirms an ACL problem.

## Workflow

1. Confirm the symptom.
   - Look for UI text like "unable to update Agent sandbox".
   - Look for errors such as `orchestrator_helper_launch_canceled`, `orchestrator_helper_incomplete`, or `sandbox setup marker missing or incompatible`.
   - Inspect the latest sandbox log under `%USERPROFILE%\.codex\.sandbox\sandbox.<date>.log`.

2. Check whether the marker exists and is readable.
   - Run:

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.codex\.sandbox\setup_marker.json"
```

   - If this returns JSON, the primary issue is probably not marker ACL corruption.
   - If it returns `Access is denied` while the file exists, treat this as a strong ACL-corruption signal.

3. Check local sandbox identities.
   - Verify `CodexSandboxUsers` exists and normally contains `CodexSandboxOffline` and `CodexSandboxOnline`.
   - If the group or accounts are missing, do not assume this skill's ACL-only repair is sufficient. Prefer rerunning official Codex sandbox setup or reinstall/repair paths.

4. Repair only the affected ACLs.
   - Do not delete the entire `.codex` directory.
   - Do not wipe Codex login state, plugins, skills, history, or configuration.
   - Use the bundled repair script from an elevated PowerShell session to grant access on `.codex\.sandbox` and `setup_marker.json` to the current user, Administrators, SYSTEM, and `CodexSandboxUsers`.

5. Validate.
   - Confirm `setup_marker.json` can be read.
   - Run a simple command through Codex.
   - Confirm `.sandbox-bin` receives a command runner.
   - Check the sandbox log for `errors=[]` and `SUCCESS`.

## Safety Rules

- Ask the user before running elevated ACL repair commands.
- Keep the repair scoped to `%USERPROFILE%\.codex\.sandbox` and `%USERPROFILE%\.codex\.sandbox\setup_marker.json`.
- Preserve existing Codex configuration and credentials.
- If `setup_marker.json` is missing rather than unreadable, first restart Codex App or trigger official sandbox setup regeneration.
- If ACL repair succeeds but the UI still shows the old error, fully quit and restart Codex App.

## Resources

- `references/windows-sandbox-acl.md`: detailed diagnosis, expected logs, repair commands, and post-repair checks.
- `scripts/repair-codex-sandbox-acl.ps1`: reusable elevated PowerShell repair script.
