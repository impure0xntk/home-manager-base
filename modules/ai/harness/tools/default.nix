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
          package = createWrappedPackage pkgs.codegraph {
            CODEGRAPH_TELEMETRY = "0";
            DO_NOT_TRACK = "1";
          };
          prompt = builtins.readFile ./CODEGRAPH.md; # Self maid
          mcpServer = {
            command = lib.getExe package;
            args = [ "serve" "--mcp" ];
          };
        };
        ctx = lib.mkIf config.my.home.ai.harness.memory.enable {
          package = config.my.home.ai.harness.memory.package;
          prompt = builtins.readFile ./CTX.md;
          # Command and exclusion list are `harness.memory` options, declared in
          # `harness/memory/default.nix`. Read one path at a time: binding that
          # whole set into a `cfg` here would make this default wait on the very
          # `codingAgentTools` entry it helps build.
          mcpServer = {
            command = lib.getExe config.my.home.ai.harness.memory.package;
            args = [ "mcp" "serve" ];
            excludeTools = [
              # Modify nothing: no historical session is ever rewritten.
              "archive"
              "archive_export_bundle"
              "archive_import_bundle"
              "archive_verify_bundle"
              "import_merge_history"
              "session_delete"
              "sources_config_add_jsonl"
              "sources_config_remove_jsonl"
              "sources_config_update_jsonl"
              "sources_identity_forget"
              "sources_identity_overwrite"
              # Supervision belongs to ctx's own units, never to an agent.
              "daemon_service_install"
              "daemon_service_uninstall"
              "daemon_start"
              "daemon_stop"
              "daemon_restart"
              "setup_config_init"
              "setup_daemon"
              "install"
              "uninstall"
              "update"
              # Reach the server through `ctx-server`, if it is ever wanted.
              "server_init"
              "server_stop"
              "server_run"
              "login_start"
              "login_status"
              "logout"
              # Delegated to other backends, which are already available and
              # cheaper: rtk condenses command output, zvec-grep does lexical
              # search and codegraph answers structural questions.
              "files_read"
              "files_grep"
              "code_search"
              "tree"
              "docs"
              "document_fetch"
              "prompt_optimize"
              "look_at"
              "graph_query"
              "graph_show"
              "graph_callers"
              "graph_callees"
              "graph_impact"
              "graph_path"
              "graph_stats"
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

  };
}
