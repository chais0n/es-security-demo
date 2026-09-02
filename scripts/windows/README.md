# Windows Attack Simulation

A multi-stage Windows attack simulation that triggers Elastic Security detection rules across five MITRE ATT&CK tactics. Non-destructive: the scheduled task created during persistence is removed during the cleanup phase.

---

## How It Works

`exploit.ps1` runs on the Windows target host and walks through the following attack chain:

| Stage | Tactic | MITRE | What Happens |
|---|---|---|---|
| 1 | Discovery | T1069, T1087 | Enumerates local admin group and domain admin accounts via `net.exe` and `wmic` |
| 2 | Initial Access | T1218.005 | Invokes `mshta.exe` with an inline VBScript payload — Elastic Endpoint prevents execution and fires a built-in malicious behavior alert before `mshta.exe` can spawn a child process |
| 3 | Execution / Defense Evasion | T1059.001, T1027.010 | Executes an obfuscated PowerShell payload (char-casting, base64 encode/decode, string concatenation) to trigger the ML anomaly detection job |
| 4 | Persistence | T1053.005 | Creates a scheduled task via `schtasks.exe`; removed during cleanup |
| 5 | Credential Access | T1003 | Invokes `ntdsutil` with `create full` arguments — fails on a non-DC host but the process creation event triggers the detection rule |
| — | Cleanup | — | Deletes the scheduled task |

---

## Elastic Detection Rules

| Rule | Tactic | Link |
|---|---|---|
| Enumeration of Administrator Accounts | Discovery | [↗](https://elastic.github.io/detection-rules-explorer/rules/871ea072-1b71-4def-b016-6278b505138d) |
| Malicious Behavior Prevention Alert: Script Execution via Microsoft HTML Application | Initial Access | Elastic Endpoint built-in |
| Suspicious Powershell Script _(ML)_ | Execution / Defense Evasion | [↗](https://elastic.github.io/detection-rules-explorer/rules/1781d055-5c66-4adf-9d60-fc0fa58337b6) |
| Malicious Behavior Prevention Alert: Scheduled Task Creation by an Unusual Process | Persistence | Elastic Endpoint built-in |
| Potential Credential Access via Windows Utilities | Credential Access | [↗](https://elastic.github.io/detection-rules-explorer/rules/00140285-b827-4aee-aa09-8113f58a08f3) |

### Rule Details

#### Enumeration of Administrator Accounts
Fires when `net.exe` or `wmic.exe` queries admin or domain group membership from a non-SYSTEM account. Specifically matches args containing `group`/`localgroup`/`useraccount` combined with targets like `administrators`, `Domain Admins`, `Enterprise Admins`, or `Remote Desktop Users`.

#### Malicious Behavior Prevention Alert: Script Execution via Microsoft HTML Application
Elastic Endpoint built-in prevention rule. Fires when `mshta.exe` executes an inline VBScript or JScript payload. `mshta.exe` is a signed Windows binary used to execute HTML Application (HTA) files — attackers abuse it as a LOLBin to proxy code execution and bypass application allowlisting. Elastic Endpoint kills `mshta.exe` before it can spawn a child process, so the SIEM rule "Suspicious Microsoft HTML Application Child Process" (which requires a child process) does not fire; the Endpoint built-in fires instead.

#### Suspicious Powershell Script (ML)
ML rule backed by the `v3_windows_anomalous_script_ea` job. Ingests PowerShell Script Block Logging events (Event ID 4104) and scores script characteristics against a baseline — entropy, obfuscation patterns, base64 usage, character substitution. Fires when the anomaly score exceeds 50. **Requires the ML job to be running and a trained baseline in your environment** — may not fire on first run.

#### Malicious Behavior Prevention Alert: Scheduled Task Creation by an Unusual Process
Elastic Endpoint built-in malicious behavior rule. Fires when a process that does not normally create scheduled tasks (e.g., a PowerShell script) spawns `schtasks.exe` to register a new task. This is a prevention-class rule — Elastic Endpoint may kill the offending process.

#### Potential Credential Access via Windows Utilities
Fires on known credential-dumping tool invocations: `procdump -ma`, `rundll32 comsvcs MiniDump`, `ntdsutil cr*fu*`, `diskshadow /s`, and others. This demo uses `ntdsutil` with `create full` arguments, which will fail on a non-domain-controller host — but the process creation event fires the detection regardless.

---

## Prerequisites

**On the Windows target host:**
- Windows 10 1809+ or Windows 11
- PowerShell 5.0+
- Windows OpenSSH Server enabled (`Settings → System → Optional Features → OpenSSH Server`)
- Elastic Agent with Endpoint integration enrolled and running
- PowerShell Script Block Logging enabled (required for the ML rule)

**On your local machine (Mac/Linux):**
- SSH access to the Windows host with key configured in `scripts/.env`

---

## Setup

### 1. Configure `scripts/.env`

```sh
WINDOWS_TARGET_HOST=''
WINDOWS_TARGET_SSH_USER='bad_guy'
WINDOWS_TARGET_SSH_KEY=''
WINDOWS_TARGET_ROOTDIR='C:/Users/bad_guy/es-security-demo'
```

### 2. Generate an SSH key pair (local machine)

Run this on your Mac/Linux machine if you don't already have a key for this host:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/cgrfn-gcp-win_badguy -C "bad_guy@demo"
```

Set `WINDOWS_TARGET_SSH_KEY` in `scripts/.env` to the path of the **private** key.

### 3. Configure SSH access on the Windows host

Do these steps **locally on the Windows host** (PowerShell as Administrator).

**Install OpenSSH Server** (if not already installed):

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

**Create the `.ssh` directory and `authorized_keys` file** for the `bad_guy` user:

```powershell
New-Item -ItemType Directory -Force -Path "C:\Users\bad_guy\.ssh"
New-Item -ItemType File -Force -Path "C:\Users\bad_guy\.ssh\authorized_keys"
```

**Add your public key** — paste the contents of your local `~/.ssh/cgrfn-gcp-win_badguy.pub` into `authorized_keys`:

```powershell
Add-Content "C:\Users\bad_guy\.ssh\authorized_keys" "paste-your-public-key-here"
```

### 4. Test SSH access

From your local machine, verify the key works before deploying:

```sh
source scripts/.env && ssh -i "$WINDOWS_TARGET_SSH_KEY" "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST" "whoami"
```

Expected output: `bad_guy` (or the fully-qualified `hostname\bad_guy`). If the connection is refused or the key is rejected, recheck the `authorized_keys` file contents and permissions on the Windows host.

### 5. Deploy to the Windows host

```sh
sh scripts/demo_setup_windows.sh
```

### 6. Run the demo

```sh
sh scripts/demo_start_windows.sh
```

---

## Cleanup

The script removes the scheduled task automatically. If it fails mid-run, remove it manually:

```bash
source scripts/.env && ssh -i "$WINDOWS_TARGET_SSH_KEY" "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST" "schtasks /Delete /TN \"WindowsSystemHealthMonitor\" /F"
```
