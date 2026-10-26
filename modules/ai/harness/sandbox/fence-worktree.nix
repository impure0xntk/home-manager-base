{
  lib,
  writeShellApplication,
  fence,
  git,
  jq,
  coreutils,
}:

writeShellApplication {
  name = "fence-worktree";

  runtimeInputs = [
    fence
    git
    jq
    coreutils
  ];

  text = ''
    set -euo pipefail

    # Parse an optional explicit settings path.
    args=()
    explicit_settings=""

    while (($#)); do
      case "$1" in
        --settings)
          if (($# < 2)); then
            echo "fence-worktree: --settings requires a path" >&2
            exit 2
          fi
          explicit_settings="$2"
          args+=("$1" "$2")
          shift 2
          ;;
        --settings=*)
          explicit_settings="''${1#--settings=}"
          args+=("$1")
          shift
          ;;
        *)
          args+=("$1")
          shift
          ;;
      esac
    done

    # Preserve Fence behavior outside a Git worktree.
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      exec ${lib.getExe fence} "''${args[@]}"
    fi

    git_dir="$(git rev-parse --path-format=absolute --git-dir)"
    git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"

    # Resolve an explicitly supplied settings path before using it
    # as the parent configuration.
    if [[ -n "$explicit_settings" ]]; then
      base_settings="$(realpath -e -- "$explicit_settings")"
    else
      base_settings="@base"
    fi

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    settings="$tmpdir/fence.json"

    jq -n \
      --arg base "$base_settings" \
      --arg git_dir "$git_dir" \
      --arg git_common_dir "$git_common_dir" \
      '{
        extends: $base,
        filesystem: {
          allowRead: ([$git_dir, $git_common_dir] | unique)
        }
      }' > "$settings"

    # Remove the original --settings arguments and replace them with
    # the generated configuration, which extends the original config.
    filtered_args=()
    skip_next=false

    for arg in "''${args[@]}"; do
      if $skip_next; then
        skip_next=false
        continue
      fi

      case "$arg" in
        --settings)
          skip_next=true
          ;;
        --settings=*)
          ;;
        *)
          filtered_args+=("$arg")
          ;;
      esac
    done

    exec ${lib.getExe fence} --settings "$settings" "''${filtered_args[@]}"
  '';
}
