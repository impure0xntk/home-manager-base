{ config, pkgs, lib, systemConfig, ... }: # should pass userList using _module.args.
{
  home.packages = with pkgs; [
    # Required for rofi-systemd
    jq
  ];

  programs.rofi = {
    enable = true;
    cycle = true;
    location = "center";
    pass = { };
    plugins = [
      pkgs.rofi-calc
    ];
    xoffset = 0;
    yoffset = -20;
    extraConfig = {
      show-icons = true;
      kb-cancel = "Escape,Super+space";
      # modi = "window,run,ssh,calc";
      sort = true;
      levenshtein-sort = true;
    };
    theme = builtins.toPath (pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/davatorium/rofi/558ab34aa3b6fc8fe6b1715b9750824999036910/themes/Arc-Dark.rasi";
      hash = "sha256-OvX2qr7wHPijkkjc7w3cCq1fobPTpO6A04gn3BYsG88=";
    });
  };
  services.picom.opacityRules = [
    "100:class_g = 'Rofi'"
  ];
}
