{ lib, config, pkgs, ... }:
let
in {
  programs.powerline-go = {
    # enable = true;
    modules = [
      "host" "cwd" "venv" "git" "hg" "docker" "wsl"
    ];
    modulesRight = [
      "newline" "time" "exit" "root"
    ];
    settings = {
      hostname-only-if-ssh = true;
      numeric-exit-codes = true;
      mode = "flat";
      cwd-max-depth = 5;
      cwd-max-dir-size = 10;
      cwd-mode = "simple";
      git-mode = "simple";
    };
  };

  # manual init because home-manager integration is not working
  # TODO: On home-manager 25.05 disable programs.fish.interactiveShellInit and enable programs.starship.enableInteractive instead to resolve the above.
  # https://github.com/nix-community/home-manager/blob/1395379a7a36e40f2a76e7b9936cc52950baa1be/modules/misc/news.nix#L1858
  programs.starship.enableBashIntegration = false;
  programs.starship.enableFishIntegration = false;
  programs.fish.interactiveShellInit = ''
    \${pkgs.starship}/bin/starship init fish | source
  '';

  programs.starship = {
    enable = true;
    enableTransience = true;
    settings = {

      add_newline = true;
      package.disabled = true;
      username = {
        show_always = true;
      };
      battery = {
        format = lib.concatStrings [
          "$symbol"
          "$percentage"
          "($style)"
          " "
        ];
        full_symbol = "🔋";
        charging_symbol = "⚡";
        discharging_symbol = "🔋";
        unknown_symbol = "❓";
        empty_symbol = "🪫";
      };
      cmd_duration.format = lib.concatStrings [
        "⌛ "
        "$duration "
        "($style)"
      ];
      scan_timeout = 10;
      character = {
        success_symbol = "[\\$](bold green)";
        error_symbol = "[\\$](bold red)";
        vimcmd_symbol = "[<](bold green)";
      };
      directory = {
        truncation_length = 5;
        truncation_symbol = "…/";
        truncate_to_repo = false;
        format = "[$path]($style)[$lock_symbol]($lock_style) ";
        read_only = "🔒";
        substitutions = {
          "/github.com/" = "/gh/";
        };
      };
      git_status = {
        ahead = "⇡\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        behind = "⇣\${count}";
        up_to_date = "✓";
        stashed = "📦";
      };
      git_commit.tag_symbol = "🔖 ";
      git_branch.symbol = "🌱 "; # alacritty default font cannot load default symbol.
      # default symbols are emojis
    };
  };
}
