#!/usr/bin/env bash

# ****************************************************
# *** MAKE VARIABLE CHANGES IN .env, NOT HERE ***
# ****************************************************
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../.env"

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

EXPLOIT_PS1="$WINDOWS_TARGET_ROOTDIR/attacks/windows/exploit.ps1"
ML_PS1="$WINDOWS_TARGET_ROOTDIR/attacks/windows/ml_trigger.ps1"

# Parse optional -s / --stage argument
STAGE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--stage)
            STAGE="$2"
            shift 2
            ;;
        *)
            printf 'Usage: %s [-s <stage>]\n' "$(basename "$0")" >&2
            printf '  -s, --stage  Run a single stage (1-8). Omit to run all stages.\n' >&2
            printf '  Stages: 1=Discovery  2=Initial Access  3=ML Anomaly  4=Persistence\n' >&2
            printf '          5=Cred Access (diskshadow)  6=Cred Access (kirbi)\n' >&2
            printf '          7=Cred Access (vaultcmd)  8=Collection  9=Cleanup\n' >&2
            exit 1
            ;;
    esac
done

# Run one stage via its own SSH connection.
# Each stage is isolated: if Elastic Endpoint kills that process (prevention),
# it cannot affect any other stage - the next SSH call starts a fresh process.
run_stage() {
    local stage_num="$1"
    local ps1="${2:-$EXPLOIT_PS1}"
    local args="${3:-}"
    ssh -i "$WINDOWS_TARGET_SSH_KEY" "$WINDOWS_TARGET_SSH_USER@$WINDOWS_TARGET_HOST" \
        "powershell.exe -ExecutionPolicy Bypass -File \"$ps1\" $args"
    local rc=$?
    if [ $rc -ne 0 ]; then
        printf '  \033[1;31m[PREVENTED - Elastic Endpoint killed the process (exit %d)]\033[0m\n' "$rc"
    fi
}

# Runs a single numbered stage, handling stage 3's special ML script invocation.
run_single_stage() {
    case "$1" in
        1) run_stage 1 "$EXPLOIT_PS1" "-Stage 1" ;;
        2) run_stage 2 "$EXPLOIT_PS1" "-Stage 2" ;;
        3)
            # Stage 3: ml_trigger.ps1 runs as its own isolated process.
            # exploit.ps1 must NOT contain any obfuscated code - Script Block Logging
            # logs the entire file on load, and Elastic would kill the process before
            # any stage runs, blocking all other stages as collateral damage.
            printf '\n'
            printf '\033[0;36m--- [3/8] Execution - Obfuscated payload for ML anomaly detection (T1059.001, T1027.010) ---\033[0m\n'
            printf '  Executing obfuscated script (ml_trigger.ps1)...'
            run_stage 3 "$ML_PS1" ""
            ;;
        4) run_stage 4 "$EXPLOIT_PS1" "-Stage 4" ;;
        5) run_stage 5 "$EXPLOIT_PS1" "-Stage 5" ;;
        6) run_stage 6 "$EXPLOIT_PS1" "-Stage 6" ;;
        7) run_stage 7 "$EXPLOIT_PS1" "-Stage 7" ;;
        8) run_stage 8 "$EXPLOIT_PS1" "-Stage 8" ;;
        9) run_stage 9 "$EXPLOIT_PS1" "-Stage 9" ;;
        *)
            printf 'Error: invalid stage "%s". Must be 1-9.\n' "$1" >&2
            exit 1
            ;;
    esac
}

if [ "$STAGE" -ne 0 ]; then
    run_single_stage "$STAGE"
else
    run_single_stage 1
    run_single_stage 2
    run_single_stage 3
    run_single_stage 4
    run_single_stage 5
    run_single_stage 6
    run_single_stage 7
    run_single_stage 8
    run_single_stage 9

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
fi
