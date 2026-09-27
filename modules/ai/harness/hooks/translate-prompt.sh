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

translated="$(
  printf '%s' "$prompt" |
    trans -b :en 2>/dev/null
)"

if [[ -z "$translated" ]]; then
  printf '%s\n' "$input"
  exit 0
fi

jq \
  --arg prompt "$translated" \
  '.prompt = $prompt' \
  <<<"$input"