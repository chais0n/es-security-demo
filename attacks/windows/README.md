# Windows Attack Simulation

A multi-stage Windows attack simulation that triggers Elastic Security detection rules across five MITRE ATT&CK tactics. Non-destructive: the scheduled task created during persistence is removed during the cleanup phase.

---

## How It Works

`exploit.ps1` runs on the Windows target host and walks through the following attack chain:

| Stage | Tactic | MITRE | Detection Rule | What Happens |
|---|---|---|---|---|
| 1 | Discovery | T1069, T1087 | [Enumeration of Administrator Accounts](https://elastic.github.io/detection-rules-explorer/rules/871ea072-1b71-4def-b016-6278b505138d) | Enumerates local admin group and domain admin accounts via `net.exe` and `wmic` |
| 2 | Defense Evasion | T1218.010 | Malicious Behavior Prevention Alert: Regsvr32 Scriptlet Execution _(Endpoint built-in)_ | Loads a COM scriptlet (`.sct`) via `regsvr32.exe /s /n /u /i: scrobj.dll` (Squiblydoo) — Elastic Endpoint intercepts scriptlet execution and fires a built-in prevention alert before `scrobj.dll` can run |
| 3 | Execution / Defense Evasion | T1059.001, T1027.010 | [Suspicious Powershell Script _(ML)_](https://elastic.github.io/detection-rules-explorer/rules/1781d055-5c66-4adf-9d60-fc0fa58337b6) | Executes an obfuscated PowerShell payload (char-casting, base64 encode/decode, string concatenation) to trigger the ML anomaly detection job |
| 4 | Persistence | T1053.005 | Malicious Behavior Prevention Alert: Suspicious Scheduled Task Creation _(Endpoint built-in)_ | Creates a scheduled task via `schtasks.exe`; removed during cleanup |
| 5 | Credential Access | T1003.003 | Malicious Behavior Prevention Alert: Credential Access via Known Utilities _(Endpoint built-in)_ | Invokes `diskshadow /s` to simulate VSS shadow copy access to NTDS.dit — Elastic Endpoint prevents execution and fires a built-in prevention alert |
| 6 | Credential Access | T1558 | [Kirbi File Creation](https://elastic.github.io/detection-rules-explorer/rules/b8f8da2d-a9dc-48c0-90e4-955c0aa1259a) | Creates a `.kirbi` Kerberos ticket dump file in the user temp directory — the file extension alone triggers the detection rule regardless of content |
| 7 | Credential Access | T1555.004 | Malicious Behavior Prevention Alert: Suspicious Vault Files Access via RPC _(Endpoint built-in)_ | Invokes `vaultcmd /listcreds` to enumerate Windows Credential Manager — Elastic Endpoint intercepts the RPC call and fires a prevention alert before any credentials are read |
| 8 | Collection | T1074.001, T1560.001 | File Staged in Root Folder of Recycle Bin _(building block)_ + PowerShell Script with Archive Compression Capabilities _(building block)_ → Multiple Alerts Involving a User _(correlated)_ | Compresses staged data files with `Compress-Archive` and copies the archive to `C:\$RECYCLE.BIN\` — both signals are building block alerts that combine with earlier demo alerts to trigger the correlation rule |
| — | Cleanup | — | — | Deletes the scheduled task and removes staged files |

---

## Detection Rule Details

#### Enumeration of Administrator Accounts
Fires when `net.exe` or `wmic.exe` queries admin or domain group membership from a non-SYSTEM account. Specifically matches args containing `group`/`localgroup`/`useraccount` combined with targets like `administrators`, `Domain Admins`, `Enterprise Admins`, or `Remote Desktop Users`.

#### Malicious Behavior Prevention Alert: Regsvr32 Scriptlet Execution
Elastic Endpoint built-in prevention rule. Fires when `regsvr32.exe` loads a COM scriptlet (`.sct` file) via `scrobj.dll` — the classic "Squiblydoo" AppLocker bypass. `regsvr32.exe` is a signed Microsoft binary; the `/s /n /u /i:<file>` flags direct it to invoke the scriptlet's install entrypoint via `scrobj.dll`, bypassing application allowlisting entirely. Elastic Endpoint intercepts the scriptlet execution at the kernel level and kills the process before `scrobj.dll` can run. Works headlessly in non-interactive SSH sessions — no Windows desktop required.

#### Suspicious Powershell Script (ML)
ML rule backed by the `v3_windows_anomalous_script_ea` job. Ingests PowerShell Script Block Logging events (Event ID 4104) and scores script characteristics against a baseline — entropy, obfuscation patterns, base64 usage, character substitution. Fires when the anomaly score exceeds 50. **Requires the ML job to be running and a trained baseline in your environment** — may not fire on first run.

#### Malicious Behavior Prevention Alert: Suspicious Scheduled Task Creation
Elastic Endpoint built-in malicious behavior rule. Fires when a process that does not normally create scheduled tasks (e.g., a PowerShell script) spawns `schtasks.exe` to register a new task. This is a prevention-class rule — Elastic Endpoint may kill the offending process.

#### Malicious Behavior Prevention Alert: Credential Access via Known Utilities
Elastic Endpoint built-in prevention rule. Fires when known credential-access utilities (`diskshadow.exe`, `ntdsutil.exe`, `procdump.exe`, etc.) are invoked with suspicious arguments. This demo uses `diskshadow /s` — a signed Windows binary that can create VSS shadow copies to access `NTDS.dit`. Elastic Endpoint kills `diskshadow.exe` before it executes. `ntdsutil.exe` is not available on non-DC hosts; `diskshadow.exe` ships with Windows 10/11 and triggers the same Endpoint built-in.

#### Malicious Behavior Prevention Alert: Suspicious Vault Files Access via RPC
Elastic Endpoint built-in prevention rule. Fires when `vaultcmd.exe` makes an RPC call to enumerate the Windows Credential Manager vault. Elastic Endpoint intercepts the RPC at the kernel level and kills the process before it can read any credentials — the "Access is denied" error the tool returns is a result of Endpoint's intervention, not a Windows ACL check.

#### File Staged in Root Folder of Recycle Bin + Multiple Alerts from Different Modules by User
[File Staged in Root Folder of Recycle Bin](https://elastic.github.io/detection-rules-explorer/rules/57bccf1d-daf5-4e1a-9049-ff79b5254704) is a building block rule that fires when any file is written to the root of `C:\$RECYCLE.BIN\`. [PowerShell Script with Archive Compression Capabilities](https://elastic.github.io/detection-rules-explorer/rules/27071ea3-e806-4697-8abc-e22c92aa4293) is a building block rule that fires via Script Block Logging (Event 4104) when PowerShell loads a script containing `Compress-Archive` or .NET compression classes. Neither rule generates a standalone alert on its own. However, combined with the detection signals from other demo stages, they push the user's alert count high enough to trigger [Multiple Alerts Involving a User](https://elastic.github.io/detection-rules-explorer/rules/0d160033-fab7-4e72-85a3-3a9d80c8bff7) — a correlation rule that fires a full alert when a user accumulates alerts from multiple distinct detection modules in a short window. **Requires the "Multiple Alerts from Different Modules by User" rule to be enabled in Kibana.**

#### Kirbi File Creation
Fires when any process creates a file with a `.kirbi` extension. `.kirbi` is the format used by Mimikatz and Rubeus to export Kerberos tickets from memory — the presence of the file on disk is a strong indicator of pass-the-ticket activity. The rule triggers on the file creation event alone; the file content is irrelevant. No elevated privileges required.

---

## Prerequisites

**On the Windows target host:**
- Windows 10 1809+ or Windows 11
- PowerShell 5.0+
- Windows OpenSSH Server enabled (`Settings → System → Optional Features → OpenSSH Server`)
- Elastic Agent with Endpoint integration enrolled and running
- PowerShell Script Block Logging enabled (required for the ML rule)

**On your local machine (Mac/Linux):**
- SSH access to the Windows host with key configured in `attacks/.env`

**Elastic detection rules that must be enabled (Kibana → Security → Rules):**
- Endpoint Security (Elastic Defend) — Stages 2, 4, 5, and 7 (Endpoint built-in prevention alerts)
- [Enumeration of Administrator Accounts](https://elastic.github.io/detection-rules-explorer/rules/871ea072-1b71-4def-b016-6278b505138d) — Stage 1
- [Suspicious Powershell Script (ML)](https://elastic.github.io/detection-rules-explorer/rules/1781d055-5c66-4adf-9d60-fc0fa58337b6) — Stage 3 (requires ML job `v3_windows_anomalous_script_ea` running with a trained baseline)
- [Potential Credential Access via Windows Utilities](https://elastic.github.io/detection-rules-explorer/rules/00140285-b827-4aee-aa09-8113f58a08f3) — Stage 5
- [Kirbi File Creation](https://elastic.github.io/detection-rules-explorer/rules/b8f8da2d-a9dc-48c0-90e4-955c0aa1259a) — Stage 6
- [Multiple Alerts Involving a User](https://elastic.github.io/detection-rules-explorer/rules/0d160033-fab7-4e72-85a3-3a9d80c8bff7) — Stage 8 (correlated; must be enabled)

---

## Setup

### 1. Configure `attacks/.env`

```sh
WINDOWS_TARGET_HOST=''
WINDOWS_TARGET_SSH_USER='bad_guy'
WINDOWS_TARGET_SSH_KEY=''
WINDOWS_TARGET_ROOTDIR='C:/Users/bad_guy/es-security-demo'
```

### 2. Configure SSH on the Windows host

#### 2a. Generate an SSH key pair (local machine)

Run this on your Mac/Linux machine if you don't already have a key for this host:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/cgrfn-gcp-win_badguy -C "bad_guy@demo"
```

Set `WINDOWS_TARGET_SSH_KEY` in `attacks/.env` to the path of the **private** key.

#### 2b. Set up OpenSSH on the Windows host

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

#### 2c. Test SSH access

From your local machine, verify the key works before continuing:

```sh
source attacks/.env && ssh -i "$WINDOWS_TARGET_SSH_KEY" "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST" "whoami"
```

Expected output: `bad_guy` (or the fully-qualified `hostname\bad_guy`). If the connection is refused or the key is rejected, recheck the `authorized_keys` file contents and permissions on the Windows host.

### 3. Enable PowerShell Script Block Logging

Script Block Logging is required for the ML anomaly detection rule (Stage 3). It enables Windows to write PowerShell script content to Event ID 4104, which Elastic ingests and scores.

Run this **locally on the Windows host** (PowerShell as Administrator):

```powershell
$path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
New-Item -Path $path -Force | Out-Null
Set-ItemProperty -Path $path -Name EnableScriptBlockLogging -Value 1
```

Verify it is active:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
```

`EnableScriptBlockLogging` should be `1`. Elastic Agent typically enables this automatically on enrolled hosts — check before configuring manually.

### 4. Deploy to the Windows host

```sh
sh attacks/windows/demo_setup_windows.sh
```

### 5. Run the demo

Run all stages sequentially:

```sh
sh attacks/windows/demo_start_windows.sh
```

Run a single stage for testing:

```sh
sh attacks/windows/demo_start_windows.sh -s &lt;stage&gt;
```

| Flag | Stage |
|---|---|
| `-s 1` | Discovery |
| `-s 2` | Initial Access |
| `-s 3` | Execution / ML Anomaly |
| `-s 4` | Persistence |
| `-s 5` | Credential Access (diskshadow) |
| `-s 6` | Credential Access (kirbi) |
| `-s 7` | Credential Access (vaultcmd) |
| `-s 8` | Collection (Recycle Bin staging) |
| `-s 9` | Cleanup |

---

## Cleanup

The script removes the scheduled task automatically. If it fails mid-run, remove it manually:

```bash
source attacks/.env && ssh -i "$WINDOWS_TARGET_SSH_KEY" "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST" "schtasks /Delete /TN \"WindowsSystemHealthMonitor\" /F"
```
