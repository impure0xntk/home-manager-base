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
# usage: jcode-pre-tool-transform.sh <rtk>

set -uo pipefail

rtk=$1

input=$(cat)

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

printf '%s' "$input" | jq -c --arg cmd "$replacement" '.command = $cmd' 2>/dev/null || exit 0
