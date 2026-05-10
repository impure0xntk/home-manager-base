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
    my.home.editors = {
      lspConfig = {
        ty.cmd = [ "${lib.getExe pkgs.unstable.ty}" "server" ];

        ruff = {
          cmd = [ "${lib.getExe pkgs.unstable.ruff}" "server" ];
          init_options.settings.configuration = ./ruff.toml;
        };
      };
    };

    home.packages = with pkgs; [
      python3
    ] ++ (with pkgs.unstable; [
      ty
      ruff
    ]);

    home.sessionVariables = {
      PYTHONPATH = "${config.home.homeDirectory}/.local/lib/python${pkgs.python3.pythonVersion}/site-packages";
      # https://www.lifewithpython.com/2021/05/python-docker-env-vars.html
      PYTHONPYCACHEPREFIX = "${config.xdg.cacheHome}/python";
      PYTHONUNBUFFERED = 1;
      PYTHONUTF8 = 1;
      PYTHONIOENCODING = "UTF-8";
      PYTHONBREAKPOINT = "IPython.terminal.debugger.set_trace";
      PIP_DISABLE_PIP_VERSION_CHECK = "on";
      PIP_NO_CACHE_DIR = "off";
    };
    programs.vscode.profiles.default = {
      extensions = pkgs.nix4vscode.forVscode [
        "ms-python.python"
        "ms-python.debugpy"
        "njpwerner.autodocstring"

        "astral-sh.ty"

        "charliermarsh.ruff"
      ];
      userSettings =
        {
          "[python]" = {
            "editor.defaultFormatter" = "charliermarsh.ruff";
          };
        }
        // (lib.my.flatten "_flattenIgnore" {
          ty.path = [ (lib.getExe pkgs.unstable.ty) ];
          # Insert the following configuration to .vscode/settings.json if there is no source path in root:
          # "ty.configuration": {
          #   "environment": {
          #     "extra-paths": [
          #       "src"
          #     ]
          #   }
          # }

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
