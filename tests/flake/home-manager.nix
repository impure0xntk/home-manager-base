{ pkgs, lib, system, self, home-manager, }@args:
(home-manager.lib.homeManagerConfiguration {
  inherit pkgs lib;
  modules = [
    self.homeManagerModules.${system}.myHomeModules
    self.homeManagerModules.${system}.myHomePlatform.native-linux
    {
      home.stateVersion = "25.05";
      home.username = "nixos";
      home.homeDirectory = "/home/nixos";

      my.home.networks.hostname = "nixos";

      # my.home.ai.enable = true;
      # my.home.languages.java.enable = true; # zulu: x86_64-linux only
      my.home.languages.shell.enable = true;
    }
    # (import ./../modules/ide/jetbrains-remote.nix args)
    # (import ./../modules/languages/java.nix args)
  ];
}).activationPackage
