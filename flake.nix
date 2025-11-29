{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
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
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    nix-ai-tools = {
      url = "github:numtide/nix-ai-tools";
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
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    nix-pkgs = {
      url = "github:impure0xntk/nix-pkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-unstable.follows = "nixpkgs-unstable";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      home-manager,
      nix4vscode,
      vscode-server,
      nix-ai-tools,
      mcp-servers-nix,
      sops-nix,
      nix-lib,
      nix-pkgs,
      ...
    }: flake-utils.lib.eachSystem (
      with flake-utils.lib.system; [ # supported system
        x86_64-linux
        aarch64-linux
      ]
    ) (system:
    let
      pkgs = import nixpkgs {
        inherit system;
      };
      lib = nix-lib.lib.${system};
      
      createModules = args: {...}: args // {
        imports = [
          vscode-server.homeModules.default
          sops-nix.homeManagerModules.sops
        ] ++ (lib.flatten (
          lib.forEach [ ./modules ] (path: lib.my.listDefaultNixDirs { inherit path; })
        ));
      };
      platform = {
        native-linux = {...}: {imports = [./platform/native-linux];};
        docker = {...}: {imports = [./platform/docker];};
        wsl = {...}: {imports = [./platform/wsl];};
      };
      overlays = (nix-pkgs.pkgsOverlay.${system} ++ [
        nix4vscode.overlays.forVscode
        mcp-servers-nix.overlays.default
      ]) ++ [
        # Add 3rd-party packages as overlays because no overlays are provided.
        (final: prev: nix-ai-tools.packages.${system})
      ];
    in
    {
      # For nixos: import myHomeModules and overlays separately
      nixosModules = {
        myHomeModules = createModules {};
        myHomePlatform = platform;
        nixpkgs.overlays = overlays;
      };

      # For home-manager
      homeManagerModules = {
        myHomeModules = createModules {
          nixpkgs = {
            config.allowUnfree = true;
            overlays = overlays;
          };
        };
        myHomePlatform = platform;
      };

      checks = {
        homeManagerModules = import ./tests/flake/home-manager.nix {inherit pkgs lib system self home-manager;};
        nixosModules = import ./tests/flake/nixos.nix {inherit pkgs lib system self home-manager;};
      };
    });
}
