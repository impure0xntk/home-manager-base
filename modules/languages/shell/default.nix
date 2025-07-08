{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.my.home.languages.shell;
in
{
  options.my.home.languages.shell.enable =
    lib.mkEnableOption "Whether to enable shell language support.";
  config = lib.mkIf cfg.enable {
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
        bashIde = {
          shellcheckPath = "${pkgs.shellcheck-minimal}/bin/shellcheck";
          backgroundAnalysisMaxFiles = 1; # otherwise hangs by OOM on search because shellcheck runs all results.
          shfmt.path = "${pkgs.shfmt}/bin/shfmt";
        };
        shellcheck = {
          enable = false;
          executablePath = bashIde.shellcheckPath;
        };
      };
    };
  };

}
