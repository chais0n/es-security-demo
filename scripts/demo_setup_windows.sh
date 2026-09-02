#!/usr/bin/env bash

# ****************************************************
# *** MAKE VARIABLE CHANGES IN .env, NOT HERE ***
# ****************************************************
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

required_vars=(
  WINDOWS_TARGET_HOST
  WINDOWS_TARGET_ROOTDIR
  WINDOWS_TARGET_SSH_USER
  WINDOWS_TARGET_SSH_KEY
)

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

if ! ssh-add -l >/dev/null 2>&1; then
  eval "$(ssh-agent -s)" >/dev/null
fi
ssh-add "$WINDOWS_TARGET_SSH_KEY" >/dev/null 2>&1

/bin/echo -n "Checking if $WINDOWS_TARGET_HOST:$WINDOWS_TARGET_ROOTDIR exists..."
ssh -i "$WINDOWS_TARGET_SSH_KEY" "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST" \
  "powershell.exe -Command \"if (Test-Path '$WINDOWS_TARGET_ROOTDIR') { exit 17 }; New-Item -ItemType Directory -Force -Path '$WINDOWS_TARGET_ROOTDIR/scripts/windows' | Out-Null\""

exit_code=$?
if [ "$exit_code" -eq 17 ]; then
  printf '\033[1;31mYes - Refusing to copy\033[0m\n' >&2
  exit 1
elif [ "$exit_code" -ne 0 ]; then
  printf 'Remote prep failed (rc=%d) for %s:%s\n' "$exit_code" "$WINDOWS_TARGET_HOST" "$WINDOWS_TARGET_ROOTDIR" >&2
  exit 1
fi

printf '\033[1;32mNo\033[0m\n'
/bin/echo -n "Copying files to $WINDOWS_TARGET_HOST:$WINDOWS_TARGET_ROOTDIR..."

scp -i "$WINDOWS_TARGET_SSH_KEY" \
    "$SCRIPT_DIR/windows/config.ps1" \
    "$SCRIPT_DIR/windows/exploit.ps1" \
    "$SCRIPT_DIR/windows/ml_trigger.ps1" \
    "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST:$WINDOWS_TARGET_ROOTDIR/scripts/windows/"

if [ $? -ne 0 ]; then
  printf '\033[1;31mFailed\033[0m\n'
  exit 1
else
  printf '\033[1;32mDone\033[0m\n'
fi
