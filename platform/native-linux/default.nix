{ config, pkgs, lib, ... }:
let
  shellAliases = {
    "open"="xdg-open";
    # "pbcopy"="xsel --clipboard --input";
    # "pbpaste"="xsel --clipboard --output";
  };
in {
  # Set platform type for other modules.
  # This modules may be imported from other platform,
  # so defines as default.
  my.home.platform.type = lib.mkDefault "native-linux";

  targets.genericLinux.enable = true;
  home.packages = with pkgs; lib.optionals config.xsession.enable [
    xdg-utils
    xsel
  ];
  home.keyboard.options = [
    "ctrl:nocaps"
  ];
  programs.bash.shellAliases = shellAliases;

  # not working...
  # dconf.settings = {
  #   "org.gnome.settings-daemon.plugins.media-keys" = {
  #     custom-keybindings = ["/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"];
  #   };

  #   "org.gnome.settings-daemon.plugins.media-keys.custom-keybindings.custom0" = {
  #     # binding = "<Super>t";
  #     binding = "<Shift><Control>t";
  #     command = "gnome-terminal";
  #     name = "Open terminal";
  #   };
  # };
  # xdg.desktopEntries = {
  #   Termnial = {
  #     name = "Gnome Terminal";
  #     genericName = "Gnome Terminal";
  #     exec = "gnome-terminal %U";
  #   };
  # };
}
