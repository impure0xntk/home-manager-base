#!/usr/bin/env bash
# Fence command audit PreToolUse hook, shared by codex and jcode.
#
# The sandbox module (harness/sandbox) already declares the command deny list
# fence enforces at runtime: `git commit`, `git stash`, `rm`, `rmdir`,
# `nixos-rebuild switch`, the profile-switching `nix-env`, and so on. Those
# rules only bite once a command runs *inside* a fence session, so an agent
# driven by codex or jcode never meets them. This hook asks the same fence
# binary the same question at PreToolUse time and blocks the call when the
# answer is deny.
#
# Asking fence rather than re-listing the denies is the point: a rule added to
# a sandbox profile takes effect here without a second edit, so the runtime
# policy and the audit cannot drift apart.
#
# Fence matches a command rule as a literal prefix of the command it is
# handed, so the audit has to give fence the command the agent meant rather
# than the one the harness rewrote. Every launcher that may end up in front
# of it -- `rtk`, `rtk proxy`, `rtk err`, `rtk test`, `RTK_DISABLED=1`,
# `env VAR=...`, `command`, `exec` -- is peeled off after each command
# boundary first. Without that, `rtk git commit` reads as an allowed command
# named `rtk`, and the whole harness becomes a bypass of the deny list it
# exists to enforce.
#
# `sh -c` and `eval` stay ways around this, exactly as they are around fence's
# own runtime deny: seeing through them needs a shell parse, and fence does not
# do one either.
#
# Both agents speak the Claude hook dialect on stdin and stdout -- jcode
# through `jcode-pre-tool.sh`, which wraps this answer back into its exit-code
# form -- so one script serves both. Allow answers `{}`, deny answers with
# fence's own deny JSON, so the reason the agent sees is fence's.
#
# Fence failing is not this hook denying. An unreadable or invalid settings
# file would otherwise turn every shell call into a hard error, and a policy
# hook that stalls the task is worse than one that lets a single command
# through. Same fail-open contract as `redirect-read-grep.sh`.

set -uo pipefail

emit_deny() {
  jq -cn --arg reason "$1" '{
    decision: "block",
    reason: $reason,
    permissionDecision: "deny",
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
}

emit_pass() {
  printf '{}\n'
}

payload=$(cat)

# A payload this shell cannot parse is the agent's own serialisation failure to
# report, not a policy decision to invent a reason for.
jq -e . >/dev/null 2>&1 <<<"$payload" || {
  emit_pass
  exit 0
}

command=$(jq -r '((.tool_input // {}) | if type == "object" then . else {} end | .command // empty) | tostring' \
  <<<"$payload" 2>/dev/null) || command=""

# Only shell commands carry anything fence has an opinion about. A native read
# or a native edit is judged by retrieval-redirect, or by the sandbox's
# filesystem rules, never by the command deny list.
if [[ -z ${command//[[:space:]]/} ]]; then
  emit_pass
  exit 0
fi

# The named capture is the command boundary that has to survive the rewrite.
# Dropping it splices `cd /repo && git commit` into one token list that no
# longer starts with any verb fence recognises, which is how a chained commit
# would slip through. `&&` and `||` have to match as whole operators: a bare
# `&` alternative consumes the first character and leaves fence a boundary it
# never sees.
#
# One repetition per layer is not enough. `env` accepts a whole run of
# assignments, `command` and `exec` nest, and the harness stacks its own rtk
# layer on top, so the group repeats until none of it matches. A bare
# `VAR=value` prefix is peeled too: `RTK_DISABLED=1 git commit` is the documented
# way to skip the rewrite, and it is also the shortest way past a prefix match.
normalised=$(jq -rn --arg cmd "$command" '
  def launcher:
    "(?:env[ \\t]+(?:[A-Za-z_][A-Za-z0-9_]*=[^ \\t]*[ \\t]+)*)?"
    + "(?:[A-Za-z_][A-Za-z0-9_]*=[^ \\t]*[ \\t]+)?"
    + "(?:command[ \\t]+|exec[ \\t]+)?"
    + "(?:rtk[ \\t]+(?:proxy|err|test)[ \\t]+)?"
    + "(?:rtk[ \\t]+)?";
  $cmd
  | reduce range(0; 8) as $pass (.;
      gsub("(?<sep>^|&&|\\|\\||[\\n;&|])[ \\t]*" + launcher; .sep))
' 2>/dev/null) || normalised=$command

# A command that is nothing but an assignment normalises to empty, and empty
# would read as "no command at all" rather than as the command fence denied.
if [[ -z $normalised ]]; then
  normalised=$command
fi

# Fence reads its settings from the working directory the hook runs in, the
# same project-local `fence/fence.json` a session started there would use.
# One spawn per newline-separated line: fence matches a rule as a prefix of
# the whole command string and stops at the first newline, while bash runs
# every line, so a single call over a chain would decide on the first line and
# read "allow" while the commit on line two went straight through. Asking per
# line is what makes the audit and the shell agree on where a command starts.
ask_fence() {
  jq -cn --arg cmd "$1" --arg cwd "$PWD" '{
    session_id: "fence-audit",
    transcript_path: "",
    cwd: $cwd,
    hook_event_name: "PreToolUse",
    tool_name: "Bash",
    tool_input: {command: $cmd}
  }' | fence --claude-pre-tool-use 2>/dev/null
}

verdict=""
while IFS= read -r line; do
  [[ -n ${line//[[:space:]]/} ]] || continue
  verdict=$(ask_fence "$line") || verdict=""
  decision=$(printf '%s' "$verdict" |
    jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null) || decision=""
  case $decision in
    deny | block) break ;;
  esac
done <<<"$normalised"

case ${decision:-} in
  deny | block)
    reason=$(printf '%s' "$verdict" |
      jq -r '.hookSpecificOutput.permissionDecisionReason // .reason // empty' 2>/dev/null) || reason=""
    emit_deny "${reason:-blocked by the fence command policy}"
    ;;
  *)
    emit_pass
    ;;
esac

exit 0