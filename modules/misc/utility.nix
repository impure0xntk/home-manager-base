{ config, pkgs, lib, ... }:
let
  # Reusable scripts.
  # These are used by systemd-user units in someday.

  # writeShellApplication automatically sets
  # the PATH of the script to contain all of the listed inputs,
  # sets some sanity shellopts (errexit, nounset, pipefail), and checks the resulting script with shellcheck.
  # see: https://ryantm.github.io/nixpkgs/builders/trivial-builders/#trivial-builder-writeShellApplication

  scripts = rec {
    fuzzyrg = pkgs.writeShellApplication {
      name = "fuzzyrg";
      runtimeInputs = with pkgs; [fzf ripgrep bat];
      text = ''
        # Use "FUZZYRG_PREVIEW_WINDOW_SIZE_PERCENT" to set the size of the popup window.
        # The default is 35.

        RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case "
        INITIAL_QUERY="''${*:-}"
        IFS=: read -ra selected < <(
          FZF_DEFAULT_COMMAND="$RG_PREFIX $(printf %q "$INITIAL_QUERY")" \
          fzf --ansi \
              --height=-1 \
              --color "hl:-1:underline,hl+:-1:underline:reverse" \
              --disabled --query "$INITIAL_QUERY" \
              --header 'ctrl-f: fzf | ctrl-r: ripgrep' \
              --bind "change:reload:sleep 0.1; $RG_PREFIX {q} || true" \
              --bind "ctrl-f:unbind(change,ctrl-f)+change-prompt(2. fzf> )+enable-search+clear-query+rebind(ctrl-r)" \
              --bind "ctrl-r:unbind(ctrl-r)+change-prompt(1. ripgrep> )+disable-search+reload($RG_PREFIX {q} || true)+rebind(change,ctrl-f)" \
              --prompt '1. ripgrep> ' \
              --delimiter : \
              --preview 'bat --color=always {1} --highlight-line {2}' \
              --preview-window "up,''${FUZZYRG_PREVIEW_WINDOW_SIZE_PERCENT:-35}%,border-bottom,+{2}+3/3,~3"
        )
        if test -n "''${selected[0]}"; then
          if [[ "''${EDITOR:?EDITOR not found.}" == *code* ]]; then
            $EDITOR --goto "''${selected[0]}":"''${selected[1]}"
          else
            $EDITOR "''${selected[0]}" "+''${selected[1]}"
          fi
        fi
      '';
    };
    search = pkgs.writeShellApplication {
      name = "search";
      runtimeInputs = [scripts.fuzzyrg pkgs.tmux];
      text = ''
          tmux popup -E -h 85% -w 85% -d '#{pane_current_path}' "fuzzyrg ''${*:-}; exit"
        '';
    };

    # git
    gitRoot = pkgs.writeShellApplication {
      name = "git-root";
      runtimeInputs = [pkgs.busybox pkgs.git];
      text = "${pkgs.busybox}/bin/readlink -f \"$(${pkgs.git}/bin/git rev-parse --git-dir)\" | sed 's/\\\/\\\.git.*//g'";
    };
    gitBlameRg = pkgs.writeShellApplication { # TODO: oil
      name = "gitblamerg";
      runtimeInputs = [pkgs.ripgrep];
      excludeShellChecks = ["SC2086"];
      text = ''
        SEARCH_WORD="''${1:-input search word.}"
        LINE="$(rg "$SEARCH_WORD" . --no-heading --line-number | cut -d':' -f1-2 | tr ':' ' ' )"
        echo "$LINE"
        while read -r line
        do
          set ''${line}
          file="$1"
          line_num="$2"
          git blame -L "$line_num",+1 "$file"
          done << EOF
$LINE
EOF
      '';
    };

    # nix, home-manager
    nixPath = pkgs.writeShellApplication {
      name = "nix-path";
      runtimeInputs = [pkgs.busybox];
      # https://discourse.nixos.org/t/setting-up-java-dev-env-vscode-with-redhat-java/2222/2
      text = ''
        ${pkgs.busybox}/bin/readlink -f "$(which "''${1:?input argument as executable file.}")" | cut -d '/' -f -4
      '';
    };
    nixPatchelf = pkgs.writeShellApplication {
      name = "nix-patchelf";
      runtimeInputs = [pkgs.patchelf];
      text = ''
        patchelf --set-interpreter "$(cat "$NIX_CC"/nix-support/dynamic-linker)" "$@"
      '';
    };
    # docker
    dockerContinue = lib.my.writeOilApplication {
      name = "docker-continue";
      errexit = false;
      text = ''
        NAME="''${1:? input container name.}"

        SHA="$(docker ps -a --filter "name=''${NAME}" -q)"
        if test -z "''${SHA}"; then
          exit 1
        fi
        STATUS="$(docker inspect --format '{{.State.Status}}' "''${SHA}")"
        case "''${STATUS:?container not found.}" in
          paused ) docker unpause "$SHA";;
          exited ) docker start "$SHA";;
          running ) true;;
          dead ) false;;
          * ) false;;
        esac
      '';
    };
    dockerVolumePruneSimple = pkgs.writeShellApplication {
      name = "docker-volume-prune-simple";
      text = ''
        # remove anonymous volumes: https://github.com/moby/moby/issues/31757
        anonymous_volumes="$(docker volume ls -q -f driver=local -f dangling=true |
          awk '$0 ~ /^[0-9a-f]{64}$/ { print }')"
        if [ -n "''${anonymous_volumes:-}" ]; then
          printf "%s\n" "''${anonymous_volumes}" | xargs docker volume rm
        fi
      '';
    };
    dockerImagesUpdate = lib.my.writeOilApplication {
      name = "docker-images-update";
      text = ''
        # check and update latest images
        while IFS="
" read -r line; do
          latest_image_tag="$(echo "$line" | awk '{ print $1 }')"
          latest_image_digest="$(echo "$line" | awk '{ print $2 }')"
          # docker images digest is "manifest digest" , and docker manifest inspect digest is "image digest", not same
          # https://github.com/docker/hub-feedback/issues/1925#issuecomment-1601129934
          registry_digest="$(docker run --rm --network=host regclient/regctl image digest "$latest_image_tag")"

          if test "$registry_digest" != "$latest_image_digest"; then
            latest_pull_target_images="''${latest_pull_target_images:-}''${latest_image_tag} "
            printf 'changed  : %s\n' "''${latest_image_tag}" >&2
          else
            printf 'no_change: %s\n' "''${latest_image_tag}" >&2
          fi
        done <<EOS
$(docker images --format "{{.Repository}}:{{.Tag}} {{.Digest}}" | grep -v ' <none>$')
EOS
        if test -n "''${latest_pull_target_images:-}"; then
          echo "''${latest_pull_target_images}" | sed 's/ /\n/g' | while read -r tag; do
            DOCKER_BUILDKIT=1 docker pull "''${tag}"
          done
        fi
      '';
    };
    # tmux
    tmuxLast = lib.my.writeOilApplication {
      # idea: https://dqn.sakusakutto.jp/2017/03/remove-matched-by-grep-awk-sed.html
      name = "last";
      text = ''
        CAPTURE_PANE="tmux capture-pane -p -S- -E-"
        SEDS="$(eval "$CAPTURE_PANE" | grep -n '^at .* \$.*$' | awk -F: '{ print "-e " $1-1 "," $1 "d " }' | tr -d '\n')"
        eval "$CAPTURE_PANE | sed ''${SEDS:-}" | sed '/^$/d' | tail -"''${1:-1}"
      '';
    };
    tmuxLastCopy = lib.my.writeOilApplication {
      # uses fish_clipboard_copy. If use from another shell, change copy method.
      name = "lastcopy";
      runtimeInputs = [tmuxLast];
      text = ''
        last "''${1:-1}" | fish -c fish_clipboard_copy
      '';
    };

    tmuxCancel = pkgs.writeShellApplication {
      name = "tmux-cancel";
      text = ''
        for pane in $(tmux list-panes | cut -d':' -f 1); do
          tmux send-keys -t "''${pane}" C-c
        done
      '';
    };

    tmuxpHasWindow = pkgs.writeShellApplication {
      name = "tmuxp-has-window";
      text = ''
        pane="$(tmux list-windows | cut -d' ' -f 2 | grep "''${1:?input window name.}" || true)"
        if [ -n "''${pane}" ]; then
          exit 0
        fi
        exit 1
      '';
    };
    tmuxpReady = pkgs.writeShellApplication {
      name = "tmuxp-ready";
      text = ''
        if ! tmuxp-has-window "''${1:?input window name.}"; then
          tmuxp load -a "''${2:-"''${1}"}"
        fi
      '';
    };
    tmuxMultiSsh = pkgs.writeShellApplication {
      name = "multi-ssh";
      excludeShellChecks = ["SC2048"];
      # https://tech.naviplus.co.jp/2014/01/09/tmux%E3%81%A7%E8%A4%87%E6%95%B0%E3%82%B5%E3%83%BC%E3%83%90%E3%81%AE%E5%90%8C%E6%99%82%E3%82%AA%E3%83%9A%E3%83%AC%E3%83%BC%E3%82%B7%E3%83%A7%E3%83%B3/
      text = ''
        session=multi-ssh-"''${SESSION_NAME:-$(date +%s)}"
        tmux new-session -d -n "multi-ssh" -s "$session"

        ### Login
        # the first session
        tmux send-keys "ssh $1" C-m
        shift

        # the other session: create pane
        for i in $*;do
          tmux split-window
          tmux select-layout tiled
          tmux send-keys "ssh $i" C-m
        done

        tmux select-pane -t 0

        tmux set-window-option synchronize-panes on
        tmux attach-session -t "$session"
      '';
    };
  };
in {
  home.packages = lib.attrValues scripts;
}
