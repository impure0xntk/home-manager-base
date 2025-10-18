{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.languages.sql;
  purePkgs = import <nixpkgs> { }; # to avoid build sqlfluff because it's build is too slow
in
{
  options.my.home.languages.sql = {
    enable = lib.mkEnableOption "Whether to enable sql language support.";
    mysql-client = {
      configFilePath = lib.mkOption {
        type = lib.types.path;
        default = "${config.home.homeDirectory}/.my.cnf";
        description = "DO NOT EDIT: config file path to mysql client config file.";
      };
    };
    lazysql = {
      configFilePath = lib.mkOption {
        type = lib.types.path;
        default = "${config.xdg.configHome}/lazysql/config.toml";
        description = "DO NOT EDIT: YAML file path to lazysql config file.";
      };
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [ lazysql ];

    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "dorzey.vscode-sqlfluff"
      ];
      userSettings = {
        "[sql]" = {
          "editor.defaultFormatter" = "dorzey.vscode-sqlfluff";
        };
        "github.copilot.enable" = {
          "sql" = false; # Disable because may include sensitive info.
        };
      } // lib.my.flatten "_flattenIgnore" {
        sqlfluff = {
          executablePath = "${purePkgs.sqlfluff}/bin/sqlfluff";
          dialect = "mysql"; # By default. If use another, set from workspace.
          format.enabled = false;
          linter.run = "onSave";
        };
      };
    };
  };

}
