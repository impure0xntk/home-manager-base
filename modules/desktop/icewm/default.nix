{ config, pkgs, lib, ... }:
let
  cfg = config.my.home.desktop.icewm;

  icepickTheme =  pkgs.fetchFromGitHub {
    owner = "Vimux";
    repo = "icewm-theme-icepick";
    rev = "4eb4ec8797bb4169253adc550d3fa0e3aa6fc922";
    sha256 = "jGkBfr8s7aJ/+VQurNDEhbA/51JB5L4p2JBx2QepSAI=";
  };
  originalPreferences = builtins.readFile "${icepickTheme}/preferences";
in {
  options.my.home.desktop.icewm.enable = lib.mkEnableOption "Whether to enable icewm";

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.icewm];
    xsession.windowManager.command = lib.mkDefault "${pkgs.icewm}/bin/icewm-session";

    xdg.configFile."icewm/preferences" = {
      text = originalPreferences + ''
        # IcePick theme
        Theme="IcePick"

        # Customization
        TaskBarAtTop = 1
      '';
      recursive = true;
    };

    xdg.configFile."icewm/menu" = {
      text = ''
        # Empty
        prog "" "" ""
      '';
      recursive = true;
    };

    xdg.configFile."icewm/themes/IcePick" = {
      source = "${icepickTheme}/IcePick";
      recursive = true;
    };
  };
}

