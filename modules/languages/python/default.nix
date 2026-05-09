# Strategy:
# * Base LSP: pyrefly
# * Strict LSP
#   * editor: zuban (performance)
#   * ide: pyright (usability)
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
        # pyright.cmd = [ "${pkgs.unstable.pyright}/bin/pyright-langserver" "--stdio" ];
        pyrefly.cmd = [ "${lib.getExe pkgs.unstable.pyrefly}" "lsp" ];
        zuban.cmd = [ "${lib.getExe pkgs.unstable.zuban}" "server" ];

        ruff = {
          cmd = [ "${lib.getExe pkgs.unstable.ruff}" "server" ];
          init_options.settings.configuration = ./ruff.toml;
        };
      };
    };

    home.packages = with pkgs; [
      python3
    ];

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

        "ms-pyright.pyright"
        "meta.pyrefly"
        # "zuban.zubanls"

        "charliermarsh.ruff"
      ];
      userSettings =
        {
          "[python]" = {
            "editor.defaultFormatter" = "charliermarsh.ruff";
          };
        }
        // (lib.my.flatten "_flattenIgnore" {
          pyrefly.lspPath = lib.getExe pkgs.unstable.pyrefly;
          python.pyrefly.syncNotebooks = false;

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
