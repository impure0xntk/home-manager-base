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
  options.my.home.ai.harness.codingAgentTools =
    with lib;
    with lib.types;
    mkOption {
      description = ''
        Tools exposed as standalone commands and to coding agents (codex, junie, goose, etc.).
        Each tool defines a package, environment variables, and a prompt fragment.
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
      default = {
        rtk = {
          package = pkgs.rtk;
          prompt = builtins.readFile ./RTK.md;
        };
        codegraph = rec {
          package = createWrappedPackage pkgs.my.codegraph {
            CODEGRAPH_TELEMETRY = "0";
            DO_NOT_TRACK = "1";
          };
          prompt = builtins.readFile ./CODEGRAPH.md; # Self maid
          mcpServer = {
            command = lib.getExe package;
            args = [ "serve" "--mcp" ];
          };
        };
        ctx = rec {
          package = createWrappedPackage pkgs.ctx {
            CTX_DATA_ROOT = "${config.xdg.dataHome}/ctx";
            CTX_ANALYTICS_ENABLED = "false";
            CTX_UPGRADE_AUTO = "off";
          };
          prompt = builtins.readFile ./CTX.md;
          mcpServer = {
            command = lib.getExe package;
            args = [ "mcp" "serve" ];
            excludeTools = [
              # graph: delegate to codegraph
              "graph_query"
              "graph_show"
              "graph_callers"
              "graph_callees"
              "graph_impact"
              "graph_path"
              "graph_stats"
              # sift: delegate to rtk
              "output_compact"
              "output_restore"
            ];
          };
        };
        zg = rec {
          package = createWrappedPackage pkgs.my.zvec-grep {
            ZVEC_GREP_HOME = "${config.xdg.configHome}/zvec-grep";
            ZVEC_GREP_MODEL_CACHE = "${config.xdg.dataHome}/zvec-grep";
            ZVEC_GREP_EMBEDDING = "local/qwen3-embedding-0.6b";
          };
          prompt = builtins.readFile ./ZVEC-GREP.md;
          mcpServer = {
            command = lib.getExe package;
            args = [ "server" "--stdio" ];
          };
        };
      };
    };

  config = lib.mkIf cfg.harness.enable {
    home.packages = lib.forEach (builtins.attrValues config.my.home.ai.harness.codingAgentTools) (v: v.package);
    xdg.configFile = lib.mkMerge defaultCodingAgentToolsXdgConfigDirs;

    home.activation.trustRtkCustomFilter = lib.hm.dag.entryAfter [ "trust-rtk-custom-filter" ] ''
      ${config.my.home.ai.harness.codingAgentTools.rtk.package}/bin/rtk trust --yes
    '';

    systemd.user.services.ctx-history =
    let
      ctxBin = lib.getExe config.my.home.ai.harness.codingAgentTools.ctx.package;
    in {
      Unit.Description = "Index local coding-agent history for CTX";
      Service = {
        Type = "simple";
        ExecStartPre = "${ctxBin} setup --no-daemon --quiet";
        ExecStart = "${ctxBin} daemon run";
        TimeoutStartSec = "10min";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}