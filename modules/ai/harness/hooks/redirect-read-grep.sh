# PreToolUse hook shared by codex and goose.
#
# codegraph and zvec-grep are already registered with both agents as MCP
# servers, so a raw cat/rg spends context on a weaker answer than the index
# gives back. This hook inspects the leading fragment of a shell command,
# denies the recognised read/search shapes with the MCP tool names to call
# instead, and passes everything else through as `{}` so the hook never
# becomes the reason a task stalls.
#
# Both agents speak the Claude hook dialect, so one script serves both; the
# tool names differ but are never inspected for shell calls, only the payload.
#
# Every tool name printed below has to be a real backend tool, or the deny
# points at a name the agent cannot call and the only remaining move is a raw
# grep, which this script also denies. Messages name backend tools only: the
# transport that carries them (the multiplexing in `harness/mcp.nix`) is not
# the agent's business, and naming it would break these messages the day the
# transport changes.
# The zvec-grep daemon runs its `agent` toolset, which registers
# `zvec_grep_search` alone -- the managed-rg surface (`zvec_grep_rg`) is not
# available, because exposing it means switching the shared daemon to the
# `full` toolset, which every client of that daemon inherits.
# Re-check against `zg server --stdio` tools/list before naming a tool below.

set -euo pipefail

readonly READ_MESSAGE='Blocked: reading a source file directly is not the retrieval path on this machine.

The codegraph MCP server registers exactly one tool, codegraph_explore(query, maxFiles, projectPath), and it replaces Read plus Grep in one call: verbatim source with line numbers plus the call path.

Fall back to a raw read only when the index has no coverage for the file, and say why in the response.'

readonly SEARCH_MESSAGE='Blocked: a workspace-wide rg/grep is not the retrieval path on this machine. Route it by what the answer is, not by habit:

- sweep, you want the matching lines themselves -> zvec_grep_search with fts, bounded by globs / fileTypes. fts is the lexical route over the same index, so one call answers an exact literal, filename, config key, error string or regex. There is no separate rg tool registered here: the managed-rg surface is not part of the installed toolset, so naming it only wastes a round trip.
- sweep, you want concepts, symbols, how-does-X-work -> zvec_grep_search with query / queries / vector.
- small scoped lookup: one symbol, one module, one file you are about to edit -> codegraph_explore with an explicit maxFiles. Verbatim source with line numbers plus the call path, and cheaper than Read plus Grep.

Never codegraph query for a sweep. It expands the bindings around every node, so 79 real hits come back as 147 nodes and 25200 bytes against the lexical route 10686 (2.4x), 40 hits cost 20512 against 3660 (5.6x), and it saturates near 20-25K bytes whatever the hit count is. Counting or listing hits is the one shape it fits, and only as codegraph query -l <n>.

The snippets a search returns are already-read evidence. Fall back to a raw grep only when the index comes back empty for a question it should cover, and say why in the response.'

readonly ENUM_MESSAGE='Blocked: this search only counts hits or lists hit paths, so a workspace-wide rg/grep is the wrong tool.

- codegraph query -l <n> answers it. The -l <n> cap is the only form of codegraph query that stays inside the byte budget: a bare query returns the surrounding bindings with every node and saturates near 20-25K bytes whatever the hit count, which is 2.4-5.6x the lexical route on the same query.
- zvec_grep_search with fts answers it when what you want is the hit paths and the matching lines rather than a count.

Say which of the two you are after, then call that one.'

readonly STRUCTURE_MESSAGE='Blocked: walking the tree with find/ls is not the retrieval path on this machine.

The codegraph and zvec-grep MCP servers are registered, so name the area instead of searching for it:
- codegraph_explore takes the module, package, or symbol and returns its files with the symbols and call paths in them
- zvec_grep_search takes globs and fileTypes to match paths inside the index

Fall back to a raw find only for a path the index does not cover, and say why in the response.'

# Structure discovery, including the native tool names some agents expose.
readonly STRUCTURE_VERBS=(
  ls
  find
  fd
  tree
  glob
  list_dir
  # qwen-code spells directory listing this way.
  list_directory
)

# Read/search tools some agents expose natively instead of going through a
# shell. The matcher in each plugin already narrows this down; matching here
# only keeps the decision identical when the name differs.
readonly NATIVE_READ_TOOLS=(
  read
  read_file
  readfile
  view_file
  grep
  search
  search_files
  codebase_search
  # qwen-code spells content search this way.
  grep_search
)

# Options whose whole job is counting hits or listing hit paths. A workspace-wide
# search in this shape is a `codegraph query -l <n>` candidate rather than a
# sweep; a scoped one is already cheap enough to leave to rtk.
readonly ENUM_ONLY_OPTIONS=(
  -l
  -c
  --count
  --count-matches
  --files
  --files-with-matches
  --files-without-match
  --stats
)

readonly SEARCH_VERBS=(
  rg
  ripgrep
  grep
  egrep
  fgrep
  ugrep
  ag
  ack
)

# Search options that swallow the token after them. Without this the pattern is
# misread as a path and the call looks file-scoped when it is not.
readonly VALUE_OPTIONS=(
  -e -f -m -A -B -C -g -t -T
  --regexp --file --max-count --maxdepth --context --after-context
  --before-context --max-filesize --sort --type --type-not --type-add
  --glob --iglob
)

# The value of these options is the pattern itself, so consuming it must still
# count as "a pattern was seen" or the following path looks like the pattern.
readonly PATTERN_VALUE_OPTIONS=(
  -e -f --regexp --file
)

readonly READ_VERBS=(
  cat
  head
  tail
  bat
  less
  more
  sed
  awk
)

# Languages codegraph and zvec-grep actually index. Extensions outside this list
# (lock files, logs, plain docs) stay readable, because pointing the agent at an
# index that never ingested the file is worse than the raw read.
readonly CODE_EXTENSIONS=(
  c cc cpp cxx h hpp cs go java kt kts scala rs rb php py ts tsx js jsx mjs cjs
  vue svelte dart lua swift m mm ex exs erl hs clj nix sh bash zsh fish sql
  proto graphql
)

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

in_list() {
  local needle=$1
  shift
  local item
  for item in "$@"; do
    if [[ $item == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

has_code_operand() {
  local token base extension
  for token in "$@"; do
    # Options and option values are never paths, and `-e '-foo'` style operands
    # would otherwise look like files.
    if [[ $token == -* || $token == *=* ]]; then
      continue
    fi
    base=${token##*/}
    if [[ $base != *.* ]]; then
      continue
    fi
    extension=${base##*.}
    extension=${extension,,}
    if in_list "$extension" "${CODE_EXTENSIONS[@]}"; then
      return 0
    fi
  done
  return 1
}

in_workspace() {
  local target=$1
  local relative
  # A tool argument is not shell-expanded, so a leading `~` is a literal here
  # and has to be turned into an absolute path before the workspace test.
  if [[ ${target:0:1} == '~' ]]; then
    target=$HOME${target:1}
  fi
  if [[ $target != /* ]]; then
    # A relative path names something inside the tree the agent is standing in.
    return 0
  fi
  relative=$(realpath -m --relative-to="$PWD" -- "$target" 2>/dev/null) || return 1
  case $relative in
    .. | ../*) return 1 ;;
  esac
  return 0
}

# Only the first non-option operand of a structure command is its search root;
# later ones are predicates and their values (`-name foo`) are not paths. No
# operand at all means the current directory, which is the workspace.
structure_root_is_workspace() {
  local token
  for token in "$@"; do
    if [[ $token == -* ]]; then
      continue
    fi
    if in_workspace "$token"; then
      return 0
    fi
    return 1
  done
  return 0
}

# A search is workspace-wide when it recurses, when it names no path after
# the pattern, or when the path it names is a directory or an indexed source
# file. A search over one named log or lock file is left to rtk.
#
# The full argument vector is passed and the verb is skipped, because deciding
# "pattern versus path" requires knowing which flags consumed a value.
is_workspace_wide_search() {
  local -a args=("$@")
  local i=1
  local token
  local recursive=0 pattern_seen=0 path_seen=0 skip_value=0 pattern_value=0

  while ((i < ${#args[@]})); do
    token=${args[i]}
    if ((skip_value)); then
      skip_value=0
      if ((pattern_value)); then
        pattern_value=0
        pattern_seen=1
      fi
      i=$((i + 1))
      continue
    fi
    if [[ $token == --*=* ]]; then
      if in_list "${token%%=*}" "${PATTERN_VALUE_OPTIONS[@]}"; then
        pattern_seen=1
      fi
      i=$((i + 1))
      continue
    fi
    if [[ $token == --* ]]; then
      if in_list "$token" "${VALUE_OPTIONS[@]}"; then
        skip_value=1
      fi
      if in_list "$token" "${PATTERN_VALUE_OPTIONS[@]}"; then
        pattern_value=1
      fi
      i=$((i + 1))
      continue
    fi
    if [[ $token == -?* ]]; then
      # `-rn` is `-r -n`, so inspect the letters rather than the whole token.
      if [[ ${token:1} == *r* || ${token:1} == *R* || ${token:1} == *l* ]]; then
        recursive=1
      fi
      if in_list "$token" "${VALUE_OPTIONS[@]}"; then
        skip_value=1
      fi
      if in_list "$token" "${PATTERN_VALUE_OPTIONS[@]}"; then
        pattern_value=1
      fi
      i=$((i + 1))
      continue
    fi
    if ((pattern_seen)); then
      path_seen=1
      if [[ $token != *\** && -d $token ]]; then
        return 0
      fi
      if has_code_operand "$token"; then
        return 0
      fi
    else
      pattern_seen=1
    fi
    i=$((i + 1))
  done

  if ((recursive)) || ((path_seen == 0)); then
    return 0
  fi
  return 1
}

payload=$(cat)
if ! jq -e . >/dev/null 2>&1 <<<"$payload"; then
  emit_pass
  exit 0
fi

tool=$(jq -r '(.tool_name // "") | tostring | ascii_downcase' <<<"$payload" 2>/dev/null || true)
if in_list "$tool" "${NATIVE_READ_TOOLS[@]}"; then
  emit_deny "$READ_MESSAGE"
  exit 0
fi

if in_list "$tool" "${STRUCTURE_VERBS[@]}"; then
  emit_deny "$STRUCTURE_MESSAGE"
  exit 0
fi

command=$(jq -r '(.tool_input.command // "") | tostring' <<<"$payload" 2>/dev/null || true)
if [[ -z ${command//[[:space:]]/} ]]; then
  emit_pass
  exit 0
fi

# Only the leading command of the invocation is judged: `ls | rg foo` is an
# agent already reaching for the shell, not a raw read of a source file.
fragment=${command%%[;|&]*}
fragment=${fragment#"${fragment%%[![:space:]]*}"}
read -r -a argv <<<"$fragment" || true
if ((${#argv[@]} == 0)); then
  emit_pass
  exit 0
fi

# Leading `VAR=value` assignments and an `env` wrapper are not the verb.
start=0
while ((start < ${#argv[@]})) && [[ ${argv[start]} == [A-Za-z_]*=* ]]; do
  start=$((start + 1))
done
if ((start < ${#argv[@]})) && [[ ${argv[start]##*/} == env ]]; then
  start=$((start + 1))
fi
if ((start >= ${#argv[@]})); then
  emit_pass
  exit 0
fi

# `rtk` only forwards to the verb behind it. Peeling it keeps the decision
# stable whether this hook sees the original command or the rewrite the rtk
# hook already put in `updatedInput`.
if [[ ${argv[start]##*/} == rtk ]] && ((start + 1 < ${#argv[@]})); then
  start=$((start + 1))
fi

verb=${argv[start]##*/}
argvec=("${argv[@]:start}")
operands=("${argvec[@]:1}")

# `git grep` is a search too, just behind a two-word verb.
if [[ $verb == git ]]; then
  verb=${operands[0]:-}
  operands=("${operands[@]:1}")
  argvec=("git" "${operands[@]}")
fi

if in_list "$verb" "${SEARCH_VERBS[@]}"; then
  if is_workspace_wide_search "${argvec[@]}"; then
    # Counting or listing is the only sweep codegraph query fits, and only behind
    # `-l <n>`; the same query asked for bodies costs 2.4-5.6x rg and saturates
    # near 20-25K bytes whatever the hit count.
    counts_only=0
    for token in "${argvec[@]:1}"; do
      if [[ $token == --* ]]; then
        if in_list "${token%%=*}" "${ENUM_ONLY_OPTIONS[@]}"; then
          counts_only=1
          break
        fi
        continue
      fi
      # `-lc`, `-cl`: single-dash bundles, so read them character-wise.
      if [[ $token == -?* ]]; then
        if [[ ${token:1} == *c* || ${token:1} == *l* ]]; then
          counts_only=1
          break
        fi
      fi
    done
    if ((counts_only)); then
      emit_deny "$ENUM_MESSAGE"
    else
      emit_deny "$SEARCH_MESSAGE"
    fi
    exit 0
  fi
  emit_pass
  exit 0
fi

if in_list "$verb" "${READ_VERBS[@]}" && has_code_operand "${operands[@]}"; then
  emit_deny "$READ_MESSAGE"
  exit 0
fi

if in_list "$verb" "${STRUCTURE_VERBS[@]}" && structure_root_is_workspace "${operands[@]}"; then
  emit_deny "$STRUCTURE_MESSAGE"
  exit 0
fi

emit_pass
