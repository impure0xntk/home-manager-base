# This test case verifies whether the module can be used from a NixOS configuration.
# For example, since `nixpkgs` is inherited from the NixOS side, any configuration 
# related to `nixpkgs` must be set manually here.

{ pkgs, lib, system, self, home-manager, }:
(home-manager.lib.homeManagerConfiguration {
  inherit pkgs lib;
  modules = [
    self.nixosModules.${system}.myHomeModules
    self.nixosModules.${system}.myHomePlatform.native-linux
    {
      nixpkgs = {
        config.allowUnfree = true;
        overlays = self.nixosModules.${system}.nixpkgs.overlays;
      };

      home.stateVersion = "25.05";
      home.username = "nixos";
      home.homeDirectory = "/home/nixos";

      my.home.networks.hostname = "nixos";

      my.home.ai = {
        enable = true;
        providers = [{
          name = "test";
          url = "http://localhost:12345";
          apiKey = "teststring";
          models = [{
            name = "testmodel";
            model = "model";
            roles = ["chat" "edit"];
          }];
        }];
      };
      # my.home.languages.java.enable = true; # zulu: x86_64-linux only
      my.home.languages.shell.enable = true;
    }
  ];
}).activationPackage