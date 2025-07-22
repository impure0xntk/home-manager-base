{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.my.home.languages.python;
in
{
  options.my.home.languages.python = {
    enable = mkEnableOption "Python language support";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      python3
      uv
      ruff
    ];

    home.sessionVariables = {
      PYTHONPATH = "${config.home.homeDirectory}/.local/lib/python${pkgs.python3.pythonVersion}/site-packages";
    };
    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "ms-python.python"
        "ms-python.debugpy"
        "njpwerner.autodocstring"
        "charliermarsh.ruff"
      ];
      userSettings =
        {
          "[python]" = {
            "editor.defaultFormatter" = "charliermarsh.ruff";
          };
        }
        // (lib.my.flatten "_flattenIgnore" {
          ruff = {
            enable = true;
            nativeServer = "on";
            path = [ (lib.getExe pkgs.ruff) ];
            configuration = ./ruff.toml;

            lint.enable = true;
            organizeImports = true;
            fixAll = true;
            codeAction = {
              fixViolation = {
                enable = true;
                _flattenIgnore = true;
              };
              disableRuleComment = {
                enable = true;
                _flattenIgnore = true;
              };
            };
          };
        });
    };
  };
}
