#!/usr/bin/env bash

set -euo pipefail

input="$(cat)"

prompt="$(
  jq -r '.prompt // empty' <<<"$input"
)"

if [[ -z "$prompt" ]]; then
  printf '%s\n' "$input"
  exit 0
fi

# A missing or failing `trans` is not an error: the prompt is passed through
# untranslated, which is what the empty check below already does for a tool
# that answers with nothing. Without the `|| true` the missing-command status
# trips `set -e` first and the hook exits without echoing the input at all,
# which drops the user's prompt instead of degrading.
translated="$(
  printf '%s' "$prompt" |
    trans -b :en 2>/dev/null || true
)"

if [[ -z "$translated" ]]; then
  printf '%s\n' "$input"
  exit 0
fi

jq \
  --arg prompt "$translated" \
  '.prompt = $prompt' \
  <<<"$input"