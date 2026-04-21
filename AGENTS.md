# AGENTS.md

## Overview
Scoop enhancement toolkit - two PowerShell scripts for Windows.

## Scripts

### scoopi.ps1
Fixes manifest relative paths, copies to cache, then installs via Scoop.

```powershell
.\scoopi.ps1 .\manifest.json
.\scoopi.ps1 -Help
```

**Requires:** `$env:SCOOP` or `$env:SCOOP_CACHE` environment variables set.

### scoopb.ps1
Backs up Scoop installation to a 7z archive.

```powershell
.\scoopb.ps1
```

**Requires:** `$env:SCOOP` set, 7z in PATH.

## Prerequisites
- Windows with PowerShell
- Scoop installed with env vars: `SCOOP`, `SCOOP_CACHE`, optionally `SCOOP_GLOBAL`
- 7z (for scoopb)