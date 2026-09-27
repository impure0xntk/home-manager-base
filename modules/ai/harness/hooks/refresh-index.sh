# SessionStart hook shared by codex and goose: refresh an index only when it
# already governs the directory the session was started in.
#
# codegraph and zvec-grep each resolve their workspace root by walking up from
# the cwd until they find their own marker directory (`.codegraph/`,
# `.zvec-grep`). Running their index commands unconditionally is therefore
# wrong in two ways outside an indexed tree: the session pays the scan cost for
# a directory nobody asked to track, and `zg index` with no index anywhere above
# the cwd silently *creates* one, pinning an unrelated tree.
#
# The gate below asks the same question the tools ask -- is there a marker
# directory at or above $PWD -- so a guarded run is indistinguishable from the
# `codegraph sync` / `zg index` a user would have run by hand in that directory,
# and a skip is a no-op that leaves stdout empty.
#
# usage: refresh-index.sh <marker-dir> <command> [args...]
#   refresh-index.sh .codegraph /nix/store/.../bin/codegraph sync --quiet
#   refresh-index.sh .zvec-grep /nix/store/.../bin/zg index

set -euo pipefail

marker=$1
shift
command_path=$1
shift

# The agent pipes the hook payload on stdin; drain it so the write cannot block
# on a full pipe buffer while the index runs.
cat >/dev/null || true

dir=$PWD
while :; do
  if [[ -d ${dir}/${marker} ]]; then
    "${command_path}" "$@" || true
    exit 0
  fi
  if [[ $dir == / ]]; then
    break
  fi
  # Shortest match, so the last component is the one dropped. On a
  # single-component path ("/home") this yields the empty string; the walk ends
  # at the filesystem root, not at "".
  dir=${dir%/*}
  if [[ -z $dir ]]; then
    dir=/
  fi
done

exit 0
