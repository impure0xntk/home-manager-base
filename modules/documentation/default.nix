# Import vscode-server to flake as input.
# https://github.com/nix-community/nixos-vscode-server
#
{ config, pkgs, lib, ... }:
let
  cfg = config.my.home.documentation;

  rcFile = pkgs.writeText "textlintrc" (import ./textlint {inherit pkgs lib;});

  cacheLocation = config.xdg.cacheHome + "/textlint";
  textlint = pkgs.textlint-all.override {
    inherit cacheLocation;
  };

  # makeWrapper is used for the last to add NODE_PATH.
  textlintWrapper = pkgs.writeShellApplication {
    name = "textlint";
    runtimeInputs = [ textlint ];
    text = ''
      textlint \
        --config ${rcFile} \
        --cache true \
        --cache-location ${cacheLocation}/textlintcache \
        "$@"
    '';
  };

in {
  options.my.home.documentation.enable = lib.mkEnableOption "Whether to enable documentation tools.";

  config = lib.mkIf cfg.enable {
    home.packages = [ textlintWrapper ];
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
