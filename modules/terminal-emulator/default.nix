{ config, pkgs, lib, ... }:
let
  shellpath = lib.getExe config.programs.fish.package;

  tmuxPackage = pkgs.tmux;

  shellAliases = {
    ":sp" = "tmux split-window -v";
    ":vsp" = "tmux split-window -h";
    ":q" = ''tmux kill-pane -t "$(tmux list-panes | grep "\(active\)" | cut -d':' -f 1)"'';
    # To cancel process, send C-c in tmux-cancel. tmux-cancel is implemented in utilit.nix
    ":qa" = ''tmux-cancel; tmux kill-window -t "$(tmux list-windows | grep "\(active\)" | cut -d':' -f 1)"'';

    "popup" = "tmux popup -h 85% -w 85% -d '#{pane_current_path}'";
    "pup" = shellAliases.popup;

    "tmuxkillwindow" = "tmux kill-window -t \"$(tmux list-windows | fzf | cut -d':' -f 1)\"";
    "tmuxkillpane" = "tmux kill-pane -t \"$(tmux list-panes | fzf | cut -d':' -f 1)\"";
  };

  copyMethod = "${lib.getExe pkgs.xsel} --clipboard --input";
in {
  home.packages = with pkgs; [
    tmux-mem-cpu-load
    ncurses  # depended by extrakto
  ];
  programs.bash.shellAliases = shellAliases;

  # snippet manager. main usecase is to use from tmux.
  programs.pet.enable = true;

  programs.tmux = {
    enable = true;
    package = tmuxPackage;
    shell = "${shellpath}";
    sensibleOnTop = true;
    keyMode = "vi";
    plugins = with pkgs; [
      {
        plugin = tmuxPlugins.tmux-thumbs;
        extraConfig = let
          regexpBase64 = # see https://stackoverflow.com/a/64467300
            ''(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/][AQgw]==|[A-Za-z0-9+/]{2}[AEIMQUYcgkosw048]=)?'';
        in ''
          set -g @thumbs-regexp-1 'sha256-${regexpBase64}' # for Nix derivation hash
          set -g @thumbs-regexp-2 '\$ .+$' # terminal prompt
          set -g @thumbs-regexp-3 '[a-f0-9]{5,40}' # git hash

          set -g @thumbs-command 'echo -n {} | ${copyMethod}'
        '';
      }
      tmuxPlugins.yank
      {
        plugin = tmuxPlugins.extrakto;
        extraConfig = ''
          set -g @extrakto_key "tab"
          set -g @extrakto_copy_key "enter"
          set -g @extrakto_insert_key "tab"
          set -g @extrakto_grab_area "recent"
          set -g @extrakto_split_direction "v"
          set -g @extrakto_fzf_layout "reverse"
          set -g @extrakto_split_size "50%"
        '';
      }
      {
        plugin = tmuxPlugins.mkTmuxPlugin {
          pluginName = "pet";
          version = "v1.0.0";
          src = pkgs.fetchFromGitHub {
            owner = "nyuyuyu";
            repo = "tmux-pet";
            rev = "c90cfcf922dc646f31063ef00315e3f4a3069645";
            sha256 = "sha256-gee0QjxAS21ESByZbp9c7uCHqX27oLfP7HTnnpHdsdM=";
          };
        };
        extraConfig = ''
          set -g @pet-vertical-split-pane-key 'C-f'
        '';
      }
      {
        plugin = tmuxPlugins.logging.overrideAttrs (prev: {
          patches = [
            (pkgs.writeText "tmux-logging-patch-copypath" ''
diff --git a/scripts/save_complete_history.sh b/scripts/save_complete_history.sh
index 569b56b..6a7f776 100755
--- a/scripts/save_complete_history.sh
+++ b/scripts/save_complete_history.sh
@@ -11,7 +11,8 @@ main() {
 		local history_limit="$(tmux display-message -p -F "#{history_limit}")"
 		tmux capture-pane -J -S "-''${history_limit}" -p > "''${file}"
 		remove_empty_lines_from_end_of_file "''${file}"
-		display_message "History saved to ''${file}"
+		echo -n "''${file}" | ${copyMethod}
+		display_message "History saved to ''${file} and copied path to clipboard"
 	fi
 }
 main
diff --git a/scripts/screen_capture.sh b/scripts/screen_capture.sh
index 9397cd3..e6ee8e1 100755
--- a/scripts/screen_capture.sh
+++ b/scripts/screen_capture.sh
@@ -10,7 +10,8 @@ main() {
 		local file=$(expand_tmux_format_path "''${screen_capture_full_filename}")
 		tmux capture-pane -J -p > "''${file}"
 		remove_empty_lines_from_end_of_file "''${file}"
-		display_message "Screen capture saved to ''${file}"
+		echo -n "''${file}" | ${copyMethod}
+		display_message "Screen capture saved to ''${file} and copy path to clipboard"
 	fi
 }
 main
diff --git a/scripts/toggle_logging.sh b/scripts/toggle_logging.sh
index e240d8c..d8b3eec 100755
--- a/scripts/toggle_logging.sh
+++ b/scripts/toggle_logging.sh
@@ -14,7 +14,8 @@ start_pipe_pane() {

 stop_pipe_pane() {
 	tmux pipe-pane
-	display_message "Ended logging to $logging_full_filename"
+	echo -n "''${file}" | ${copyMethod}
+	display_message "Ended logging to ''${file} and copied path to clipboard"
 }
'')
        ];
          });
        extraConfig = ''
          set -g @logging-path "/tmp"
          set -g @screen-capture-path "/tmp"
          set -g @save-complete-history-path "/tmp"

          # Replace logging-key to save-complete-history
          set -g @logging-key 'M-P' # prefix + Alt-Shift-p
          set -g @save-complete-history-key 'P' # prefix + Shift-p
        '';
      }
    ];
    extraConfig =
    let
      # Display whatever you want when the window is zoomed '+' or not zoomed ' '
      windowStatusFormat = " #I #W #{?window_zoomed_flag,+, } ";
    in ''
      # for tmux >= 3.0

      # change prefix
      set -g prefix C-g
      unbind C-b  # disable default
      bind C-g send-prefix # for nested tmux

      # pane keybind
      ## new mode: NAVIGATOR
      ### for nonoverwrite C-h backspace to move pane
      ### https://qiita.com/izumin5210/items/d2e352de1e541ff97079
      bind -n C-w switch-client -T NAVIGATOR
      bind -T NAVIGATOR C-w send-keys C-w  # for vim
      ## move pane
      ### Smart pane switching with awareness of Vim splits.
      ### See: https://github.com/christoomey/vim-tmux-navigator, https://qiita.com/izumin5210/items/d2e352de1e541ff97079
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
          | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
      bind -T NAVIGATOR h if-shell "$is_vim" "send-keys C-w h"  "select-pane -L"
      bind -T NAVIGATOR j if-shell "$is_vim" "send-keys C-w j"  "select-pane -D"
      bind -T NAVIGATOR k if-shell "$is_vim" "send-keys C-w k"  "select-pane -U"
      bind -T NAVIGATOR l if-shell "$is_vim" "send-keys C-w l"  "select-pane -R"
      bind -T NAVIGATOR '\' if-shell "$is_vim" "send-keys C-w \\" "select-pane -l"
      ## resize pane
      bind -r H resize-pane -L 10
      bind -r J resize-pane -D 10
      bind -r K resize-pane -U 10
      bind -r L resize-pane -R 10
      ## split
      bind v split-window -h -c '#{pane_current_path}'
      bind s split-window -v -c '#{pane_current_path}'

      # status line view
      ## enable 256 color. https://www.pandanoir.info/entry/2019/11/02/202146
      set -g default-terminal screen-256color
      set -ga terminal-overrides ",$TERM:Tc"
      ## change color
      set -g status-style "fg=white bg=default"
      ## disable status-left/right
      set -g status-left ""
      set -g status-right ""
      ## align right
      set -g status-justify right
      ## change window status view
      setw -g window-status-current-format '#[bg=colour2,fg=colour255]#{?client_prefix,#[reverse],}${windowStatusFormat}'
      setw -g window-status-format '#[fg=colour242]${windowStatusFormat}'
      ## change window number origin 0 to 1
      set -g base-index 1

      # visual/clip
      setw -g mode-keys vi
      ## change keybind like vi
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${copyMethod}"
      bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "${copyMethod}"
      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind-key -T copy-mode-vi C-[ send-keys -X clear-selection
      # misc
      ## disable login shell, for disable loading .profile
      ## see: https://wiki.archlinux.jp/index.php/Tmux
      set -g default-command "${shellpath}"
      ## enable mouse
      set -g mouse on
      ## expand scroll buffer
      set -g history-limit 50000
      ## for vscode
      set -ga update-environment ' VSCODE_GIT_ASKPASS_NODE VSCODE_GIT_ASKPASS_MAIN VSCODE_IPC_HOOK_CLI PATH GIT_ASKPASS'

      # statusline(tmux-mem-cpu-load)
      set -g status-interval 2
      set -g status-left "#S #[default]#(tmux-mem-cpu-load --averages-count 0 --interval 2)#[default]"
      set -g status-left-length 60

      # windows terminal display corruption workaround.
      # see: https://github.com/microsoft/terminal/issues/6987#issuecomment-1602619926
      set -ag terminal-overrides ',*:cud1=\E[1B'

      # misc
      ## https://www.reddit.com/r/neovim/
      ## In vscode, the workaround of ANSI escapes like "^[]10;rgb:d1d1/d5d5/dada^[\^[]11;rgb:1f1f/2424/2828^[\"
      ## 10 does not work so set to 80.
      ## https://www.reddit.com/r/vscode/comments/1evi4er/strange_characters_when_using_tmux_inside_vscode/
      if-shell 'test -n "$VSCODE_IPC_HOOK_CLI"' \
        'set -sg escape-time 80' \
        'set -sg escape-time 0'
    '';
  };
  programs.bash = {
    enable = true;
    initExtra = ''
      # Base: https://gist.github.com/ClassicOldSong/c9d43e199a8929ad8d783e8a3bc3793b

      # Switch to bash when there's arguments exist
      # such as `scp' or `sftp' or `ssh -t'
      if [ -n "$1" ]; then
        exec -l \${pkgs.bash}/bin/bash "$@"
      fi

      # Boot tmux
      if test -z "$VSCODE_IPC_HOOK_CLI"; then
        \${pkgs.tmux}/bin/tmux new
        EXITSTATUS=$?
        echo -e $NC
        exit $EXITSTATUS
      fi
    '';
  };
}
