{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.languages.shell;

  bashIdeConfig = {
    globPattern = "*@(.sh|.inc|.bash|.command)";
    shellcheckPath = lib.getExe pkgs.unstable.shellcheck-minimal;
    backgroundAnalysisMaxFiles = 1; # otherwise hangs by OOM on search because shellcheck runs all results.
    shfmt.path = lib.getExe pkgs.unstable.shfmt;
  };
in
{
  options.my.home.languages.shell.enable =
    lib.mkEnableOption "Whether to enable shell language support.";
  config = lib.mkIf cfg.enable {
    my.home.editors = {
      lspConfig = {
        bashls = {
          cmd = [ "${lib.getExe pkgs.unstable.bash-language-server}" "start" ];
          settings.bashIde = bashIdeConfig;
        };
      };
      lspIntegrationConfig = lib.forEach [
        ''formatting.shellharden.with({ command = "${lib.getExe pkgs.unstable.shellharden}" })''
        ''formatting.shfmt.with({ command = "${lib.getExe pkgs.unstable.shfmt}" })''
      ] (source: "null_ls.builtins.${source}");
    };

    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "mads-hartmann.bash-ide-vscode"
        "timonwong.shellcheck"
        "foxundermoon.shell-format" # shell in Dockerfile support
        "jetmartin.bats"
        "rogalmic.bash-debug"
        "dotiful.dotfiles-syntax-highlighting"
      ];
      userSettings = {
        "[shellscript]" = {
          "editor.defaultFormatter" = "mads-hartmann.bash-ide-vscode";
          "editor.formatOnSave" = false; # if true, sometimes hangs
        };
      } // lib.my.flatten "_flattenIgnore" rec {
        bashIde = bashIdeConfig;
        shellcheck = {
          enable = false;
          executablePath = bashIde.shellcheckPath;
        };
      };
    };
  };

}
