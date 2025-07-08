{ config, pkgs, lib, ... }:
let
  cfg = config.my.home.desktop.i3;

  altTabScript = pkgs.fetchurl {
    url =
      "https://raw.githubusercontent.com/yoshimoto/i3-alt-tab.py/2455ac2db25f98f4dd84142dad5caf3dc432ea97/i3-alt-tab.py";
    hash = "sha256-C01KU0iX3BnPh+OeEmvMXQMknY9O+WTYv5Ur7BPmqcY=";
  };
  altTab = pkgs.writeShellApplication {
    name = "i3-alt-tab";
    runtimeInputs = [pkgs.python3 altTabScript];
    text = ''
      python3 "${altTabScript}" "$@"
      '';
  };
in {
  options.my.home.desktop.i3 = {
    enable = lib.mkEnableOption "Whether to enable i3";
    enablei3status = lib.mkEnableOption "Whether to enable i3status. This uses i3status-rust";
    terminalCommand = lib.mkOption {
      description = "Terminal command to execute from Ctrl + Shift + t shortcut keys. This is planned to replace xbindkeys.";
      example = "alacritty";
      default = "true";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables.XDG_CURRENT_DESKTOP = "i3";

    xsession.windowManager.i3 = {
      enable = true;
      config = rec {
        # inherit terminal menu;
        workspaceLayout = "tabbed";
        bars = [
          (lib.mkIf config.programs.i3status-rust.enable {
            # config-{i3status-rust.bars name}.toml
            statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config-default.toml";
          })
        ];
        gaps = {
          smartBorders = "on";
          smartGaps = true;
          inner = 10;
          outer = 5;
        };
        terminal = cfg.terminalCommand;
        keybindings =
          let
            mod = config.xsession.windowManager.i3.config.modifier;
          in lib.mkOptionDefault {
            "Ctrl+Shift+t" = "exec ${terminal}";
            "${mod}+Tab" = "exec ${altTab}/bin/i3-alt-tab n";
            "${mod}+Shift+Tab" = "exec ${altTab}/bin/i3-alt-tab p";
            "${mod}+Shift+q" = "kill";
          };
      };
    };
    programs.i3status.enable = false;
    programs.i3status-rust = {
      enable = cfg.enablei3status;
      bars = {
        default = {
          icons = "emoji";

          blocks = [
            {
              block = "disk_space";
              alert = 10.0;
              format = " $icon root: $available.eng(w:2) ";
              info_type = "available";
              interval = 60;
              path = "/";
              warning = 20.0;
            }
            {
              block = "memory";
              format = " $icon $mem_total_used_percents.eng(w:2) ";
            }
            {
              block = "cpu";
              interval = 2;
            }
            # (lib.mkIf systemConfig.services.pipewire.enable {block = "sound";})
            {
              block = "time";
              interval = 60;
              format = " $timestamp.datetime(f:'%a %d/%m %R') ";
            }
          ];
        };
      };
    };
  };
}

