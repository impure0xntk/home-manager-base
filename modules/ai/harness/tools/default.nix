{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

  # Execute `rtk trust` when new files are created.
  rtkFilterPath = language: ./rtk/filters/${language}.toml;
  rtkFiltersCombined = pkgs.writeText "filters.toml" (
    lib.concatStringsSep "\n" (
      [ (builtins.readFile ./rtk/filters/common.toml) ]
      ++ lib.mapAttrsToList (
        language: languageConfig:
        lib.optionalString languageConfig.enable (
          lib.optionalString (builtins.pathExists (rtkFilterPath language)) (
            builtins.readFile (rtkFilterPath language)
          )
        )
      ) config.my.home.languages
    )
  );

  defaultCodingAgentToolsXdgConfigDirs = [
    {
      "rtk/config.toml".source = ./rtk/config.toml;
      "rtk/filters.toml".source = rtkFiltersCombined;
    }
  ];
  defaultCodingAgentToolsXdgDataDirs = [
    {
      "ctx/config.toml".source = ./ctx/config.toml;
    }
  ];
in
{
  options.my.home.ai.harness.codingAgentTools =
    with lib;
    with lib.types;
    mkOption {
      description = ''
        Tools that are only available inside coding agent wrappers (codex, junie, goose, etc.).
        Each tool defines a package, environment variables, and a prompt fragment.
      '';
      type = attrsOf (submodule {
        options = {
          package = mkOption {
            type = package;
            description = "The Nix package to provide for this tool.";
          };
          envVars = mkOption {
            type = attrsOf str;
            default = { };
            description = "Environment variables to set in the agent wrapper.";
          };
          prompt = mkOption {
            type = str;
            default = "";
            description = "Prompt fragment to include in AGENTS.md for agents.";
          };
        };
      });
      default = {
        rtk = {
          package = pkgs.rtk;
          prompt = builtins.readFile ./RTK.md;
        };
        codegraph = {
          package = pkgs.my.codegraph;
          # Self maid
          prompt = builtins.readFile ./CODEGRAPH.md;
        };
        ctx = {
          package = pkgs.ctx;
          envVars = {
            CTX_DATA_ROOT = "${config.xdg.dataHome}/ctx";
            CTX_ANALYTICS_ENABLED = "false";
            CTX_UPGRADE_AUTO = "off";
          };
          prompt = builtins.readFile ./CTX.md;
        };
      };
    };

  config = lib.mkIf cfg.harness.enable {
    xdg.configFile = lib.mkMerge defaultCodingAgentToolsXdgConfigDirs;
    # xdg.dataFile = lib.mkMerge defaultCodingAgentToolsXdgDataDirs;

    systemd.user.services.ctx-history =
    let
      ctxBin = lib.getExe config.my.home.ai.harness.codingAgentTools.ctx.package;
      ctxEnvVars = config.my.home.ai.harness.codingAgentTools.ctx.envVars;
    in {
      Unit.Description = "Index local coding-agent history for CTX";
      Service = {
        Type = "simple";
        ExecStartPre = "${ctxBin} setup --no-daemon --quiet";
        ExecStart = "${ctxBin} daemon run";
        TimeoutStartSec = "10min";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") ctxEnvVars;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
