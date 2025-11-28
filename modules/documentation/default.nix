# Import vscode-server to flake as input.
# https://github.com/nix-community/nixos-vscode-server
#
{ config, pkgs, lib, ... }:
let
  cfg = config.my.home.documentation;

  textlintRcFile = pkgs.writeText "textlintrc" (import ./textlint {
    inherit pkgs lib;
    gramma = cfg.gramma;
  });

  textlintCacheLocation = config.xdg.cacheHome + "/textlint";
  textlint = pkgs.textlint-all.override {
    inherit textlintCacheLocation;
  };

  # makeWrapper is used for the last to add NODE_PATH.
  textlintWrapper = pkgs.writeShellApplication {
    name = "textlint";
    runtimeInputs = [ textlint ];
    text = ''
      textlint \
        --config ${textlintRcFile} \
        --cache \
        --cache-location ${textlintCacheLocation}/textlintcache \
        "$@"
    '';
  };

in {
  options.my.home.documentation = {
    enable = lib.mkEnableOption "Whether to enable documentation tools.";
    executablePath = lib.mkOption {
      type = lib.types.pathInStore;
      description = "The path to the textlint executable with wrapper.";
      default = textlintWrapper;
      readOnly = true;
    };
    gramma = {
      enable = lib.mkEnableOption "Whether to enable gramma rule.";
      apiUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:18181/v2/check";
        description = "The API URL for gramma rule.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      textlintWrapper
      # pkgs.markitdown.all
      pkgs.python3Packages.markitdown
    ];
    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "yzane.markdown-pdf"
        "hediet.vscode-drawio"
        "jebbs.plantuml"
        "3w36zj6.textlint"
      ];
      userSettings = {
        "linter.linters" = {
          "textlint" = {
            "name" = "textlint";
            "capabilities" = [ "fix-inline" ];
            "command" = [
              "textlint" "--format" "json"
              [ "$debug" "--debug" ]
              # [ "$config" "--config" "$config" ] # read from textlint wrapper.
              "--stdin" "--stdin-filename"
              "$file"
            ];
            "configFiles" = []; # read from textlint wrapper.
            "enabled" = true;
            "languages" = [
              "markdown"
              "plaintext"
              "html"
            ];
          };
        };
      };
    };
  };
}
