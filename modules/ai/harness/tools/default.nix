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

  # `writeShellApplication` builds with `runCommand`, so the standard phases
  # after `buildPhase` never run: a `wrapProgram` appended to `postInstall` is
  # accepted by the evaluation and then dropped at build time, and the wrapper
  # ships with none of the env vars. `runtimeEnv` goes into the script text
  # instead, which is written by the same `runCommand` build, so it survives.
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
        semble = rec {
          package = createWrappedPackage pkgs.my.semble {
            # One XDG subtree for the three caches semble keeps, so a
            # `semble clear` and a cache prune have a single place to look.
            SEMBLE_CACHE_LOCATION = "${config.xdg.cacheHome}/semble/index";
            # tree-sitter grammars unpack out of the wheel on first use
            SEMBLE_GRAMMARS_CACHE_DIR = "${config.xdg.cacheHome}/semble/grammars";
            # the potion-code-16M-v2 embedding model, fetched on first use
            HF_HOME = "${config.xdg.cacheHome}/semble/huggingface";
          };
          prompt = builtins.readFile ./SEMBLE.md;
          mcpServer = {
            command = lib.getExe package;
            # `code` alone would blind the server to config keys and doc pages,
            # which is a large share of what an agent asks a codebase. The
            # `content` argument on a call still narrows it back to one scope.
            args = [ "--content" "all" ];
            # Each searched repo stays resident in memory for the session, so
            # drop the ones idle for 30 min rather than pinning every repo the
            # session ever touched.
            env.SEMBLE_MCP_IDLE_TIMEOUT = "1800";
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