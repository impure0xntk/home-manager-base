{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.languages.sql;
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
    my.home.editors = {
      lspConfig = {
        sqls.cmd = [ "${lib.getExe pkgs.unstable.sqls}" ];
      };
      lspIntegrationConfig = lib.forEach [
        ''diagnostics.sqruff.with({ command = "${lib.getExe pkgs.unstable.sqruff}" })''
        ''formatting.sqruff.with({ command = "${lib.getExe pkgs.unstable.sqruff}" })''
      ] (source: "null_ls.builtins.${source}");
    };

    home.packages = with pkgs; [ lazysql ];

    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "quary.sqruff"
      ];
      userSettings = {
        "[sql]" = {
          "editor.defaultFormatter" = "quary.sqruff";
        };
        "github.copilot.enable" = {
          "sql" = false; # Disable because may include sensitive info.
        };
      } // lib.my.flatten "_flattenIgnore" {
        sqruff.executablePath = lib.getExe pkgs.unstable.sqruff;
      };
    };
  };

}
