{ config, pkgs, lib, ... }:
let
  shellAliases = {
    "diff"="diff --color=auto";
    "grep"="grep --color=auto";
    # eza overrides in cli-tools.nix
    "l"="ls";
    "la"="ls -a";
    "ll"="ls -alF";

    "cp"="cp -i";
    "mv"="mv -i";
    # using trash in cli_tools.nix
    "rm"="rm -i";

    "mkdir"="mkdir -p";

    "reload"="exec $SHELL -l";
    "rl"= shellAliases.reload;

    "dive"="docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive:latest";
    "dc"="docker compose";
    "dp"="docker ps";
    "dr"="docker run -it --rm=true";
    "dx"="docker exec -it";

    "o"="open";

    "pbcopy"="fish_clipboard_copy";
    "pbpaste"="fish_clipboard_paste";

    "download" = "curl -fsSLO";
    "dl" = shellAliases.download;

    "ghqo" = "ghqc";

    "sy" = "systemctl";
    "sys" = "systemctl status";
    "syc" = "systemctl cat";
    "syr" = "systemctl restart";

    "jc" = "journalctl";
    "jcu" = "journalctl -u";
    "jcf" = "journalctl -f";

    # e.g. display<space>xeyes
    "display" = ''export DISPLAY="$(command ps -u "$(id -u)" -o pid= | xargs -I PID -r cat /proc/PID/environ 2> /dev/null | tr '\0' '\n' | grep ^DISPLAY=: | sort -u | cut -d= -f 2)"'';
    "disp" = shellAliases.display;
  };
  # inspire: https://discourse.nixos.org/t/home-manager-make-fish-plugins-actually-load/26464
  fishConfig = {
    pluginLoader = (plugin:
      let
        source_dir = dir_name:
          ''
            if test -d ${plugin.src}/share/fish/${dir_name}
                for file in ${plugin.src}/share/fish/${dir_name}/*.fish
                    source $file
                end
            end
          '';
      in
      ''
        # source ${config.xdg.configHome}/fish/conf.d/plugin-${plugin.name}.fish
        if test -d ${plugin.src}/conf.d
            for file in ${plugin.src}/conf.d/*.fish
                source $file
            end
        end
        ${source_dir "vendor_functions.d"}
        ${source_dir "vendor_completions.d"}
        ${source_dir "vendor_conf.d"}
        ${source_dir "vendor_themes.d"}
      ''
    );
    plugins = [
      {
        name = "sponge";
        src = pkgs.fishPlugins.sponge;
      }
      {
        name = "foreign-env";
        src = pkgs.fishPlugins.foreign-env;
      }
      {
        name = "fish-ghq";
        src = pkgs.fetchFromGitHub {
          owner = "decors";
          repo = "fish-ghq";
          rev = "cafaaabe63c124bf0714f89ec715cfe9ece87fa2";
          sha256 = "6b1zmjtemNLNPx4qsXtm27AbtjwIZWkzJAo21/aVZzM=";
        };
      }
      {
        name = "fish-abbreviation-tips";
        src = pkgs.fetchFromGitHub {
          owner = "gazorby";
          repo = "fish-abbreviation-tips";
          rev = "8ed76a62bb044ba4ad8e3e6832640178880df485";
          sha256 = "F1t81VliD+v6WEWqj1c1ehFBXzqLyumx5vV46s/FZRU=";
        };
      }
      {
        name = "wakatime-fish";
        src = pkgs.fishPlugins.wakatime-fish;
      }
      # does not work...
      # { name = "autopair.fish"; src = pkgs.fishPlugins.autopair; }
      # { name = "puffer-fish"; src = pkgs.fishPlugins.puffer; }
      # { name = "pisces"; src = pkgs.fishPlugins.pisces; }
      # { name = "async-prompt"; src = pkgs.fishPlugins.async-prompt; }
      # works but too slow...
      # { name = "transient-fish"; src = pkgs.fishPlugins.transient-fish; }
      # { name = "done"; src = pkgs.fishPlugins.done; }
    ];
  };
in {
  home.packages = with pkgs; [
    babelfish  # translate bash and fish
    fishPlugins.foreign-env  # translate bash and fish
    oils-for-unix # defined by overlay/default.nix
  ];
  programs.bash = {
    enable = true;
    shellAliases = shellAliases;
  };
  programs.fish = {
    enable = true;
    package = pkgs.fishMinimal;
    shellAbbrs = config.programs.bash.shellAliases; # inherit config.programs.bash.shellAliases;
    preferAbbrs = true;
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" (lib.flatten [
      (lib.forEach fishConfig.plugins (plugin:
        fishConfig.pluginLoader plugin))
    ])) + ''
      set fish_greeting
      set fish_color_command blue

      # Custom keybindings must set in this function only!
      function fish_user_key_bindings
          # vi mode: https://fishshell.com/docs/current/interactive.html#vi-mode-commands
          #   Execute this once per mode that emacs bindings should be used in
          fish_default_key_bindings -M insert

          #   Then execute the vi-bindings so they take precedence when there's a conflict.
          #   Without --no-erase fish_vi_key_bindings will default to
          #   resetting all bindings.
          #   The argument specifies the initial mode (insert, "default" or visual).
          fish_vi_key_bindings --no-erase insert

          # fzf completion
          #   https://github.com/junegunn/fzf/issues/868#issuecomment-1096845055
          #   https://github.com/junegunn/fzf/issues/868#issuecomment-425592957
          function __fuzzy_complete
              # deny the letters of completion that is less than 2 for another application tabkey entering
              # TODO: WIP. If use pipe, completion is enabled.
              set cmd (commandline -p)

              if test (string length "$cmd") -eq 0
                # If empty or too little, switch to search recent changed directory and cd.
                set result 1
                if type -q zi
                  set result (zi)
                end
                commandline -f repaint
                return $result
              end

              if test (string length "$cmd") -le 2
                return 1
              end

              set -l token (commandline -t)
              # sort~ : Format input: sort, label as value/description sep, and create table using sep.
              # cut~ : Format output: cut descriptions, concat multi selected values, and trim begin/end whitespaces.
              # only "complete -C" is not working on "z " and "cd ", so input the redundant argument STRING.
              complete -C (commandline) \
                | string replace -r \t'(.*)$' \t(set_color $fish_pager_color_description)'$1'(set_color normal) \
                | sort -u \
                | fzf --ansi --multi -1 -0 --reverse --info=hidden --tabstop=4 --query=$token \
                  --bind=space:toggle+down --bind=tab:down,shift-tab:up \
                  --preview '\
                    if test -f {}; bat --color=always --plain --line-range=:200 {}; \
                    else if test -d {}; eza --color=always --tree --level 1 {} | head -200; \
                    else if command -v -- {1} 2>&1 >/dev/null; \
                      tldr {1} --compact --color always || man {1};
                    end' \
                | cut -f 1 | tr '\n' ' '  | awk '{$1=$1;print}'\
                | read -l token
              if test -n "$token"
                  set token (string escape -n "$token" | string replace "\~/" "~/") # allow ~/ as HOME
                  commandline -t -- "$token"
              end
              commandline -f repaint
          end
          if command -v fzf 2>&1 >/dev/null
              bind --erase -M insert --preset \t
              bind -M insert \t '__fuzzy_complete'
          end
      end
      fish_user_key_bindings

      # Emulates vim's cursor shape behavior
      set fish_cursor_default block
      set fish_cursor_insert line
      set fish_cursor_replace_one underscore
      set fish_cursor_visual block

      # disable typo history
      set sponge_allow_previously_successful false
    '';
  };

  programs.fish.functions = {
    # This is so useful. If necessary, rewrite for bash.
    bk = {
      description = "Move file with or without .bak extension.";
      wraps = "mv";
      body = ''
        set BAK_EXT ".bak"
        set dry_run 0
        set HELP_MSG "Usage: bk [--dry-run] <file> <other options to mv>"

        if test (count $argv) -lt 1 -o "$argv[1]" = "-h" -o "$argv[1]" = "--help"
          echo $HELP_MSG >&2
          return 1
        end

        if test "$argv[1]" = "--dry-run"
          set dry_run 1
          set argv $argv[2..-1]
        end

        set file $argv[1]

        if not test -f "$file"
          echo "Error: '$file' does not exist or is not a regular file." >&2
          echo $HELP_MSG >&2
          return 1
        end

        set ext (path extension "$file")
        set file_noext (path change-extension "" "$file")

        if test "$ext" = "$BAK_EXT"
          set target "$file_noext"
        else
          set target "$file$BAK_EXT"
        end

        if test $dry_run -eq 1
          echo "Would move '$file' to '$target'"
        else
          mv -i "$file" "$target" $argv[2..-1]
          echo "Moved '$file' to '$target'." >&2
        end
      '';
    };

  };
  programs.fish.plugins = fishConfig.plugins;
}
