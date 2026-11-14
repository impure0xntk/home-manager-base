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

  createWrappedPackage = package: envVars: pkgs.writeShellApplication {
    name = package.meta.mainProgram;
    runtimeInputs = [ package ];
    runtimeEnv = envVars;
    text = ''
      exec ${lib.getExe package} "$@"
    '';
  };
in
{
  imports = [
    ./rtk.nix
    ./codegraph.nix
  ];

  options.my.home.ai.harness.codingAgentTools =
    with lib;
    with lib.types;
    mkOption {
      description = ''
        Tools exposed as standalone commands and to coding agents (codex, junie, goose, etc.).
        Each tool defines a package, environment variables, and a prompt fragment.

        No tool is enabled by default: `harness/tools/rtk.nix`,
        `harness/tools/codegraph.nix` and `harness/memory/default.nix` contribute
        the rtk, codegraph and ctx defaults respectively through `mkDefault`, so
        every entry can be removed, replaced or extended from a machine config.
      '';
      type = attrsOf (submodule {
        options = {
          package = mkOption {
            type = package;
            description = "The Nix package to provide for this tool.";
          };
          prompt = mkOption {
            type = nullOr str;
            default = null;
            description = "Prompt fragment to include in AGENTS.md for agents.";
          };
          mcpServer = mkOption {
            type = nullOr (import ../mcp-server-type.nix { inherit lib; });
            default = null;
            description = ''
              MCP server definition. When set, the tool is registered as a stdio
              MCP server in every agent that supports MCP (codex, goose, ...).
            '';
          };
        };
      });
      default = { };
    };

  config = lib.mkIf cfg.harness.enable {
    home.packages = lib.forEach (builtins.attrValues config.my.home.ai.harness.codingAgentTools) (v: v.package);
    xdg.configFile = lib.mkMerge defaultCodingAgentToolsXdgConfigDirs;

    home.activation.trustRtkCustomFilter = lib.mkIf (
      builtins.hasAttr "rtk" config.my.home.ai.harness.codingAgentTools
    ) (lib.hm.dag.entryAfter [ "trust-rtk-custom-filter" ] ''
      ${config.my.home.ai.harness.codingAgentTools.rtk.package}/bin/rtk trust --yes
    '');

  };
}
