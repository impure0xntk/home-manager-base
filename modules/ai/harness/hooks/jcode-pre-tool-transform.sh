#!/usr/bin/env bash

# jcode `pre_tool_transform` adapter that rewrites the shell command through rtk.
#
# jcode transformers get the raw tool input on stdin and may print a
# replacement object on stdout, where the Claude dialect rtk speaks wraps the
# same command in {tool_name, tool_input} and answers with
# hookSpecificOutput.updatedInput. This unwraps, calls rtk, and rewraps.
#
# Printing nothing is jcode's "leave the input unchanged", which is also what an
# unrecognised tool or an rtk with no substitution must produce -- same
# fail-open contract as the gate adapter.
#
# jcode runs transformers *before* the pre_tool gate, so a rewrite landing on a
# command the gate denies would be judged by the gate in its rewritten form and
# pass, leaving the gate as dead code for exactly the shapes rtk rewrites. The
# replacement is therefore put to the same gate here, and a rewrite the gate
# denies is dropped: the original command reaches the gate untouched, so the
# model gets the gate's message naming the index tools.
#
# jcode's `command` field is not unique to the shell: `mcp`'s `connect` action
# takes a `command` that spawns the server, and `compile_remote` takes one that
# builds it. Rewriting those would replace a real server spawn with `rtk npx ...`
# and break every MCP server on the machine, so the tool name is what decides,
# not the presence of the field. jcode spells the shell `bash`; the rest of the
# harness (`redirect-read-grep.sh`) names the Claude shape, so both spellings are
# accepted here and the tool name is compared case-insensitively.
#
# usage: jcode-pre-tool-transform.sh <rtk> [retrieval-redirect]

set -uo pipefail

rtk=$1
redirect=${2:-}

input=$(cat)

# Only the shell carries a command worth rewriting. An unset name is treated as
# "not the shell" rather than assumed to be: the gate adapter fails open on the
# same unknown, and a transformer must never be the one that guesses.
tool=${JCODE_HOOK_TOOL_NAME:-}
tool=${tool,,}
case $tool in
bash | shell) ;;
*) exit 0 ;;
esac

command=$(printf '%s' "$input" | jq -r '.command // empty' 2>/dev/null) || exit 0
[[ -n $command ]] || exit 0

rewrite=$(
  printf '%s' "$input" |
    jq -cn --arg cmd "$command" '{tool_name: "Bash", tool_input: {command: $cmd}}' |
    "$rtk" hook claude
) || exit 0

replacement=$(printf '%s' "$rewrite" |
  jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null) || exit 0

# rtk echoes the input back unchanged when it has no substitution for it, and
# rewriting a command to itself would still invalidate jcode's tool cache.
[[ -n $replacement && $replacement != "$command" ]] || exit 0

# No gate to consult means this transformer cannot know, so it rewrites: the
# fail-open direction is the one that keeps the token saving.
if [[ -n $redirect ]]; then
  # `--arg` and `.` read different streams: `.` is the jq *input*, which is the
  # replacement string, while the Claude envelope is built from scratch. Passing
  # the string down stdin and reading `.` inside a filter that also declares
  # `--arg` leaves `tool_input.command` null, so every gate answer reads as
  # "allow" and the rewrite the gate would deny always survives.
  verdict=$(
    jq -cn --arg name "${JCODE_HOOK_TOOL_NAME:-}" --arg cmd "$replacement" \
      '{tool_name: $name, tool_input: {command: $cmd}}' |
      "$redirect" 2>/dev/null
  ) || verdict=""
  decision=$(printf '%s' "$verdict" |
    jq -r '.hookSpecificOutput.permissionDecision // .permissionDecision // .decision // empty' \
      2>/dev/null) || decision=""
  case $decision in
    deny | block) exit 0 ;;
  esac
fi

printf '%s' "$input" | jq -c --arg cmd "$replacement" '.command = $cmd' 2>/dev/null || exit 0
