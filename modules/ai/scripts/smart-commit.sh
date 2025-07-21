#!/usr/bin/env bash

set -euo pipefail

# Default values
DRY_RUN=false
AUTO_COMMIT=false
CONFIRM='n'
MODELS=""

print_help() {
  cat >&2 <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -n, --dry-run     Show the generated commit message without committing
  -y, --yes         Auto-confirm commit without prompt
  -m, --model       Specify one or more models (comma-separated) to use for commit message generation (e.g. -m model1,model2)
  -h, --help        Show this help message and exit
EOF
}

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run | -n)
      DRY_RUN=true
      shift
      ;;
    -y | --yes)
      AUTO_COMMIT=true
      shift
      ;;
    -m | --model)
      MODELS="$2"
      shift 2
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      print_help
      exit 1
      ;;
  esac
done

# Get staged diff
DIFF=$(git diff --staged)
if [[ -z "$DIFF" ]]; then
  echo "[INFO] No staged changes found." >&2
  exit 1
fi

# Split models by comma
IFS=',' read -ra MODELS_ARR <<<"$MODELS"
# If no model is specified, use default (empty string)
if [[ -z "$MODELS" ]]; then
  MODELS_ARR=("")
fi

# Generate commit messages with each model in parallel
COMMIT_MESSAGES=()
TMPFILES=()
PIDS=()
for idx in "${!MODELS_ARR[@]}"; do
  m="${MODELS_ARR[$idx]}"
  tmpfile=$(mktemp)
  TMPFILES+=("$tmpfile")
  sgpt_args=("--no-interaction" "--no-md" "--no-cache" "--role" "Commit Message Generator")
  # If model is specified, add model argument
  if [[ -n "$m" ]]; then
    sgpt_args+=("--model" "$m")
  fi
  # Run sgpt in background and write output to tmpfile
  (echo "$DIFF" | sgpt "${sgpt_args[@]}" >"$tmpfile" 2>"$tmpfile.err") &
  PIDS+=("$!")
done

# Wait for all sgpt processes to finish
for pid in "${PIDS[@]}"; do
  wait "$pid"
done

# Collect results and handle errors
for idx in "${!TMPFILES[@]}"; do
  m="${MODELS_ARR[$idx]}"
  tmpfile="${TMPFILES[$idx]}"
  if [[ -s "$tmpfile.err" ]]; then
    echo "[ERROR] Failed to generate commit message for model: $m" >&2
    cat "$tmpfile.err" >&2
    exit 1
  fi
  # Remove unnecessary lines
  msg=$(cat "$tmpfile" | sed -E '/^<think>$/d; /^<\/think>$/d; /^[[:space:]]*$/d')
  COMMIT_MESSAGES+=("$msg")
  echo -e "\n[$m] commit message generated"
  rm -f "$tmpfile" "$tmpfile.err"
done

# Select commit message from multiple models
if ((${#COMMIT_MESSAGES[@]} > 1)); then
  echo -e "\nGenerated commit messages:" # Show all generated messages
  for i in "${!COMMIT_MESSAGES[@]}"; do
    printf "\n[%d] Model: %s\n\033[35m%s\033[m\n" $((i + 1)) "${MODELS_ARR[i]}" "${COMMIT_MESSAGES[i]}"
  done
  if [[ $AUTO_COMMIT == true ]]; then
    SELECTED=1 # Auto-select first message if auto-commit
  else
    read -rp "Select the message number to use [1-${#COMMIT_MESSAGES[@]}]: " SELECTED
  fi
  SELECTED=$((SELECTED - 1))
  COMMIT_MESSAGE="${COMMIT_MESSAGES[$SELECTED]}"
else
  COMMIT_MESSAGE="${COMMIT_MESSAGES[0]}"
fi

# Display selected commit message in magenta
printf "\nSelected commit message:\n\033[35m%s\033[m\n" "$COMMIT_MESSAGE"

if $DRY_RUN; then
  echo -e "\n[INFO] --dry-run enabled: No commit will be made."
  exit 0
fi

# Confirmation before commit
if [[ $AUTO_COMMIT == true ]]; then
  CONFIRM='y' # Auto-confirm if auto-commit
else
  read -rp "Proceed with commit? [y/N]: " CONFIRM
fi

# Commit if confirmed
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  # Remove ANSI escape codes from message
  CLEAN_MESSAGE=$(echo "$COMMIT_MESSAGE" | sed 's/\x1b\[[0-9;]*m//g')
  git commit -m "$CLEAN_MESSAGE"
  echo "[INFO] Committed successfully."
else
  echo "[INFO] Commit cancelled."
fi
