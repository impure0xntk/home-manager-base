{ config, lib, ... }:
let
  cfg = config.my.home.desktop.alacritty;
in {
  options.my.home.desktop.alacritty.enable = lib.mkEnableOption "Whether to enable alacritty.";

  config = lib.mkIf cfg.enable {
    programs.alacritty = {
      enable = true;
    };
    services.picom.opacityRules = [
      "80:class_g = 'Alacritty'"
    ];
  };
}
