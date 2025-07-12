{ pkgs, lib, system, self, home-manager, }:

(home-manager.lib.homeManagerConfiguration {
  inherit pkgs lib;
  modules = [
    self.homeManagerModules.myHomeModules
    self.homeManagerModules.myHomePlatform.native-linux
    {
      nixpkgs.overlays = self.nixpkgs.overlays;

      home.stateVersion = "25.05";
      home.username = "nixos";
      home.homeDirectory = "/home/nixos";

      my.home.networks.hostname = "nixos";

      # my.home.ai.enable = true;
      my.home.languages.java.enable = true;
    }
  ];
}).activationPackage