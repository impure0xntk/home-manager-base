{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.languages.markdown;
in
{
  options.my.home.languages.markdown = {
    enable = lib.mkEnableOption "Whether to enable markdown language support.";
    lint.config = lib.mkOption {
      type = lib.types.attrs;
      default = {
        MD007 = {
          indent = 4;
        };
        MD013 = false;
      };
      description = "Markdownlint config.";
    };
  };
  config = lib.mkIf cfg.enable {
    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "shd101wyy.markdown-preview-enhanced"
        "davidanson.vscode-markdownlint"
        "arr.marksman"
      ];
      userSettings = {
        "[markdown]" = {
          "editor.defaultFormatter" = "DavidAnson.vscode-markdownlint";
        };
      } // lib.my.flatten "_flattenIgnore" {
        markdownlint = {
          config = cfg.lint.config;
          run = "onSave";
        };
        markdown-preview-enhanced = {
          enableExtendedTableSyntax = true;
          previewTheme = "github-light.css";
        };

        marksman = {
          customCommand = "${pkgs.marksman}/bin/marksman";
          trace.server = "messages";
        };
      };
    };
  };

}
