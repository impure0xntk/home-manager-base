{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix4vscode = {
      url = "github:nix-community/nix4vscode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Self-maid flakes in private repo. ssh config sets on run_once_before_01_ready.sh.tmpl
    # For old git that does not have -C option, this is temporary disabled (e.g. centos7)
    # sh-utils.url = "git+ssh://git@github.com/828132de77965787/sh-utils";
    nix-lib = {
      url = "github:impure0xntk/nix-lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-pkgs = {
      url = "github:impure0xntk/nix-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix4vscode,
      vscode-server,
      mcp-servers-nix,
      sops-nix,
      nix-lib,
      nix-pkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
      lib = nixpkgs.lib.extend nix-lib.overlays.default;
    in
    {
      homeManagerModules.myHomeModules = {...}: {
        nixpkgs = {
          config.allowUnfree = true;
          overlays = nix-pkgs.nixpkgs.overlays ++ [
            nix4vscode.overlays.forVscode
            mcp-servers-nix.overlays.default
          ];
        };
        imports = [
          vscode-server.homeModules.default
          sops-nix.homeManagerModules.sops
        ] ++ (lib.flatten (
          lib.forEach [ ./modules ] (path: lib.my.listDefaultNixDirs { inherit path; })
        ));
      };

      homeManagerModules.myHomePlatform = {
        native-linux = {...}: {imports = [./platform/native-linux];};
        docker = {...}: {imports = [./platform/docker];};
        wsl = {...}: {imports = [./platform/wsl];};
      };

      checks.${system}.myHomeModules = import ./tests/modules {inherit pkgs lib system self home-manager;};
    };
}
