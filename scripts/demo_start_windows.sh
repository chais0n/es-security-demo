#!/usr/bin/env bash

# Load shared variables from .env
# This expects the .env file to be in the same directory as this script
# ****************************************************
# *** MAKE VARIABLE CHANGES IN .env, NOT HERE ***
# ****************************************************
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

# List of required variables
required_vars=(
  WINDOWS_TARGET_HOST
  WINDOWS_TARGET_ROOTDIR
  WINDOWS_TARGET_SSH_USER
  WINDOWS_TARGET_SSH_KEY
)

# Check each one
missing=()
for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    missing+=("$var")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Error: The following required variables are not set:" >&2
  for var in "${missing[@]}"; do
    echo "  - $var" >&2
  done
  exit 1
fi

# Ensure an SSH agent is running
if ! ssh-add -l >/dev/null 2>&1; then
  eval "$(ssh-agent -s)" >/dev/null
fi
# Load SSH key
ssh-add "$WINDOWS_TARGET_SSH_KEY" >/dev/null 2>&1

# SSH into the Windows host and run the exploit via PowerShell
# Windows OpenSSH must be enabled on the target (Settings → Apps → Optional Features → OpenSSH Server)
ssh "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST" \
  "powershell.exe -ExecutionPolicy Bypass -File \"$WINDOWS_TARGET_ROOTDIR/scripts/windows/exploit.ps1\""

ping "$WINDOWS_TARGET_HOST"

printf '\n'
printf '\033[1;33m══════════════════════════════════════════════\033[0m\n'
printf '\033[1;33m  CLEANUP REQUIRED ON THE WINDOWS HOST\033[0m\n'
printf '\033[1;33m══════════════════════════════════════════════\033[0m\n'
printf '\n'
printf 'If the script failed before its cleanup stage, the scheduled task\n'
printf 'may still be registered on %s.\n' "$WINDOWS_TARGET_HOST"
printf 'Remove it with:\n'
printf '\n'
printf '  \033[1;36mssh -i "%s" "%s@%s" "schtasks /Delete /TN \\"WindowsSystemHealthMonitor\\" /F"\033[0m\n' \
    "$WINDOWS_TARGET_SSH_KEY" "$WINDOWS_TARGET_SSH_USER" "$WINDOWS_TARGET_HOST"
printf '\n'
printf '\033[1;33m══════════════════════════════════════════════\033[0m\n'
printf '\n'
