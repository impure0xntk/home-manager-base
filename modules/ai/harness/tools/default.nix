{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.home.ai;

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
      };
    };

  config = lib.mkIf cfg.harness.enable {
    xdg.configFile = lib.mkMerge defaultCodingAgentToolsXdgConfigDirs;
  };
}
