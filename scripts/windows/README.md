# Windows Attack Simulation

A multi-stage Windows attack simulation that triggers Elastic Security detection rules across eight MITRE ATT&CK tactics — from initial discovery through exfiltration. Non-destructive: all changes made to the host are reversed during the cleanup phase.

Exfiltrated data is SCP'd to a separate Ubuntu host (the same exfil target used by the Linux demo).

---

## How It Works

`exploit.ps1` runs on the Windows target host and walks through the following attack chain:

| Stage | Tactic | What Happens |
|---|---|---|
| 1 | Discovery | Enumerates the user, system info, local accounts, network config, and domain trusts; queries a public IP lookup service |
| 2 | Execution | Spawns a PowerShell child process with encoded command flags; calls `[Reflection.Assembly]::Load` on a non-existent path (fails silently but triggers detection via Script Block Logging); starts a hidden background `powershell.exe` process |
| 3 | Defense Evasion | Clears PowerShell console history (`Add-MpPreference`/`Set-MpPreference` are skipped — Elastic tamper protection terminates the parent process regardless of indirection) |
| 4 | Credential Access | Enumerates saved credentials via `cmdkey` and `VaultCmd` |
| 5 | Persistence | Registers a scheduled task (removed during cleanup) |
| 6 | Collection | Captures clipboard data; collects the hosts file and environment variables; compresses everything into an archive |
| 7 | Command & Control | Makes HTTP requests to Pastebin and a known indicator URL via `curl.exe` |
| 8 | Exfiltration | SCPs the compressed archive to the Ubuntu exfil host |
| — | Cleanup | Removes the staged archive, staging directory, and scheduled task; a hidden background `powershell.exe` process and the in-memory assembly remain running for demo observation |

### Windows Analog to the Linux `/dev/shm` Trick

The Linux demo runs binaries from `/dev/shm`, deletes them, then shows the process still running in memory. The Windows equivalent is a hidden `powershell.exe` process started during the Execution stage that stays alive after the script finishes — observable in Task Manager or Elastic Event Analyzer.

The `defense_evasion_posh_assembly_load` rule is triggered via Script Block Logging: `[System.Reflection.Assembly]::Load` is called in the script and captured by Event ID 4104. The call itself fails silently (the path does not exist), but the detection rule fires on the pattern in the logged script block — no compiler is spawned, which keeps Elastic Endpoint from killing the process mid-run.

---

## Prerequisites

**On the Windows target host:**
- Windows 10 1809+ or Windows 11
- PowerShell 5.0+
- Windows OpenSSH Server enabled (`Settings → System → Optional Features → OpenSSH Server`)
- Elastic Agent with Endpoint integration enrolled and running
- PowerShell Script Block Logging enabled (see note below)

**On your local machine (Mac/Linux):**
- SSH access to the Windows host
- SSH key for the Windows host added to your agent or specified in `scripts/.env`

### Why PowerShell Script Block Logging Is Required

Several Elastic detection rules work by reading the content of PowerShell scripts as they execute, not just the fact that `powershell.exe` was launched. Windows captures that content via **Event ID 4104** — but only when Script Block Logging is enabled.

Without it, the commands still run, but Windows never writes the event and Elastic never sees the script content. The rules that depend on it will not fire.

The affected rules in this demo are:

| Rule | What it looks for in the script |
|---|---|
| `defense_evasion_posh_assembly_load` | `[System.Reflection.Assembly]::Load($bytes)` |
| `defense_evasion_defender_exclusion_via_powershell` | `Add-MpPreference -ExclusionPath` |
| `defense_evasion_disabling_windows_defender_powershell` | `Set-MpPreference -DisableRealtimeMonitoring` |
| `collection_posh_clipboard_capture` | `Get-Clipboard` |
| `defense_evasion_clearing_windows_console_history` | `Remove-Item` targeting `ConsoleHost_history.txt` |

Rules that trigger on **process execution events** (e.g. `whoami.exe`, `nltest.exe`, `schtasks.exe` being spawned) do not need Script Block Logging — Elastic Endpoint captures those at the kernel level regardless.

Elastic Endpoint typically enables Script Block Logging automatically on enrolled hosts. Verify it is active before the demo with the command in the checklist below.

**On the Ubuntu exfil host:**
- Elastic Agent enrolled and running
- The Windows host's SSH public key in `~/.ssh/authorized_keys` for the exfil user

---

## Setup

### 1. Configure `scripts/.env` (local machine)

Add your Windows target host details to `scripts/.env`:

```sh
WINDOWS_TARGET_HOST=''          # IP or hostname of the Windows host
WINDOWS_TARGET_SSH_USER='bad_guy'
WINDOWS_TARGET_SSH_KEY=''       # Local path to your SSH private key for the Windows host
WINDOWS_TARGET_ROOTDIR='C:/Users/bad_guy/es-security-demo'
```

### 2. Configure `scripts/windows/config.ps1` (Windows host)

Update these values to match your environment before deploying to the Windows host:

```powershell
$ExfilTarget  = ''              # IP of the Ubuntu exfil host
$ExfilUser    = 'bad_lady'      # SSH user on the Ubuntu exfil host
$ExfilKeyPath = 'C:\Users\bad_guy\.ssh\your-key'  # SSH key on the Windows host for SCP to Ubuntu
$ExfilFile    = "$env:TEMP\totally_not_exfil_win.zip"
```

### 3. Deploy the repo to the Windows host

Copy the repo to the Windows host via SCP or another method. The files must exist at `WINDOWS_TARGET_ROOTDIR` before running the demo. Example using SCP from your local machine:

```sh
scp -r /path/to/es-security-demo bad_guy@<WINDOWS_HOST>:C:/Users/bad_guy/
```

### 4. Place the SSH key for the exfil host on the Windows host

The Windows host needs an SSH private key to SCP data to the Ubuntu exfil host. Copy it to the path set in `$ExfilKeyPath` in `config.ps1`.

---

## Running the Demo

### From your local machine (recommended)

```sh
sh scripts/demo_start_windows.sh
```

This SSHes into the Windows host and runs `exploit.ps1` remotely via PowerShell.

### Directly on the Windows host

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\Users\bad_guy\es-security-demo\scripts\windows\exploit.ps1
```

---

## Pre-Demo Checklist

Run these on the Windows host before the demo to avoid surprises:

```powershell
# Confirm Script Block Logging is enabled (required for several rules)
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -ErrorAction SilentlyContinue
# EnableScriptBlockLogging should be 1; if the key is missing, Elastic Endpoint may still enable it

# Confirm OpenSSH is available (required for exfil)
Get-Command scp.exe

# Confirm Elastic Endpoint is running
Get-Service -Name "Elastic Endpoint" | Select-Object Status

# Confirm the exfil SSH key is in place
Test-Path $ExfilKeyPath   # run after dot-sourcing config.ps1

# Verify connectivity to the exfil host
ssh -i $ExfilKeyPath -o BatchMode=yes $ExfilUser@$ExfilTarget "echo ok"
```

---

## Elastic Detection Rules

### Rules that will fire (no conditions)

These trigger on process execution events, which Elastic Endpoint collects by default.

| Rule | Trigger |
|---|---|
| `discovery_whoami_command_activity` | `whoami /all` spawned from `powershell.exe` |
| `discovery_privileged_localgroup_membership` | `net localgroup administrators` |
| `discovery_enumerating_domain_trusts_via_nltest` | `nltest /domain_trusts` — fires even on non-domain-joined machines |
| `discovery_host_public_ip_address_lookup` | `curl.exe` connecting to `ifconfig.me` from a non-browser process |
| `execution_windows_powershell_susp_args` | `powershell.exe -NoProfile -NonInteractive -EncodedCommand` |
| `credential_access_saved_creds_vaultcmd` | `cmdkey /list` and `VaultCmd /list` |
| `persistence_local_scheduled_task_creation` | Windows Security Event 4698 fires on `Register-ScheduledTask` |
| `command_and_control_common_webservices` | `Invoke-WebRequest` to `pastebin.com` from `powershell.exe` |

### Rules that fire only if PowerShell Script Block Logging is enabled

Elastic Endpoint typically enables Script Block Logging (Event ID 4104) automatically on managed hosts. Verify before the demo.

| Rule | Trigger |
|---|---|
| `defense_evasion_posh_assembly_load` | `[System.Reflection.Assembly]::Load($bytes)` in the script block |
| `collection_posh_clipboard_capture` | `Get-Clipboard` in the script block |
| `defense_evasion_clearing_windows_console_history` | `Remove-Item` targeting `ConsoleHost_history.txt` — only fires if the history file exists on the host |

### Additional rules likely to fire

| Rule | Why |
|---|---|
| `persistence_local_scheduled_task_scripting` | The registered task runs `powershell.exe -WindowStyle Hidden` |

### Rules that may not fire

| Rule | Why |
|---|---|
| `discovery_admin_recon` | `systeminfo` and `net user` alone may not satisfy the threshold — this rule typically requires a sequence of recon commands within a short window |
| `command_and_control_tool_transfer_via_curl` | The rule may specifically look for curl used with file-write flags (`-O`, `-o`); a basic `curl -s` GET may not qualify — the indicator match on `x.com/dlr.ppc` is more reliable |

### What will not fire

- **Any named exfiltration rule** — `scp.exe` over port 22 appears as network telemetry but does not match `exfiltration_smb_rare_destination`, `exfiltration_rclone_cloud_upload`, or `exfiltration_excessive_dns_queries_by_process`. The exfil is visible in Discover and network views.
- **LSASS / credential dumping rules** — the script does not touch LSASS
- **Lateral movement rules** — this exploit runs on a single host

---

## Cleanup

Everything is cleaned up automatically at the end of `exploit.ps1`. If the script fails before reaching its cleanup stage, the scheduled task may still be registered — remove it manually:

```bash
source scripts/.env && ssh -i "$WINDOWS_TARGET_SSH_KEY" "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST" "schtasks /Delete /TN \"WindowsSystemHealthMonitor\" /F"
```
