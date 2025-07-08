{ config, pkgs, lib, ... }: # should pass userList using _module.args.
let
  cfg = config.my.home.desktop;
in {
  options.my.home.desktop.enable = lib.mkEnableOption "Whether to enable desktop environment for each users.";

  config = lib.mkIf cfg.enable {
    xsession = {
      enable = true;
      initExtra = ''
        xset -dpms # Disable DPMS (Energy Star) features.
        xset s off # Disable screen saver.
        xset b off # Disable beep.
      '';
    };

    # compositor
    # TODO: In 24.11 and WSL cannot work correctly.
    services.picom = {
      enable = false;
      inactiveOpacity = 0.6;
      opacityRules = [
        "0:_NET_WM_STATE@:32a *= '_NET_WM_STATE_HIDDEN'"
      ];
    };

    # color theme
    xresources.extraConfig = builtins.readFile (
      pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/b4a9c4ded7ff2cb52f0de2975dc552091b0502e8/Xresources/GitHub%20Dark";
        hash = "sha256-/z8IiOSScMPbmrxjTjoIpIt6tDYzKR1KI4bQtqnI8b0=";
      });

    # To run java's GUI application without GNOME/Plasma
    # https://wiki.archlinux.jp/index.php/Java_Runtime_Environment_%E3%81%AE%E3%83%95%E3%82%A9%E3%83%B3%E3%83%88
    # https://wiki.archlinux.jp/index.php/%E3%83%95%E3%82%A9%E3%83%B3%E3%83%88%E8%A8%AD%E5%AE%9A
    services.xsettingsd = {
      enable = true;
      settings = {
        "Xft/Hinting" = 1;
        "Xft/HintStyle" = "hintslight";
        "Xft/Antialias" = 1;
        "Xft/RGBA" = "rgb";
      };
    };
    # The workaround of unit failed caused by "xsettingsd: Unable to open connection to X server" on boot.
    # This may occur when use wsl only.
    systemd.user.services.xsettingsd.Service.ExecStart = lib.mkForce (
      let
        cfg = config.services.xsettingsd;
      in pkgs.writeShellScript "start-xsettingsd"
        "${cfg.package}/bin/xsettingsd -c ${lib.escapeShellArg cfg.configFile} || true");
  };
}

