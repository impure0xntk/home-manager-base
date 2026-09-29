#!/usr/bin/env bash

# jcode `pre_tool` gate adapter around the shared retrieval-redirect script.
#
# The two hook dialects disagree on both ends of the wire:
#   - jcode puts the *raw* tool input on stdin and the tool name in
#     $JCODE_HOOK_TOOL_NAME, while the Claude dialect wraps both into one
#     {tool_name, tool_input} object on stdin.
#   - jcode reports a decision as an exit code (2 blocks, stderr becomes the
#     error the model sees), while the Claude dialect answers with JSON on
#     stdout and has no exit code at all.
#
# So this wrapper builds the payload the shared script already speaks, then
# turns its verdict back into an exit code. `set -e` is deliberately absent and
# every uncertain step exits 0: jcode fails open on anything that is not 0 or 2,
# and a policy script must never be the reason a task stalls.
#
# usage: jcode-pre-tool.sh <retrieval-redirect>

set -uo pipefail

redirect=$1

input=$(cat)

# jcode always writes JSON here, but a tool that fails to serialise would
# otherwise leave a parse error on the stderr that jcode reports as the reason.
payload=$(jq -cn \
  --arg name "${JCODE_HOOK_TOOL_NAME:-}" \
  --argjson input "${input:-null}" \
  '{tool_name: $name, tool_input: (if $input == null then {} else $input end)}' 2>/dev/null) || exit 0

verdict=$(printf '%s' "$payload" | "$redirect") || exit 0

# `emit_pass` answers `{}`, which reads as no decision at all: allow.
decision=$(printf '%s' "$verdict" |
  jq -r '.hookSpecificOutput.permissionDecision // .permissionDecision // .decision // empty' \
    2>/dev/null) || exit 0

case $decision in
deny | block)
  reason=$(printf '%s' "$verdict" |
    jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // empty' 2>/dev/null)
  printf '%s\n' "${reason:-blocked by pre_tool hook}" >&2
  exit 2
  ;;
*)
  exit 0
  ;;
esac
