{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.my.home.languages.nix;
in
{
  options.my.home.languages.nix = {
    enable = lib.mkEnableOption "Whether to enable nix language support.";
    currentConfigurations = lib.mkOption {
      type = lib.types.attrs;
      description = "Current configurations to handle nix language server";
      default = {};
      example = {
        nixos = {
          expr = "(builtins.getFlake \"/absolute/path/to/flake\").nixosConfigurations.<name>.options";
        };
        home-manager = {
          expr = "(builtins.getFlake \"/absolute/path/to/flake\").homeConfigurations.<name>.options";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      nixfmt-rfc-style
      nix-tree
      nvd
      deploy-rs
      nurl
    ];

    programs.nh = {
      enable = true;
      clean = {
        enable = true;
        dates = "weekly";
        extraArgs = "--keep 5 --keep-since 7d";
      };
    };

    programs.nix-index = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };

    programs.nix-your-shell = {
      enable = true;
      enableFishIntegration = true;
    };

    programs.vscode = {
      profiles.default = {
        extensions = pkgs.nix4vscode.forVscode [
          "arrterian.nix-env-selector"
          "jnoortheen.nix-ide"
        ];

        userSettings = {
          "[nix]" = {
            "editor.defaultFormatter" = "jnoortheen.nix-ide";
          };
        } // lib.my.flatten "_flattenIgnore" {
          nix = rec {
            enableLanguageServer = true;
            serverPath = "${pkgs.nixd}/bin/nixd"; # nixd depends old llvm(too large)...
            # The workaround of "textDocument/documentHighlight failed".
            # https://github.com/nix-community/vscode-nix-ide/issues/411
            hiddenLanguageServerErrors = [
              "textDocument/definition"
            ];
            formatterPath = "nixfmt";
            serverSettings = {
              "nixd" = {
                "formatting" = {
                  "command" = [ formatterPath ];
                };
                options = cfg.currentConfigurations;
              };
              _flattenIgnore = true;
            };
          };
        };
      };
    };
  };
}
